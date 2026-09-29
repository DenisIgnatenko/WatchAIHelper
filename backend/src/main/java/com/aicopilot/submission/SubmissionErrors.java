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

 /** The question was already sent to the AI (HTTP 409). */
 public static class RequestNotCancellable extends RuntimeException {

  public RequestNotCancellable() {
   super("The request can no longer be cancelled");
  }
 }

 /** Only a failed answer to the latest question can be retried (HTTP 409). */
 public static class RequestNotRetryable extends RuntimeException {

  public RequestNotRetryable(String reason) {
   super(reason);
  }
 }
}
