package com.aicopilot.storage;

import java.io.IOException;
import java.io.InputStream;

/**
 * Storage for image bytes (spec 48: not in database rows).
 *
 * <p>Dependency Inversion with a known second implementation: local disk now (a Docker volume on the VM),
 * S3 later - without touching drafts, submissions or the AI code.
 */
public interface BlobStorage {

 /**
  * Stores the stream under {@code key}, replacing any previous content atomically
  * (a reader never sees a half-written file). Reads at most {@code maxBytes + 1} bytes.
  *
  * @return size and SHA-256 of what was actually stored, for verification by the caller
  */
 StoredBlob put(String key, InputStream content, long maxBytes) throws IOException;

 byte[] read(String key) throws IOException;

 /** Idempotent: deleting a missing key is not an error. */
 void delete(String key) throws IOException;

 /** @param tooLarge true when the stream had more than {@code maxBytes} bytes (the blob is then not stored) */
 record StoredBlob(long size, String sha256, boolean tooLarge) {
 }
}
