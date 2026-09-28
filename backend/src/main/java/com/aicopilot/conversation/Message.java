package com.aicopilot.conversation;

import java.time.Instant;
import java.util.List;
import java.util.UUID;

/**
 * An immutable message (spec 7, 8). There is no update operation for messages anywhere in the code.
 *
 * @param seq             position inside the conversation (1, 2, 3, ...)
 * @param text            null for image-only user messages
 * @param draftId         the draft a user message was created from (its images); null for answers
 * @param attachmentCount number of images of a user message
 */
public record Message(
 UUID id,
 UUID conversationId,
 int seq,
 Role role,
 String text,
 UUID draftId,
 int attachmentCount,
 List<SuggestedAction> suggestedActions,
 Instant createdAt
) {

 public enum Role { USER, ASSISTANT }

 /** A follow-up offered under an assistant answer (spec 16). */
 public record SuggestedAction(String title, String prompt) {
 }
}
