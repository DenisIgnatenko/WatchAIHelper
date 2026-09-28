package com.aicopilot;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;

import com.aicopilot.TestInfrastructure.FakeAiEngine;
import com.aicopilot.ai.AiEngine.Turn;
import java.util.List;
import java.util.UUID;
import java.util.concurrent.Callable;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.Executors;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.context.annotation.Import;
import org.springframework.http.MediaType;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.MvcResult;
import org.springframework.test.web.servlet.request.MockHttpServletRequestBuilder;
import tools.jackson.databind.JsonNode;
import tools.jackson.databind.ObjectMapper;

/**
 * End-to-end backend tests through the HTTP API: draft -> submit -> message -> AI -> answer.
 * Covers the spec 58 invariants that exist in Phase 2 (text-only).
 */
@SpringBootTest(properties = {
 "copilot.client-api-token=" + SubmissionFlowIT.TOKEN,
 "copilot.processing.poll-interval=PT0.05S",
})
@AutoConfigureMockMvc
@Import(TestInfrastructure.class)
class SubmissionFlowIT {

 static final String TOKEN = "test-device-token";

 @Autowired
 MockMvc mvc;
 @Autowired
 ObjectMapper json;
 @Autowired
 JdbcClient jdbc;
 @Autowired
 FakeAiEngine ai;

 @BeforeEach
 void cleanState() {
  // Users/devices stay (created once by the bootstrap); everything conversational is reset.
  jdbc.sql("truncate ai_requests, messages, drafts, user_settings, conversations cascade").update();
  ai.reset();
 }

 @Test
 void rejectsRequestsWithoutValidToken() throws Exception {
  MvcResult result = mvc.perform(get("/v1/home")).andReturn();
  assertThat(result.getResponse().getStatus()).isEqualTo(401);

  MvcResult wrong = mvc.perform(get("/v1/home").header("Authorization", "Bearer nope")).andReturn();
  assertThat(wrong.getResponse().getStatus()).isEqualTo(401);
 }

 @Test
 void homeCreatesActiveConversationAndDraftOnce() throws Exception {
  JsonNode first = home();
  JsonNode second = home();
  assertThat(second.at("/activeConversation/id")).isEqualTo(first.at("/activeConversation/id"));
  assertThat(second.at("/draft/id")).isEqualTo(first.at("/draft/id"));
  assertThat(first.at("/draft/totalAttachments").asInt()).isZero();
 }

 @Test
 void textQuestionIsAnsweredInTheSameConversation() throws Exception {
  JsonNode home = home();
  String question = "Hvorfor er nummer 4 B? Почему?";

  JsonNode request = submit(home.at("/draft/id").asString(), question, UUID.randomUUID(), 202);
  JsonNode done = awaitTerminal(request.at("/id").asString());

  assertThat(done.at("/state").asString()).isEqualTo("completed");
  JsonNode messages = messages(home.at("/activeConversation/id").asString());
  assertThat(messages).hasSize(2);
  assertThat(messages.get(0).at("/role").asString()).isEqualTo("user");
  // Unicode preserved end-to-end (spec 14).
  assertThat(messages.get(0).at("/text").asString()).isEqualTo(question);
  assertThat(messages.get(1).at("/role").asString()).isEqualTo("assistant");
  assertThat(messages.get(1).at("/id").asString()).isEqualTo(done.at("/assistantMessageId").asString());
  assertThat(messages.get(1).at("/suggestedActions/0/title").asString()).isEqualTo("Подробнее");
  // Home shows the answer and a fresh draft for the next question.
  JsonNode after = home();
  assertThat(after.at("/lastAnswer/id")).isEqualTo(messages.get(1).at("/id"));
  assertThat(after.at("/draft/id")).isNotEqualTo(home.at("/draft/id"));
 }

 @Test
 void followUpSeesPreviousTurns() throws Exception {
  String first = submit(home().at("/draft/id").asString(), "Ответь на вопросы.", UUID.randomUUID(), 202).at("/id").asString();
  awaitTerminal(first);
  String second = submit(home().at("/draft/id").asString(), "Почему 4 B?", UUID.randomUUID(), 202).at("/id").asString();
  awaitTerminal(second);

  // The backend owns the context (spec 32): the second call carries the whole conversation.
  List<Turn> turns = ai.calls.get(1).turns();
  assertThat(turns).extracting(Turn::role).containsExactly(Turn.Role.USER, Turn.Role.ASSISTANT, Turn.Role.USER);
  assertThat(turns.get(2).text()).isEqualTo("Почему 4 B?");
  assertThat(ai.calls.get(1).instructions()).contains("Always answer in Russian");
 }

