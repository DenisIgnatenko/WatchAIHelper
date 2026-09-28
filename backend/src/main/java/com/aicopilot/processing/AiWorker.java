package com.aicopilot.processing;

import com.aicopilot.ai.AiEngine;
import com.aicopilot.ai.AiEngine.AiContext;
import com.aicopilot.ai.AiEngineException;
import com.aicopilot.ai.ContextBuilder;
import com.aicopilot.config.CopilotProperties;
import com.aicopilot.submission.AiRequest;
import com.aicopilot.submission.RequestQueuedEvent;
import jakarta.annotation.PreDestroy;
import java.util.Optional;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Semaphore;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;
import org.springframework.transaction.event.TransactionalEventListener;

/**
 * Backend-owned AI processing (spec 35): clients submit and go away; this worker does the slow part.
 *
 * <p>Queue = the ai_requests table (no Kafka/Redis, YAGNI). Work is picked up:
 * <ul>
 *  <li>immediately after a submit commits ({@link RequestQueuedEvent});</li>
 *  <li>by a periodic poll - safety net for retries with backoff and for requests abandoned by a crash.</li>
 * </ul>
 * Each AI call runs on its own virtual thread; a semaphore caps concurrency.
 */
@Component
class AiWorker {

 private static final Logger log = LoggerFactory.getLogger(AiWorker.class);

 private final ProcessingTransitions transitions;
 private final ContextBuilder contextBuilder;
 private final AiEngine engine;
 private final Semaphore slots;
 private final ExecutorService executor = Executors.newVirtualThreadPerTaskExecutor();

 AiWorker(ProcessingTransitions transitions, ContextBuilder contextBuilder, AiEngine engine, CopilotProperties properties) {
  this.transitions = transitions;
  this.contextBuilder = contextBuilder;
  this.engine = engine;
  this.slots = new Semaphore(properties.processing().maxConcurrency());
 }

 /** Fires after the submitting transaction committed; hands off to another thread at once. */
 @TransactionalEventListener
 void onQueued(RequestQueuedEvent event) {
  executor.execute(this::poll);
 }

 @Scheduled(fixedDelayString = "${copilot.processing.poll-interval}")
 void poll() {
  while (slots.tryAcquire()) {
   Optional<AiRequest> claimed;
   try {
    claimed = transitions.claimNext();
   } catch (RuntimeException e) {
    slots.release();
    log.error("Claiming AI requests failed", e);
    return;
   }
   if (claimed.isEmpty()) {
    slots.release();
    return;
   }
   AiRequest request = claimed.get();
   executor.execute(() -> {
    try {
     process(request);
    } finally {
     slots.release();
    }
   });
  }
 }

 private void process(AiRequest request) {
  long started = System.nanoTime();
  try {
   AiContext context = contextBuilder.build(request.conversationId(), request.userMessageId(), request.responseMode());
   AiEngine.AiReply reply = engine.generate(context);
   boolean stored = transitions.complete(request, reply);
   log.info("Processed aiRequestId={} conversationId={} attempt={} stored={} durationMs={}", request.id(),
    request.conversationId(), request.attemptCount(), stored, (System.nanoTime() - started) / 1_000_000);
  } catch (AiEngineException e) {
   transitions.fail(request, e);
  } catch (RuntimeException e) {
   transitions.fail(request, AiEngineException.permanent("internal_error", e.getMessage(), e));
  }
 }

 @PreDestroy
 void shutdown() {
  // Running calls finish or are abandoned; abandoned ones are retried after their lease expires.
  executor.shutdownNow();
 }
}
