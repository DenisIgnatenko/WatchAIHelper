package com.aicopilot.draft;

import java.util.UUID;

/**
 * An image of a draft (spec 11). It never moves to another owner: a user message references its draft,
 * and the message's images are that draft's attachments ordered by {@code position}.
 *
 * <pre>
 *  register ─► PENDING ── bytes stored + SHA-256 ok ──► UPLOADED
 *                 │  ▲
 *  upload timeout │  │ upload again (retry)
 *                 ▼  │
 *               FAILED
 * </pre>
 */
public record Attachment(
 UUID id,
 UUID userId,
 UUID draftId,
 int position,
 Source source,
 String mimeType,
 long byteSize,
 String sha256,
 State state,
 String failureReason,
 String blobKey
) {

 public enum Source { CAMERA, PHOTO_LIBRARY }

 /**
  * Where the bytes of an image are stored. Derived from ids only, so the key of an image is known even while
  * its upload is still running (conversation deletion relies on this).
  */
 public static String blobKey(UUID userId, UUID attachmentId) {
  return userId + "/" + attachmentId;
 }

 public enum State { PENDING, UPLOADED, FAILED }
}
