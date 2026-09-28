package com.aicopilot.submission;

/** Business errors of Send, mapped to HTTP problems by the API layer. */
public final class SubmissionErrors {

 private SubmissionErrors() {
 }

 /** The draft was already sent with another idempotency key (HTTP 409). */
 public static class DraftAlreadySubmitted extends RuntimeException {

  public DraftAlreadySubmitted() {
   super("The draft was already submitted");
  }
 }

 /** Neither text nor attachments (HTTP 422). */
 public static class EmptyDraft extends RuntimeException {

  public EmptyDraft() {
   super("The draft has neither text nor attachments");
  }
 }
}
