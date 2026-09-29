package com.aicopilot.draft;

import com.aicopilot.common.NotFoundException;
import com.aicopilot.storage.BlobStorage;
import java.io.IOException;
import java.io.UncheckedIOException;
import java.time.Clock;
import java.util.Collection;
import java.util.List;
import java.util.Objects;
import java.util.UUID;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;

/** Draft lifecycle and read access to draft images. */
@Service
public class DraftService {

 private static final Logger log = LoggerFactory.getLogger(DraftService.class);

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

 /**
  * Cancelled Send: the frozen draft becomes the editable draft again, with its images and text (spec 26:
  * input is never silently discarded). The caller holds the lock of {@code frozen}.
  *
  * <p>If the user already started a new draft meanwhile (e.g. took more photos), the two are merged: the new
  * images go after the old ones, and the new draft disappears. Its images keep their ids, so uploads that are
  * still running complete normally.
  */
 @Transactional(propagation = Propagation.MANDATORY)
 public void reopen(Draft frozen) {
  String text = frozen.text();
  var newer = drafts.findOpen(frozen.conversationId());
  if (newer.isPresent()) {
   Draft open = drafts.lock(frozen.userId(), newer.get().id()).orElseThrow();
   attachments.moveAll(open.id(), frozen.id());
   text = mergeTexts(text, open.text());
   drafts.delete(open.id());
   log.info("Merged draftId={} into reopened draftId={}", open.id(), frozen.id());
  }
  drafts.reopen(frozen.id(), text, clock.instant());
 }

 /**
  * Locks all drafts of a conversation (new images cannot be registered meanwhile) and returns the storage keys
  * of all their images. Used right before the conversation is deleted.
  */
 @Transactional(propagation = Propagation.MANDATORY)
 public List<String> lockDraftsAndListBlobKeys(UUID userId, UUID conversationId) {
  drafts.lockAllOfConversation(conversationId);
  return attachments.idsByConversation(conversationId).stream()
   .map(id -> Attachment.blobKey(userId, id))
   .toList();
 }

 /** Best effort: the rows are already gone, a leftover file is only logged. */
 public void deleteBlobsQuietly(Collection<String> keys) {
  keys.forEach(this::deleteBlobQuietly);
 }

 public void deleteBlobQuietly(String key) {
  try {
   blobs.delete(key);
  } catch (IOException | RuntimeException e) {
   log.warn("Could not delete blob {}", key, e);
  }
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

 private static String mergeTexts(String first, String second) {
  if (first == null) {
   return second;
  }
  return second == null || Objects.equals(first, second) ? first : first + "\n" + second;
 }

 public record AttachmentCounts(int total, int uploaded, int failed) {

  public int pending() {
   return total - uploaded - failed;
  }
 }

 public record ImageData(String mimeType, byte[] bytes) {
 }
}
