package com.aicopilot.ai;

import com.aicopilot.ai.AiEngine.AiContext;
import com.aicopilot.ai.AiEngine.Turn;
import com.aicopilot.config.CopilotProperties;
import com.aicopilot.conversation.ConversationService;
import com.aicopilot.conversation.Message;
import java.io.IOException;
import java.io.UncheckedIOException;
import java.nio.charset.StandardCharsets;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.concurrent.ConcurrentHashMap;
import org.springframework.core.io.ClassPathResource;
import org.springframework.stereotype.Component;

/**
 * Builds the model input from the backend's conversation history (the backend owns context, spec 32).
 * Clients never send history; a follow-up like "Почему 4 B?" works because the earlier turns come from here.
 */
@Component
public class ContextBuilder {

 /**
  * Applied to image-only messages at inference time only, never at upload (spec 28).
  * Used from Phase 3, when messages can have images and no text.
  */
 static final String DEFAULT_IMAGE_INSTRUCTION = """
  Analyze the attached images in their given order and in the context of the current conversation. \
  Identify what the user is working on and provide the most useful concise response. \
  If the images contain questions or exercises, answer them clearly and preserve their numbering.""";

 private final ConversationService conversations;
 private final CopilotProperties properties;
 private final Map<ResponseMode, String> promptCache = new ConcurrentHashMap<>();

 ContextBuilder(ConversationService conversations, CopilotProperties properties) {
  this.conversations = conversations;
  this.properties = properties;
 }

 /**
  * @param userMessageId the message being answered; later messages (if any) are not included
  */
 public AiContext build(UUID conversationId, UUID userMessageId, ResponseMode mode) {
  Message question = conversations.message(userMessageId);
  List<Message> recent = conversations.recentMessages(
   conversationId, question.seq(), properties.processing().contextMessages());
  List<Turn> turns = recent.stream().map(ContextBuilder::toTurn).toList();
  return new AiContext(instructions(mode), turns);
 }

 private static Turn toTurn(Message message) {
  return switch (message.role()) {
   case USER -> new Turn(Turn.Role.USER, message.text() != null ? message.text() : DEFAULT_IMAGE_INSTRUCTION);
   case ASSISTANT -> new Turn(Turn.Role.ASSISTANT, message.text());
  };
 }

 private String instructions(ResponseMode mode) {
  return promptCache.computeIfAbsent(mode, m -> {
   try {
    return new ClassPathResource(m.promptResource()).getContentAsString(StandardCharsets.UTF_8);
   } catch (IOException e) {
    throw new UncheckedIOException("Missing prompt " + m.promptResource(), e);
   }
  });
 }
}
