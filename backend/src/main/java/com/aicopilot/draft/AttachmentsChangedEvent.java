package com.aicopilot.draft;

import java.util.UUID;

/**
 * The set or state of a draft's images changed (registered, uploaded, failed, removed).
 * Published inside the changing transaction; synchronous listeners run in the same transaction.
 */
public record AttachmentsChangedEvent(UUID draftId) {
}
