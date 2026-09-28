package com.aicopilot.draft;

import com.aicopilot.common.NotFoundException;
import com.aicopilot.storage.BlobStorage;
import java.io.IOException;
import java.io.UncheckedIOException;
import java.time.Clock;
import java.util.List;
import java.util.UUID;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;

/** Draft lifecycle and read access to draft images. */
@Service
public class DraftService {

 private final DraftRepository drafts;
 private final AttachmentRepository attachments;
 private final BlobStorage blobs;
 private final Clock clock;

 DraftService(DraftRepository drafts, AttachmentRepository attachments, BlobStorage blobs, Clock clock) {
  this.drafts = drafts;
  this.attachments = attachments;
  this.blobs = blobs;
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

 public Draft get(UUID draftId) {
  return drafts.find(draftId).orElseThrow(() -> new NotFoundException("Draft"));
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

 public AttachmentCounts attachmentCounts(UUID draftId) {
  AttachmentRepository.Counts counts = attachments.counts(draftId);
  return new AttachmentCounts(counts.total(), counts.uploaded(), counts.failed());
 }

 public List<Attachment> attachments(UUID draftId) {
  return attachments.listByDraft(draftId);
 }

 /**
  * Bytes of the uploaded images of a draft, in message order (spec 27). Used only at inference time.
  * Images whose bytes were purged by retention are skipped.
  */
 public List<ImageData> images(UUID draftId) {
  return attachments.listByDraft(draftId).stream()
   .filter(a -> a.state() == Attachment.State.UPLOADED && a.blobKey() != null)
   .map(a -> new ImageData(a.mimeType(), read(a.blobKey())))
   .toList();
 }

 private byte[] read(String key) {
  try {
   return blobs.read(key);
  } catch (IOException e) {
   throw new UncheckedIOException("Cannot read image " + key, e);
  }
 }

 public record AttachmentCounts(int total, int uploaded, int failed) {

  public int pending() {
   return total - uploaded - failed;
  }
 }

 public record ImageData(String mimeType, byte[] bytes) {
 }
}
