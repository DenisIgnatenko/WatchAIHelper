package com.aicopilot.conversation;

import java.time.Instant;
import java.util.UUID;

/** A conversation shared by all devices of its user (spec 6). */
public record Conversation(UUID id, UUID userId, String title, Instant updatedAt) {

 /** Title until the first message gives the conversation a better one. */
 public static final String DEFAULT_TITLE = "New conversation";
}
