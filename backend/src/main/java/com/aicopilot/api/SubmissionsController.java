package com.aicopilot.api;

import com.aicopilot.api.generated.SubmissionsApi;
import com.aicopilot.api.generated.model.AiRequestDto;
import com.aicopilot.api.generated.model.SubmitDraftRequestDto;
import com.aicopilot.auth.CurrentUser;
import com.aicopilot.submission.AiRequest;
import com.aicopilot.submission.SubmissionService;
import java.time.Duration;
import java.util.UUID;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.RestController;

@RestController
class SubmissionsController implements SubmissionsApi {

 /** How often the long-poll re-reads the request. Cheap: one indexed row read. */
 private static final Duration LONG_POLL_STEP = Duration.ofMillis(250);

 private final SubmissionService submissions;
 private final CurrentUser currentUser;
 private final ApiMapper mapper;

 SubmissionsController(SubmissionService submissions, CurrentUser currentUser, ApiMapper mapper) {
  this.submissions = submissions;
  this.currentUser = currentUser;
  this.mapper = mapper;
 }

 @Override
 public ResponseEntity<AiRequestDto> submitDraft(UUID draftId, UUID idempotencyKey, SubmitDraftRequestDto body) {
  String text = body == null ? null : body.getText();
  AiRequest request = submissions.submit(currentUser.id(), draftId, text, idempotencyKey);
  return ResponseEntity.status(HttpStatus.ACCEPTED).body(mapper.request(request));
 }

 @Override
 public ResponseEntity<AiRequestDto> cancelRequest(UUID requestId) {
  return ResponseEntity.ok(mapper.request(submissions.cancel(currentUser.id(), requestId)));
 }

 @Override
 public ResponseEntity<AiRequestDto> retryRequest(UUID requestId) {
  return ResponseEntity.status(HttpStatus.ACCEPTED).body(mapper.request(submissions.retry(currentUser.id(), requestId)));
 }

 /**
  * Long-poll: waits until the state changes or the time is up. Sleeping is cheap here because every
  * request runs on a virtual thread (application.yml: spring.threads.virtual.enabled).
  */
 @Override
 public ResponseEntity<AiRequestDto> getRequest(UUID requestId, Integer waitSeconds) {
  UUID userId = currentUser.id();
  AiRequest initial = submissions.get(userId, requestId);
  AiRequest current = initial;
  long deadline = System.nanoTime() + Duration.ofSeconds(waitSeconds == null ? 0 : waitSeconds).toNanos();
  while (!current.state().isTerminal() && current.state() == initial.state() && System.nanoTime() < deadline) {
   try {
    Thread.sleep(LONG_POLL_STEP);
   } catch (InterruptedException e) {
    Thread.currentThread().interrupt();
    break;
   }
   current = submissions.get(userId, requestId);
  }
  return ResponseEntity.ok(mapper.request(current));
 }
}
