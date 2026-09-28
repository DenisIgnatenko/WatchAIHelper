package com.aicopilot.submission;

import com.aicopilot.ai.ResponseMode;
import java.util.UUID;

/**
 * One AI inference request, created only by an explicit Send (Invariant 5).
 * State machine: docs/architecture.md, section 9.
 */
public record AiRequest(
 UUID id,
 UUID userId,
 UUID conversationId,
 UUID draftId,
 State state,
 UUID userMessageId,
 UUID assistantMessageId,
 ResponseMode responseMode,
 int attemptCount,
 String lastErrorCode
) {

 public enum State {
  WAITING_FOR_ATTACHMENTS,
  BLOCKED,
  QUEUED,
  PROCESSING,
  COMPLETED,
  FAILED,
  CANCELLED;

  public boolean isTerminal() {
   return this == COMPLETED || this == FAILED || this == CANCELLED;
  }
 }
}
