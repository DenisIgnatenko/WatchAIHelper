package com.aicopilot.api;

import com.aicopilot.common.NotFoundException;
import com.aicopilot.submission.SubmissionErrors.DraftAlreadySubmitted;
import com.aicopilot.submission.SubmissionErrors.EmptyDraft;
import org.springframework.http.HttpStatus;
import org.springframework.http.ProblemDetail;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;

/**
 * Maps domain errors to RFC 9457 problem responses with a stable {@code code} property,
 * which clients switch on (e.g. keep the typed text on {@code draft_already_submitted}).
 */
@RestControllerAdvice
class ApiExceptionHandler {

 @ExceptionHandler(NotFoundException.class)
 ProblemDetail notFound(NotFoundException e) {
  return problem(HttpStatus.NOT_FOUND, "not_found", e.getMessage());
 }

 @ExceptionHandler(DraftAlreadySubmitted.class)
 ProblemDetail alreadySubmitted(DraftAlreadySubmitted e) {
  return problem(HttpStatus.CONFLICT, "draft_already_submitted", e.getMessage());
 }

 @ExceptionHandler(EmptyDraft.class)
 ProblemDetail emptyDraft(EmptyDraft e) {
  return problem(HttpStatus.UNPROCESSABLE_CONTENT, "empty_draft", e.getMessage());
 }

 private static ProblemDetail problem(HttpStatus status, String code, String detail) {
  ProblemDetail problem = ProblemDetail.forStatusAndDetail(status, detail);
  problem.setProperty("code", code);
  return problem;
 }
}