 @Test
 void retryWithSameIdempotencyKeyReturnsSameRequest() throws Exception {
  String draftId = home().at("/draft/id").asString();
  UUID key = UUID.randomUUID();

  String firstId = submit(draftId, "why kafka?", key, 202).at("/id").asString();
  String retryId = submit(draftId, "why kafka?", key, 202).at("/id").asString();
  awaitTerminal(firstId);

  assertThat(retryId).isEqualTo(firstId);
  assertThat(count("ai_requests")).isEqualTo(1);
  assertThat(count("messages where role = 'USER'")).isEqualTo(1);
  assertThat(ai.calls).hasSize(1);
 }

 @Test
 void concurrentSendsOfOneDraftProduceExactlyOneRequest() throws Exception {
  // Watch and iPhone press Send at the same time with different keys (spec 37).
  String draftId = home().at("/draft/id").asString();
  CountDownLatch start = new CountDownLatch(1);
  Callable<Integer> send = () -> {
   start.await();
   return mvc.perform(authorized(post("/v1/drafts/{id}/submit", draftId))
     .header("Idempotency-Key", UUID.randomUUID().toString())
     .contentType(MediaType.APPLICATION_JSON)
     .content("{\"text\":\"ответ 3?\"}"))
    .andReturn().getResponse().getStatus();
  };
  try (var pool = Executors.newFixedThreadPool(2)) {
   var a = pool.submit(send);
   var b = pool.submit(send);
   start.countDown();
   assertThat(List.of(a.get(), b.get())).containsExactlyInAnyOrder(202, 409);
  }
  assertThat(count("ai_requests")).isEqualTo(1);
  awaitTerminal(jdbc.sql("select id from ai_requests").query(UUID.class).single().toString());
  assertThat(ai.calls).hasSize(1);
 }

 @Test
 void emptyDraftIsRejected() throws Exception {
  JsonNode problem = submit(home().at("/draft/id").asString(), "   ", UUID.randomUUID(), 422);
  assertThat(problem.at("/code").asString()).isEqualTo("empty_draft");
  assertThat(count("ai_requests")).isZero();
 }

 @Test
 void transientFailureIsRetriedAndAnsweredOnce() throws Exception {
  ai.script.add(FakeAiEngine.failing(true));
  String id = submit(home().at("/draft/id").asString(), "why kafka?", UUID.randomUUID(), 202).at("/id").asString();

  JsonNode done = awaitTerminal(id);

  assertThat(done.at("/state").asString()).isEqualTo("completed");
  assertThat(ai.calls).hasSize(2);
  assertThat(count("messages where role = 'ASSISTANT'")).isEqualTo(1);
 }

 @Test
 void permanentFailureFailsWithoutAnswer() throws Exception {
  ai.script.add(FakeAiEngine.failing(false));
  String id = submit(home().at("/draft/id").asString(), "why kafka?", UUID.randomUUID(), 202).at("/id").asString();

  JsonNode done = awaitTerminal(id);

  assertThat(done.at("/state").asString()).isEqualTo("failed");
  assertThat(done.at("/failureReason").asString()).isNotBlank();
  assertThat(ai.calls).hasSize(1);
  assertThat(count("messages where role = 'ASSISTANT'")).isZero();
 }

 // --- helpers ---

 private MockHttpServletRequestBuilder authorized(MockHttpServletRequestBuilder request) {
  return request.header("Authorization", "Bearer " + TOKEN);
 }

 private JsonNode home() throws Exception {
  return body(mvc.perform(authorized(get("/v1/home"))).andReturn(), 200);
 }

 private JsonNode messages(String conversationId) throws Exception {
  return body(mvc.perform(authorized(get("/v1/conversations/{id}/messages", conversationId))).andReturn(), 200);
 }

 private JsonNode submit(String draftId, String text, UUID key, int expectedStatus) throws Exception {
  MvcResult result = mvc.perform(authorized(post("/v1/drafts/{id}/submit", draftId))
    .header("Idempotency-Key", key.toString())
    .contentType(MediaType.APPLICATION_JSON)
    .content(json.writeValueAsString(java.util.Map.of("text", text))))
   .andReturn();
  return body(result, expectedStatus);
 }

 /** Uses the long-poll endpoint exactly like the Watch does. */
 private JsonNode awaitTerminal(String requestId) throws Exception {
  for (int i = 0; i < 10; i++) {
   JsonNode state = body(mvc.perform(authorized(get("/v1/requests/{id}", requestId).param("waitSeconds", "5")))
    .andReturn(), 200);
   String value = state.at("/state").asString();
   if (value.equals("completed") || value.equals("failed") || value.equals("cancelled")) {
    return state;
   }
  }
  throw new AssertionError("Request did not finish: " + requestId);
 }

 private JsonNode body(MvcResult result, int expectedStatus) throws Exception {
  assertThat(result.getResponse().getStatus()).as(result.getResponse().getContentAsString()).isEqualTo(expectedStatus);
  return json.readTree(result.getResponse().getContentAsString(java.nio.charset.StandardCharsets.UTF_8));
 }

 private int count(String tableAndCondition) {
  return jdbc.sql("select count(*) from " + tableAndCondition).query(Integer.class).single();
 }
}
