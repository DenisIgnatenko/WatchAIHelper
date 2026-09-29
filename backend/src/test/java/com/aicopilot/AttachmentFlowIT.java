package com.aicopilot;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.delete;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;

import com.aicopilot.ai.AiEngine.Turn;
import com.aicopilot.draft.AttachmentService;
import java.nio.charset.StandardCharsets;
import java.util.UUID;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.MediaType;
import tools.jackson.databind.JsonNode;

/**
 * Image flow through the HTTP API (spec 58): multi-image drafts, ordering, Send while uploading,
 * failed upload blocks inference, immutability after Send, integrity check of uploads.
 */
class AttachmentFlowIT extends ApiTestBase {

 @Autowired
 AttachmentService attachmentService;

 @Test
 void imageOnlyDraftIsAnsweredWithAllImagesInOrder() throws Exception {
  JsonNode home = home();
  String draftId = home.at("/draft/id").asString();
  byte[] page1 = "page-1-bytes".getBytes(StandardCharsets.UTF_8);
  byte[] page2 = "page-2-bytes".getBytes(StandardCharsets.UTF_8);
  upload(register(draftId, page1, "camera"), page1, 200);
  upload(register(draftId, page2, "photoLibrary"), page2, 200);

  // Registering and uploading never start inference (Invariant 2 / 5).
  assertThat(ai.calls).isEmpty();

  JsonNode done = awaitTerminal(submitWithoutText(draftId, 202).at("/id").asString());

  assertThat(done.at("/state").asString()).isEqualTo("completed");
  Turn question = ai.calls.getFirst().turns().getLast();
  assertThat(question.images()).hasSize(2);
  // Order preserved (spec 27); camera and library images treated the same (spec 22).
  assertThat(question.images().get(0).bytes()).isEqualTo(page1);
  assertThat(question.images().get(1).bytes()).isEqualTo(page2);
  // Image-only: the default instruction is applied at inference time only (spec 28).
  assertThat(question.text()).startsWith("Analyze the attached images");
  JsonNode userMessage = messages(home.at("/activeConversation/id").asString()).get(0);
  assertThat(userMessage.at("/attachmentCount").asInt()).isEqualTo(2);
  assertThat(userMessage.at("/text").isNull()).isTrue();
 }

 @Test
 void sendWhileUploadingWaitsAndThenProceedsAutomatically() throws Exception {
  String draftId = home().at("/draft/id").asString();
  byte[] page1 = "p1".getBytes(StandardCharsets.UTF_8);
  byte[] page2 = "p2".getBytes(StandardCharsets.UTF_8);
  upload(register(draftId, page1, "camera"), page1, 200);
  String second = register(draftId, page2, "camera");

  JsonNode request = submit(draftId, "Ответь на вопросы.", UUID.randomUUID(), 202);

  assertThat(request.at("/state").asString()).isEqualTo("waitingForAttachments");
  assertThat(request.at("/uploadedAttachments").asInt()).isEqualTo(1);
  assertThat(request.at("/totalAttachments").asInt()).isEqualTo(2);
  // No user message and no inference while a page is missing (Invariant 6).
  assertThat(count("messages")).isZero();
  assertThat(ai.calls).isEmpty();

  // The last upload completes the Send - the user does not press Send again (spec 26).
  upload(second, page2, 200);
  JsonNode done = awaitTerminal(request.at("/id").asString());
  assertThat(done.at("/state").asString()).isEqualTo("completed");
  assertThat(ai.calls.getFirst().turns().getLast().images()).hasSize(2);
 }

 @Test
 void failedUploadBlocksInferenceUntilRetried() throws Exception {
  String draftId = home().at("/draft/id").asString();
  byte[] page = "page".getBytes(StandardCharsets.UTF_8);
  String attachmentId = register(draftId, page, "camera");
  String requestId = submitWithoutText(draftId, 202).at("/id").asString();

  // Simulate an upload that never arrived (e.g. the iPhone app was force-quit).
  jdbc.sql("update attachments set created_at = now() - interval '1 hour'").update();
  attachmentService.failStaleUploads();

  JsonNode blocked = requestState(requestId);
  assertThat(blocked.at("/state").asString()).isEqualTo("blocked");
  assertThat(blocked.at("/failedAttachments").asInt()).isEqualTo(1);
  assertThat(ai.calls).isEmpty();

  // Retry = upload again with the same id; the waiting Send continues by itself.
  upload(attachmentId, page, 200);
  assertThat(awaitTerminal(requestId).at("/state").asString()).isEqualTo("completed");
 }

 @Test
 void submittedDraftIsImmutable() throws Exception {
  String draftId = home().at("/draft/id").asString();
  submit(draftId, "why kafka?", UUID.randomUUID(), 202);

  byte[] late = "late".getBytes(StandardCharsets.UTF_8);
  var result = mvc.perform(authorized(put("/v1/drafts/{d}/attachments/{a}", draftId, UUID.randomUUID()))
    .contentType(MediaType.APPLICATION_JSON)
    .content(json.writeValueAsString(registration(late, "camera"))))
   .andReturn();
  assertThat(result.getResponse().getStatus()).isEqualTo(409);
  assertThat(count("attachments")).isZero();
 }

 @Test
 void removingAnImageUpdatesTheDraft() throws Exception {
  String conversationId = home().at("/activeConversation/id").asString();
  String draftId = home().at("/draft/id").asString();
  byte[] a = "a".getBytes(StandardCharsets.UTF_8);
  byte[] b = "b".getBytes(StandardCharsets.UTF_8);
  String first = register(draftId, a, "camera");
  String second = register(draftId, b, "camera");

  int status = mvc.perform(authorized(delete("/v1/drafts/{d}/attachments/{a}", draftId, first)))
   .andReturn().getResponse().getStatus();

  assertThat(status).isEqualTo(204);
  JsonNode draft = body(mvc.perform(authorized(get("/v1/conversations/{c}/draft", conversationId))).andReturn(), 200);
  assertThat(draft.at("/attachments")).hasSize(1);
  assertThat(draft.at("/attachments/0/id").asString()).isEqualTo(second);
  assertThat(home().at("/draft/totalAttachments").asInt()).isEqualTo(1);
 }

 @Test
 void uploadWithWrongContentIsRejectedAndCanBeRetried() throws Exception {
  String draftId = home().at("/draft/id").asString();
  byte[] expected = "expected".getBytes(StandardCharsets.UTF_8);
  String id = register(draftId, expected, "camera");

  JsonNode problem = upload(id, "tampered".getBytes(StandardCharsets.UTF_8), 422);

  assertThat(problem.at("/code").asString()).isEqualTo("content_mismatch");
  assertThat(upload(id, expected, 200).at("/state").asString()).isEqualTo("uploaded");
  // Registration is idempotent by id: repeating it does not add a second image.
  register(draftId, expected, "camera", id);
  assertThat(count("attachments")).isEqualTo(1);
 }
}
