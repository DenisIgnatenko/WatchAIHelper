package com.aicopilot.draft;

/** Business errors of drafts and attachments, mapped to HTTP problems by the API layer. */
public final class DraftErrors {

 private DraftErrors() {
 }

 /** The draft was already sent; its content is immutable (HTTP 409). */
 public static class DraftNotEditable extends RuntimeException {

  public DraftNotEditable() {
   super("The draft is no longer editable");
  }
 }

 /** The client reused an attachment id for another draft (HTTP 409). */
 public static class AttachmentConflict extends RuntimeException {

  public AttachmentConflict() {
   super("The attachment id belongs to another draft");
  }
 }

 /** Uploaded bytes do not match the registered size or SHA-256 (HTTP 422). */
 public static class ContentMismatch extends RuntimeException {

  public ContentMismatch() {
   super("Uploaded content does not match the registered size or SHA-256");
  }
 }
}
