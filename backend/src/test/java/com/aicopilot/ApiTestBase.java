package com.aicopilot;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;

import com.aicopilot.TestInfrastructure.FakeAiEngine;
import java.util.UUID;
import org.junit.jupiter.api.BeforeEach;
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
 * Shared setup of the HTTP-level integration tests: one Spring context (reused across test classes),
 * real PostgreSQL, fake AI engine, and helpers that call the API the way the apps do.
 */
@SpringBootTest(properties = {
 "copilot.client-api-token=" + ApiTestBase.TOKEN,
 "copilot.processing.poll-interval=PT0.05S",
 "copilot.storage.path=${java.io.tmpdir}/aicopilot-test-blobs",
 "copilot.knowledge.path=src/test/resources/knowledge-test",
})
@AutoConfigureMockMvc
@Import(TestInfrastructure.class)
abstract class ApiTestBase {

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
  jdbc.sql("truncate attachments, ai_requests, messages, drafts, user_settings, conversations cascade").update();
  ai.reset();
 }


 MockHttpServletRequestBuilder authorized(MockHttpServletRequestBuilder request) {
  return request.header("Authorization", "Bearer " + TOKEN);
 }

 JsonNode home() throws Exception {
  return body(mvc.perform(authorized(get("/v1/home"))).andReturn(), 200);
 }

 JsonNode messages(String conversationId) throws Exception {
  return body(mvc.perform(authorized(get("/v1/conversations/{id}/messages", conversationId))).andReturn(), 200);
 }

 JsonNode submit(String draftId, String text, UUID key, int expectedStatus) throws Exception {
  MvcResult result = mvc.perform(authorized(post("/v1/drafts/{id}/submit", draftId))
    .header("Idempotency-Key", key.toString())
    .contentType(MediaType.APPLICATION_JSON)
    .content(json.writeValueAsString(java.util.Map.of("text", text))))
   .andReturn();
  return body(result, expectedStatus);
 }

 /** Uses the long-poll endpoint exactly like the Watch does. */
 JsonNode awaitTerminal(String requestId) throws Exception {
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

 JsonNode body(MvcResult result, int expectedStatus) throws Exception {
  assertThat(result.getResponse().getStatus()).as(result.getResponse().getContentAsString()).isEqualTo(expectedStatus);
  return json.readTree(result.getResponse().getContentAsString(java.nio.charset.StandardCharsets.UTF_8));
 }

 int count(String tableAndCondition) {
  return jdbc.sql("select count(*) from " + tableAndCondition).query(Integer.class).single();
 }
}
