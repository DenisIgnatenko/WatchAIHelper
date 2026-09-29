package com.aicopilot.submission;

import com.aicopilot.ai.ResponseMode;
import com.aicopilot.common.NotFoundException;
import com.aicopilot.conversation.Conversation;
import com.aicopilot.conversation.ConversationService;
import com.aicopilot.draft.AttachmentsChangedEvent;
import com.aicopilot.draft.Draft;
import com.aicopilot.draft.DraftService;
import com.aicopilot.draft.DraftService.AttachmentCounts;
import com.aicopilot.submission.SubmissionErrors.DraftAlreadySubmitted;
import com.aicopilot.submission.SubmissionErrors.EmptyDraft;
import com.aicopilot.submission.SubmissionErrors.RequestNotCancellable;
import com.aicopilot.submission.SubmissionErrors.RequestNotRetryable;
import java.time.Clock;
import java.util.Optional;
import java.util.UUID;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.context.ApplicationEventPublisher;
import org.springframework.context.event.EventListener;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;

/**
 * Explicit Send: the only entry point that starts AI inference (Invariant 5, spec 25, 50).
 *
 * <p>Guarantees (spec 37):
 * <ul>
 *  <li>same idempotency key again -> the same request, nothing new is created;</li>
 *  <li>two Sends of one draft with different keys -> exactly one wins (draft row lock + unique draft_id);</li>
 *  <li>the user message exists only when all attachments are available (Invariant 6).</li>
 * </ul>
 */
@Service
public class SubmissionService {

 private static final Logger log = LoggerFactory.getLogger(SubmissionService.class);

 private final DraftService drafts;
 private final ConversationService conversations;
 private final AiRequestRepository requests;
 private final ApplicationEventPublisher events;
 private final Clock clock;

 SubmissionService(DraftService drafts, ConversationService conversations, AiRequestRepository requests,
  ApplicationEventPublisher events, Clock clock) {
  this.drafts = drafts;
  this.conversations = conversations;
  this.requests = requests;
  this.events = events;
  this.clock = clock;
 }

 @Transactional
 public AiRequest submit(UUID userId, UUID draftId, String text, UUID idempotencyKey) {
  // 1. Lock first: concurrent submits of this draft wait here one by one.
  Draft draft = drafts.lock(userId, draftId);

  // 2. Replay of the same action (network retry) -> same answer.
  Optional<AiRequest> replay = requests.findByIdempotencyKey(userId, idempotencyKey);
  if (replay.isPresent()) {
   return replay.get();
  }

  // 3. Already sent by another action (e.g. the other device).
  if (draft.state() != Draft.State.OPEN) {
   throw new DraftAlreadySubmitted();
  }

  // 4. Validate content. Text is optional when there are attachments (spec 28).
  String normalizedText = normalize(text);
  if (normalizedText == null && drafts.attachmentCounts(draftId).total() == 0) {
   throw new EmptyDraft();
  }

  // 5. Freeze the draft and record the request.
  drafts.freeze(draftId, normalizedText);
  UUID requestId = UUID.randomUUID();
  requests.insertWaiting(requestId, userId, draft.conversationId(), draftId, idempotencyKey,
   responseMode(conversations.get(userId, draft.conversationId()).mode()), clock.instant());
  log.info("Submitted draftId={} aiRequestId={} conversationId={}", draftId, requestId, draft.conversationId());

  // 6. Start at once if nothing is missing; otherwise the upload that completes the set will do it.
  reevaluate(requests.find(requestId).orElseThrow(), drafts.get(draftId));
  return requests.find(requestId).orElseThrow();
 }

 /**
  * A waiting Send reacts to image changes (upload finished, upload failed, image removed).
  * Runs synchronously inside the transaction that changed the images.
  */
 @EventListener
 @Transactional(propagation = Propagation.MANDATORY)
 public void onAttachmentsChanged(AttachmentsChangedEvent event) {
  requests.findByDraft(event.draftId())
   .filter(r -> r.state() == AiRequest.State.WAITING_FOR_ATTACHMENTS || r.state() == AiRequest.State.BLOCKED)
   .flatMap(r -> requests.lock(r.id()))
   .ifPresent(r -> reevaluate(r, drafts.get(event.draftId())));
 }

