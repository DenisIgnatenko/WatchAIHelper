package com.aicopilot.draft;

import com.aicopilot.common.NotFoundException;
import java.time.Clock;
import java.util.UUID;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;

/** Draft lifecycle. Attachments arrive in Phase 3; until then every draft has zero of them. */
@Service
public class DraftService {

 private final DraftRepository drafts;
 private final Clock clock;

 DraftService(DraftRepository drafts, Clock clock) {
  this.drafts = drafts;
  this.clock = clock;
 }

 /** The editable draft of a conversation, created lazily (the backend always has one ready). */
 @Transactional
 public Draft currentDraft(UUID userId, UUID conversationId) {
  return drafts.findOpen(conversationId).orElseGet(() -> {
   drafts.insertOpenIfAbsent(UUID.randomUUID(), userId, conversationId, clock.instant());
   return drafts.findOpen(conversationId).orElseThrow();
  });
 }

 /** Locks the draft for a state transition; the caller's transaction owns the lock. */
 @Transactional(propagation = Propagation.MANDATORY)
 public Draft lock(UUID userId, UUID draftId) {
  return drafts.lock(userId, draftId).orElseThrow(() -> new NotFoundException("Draft"));
 }

 @Transactional(propagation = Propagation.MANDATORY)
 public void freeze(UUID draftId, String text) {
  drafts.freeze(draftId, text, clock.instant());
 }

 @Transactional(propagation = Propagation.MANDATORY)
 public void consume(UUID draftId) {
  drafts.consume(draftId, clock.instant());
 }

 /** Attachment counters of a draft (Phase 3 will read them from the attachments table). */
 public AttachmentCounts attachmentCounts(UUID draftId) {
  return AttachmentCounts.NONE;
 }

 public record AttachmentCounts(int total, int uploaded, int failed) {

  static final AttachmentCounts NONE = new AttachmentCounts(0, 0, 0);

  public int pending() {
   return total - uploaded - failed;
  }
 }
}
