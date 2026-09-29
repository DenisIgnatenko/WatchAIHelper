package com.aicopilot.conversation;

import com.aicopilot.common.NotFoundException;
import com.aicopilot.conversation.Message.Role;
import com.aicopilot.conversation.Message.SuggestedAction;
import com.aicopilot.conversation.MessageRepository.NewMessage;
import com.aicopilot.draft.DraftService;
import java.time.Clock;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.transaction.support.TransactionSynchronization;
import org.springframework.transaction.support.TransactionSynchronizationManager;

/**
 * Conversations and their message sequence. The only place that appends messages, so ordering
 * and titles are handled in one spot (SRP, DRY).
 */
@Service
public class ConversationService {

 private static final Logger log = LoggerFactory.getLogger(ConversationService.class);

 /** Length of a title derived from the first question. */
 private static final int TITLE_LENGTH = 40;
 /** Longest title a user or the AI may set (matches the API contract). */
 public static final int MAX_TITLE_LENGTH = 80;

 private final ConversationRepository conversations;
 private final MessageRepository messages;
 private final DraftService drafts;
 private final Clock clock;

 ConversationService(ConversationRepository conversations, MessageRepository messages, DraftService drafts, Clock clock) {
  this.conversations = conversations;
  this.messages = messages;
  this.drafts = drafts;
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
 public Conversation create(UUID userId, UUID conversationId, Conversation.Mode mode) {
  conversations.insertIfAbsent(conversationId, userId, Conversation.DEFAULT_TITLE, mode, clock.instant());
  Conversation conversation = get(userId, conversationId);
  conversations.setActive(userId, conversationId);
  return conversation;
 }

 @Transactional
 public void setActive(UUID userId, UUID conversationId) {
  get(userId, conversationId);
  conversations.setActive(userId, conversationId);
 }

 /** A title set by the user is final: the AI never replaces it. */
 @Transactional
 public Conversation rename(UUID userId, UUID conversationId, String title) {
  String normalized = title == null ? "" : title.strip();
  if (normalized.isEmpty() || normalized.length() > MAX_TITLE_LENGTH) {
   throw new InvalidTitle();
  }
  if (!conversations.renameByUser(userId, conversationId, normalized)) {
   throw new NotFoundException("Conversation");
  }
  return get(userId, conversationId);
 }

 /**
  * Deletes the conversation with everything in it (spec 47): messages, drafts, AI requests (database cascade)
  * and the image bytes (after commit). Idempotent.
  *
  * <p>Races: the drafts are locked before their images are listed, so an image registered concurrently either
  * waits for this transaction (and then finds no draft) or is already listed. An upload that finishes later
  * finds no row and deletes its own bytes ({@code AttachmentService.upload}).
  */
 @Transactional
 public void delete(UUID userId, UUID conversationId) {
  if (conversations.find(userId, conversationId).isEmpty()) {
   return;
  }
  conversations.lock(conversationId);
  List<String> blobKeys = drafts.lockDraftsAndListBlobKeys(userId, conversationId);
  conversations.delete(userId, conversationId);
  // The foreign key cleared the active conversation if it was this one: continue with the most recent other one.
  if (conversations.activeConversationId(userId).isEmpty()) {
   conversations.mostRecentlyUpdated(userId).ifPresent(id -> conversations.setActive(userId, id));
  }
  log.info("Deleted conversationId={} images={}", conversationId, blobKeys.size());
  // Bytes go only after the rows are really gone; a rollback must not leave messages without their images.
  TransactionSynchronizationManager.registerSynchronization(new TransactionSynchronization() {
   @Override
   public void afterCommit() {
    drafts.deleteBlobsQuietly(blobKeys);
   }
  });
 }

 /**
  * Applies the title the AI suggested with an answer, unless the conversation already has a real one
  * (set by the AI earlier or by the user). Runs in the caller's transaction.
  */
 @Transactional(propagation = Propagation.MANDATORY)
 public void suggestTitle(UUID conversationId, String title) {
  if (title == null || title.isBlank()) {
   return;
  }
  String line = title.strip().lines().findFirst().orElse("");
  conversations.applyAiTitle(conversationId, line.length() <= MAX_TITLE_LENGTH ? line : line.substring(0, MAX_TITLE_LENGTH - 1) + "…");
 }

 /** The active conversation; on first use of the app a new one is created. */
 @Transactional
 public Conversation activeOrCreate(UUID userId) {
  Optional<Conversation> active = conversations.activeConversationId(userId)
   .flatMap(id -> conversations.find(userId, id));
  return active.orElseGet(() -> create(userId, UUID.randomUUID(), Conversation.Mode.GENERAL));
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

 /** True when no message follows the given one in its conversation. */
 @Transactional(readOnly = true)
 public boolean isLastMessage(UUID conversationId, UUID messageId) {
  return messageId != null && messages.lastId(conversationId).filter(messageId::equals).isPresent();
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
  // A provisional title until the AI suggests a better one with its answer.
  conversations.renameIfDefault(conversationId, titleFrom(text, get(userId, conversationId).mode()));
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

 private static String titleFrom(String text, Conversation.Mode mode) {
  if (text == null || text.isBlank()) {
   return switch (mode) {
    case GENERAL -> "Photos";
    case DANISH_EXAM -> "Danish exam";
   };
  }
  String line = text.strip().lines().findFirst().orElse("");
  return line.length() <= TITLE_LENGTH ? line : line.substring(0, TITLE_LENGTH - 1) + "…";
 }

 /** The title is empty or longer than {@link #MAX_TITLE_LENGTH} (HTTP 400). */
 public static class InvalidTitle extends RuntimeException {

  public InvalidTitle() {
   super("The title must have 1 to " + MAX_TITLE_LENGTH + " characters");
  }
 }
}