 /**
  * Cancel Send (spec 26): possible while the request still waits for its images, i.e. before the question became
  * a message. The request becomes CANCELLED and the draft editable again with its photos and text, so the user can
  * fix the images and press Send again. Idempotent.
  *
  * <p>Lock order is the same as in submit (draft, then request), so a concurrent upload or Send cannot deadlock.
  */
 @Transactional
 public AiRequest cancel(UUID userId, UUID requestId) {
  AiRequest request = get(userId, requestId);
  Draft draft = drafts.lock(userId, request.draftId());
  AiRequest current = requests.lock(requestId).orElseThrow();
  switch (current.state()) {
   case CANCELLED -> {
    return current;
   }
   case WAITING_FOR_ATTACHMENTS, BLOCKED -> {
    requests.markCancelled(requestId, clock.instant());
    drafts.reopen(draft);
    log.info("Cancelled aiRequestId={} draftId={}", requestId, draft.id());
    return requests.find(requestId).orElseThrow();
   }
   default -> throw new RequestNotCancellable();
  }
 }

 /**
  * Retry after a failed answer: the same question is queued again, no new message is created (spec 26, 37).
  * Only for the latest question of the conversation, so the new answer lands right after its question.
  * Idempotent: a request that is already queued, processing or completed is returned unchanged.
  */
 @Transactional
 public AiRequest retry(UUID userId, UUID requestId) {
  get(userId, requestId);
  AiRequest current = requests.lock(requestId).orElseThrow();
  switch (current.state()) {
   case QUEUED, PROCESSING, COMPLETED -> {
    return current;
   }
   case FAILED -> {
    if (!conversations.isLastMessage(current.conversationId(), current.userMessageId())) {
     throw new RequestNotRetryable("Newer messages exist; ask the question again instead");
    }
    requests.requeueFailed(requestId, clock.instant());
    log.info("Retry aiRequestId={} after {}", requestId, current.lastErrorCode());
    events.publishEvent(new RequestQueuedEvent(requestId));
    return requests.find(requestId).orElseThrow();
   }
   default -> throw new RequestNotRetryable("The request did not fail");
  }
 }

 @Transactional(readOnly = true)
 public AiRequest get(UUID userId, UUID requestId) {
  return requests.findForUser(userId, requestId).orElseThrow(() -> new NotFoundException("Request"));
 }

 @Transactional(readOnly = true)
 public Optional<AiRequest> latestForConversation(UUID conversationId) {
  return requests.latestForConversation(conversationId);
 }

 /**
  * The request state machine around images (docs/architecture.md, section 9):
  * <ul>
  *  <li>any image FAILED -> BLOCKED (never continue without it, Invariant 6);</li>
  *  <li>some still uploading -> WAITING_FOR_ATTACHMENTS;</li>
  *  <li>all uploaded -> QUEUED, atomically with creating the user message and consuming the draft.</li>
  * </ul>
  */
 private void reevaluate(AiRequest request, Draft draft) {
  AttachmentCounts attachments = drafts.attachmentCounts(draft.id());
  if (attachments.failed() > 0) {
   requests.markBlocked(request.id(), clock.instant());
   return;
  }
  if (attachments.pending() > 0) {
   requests.markWaiting(request.id(), clock.instant());
   return;
  }
  UUID messageId = conversations.appendUserMessage(draft.userId(), draft.conversationId(), draft.text(), draft.id(),
   request.id());
  drafts.consume(draft.id());
  requests.markQueued(request.id(), messageId, clock.instant());
  log.info("Queued aiRequestId={} images={}", request.id(), attachments.total());
  events.publishEvent(new RequestQueuedEvent(request.id()));
 }

 /** The conversation type decides how the AI answers (and which study materials it gets). */
 private static ResponseMode responseMode(Conversation.Mode mode) {
  return switch (mode) {
   case GENERAL -> ResponseMode.WATCH_CONCISE;
   case DANISH_EXAM -> ResponseMode.DANISH_EXAM;
  };
 }

 private static String normalize(String text) {
  if (text == null) {
   return null;
  }
  String stripped = text.strip();
  return stripped.isEmpty() ? null : stripped;
 }
}
