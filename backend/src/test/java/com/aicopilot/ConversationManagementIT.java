package com.aicopilot;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.delete;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.patch;

import com.aicopilot.TestInfrastructure.FakeAiEngine;
import com.aicopilot.draft.AttachmentService;
import java.nio.charset.StandardCharsets;
import java.nio.file.Path;
import java.util.Map;
import java.util.UUID;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.MediaType;
import tools.jackson.databind.JsonNode;

/** Titles, renaming, deletion and image retention (spec 47). */
class ConversationManagementIT extends ApiTestBase {

 @Autowired
 AttachmentService attachmentService;

 @Value("${copilot.storage.path}")
 String storagePath;

 @Test
 void aiSuggestedTitleReplacesThePlaceholderButNeverAUserTitle() throws Exception {
  String conversationId = createConversation("danishExam").at("/id").asString();
  ai.script.add(() -> FakeAiEngine.titledReply("Ответ.", "Læsning 4: julefrokost"));
  awaitTerminal(submit(home().at("/draft/id").asString(), "Hvad handler teksten om?", UUID.randomUUID(), 202)
   .at("/id").asString());
  assertThat(home().at("/activeConversation/title").asString()).isEqualTo("Læsning 4: julefrokost");

  JsonNode renamed = rename(conversationId, "  Экзамен: чтение  ", 200);
  assertThat(renamed.at("/title").asString()).isEqualTo("Экзамен: чтение");

  ai.script.add(() -> FakeAiEngine.titledReply("Ответ 2.", "Something else"));
  awaitTerminal(submit(home().at("/draft/id").asString(), "Og nummer 2?", UUID.randomUUID(), 202).at("/id").asString());
  assertThat(home().at("/activeConversation/title").asString()).isEqualTo("Экзамен: чтение");
 }

 @Test
 void photoOnlyExamConversationGetsAReadablePlaceholder() throws Exception {
  createConversation("danishExam");
  String draftId = home().at("/draft/id").asString();
  byte[] page = "page".getBytes(StandardCharsets.UTF_8);
  upload(register(draftId, page, "camera"), page, 200);

  awaitTerminal(submitWithoutText(draftId, 202).at("/id").asString());

  // The fake AI suggests no title, so the placeholder stays.
  assertThat(home().at("/activeConversation/title").asString()).isEqualTo("Danish exam");
 }

 @Test
 void renameRejectsBlankTitle() throws Exception {
  String conversationId = home().at("/activeConversation/id").asString();
  assertThat(rename(conversationId, "   ", 400).at("/code").asString()).isEqualTo("invalid_title");
 }

 @Test
 void deleteRemovesContentAndImagesButKeepsTheCostRecord() throws Exception {
  String older = home().at("/activeConversation/id").asString();
  String deleted = createConversation("general").at("/id").asString();
  String draftId = home().at("/draft/id").asString();
  byte[] page = "secret page".getBytes(StandardCharsets.UTF_8);
  String attachmentId = register(draftId, page, "camera");
  upload(attachmentId, page, 200);
  awaitTerminal(submitWithoutText(draftId, 202).at("/id").asString());
  Path blob = blobPath(attachmentId);
  assertThat(blob).exists();

  int status = mvc.perform(authorized(delete("/v1/conversations/{id}", deleted))).andReturn().getResponse().getStatus();

  assertThat(status).isEqualTo(204);
  assertThat(count("conversations where id = '" + deleted + "'")).isZero();
  assertThat(count("messages")).isZero();
  assertThat(count("attachments")).isZero();
  assertThat(count("ai_requests")).isZero();
  assertThat(blob).doesNotExist();
  assertThat(count("ai_usage")).isEqualTo(1);
  // It was active: the remaining conversation takes over.
  assertThat(home().at("/activeConversation/id").asString()).isEqualTo(older);
  // Idempotent.
  assertThat(mvc.perform(authorized(delete("/v1/conversations/{id}", deleted))).andReturn().getResponse().getStatus())
   .isEqualTo(204);
 }

 @Test
 void retentionDeletesOldImageBytesButKeepsTheMessage() throws Exception {
  String conversationId = home().at("/activeConversation/id").asString();
  String draftId = home().at("/draft/id").asString();
  byte[] page = "old page".getBytes(StandardCharsets.UTF_8);
  String attachmentId = register(draftId, page, "camera");
  upload(attachmentId, page, 200);
  awaitTerminal(submitWithoutText(draftId, 202).at("/id").asString());
  jdbc.sql("update attachments set uploaded_at = now() - interval '31 days'").update();

  attachmentService.purgeExpiredImages();

  assertThat(blobPath(attachmentId)).doesNotExist();
  assertThat(count("attachments where blob_key is null and purged_at is not null")).isEqualTo(1);
  assertThat(messages(conversationId).get(0).at("/attachmentCount").asInt()).isEqualTo(1);
 }

 @Test
 void retentionKeepsRecentImages() throws Exception {
  String draftId = home().at("/draft/id").asString();
  byte[] page = "new page".getBytes(StandardCharsets.UTF_8);
  String attachmentId = register(draftId, page, "camera");
  upload(attachmentId, page, 200);

  attachmentService.purgeExpiredImages();

  assertThat(blobPath(attachmentId)).exists();
 }

 private JsonNode rename(String conversationId, String title, int expectedStatus) throws Exception {
  var result = mvc.perform(authorized(patch("/v1/conversations/{id}", conversationId))
    .contentType(MediaType.APPLICATION_JSON)
    .content(json.writeValueAsString(Map.of("title", title))))
   .andReturn();
  return body(result, expectedStatus);
 }

 private Path blobPath(String attachmentId) {
  UUID userId = jdbc.sql("select id from users").query(UUID.class).single();
  return Path.of(storagePath, userId.toString(), attachmentId);
 }
}
