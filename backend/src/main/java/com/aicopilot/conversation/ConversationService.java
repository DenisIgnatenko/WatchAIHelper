package com.aicopilot.conversation;

import com.aicopilot.common.NotFoundException;
import com.aicopilot.conversation.Message.Role;
import com.aicopilot.conversation.Message.SuggestedAction;
import com.aicopilot.conversation.MessageRepository.NewMessage;
import java.time.Clock;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;

/**
 * Conversations and their message sequence. The only place that appends messages, so ordering
 * and titles are handled in one spot (SRP, DRY).
 */
@Service
public class ConversationService {

 private static final int TITLE_LENGTH = 40;

 private final ConversationRepository conversations;
 private final MessageRepository messages;
 private final Clock clock;

 ConversationService(ConversationRepository conversations, MessageRepository messages, Clock clock) {
  this.conversations = conversations;
  this.messages = messages;
  this.clock = clock;
 }

 @Transactional(readOnly = true)
 public List<Conversation> list(UUID userId) {
  return conversations.listByUser(userId);
 }

 @Transactional(readOnly = true)
 public Conversation get(UUID userId, UUID conversationId) {
  return conversations.find(userId, conversationId).orElseThrow(() -> new NotFoundException("Conversation"));
 }

 /** Creates (idempotently by id) and makes it active on all devices. */
 @Transactional
 public Conversation create(UUID userId, UUID conversationId) {
  conversations.insertIfAbsent(conversationId, userId, Conversation.DEFAULT_TITLE, clock.instant());
  Conversation conversation = get(userId, conversationId);
  conversations.setActive(userId, conversationId);
  return conversation;
 }

 @Transactional
 public void setActive(UUID userId, UUID conversationId) {
  get(userId, conversationId);
  conversations.setActive(userId, conversationId);
 }

 /** The active conversation; on first use of the app a new one is created. */
 @Transactional
 public Conversation activeOrCreate(UUID userId) {
  Optional<Conversation> active = conversations.activeConversationId(userId)
   .flatMap(id -> conversations.find(userId, id));
  return active.orElseGet(() -> create(userId, UUID.randomUUID()));
 }

 @Transactional(readOnly = true)
 public List<Message> messages(UUID userId, UUID conversationId) {
  get(userId, conversationId);
  return messages.listByConversation(conversationId);
 }

 @Transactional(readOnly = true)
 public Optional<Message> lastAnswer(UUID conversationId) {
  return messages.lastAssistant(conversationId);
 }

 @Transactional(readOnly = true)
 public Message message(UUID messageId) {
  return messages.find(messageId).orElseThrow(() -> new NotFoundException("Message"));
 }

 /** Context window for the AI: recent messages up to and including {@code upToSeq}. */
 @Transactional(readOnly = true)
 public List<Message> recentMessages(UUID conversationId, int upToSeq, int limit) {
  return messages.recent(conversationId, upToSeq, limit);
 }

 /**
  * Appends the user message created from a submitted draft. Must run inside the caller's transaction
  * ({@link Propagation#MANDATORY}), so draft consumption and message creation are atomic (spec 25).
  */
 @Transactional(propagation = Propagation.MANDATORY)
 public UUID appendUserMessage(UUID userId, UUID conversationId, String text, UUID draftId, UUID aiRequestId) {
  UUID id = UUID.randomUUID();
  append(new NewMessage(id, userId, conversationId, 0, Role.USER, text, draftId, aiRequestId,
   List.of(), null, null, null, clock.instant()));
  conversations.renameIfDefault(conversationId, titleFrom(text));
  return id;
 }

 /** Appends an assistant answer; must run inside the caller's transaction. */
 @Transactional(propagation = Propagation.MANDATORY)
 public UUID appendAssistantMessage(
  UUID userId, UUID conversationId, UUID aiRequestId, String text, List<SuggestedAction> actions,
  String responseMode, String model, String usageJson
 ) {
  UUID id = UUID.randomUUID();
  append(new NewMessage(id, userId, conversationId, 0, Role.ASSISTANT, text, null, aiRequestId,
   actions, responseMode, model, usageJson, clock.instant()));
  return id;
 }

 /** Locks the conversation, assigns the next seq and inserts. */
 private void append(NewMessage message) {
  conversations.lock(message.conversationId());
  int seq = messages.nextSeq(message.conversationId());
  messages.insert(new NewMessage(message.id(), message.userId(), message.conversationId(), seq, message.role(),
   message.text(), message.draftId(), message.aiRequestId(), message.suggestedActions(),
   message.responseMode(), message.model(), message.usageJson(), message.createdAt()));
  conversations.touch(message.conversationId(), message.createdAt());
 }

 private static String titleFrom(String text) {
  if (text == null || text.isBlank()) {
   return "Photos";
  }
  String line = text.strip().lines().findFirst().orElse("");
  return line.length() <= TITLE_LENGTH ? line : line.substring(0, TITLE_LENGTH - 1) + "…";
 }
}
