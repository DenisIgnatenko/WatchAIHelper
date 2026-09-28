package com.aicopilot.draft;

import com.aicopilot.common.NotFoundException;
import com.aicopilot.config.CopilotProperties;
import com.aicopilot.storage.BlobStorage;
import com.aicopilot.storage.BlobStorage.StoredBlob;
import java.io.IOException;
import java.io.InputStream;
import java.io.UncheckedIOException;
import java.time.Clock;
import java.util.List;
import java.util.Objects;
import java.util.UUID;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.context.ApplicationEventPublisher;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Service;
import org.springframework.transaction.support.TransactionTemplate;

/**
 * Images of drafts: register, upload, remove, and the upload timeout (docs/architecture.md, section 8).
 *
 * <p>Invariant 2/5: nothing here starts AI inference. When the set of images changes, an
 * {@link AttachmentsChangedEvent} is published; the submission side decides whether a Send that is
 * already waiting can now proceed (or must be blocked). Events keep the draft package independent
 * of the submission package (no cyclic dependency).
 */
@Service
public class AttachmentService {

 private static final Logger log = LoggerFactory.getLogger(AttachmentService.class);

 private final AttachmentRepository attachments;
 private final DraftService drafts;
 private final BlobStorage blobs;
 private final ApplicationEventPublisher events;
 private final TransactionTemplate tx;
 private final CopilotProperties properties;
 private final Clock clock;

 AttachmentService(AttachmentRepository attachments, DraftService drafts, BlobStorage blobs,
  ApplicationEventPublisher events, TransactionTemplate tx, CopilotProperties properties, Clock clock) {
  this.attachments = attachments;
  this.drafts = drafts;
  this.blobs = blobs;
  this.events = events;
  this.tx = tx;
  this.properties = properties;
  this.clock = clock;
 }

 /** Step 1: metadata only. Idempotent by the client-generated id. Position = registration order. */
 public Attachment register(UUID userId, UUID draftId, UUID attachmentId, NewAttachment request) {
  return tx.execute(status -> {
   Draft draft = drafts.lock(userId, draftId);
   var existing = attachments.find(userId, attachmentId);
   if (existing.isPresent()) {
    if (!existing.get().draftId().equals(draftId)) {
     throw new DraftErrors.AttachmentConflict();
    }
    return existing.get();
   }
   if (draft.state() != Draft.State.OPEN) {
    // Immutability (spec 8): new content after Send belongs to a new draft.
    throw new DraftErrors.DraftNotEditable();
   }
   Attachment attachment = new Attachment(attachmentId, userId, draftId, attachments.nextPosition(draftId),
    request.source(), request.mimeType(), request.byteSize(), request.sha256(), Attachment.State.PENDING, null, null);
   attachments.insert(attachment, request.width(), request.height(), clock.instant());
   log.info("Registered attachmentId={} draftId={} position={}", attachmentId, draftId, attachment.position());
   events.publishEvent(new AttachmentsChangedEvent(draftId));
   return attachment;
  });
 }

 /**
  * Step 2: the bytes. They are streamed to storage OUTSIDE any transaction (no row lock is held during a slow
  * mobile upload), verified against the registration, and only then marked UPLOADED in a short transaction.
  */
 public Attachment upload(UUID userId, UUID attachmentId, InputStream content) {
  Attachment attachment = attachments.find(userId, attachmentId).orElseThrow(() -> new NotFoundException("Attachment"));
  if (attachment.state() == Attachment.State.UPLOADED) {
   return attachment;
  }
  if (drafts.get(attachment.draftId()).state() == Draft.State.CONSUMED) {
   throw new DraftErrors.DraftNotEditable();
  }
  String key = userId + "/" + attachmentId;
  StoredBlob stored = store(key, content, attachment.byteSize());
  if (stored.tooLarge() || stored.size() != attachment.byteSize() || !Objects.equals(stored.sha256(), attachment.sha256())) {
   deleteQuietly(key);
   throw new DraftErrors.ContentMismatch();
  }
  Attachment result = tx.execute(status -> {
   var current = attachments.lock(attachmentId);
   if (current.isEmpty()) {
    // Removed while the bytes were uploading.
    throw new DraftErrors.DraftNotEditable();
   }
   attachments.markUploaded(attachmentId, key, clock.instant());
   events.publishEvent(new AttachmentsChangedEvent(attachment.draftId()));
   return attachments.lock(attachmentId).orElseThrow();
  });
  log.info("Uploaded attachmentId={} draftId={} bytes={}", attachmentId, attachment.draftId(), stored.size());
  return result;
 }

 /** Only from an editable draft. Idempotent: removing a missing image is fine. */
 public void remove(UUID userId, UUID draftId, UUID attachmentId) {
  String blobKey = tx.execute(status -> {
   Draft draft = drafts.lock(userId, draftId);
   if (draft.state() != Draft.State.OPEN) {
    throw new DraftErrors.DraftNotEditable();
   }
   var attachment = attachments.find(userId, attachmentId).filter(a -> a.draftId().equals(draftId));
   if (attachment.isEmpty()) {
    return null;
   }
   attachments.delete(attachmentId);
   events.publishEvent(new AttachmentsChangedEvent(draftId));
   return attachment.get().blobKey();
  });
  if (blobKey != null) {
   deleteQuietly(blobKey);
  }
 }

 public DraftDetail detail(UUID userId, UUID conversationId) {
  Draft draft = drafts.currentDraft(userId, conversationId);
  return new DraftDetail(draft, attachments.listByDraft(draft.id()));
 }

 /**
  * Images whose bytes never arrive (e.g. the iPhone app was force-quit, which cancels background uploads)
  * become FAILED, so a waiting Send is blocked instead of waiting forever - and never proceeds without them
  * (Invariant 6).
  */
 @Scheduled(fixedDelayString = "PT1M")
 public void failStaleUploads() {
  var olderThan = clock.instant().minus(properties.attachments().uploadTimeout());
  tx.executeWithoutResult(status -> {
   List<UUID> affected = attachments.failStalePending(olderThan);
   affected.forEach(draftId -> events.publishEvent(new AttachmentsChangedEvent(draftId)));
   if (!affected.isEmpty()) {
    log.warn("Upload timeout: marked attachments FAILED in drafts {}", affected);
   }
  });
 }

 private StoredBlob store(String key, InputStream content, long expectedSize) {
  try {
   return blobs.put(key, content, expectedSize);
  } catch (IOException e) {
   throw new UncheckedIOException("Storing " + key + " failed", e);
  }
 }

 private void deleteQuietly(String key) {
  try {
   blobs.delete(key);
  } catch (IOException e) {
   log.warn("Could not delete blob {}", key, e);
  }
 }

 public record NewAttachment(Attachment.Source source, String mimeType, long byteSize, String sha256,
  Integer width, Integer height) {
 }

 public record DraftDetail(Draft draft, List<Attachment> attachments) {
 }
}
