package com.aicopilot.submission;

import java.util.UUID;

/**
 * Published when a request becomes QUEUED. The worker reacts after the transaction commits, so
 * processing starts immediately instead of waiting for the next poll.
 */
public record RequestQueuedEvent(UUID requestId) {
}
