package com.aicopilot;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;

import com.aicopilot.TestInfrastructure.FakeAiEngine;
import com.aicopilot.ai.AiEngine.Turn;
import java.nio.charset.StandardCharsets;
import java.util.UUID;
import org.junit.jupiter.api.Test;
import tools.jackson.databind.JsonNode;

/**
 * Cancel Send and Retry (spec 26, 37): a Send waiting for photos can be cancelled without losing them,
 * and a failed answer can be requested again without a duplicate question.
 */
class SendControlIT extends ApiTestBase {

 @Test
 void cancelledSendReturnsPhotosAndTextToTheDraftAndCanBeSentAgain() throws Exception {
  JsonNode home = home();
  String draftId = home.at("/draft/id").asString();
  byte[] page = "page".getBytes(StandardCharsets.UTF_8);
  String attachmentId = register(draftId, page, "camera");
  JsonNode waiting = submit(draftId, "Объясни задание", UUID.randomUUID(), 202);
  assertThat(waiting.at("/state").asString()).isEqualTo("waitingForAttachments");

  JsonNode cancelled = cancel(waiting.at("/id").asString(), 200);

  assertThat(cancelled.at("/state").asString()).isEqualTo("cancelled");
  JsonNode draft = draft(home.at("/activeConversation/id").asString());
  assertThat(draft.at("/id").asString()).isEqualTo(draftId);
  assertThat(draft.at("/state").asString()).isEqualTo("open");
  assertThat(draft.at("/text").asString()).isEqualTo("Объясни задание");
  assertThat(draft.at("/attachments/0/id").asString()).isEqualTo(attachmentId);
  // Idempotent.
  assertThat(cancel(waiting.at("/id").asString(), 200).at("/state").asString()).isEqualTo("cancelled");

  // Fix the photo and send again (without retyping the text: it was kept).
  upload(attachmentId, page, 200);
  JsonNode done = awaitTerminal(submitWithoutText(draftId, 202).at("/id").asString());

  assertThat(done.at("/state").asString()).isEqualTo("completed");
  assertThat(ai.calls).hasSize(1);
  Turn question = ai.calls.getFirst().turns().getLast();
  assertThat(question.text()).isEqualTo("Объясни задание");
  assertThat(question.images()).hasSize(1);
  assertThat(count("messages where role = 'USER'")).isEqualTo(1);
 }

 @Test
 void cancelMergesPhotosTakenMeanwhileAfterTheOriginalOnes() throws Exception {
  JsonNode home = home();
  String conversationId = home.at("/activeConversation/id").asString();
  String firstDraft = home.at("/draft/id").asString();
  String first = register(firstDraft, "p1".getBytes(StandardCharsets.UTF_8), "camera");
  String requestId = submitWithoutText(firstDraft, 202).at("/id").asString();
  // Meanwhile the user takes another photo: it goes to a new draft.
  String secondDraft = home().at("/draft/id").asString();
  assertThat(secondDraft).isNotEqualTo(firstDraft);
  String second = register(secondDraft, "p2".getBytes(StandardCharsets.UTF_8), "camera");

  cancel(requestId, 200);

  JsonNode draft = draft(conversationId);
  assertThat(draft.at("/id").asString()).isEqualTo(firstDraft);
  assertThat(draft.at("/attachments")).hasSize(2);
  assertThat(draft.at("/attachments/0/id").asString()).isEqualTo(first);
  assertThat(draft.at("/attachments/1/id").asString()).isEqualTo(second);
  assertThat(count("drafts")).isEqualTo(1);
 }

 @Test
 void sendThatAlreadyReachedTheAiCannotBeCancelled() throws Exception {
  String requestId = submit(home().at("/draft/id").asString(), "why kafka?", UUID.randomUUID(), 202).at("/id").asString();
  awaitTerminal(requestId);

  assertThat(cancel(requestId, 409).at("/code").asString()).isEqualTo("request_not_cancellable");
 }

 @Test
 void retryOfFailedAnswerReusesTheSameQuestion() throws Exception {
  ai.script.add(FakeAiEngine.failing(false));
  String requestId = submit(home().at("/draft/id").asString(), "why kafka?", UUID.randomUUID(), 202).at("/id").asString();
  assertThat(awaitTerminal(requestId).at("/state").asString()).isEqualTo("failed");

  JsonNode retried = retry(requestId, 202);

  assertThat(retried.at("/id").asString()).isEqualTo(requestId);
  assertThat(awaitTerminal(requestId).at("/state").asString()).isEqualTo("completed");
  assertThat(ai.calls).hasSize(2);
  // No duplicate question, exactly one answer.
  assertThat(count("messages where role = 'USER'")).isEqualTo(1);
  assertThat(count("messages where role = 'ASSISTANT'")).isEqualTo(1);
  // Idempotent after success.
  assertThat(retry(requestId, 202).at("/state").asString()).isEqualTo("completed");
  assertThat(ai.calls).hasSize(2);
 }

 @Test
 void retryIsRejectedWhenNewerMessagesExist() throws Exception {
  ai.script.add(FakeAiEngine.failing(false));
  String failed = submit(home().at("/draft/id").asString(), "first", UUID.randomUUID(), 202).at("/id").asString();
  awaitTerminal(failed);
  awaitTerminal(submit(home().at("/draft/id").asString(), "second", UUID.randomUUID(), 202).at("/id").asString());

  assertThat(retry(failed, 409).at("/code").asString()).isEqualTo("request_not_retryable");
 }

 @Test
 void requestReportsWhenItWasSent() throws Exception {
  JsonNode request = submit(home().at("/draft/id").asString(), "why kafka?", UUID.randomUUID(), 202);
  assertThat(request.at("/createdAt").asString()).isNotBlank();
 }

 private JsonNode cancel(String requestId, int expectedStatus) throws Exception {
  return body(mvc.perform(authorized(post("/v1/requests/{id}/cancel", requestId))).andReturn(), expectedStatus);
 }

 private JsonNode retry(String requestId, int expectedStatus) throws Exception {
  return body(mvc.perform(authorized(post("/v1/requests/{id}/retry", requestId))).andReturn(), expectedStatus);
 }

 private JsonNode draft(String conversationId) throws Exception {
  return body(mvc.perform(authorized(get("/v1/conversations/{c}/draft", conversationId))).andReturn(), 200);
 }
}
