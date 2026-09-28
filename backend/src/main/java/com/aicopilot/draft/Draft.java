package com.aicopilot.draft;

import java.util.UUID;

/**
 * Content being prepared but not yet sent to the AI (spec 9).
 *
 * <pre>
 *  OPEN ── submit ──► FROZEN ── all attachments uploaded ──► CONSUMED (became a user message)
 * </pre>
 */
public record Draft(UUID id, UUID userId, UUID conversationId, String text, State state) {

 public enum State { OPEN, FROZEN, CONSUMED }
}
