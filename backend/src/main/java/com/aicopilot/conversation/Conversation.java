package com.aicopilot.conversation;

import java.time.Instant;
import java.util.UUID;

/** A conversation shared by all devices of its user (spec 6). */
public record Conversation(UUID id, UUID userId, String title, Mode mode, Instant updatedAt) {

 /** Title until the first message gives the conversation a better one. */
 public static final String DEFAULT_TITLE = "New conversation";

 /**
  * What the conversation is for, chosen at creation. Decides the AI's instructions and study materials
  * (mapped to a response mode by the submission side, so this package does not depend on the AI package).
  */
 public enum Mode { GENERAL, DANISH_EXAM }
}
