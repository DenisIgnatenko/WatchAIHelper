package com.aicopilot;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;

import java.util.Map;
import java.util.UUID;
import org.junit.jupiter.api.Test;
import org.springframework.http.MediaType;
import tools.jackson.databind.JsonNode;

/** The conversation type decides the AI's instructions and study materials (ResponseMode, spec 34). */
class ConversationModeIT extends ApiTestBase {

 @Test
 void danishExamConversationGetsGuideAndMaterials() throws Exception {
  JsonNode conversation = createConversation("danishExam");
  assertThat(conversation.at("/mode").asString()).isEqualTo("danishExam");

  awaitTerminal(submit(home().at("/draft/id").asString(), "Hvor mange ord skal jeg skrive?", UUID.randomUUID(), 202)
   .at("/id").asString());

  String instructions = ai.calls.getFirst().instructions();
  assertThat(instructions).contains("Always answer in Russian");      // base Watch rules
  assertThat(instructions).contains("Modul 3 (test 3.3)");            // exam guide
  assertThat(instructions).contains("MARKER-DU3-MATERIALS");          // knowledge pack
 }

 @Test
 void generalConversationHasNoExamMaterials() throws Exception {
  JsonNode conversation = createConversation("general");
  assertThat(conversation.at("/mode").asString()).isEqualTo("general");

  awaitTerminal(submit(home().at("/draft/id").asString(), "why kafka?", UUID.randomUUID(), 202).at("/id").asString());

  assertThat(ai.calls.getFirst().instructions()).doesNotContain("MARKER-DU3-MATERIALS").doesNotContain("Modul 3");
 }

 @Test
 void modeDefaultsToGeneral() throws Exception {
  var result = mvc.perform(authorized(post("/v1/conversations"))
    .contentType(MediaType.APPLICATION_JSON)
    .content(json.writeValueAsString(Map.of("id", UUID.randomUUID().toString()))))
   .andReturn();
  assertThat(body(result, 201).at("/mode").asString()).isEqualTo("general");
 }
}
