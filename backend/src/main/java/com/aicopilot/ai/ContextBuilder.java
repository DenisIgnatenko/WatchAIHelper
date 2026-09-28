package com.aicopilot.ai;

import com.aicopilot.ai.AiEngine.AiContext;
import com.aicopilot.ai.AiEngine.Turn;
import com.aicopilot.config.CopilotProperties;
import com.aicopilot.conversation.ConversationService;
import com.aicopilot.conversation.Message;
import com.aicopilot.draft.DraftService;
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
  */
 static final String DEFAULT_IMAGE_INSTRUCTION = """
  Analyze the attached images in their given order and in the context of the current conversation. \
  Identify what the user is working on and provide the most useful concise response. \
  If the images contain questions or exercises, answer them clearly and preserve their numbering.""";

 private final ConversationService conversations;
 private final DraftService drafts;
 private final CopilotProperties properties;
 private final KnowledgeLibrary knowledge;
 private final Map<ResponseMode, String> promptCache = new ConcurrentHashMap<>();

 ContextBuilder(ConversationService conversations, DraftService drafts, CopilotProperties properties,
  KnowledgeLibrary knowledge) {
  this.conversations = conversations;
  this.drafts = drafts;
  this.properties = properties;
  this.knowledge = knowledge;
 }

 /**
  * @param userMessageId the message being answered; later messages (if any) are not included
  */
 public AiContext build(UUID conversationId, UUID userMessageId, ResponseMode mode) {
  Message question = conversations.message(userMessageId);
  List<Message> recent = conversations.recentMessages(
   conversationId, question.seq(), properties.processing().contextMessages());

  // Newest messages keep their images first: the question being answered always has all of its images;
  // when the budget is exhausted, older images are replaced by a short note (keeps cost and latency bounded).
  int imageBudget = properties.processing().contextImages();
  Turn[] turns = new Turn[recent.size()];
  for (int i = recent.size() - 1; i >= 0; i--) {
   Message message = recent.get(i);
   boolean isQuestion = message.id().equals(userMessageId);
   List<AiEngine.Image> images = List.of();
   String note = null;
   if (message.role() == Message.Role.USER && message.attachmentCount() > 0) {
    if (isQuestion || message.attachmentCount() <= imageBudget) {
     images = drafts.images(message.draftId()).stream()
      .map(image -> new AiEngine.Image(image.mimeType(), image.bytes()))
      .toList();
     imageBudget = Math.max(0, imageBudget - images.size());
     if (images.size() < message.attachmentCount()) {
      note = "[" + (message.attachmentCount() - images.size()) + " image(s) of this message are no longer available]";
     }
    } else {
     note = "[" + message.attachmentCount() + " earlier image(s) omitted]";
    }
   }
   turns[i] = toTurn(message, images, note);
  }
  return new AiContext(instructions(mode), List.of(turns));
 }

 private static Turn toTurn(Message message, List<AiEngine.Image> images, String note) {
  return switch (message.role()) {
   case USER -> {
    String text = message.text() != null ? message.text()
     : message.attachmentCount() > 0 ? DEFAULT_IMAGE_INSTRUCTION : "";
    yield new Turn(Turn.Role.USER, note == null ? text : note + "\n" + text, images);
   }
   case ASSISTANT -> new Turn(Turn.Role.ASSISTANT, message.text());
  };
 }

 /**
  * Instruction files of the mode, then its knowledge pack. The result is identical for every request of the
  * mode, so it forms a stable prefix that OpenAI caches (prompt caching) - keep dynamic data out of it.
  */
 private String instructions(ResponseMode mode) {
  return promptCache.computeIfAbsent(mode, m -> {
   StringBuilder text = new StringBuilder();
   for (String resource : m.promptResources()) {
    try {
     text.append(new ClassPathResource(resource).getContentAsString(StandardCharsets.UTF_8)).append("\n");
    } catch (IOException e) {
     throw new UncheckedIOException("Missing prompt " + resource, e);
    }
   }
   m.knowledgePack().flatMap(knowledge::pack).ifPresent(pack -> text.append("\n").append(pack));
   return text.toString();
  });
 }
}
