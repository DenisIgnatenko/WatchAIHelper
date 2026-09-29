package com.aicopilot.processing;

import com.aicopilot.ai.AiEngine.AiReply;
import com.aicopilot.ai.AiEngineException;
import com.aicopilot.config.CopilotProperties;
import com.aicopilot.conversation.ConversationService;
import com.aicopilot.conversation.Message.SuggestedAction;
import com.aicopilot.submission.AiRequest;
import com.aicopilot.submission.AiRequestRepository;
import com.aicopilot.usage.UsageService;
import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.Optional;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import tools.jackson.databind.ObjectMapper;

/**
 * The short database transactions around one AI call: claim before, complete or fail after.
 * The AI call itself runs outside any transaction (it can take many seconds; no DB locks are held).
 */
@Service
class ProcessingTransitions {

 private static final Logger log = LoggerFactory.getLogger(ProcessingTransitions.class);

 private final AiRequestRepository requests;
 private final ConversationService conversations;
 private final UsageService usage;
 private final CopilotProperties.Processing settings;
 private final ObjectMapper json;
 private final Clock clock;

 ProcessingTransitions(AiRequestRepository requests, ConversationService conversations, UsageService usage,
  CopilotProperties properties, ObjectMapper json, Clock clock) {
  this.requests = requests;
  this.conversations = conversations;
  this.usage = usage;
  this.settings = properties.processing();
  this.json = json;
  this.clock = clock;
 }

 /** QUEUED (or abandoned PROCESSING) -> PROCESSING with a lease. */
 @Transactional
 public Optional<AiRequest> claimNext() {
  Instant now = clock.instant();
  return requests.claimNext(now, now.plus(settings.lease()));
 }

 /**
  * PROCESSING -> COMPLETED together with the assistant message. If the lease expired and another attempt
  * already finished the request, this attempt's answer is dropped: one assistant message per request.
  * The answer is dropped too when the conversation was deleted while the AI was thinking.
  */
 @Transactional
 public boolean complete(AiRequest request, AiReply reply) {
  var current = requests.lock(request.id());
  if (current.isEmpty()) {
   log.info("Dropping answer of deleted conversation aiRequestId={}", request.id());
   return false;
  }
  if (current.get().state() != AiRequest.State.PROCESSING || current.get().attemptCount() != request.attemptCount()) {
   log.warn("Dropping stale answer aiRequestId={} state={}", request.id(), current.get().state());
   return false;
  }
  var actions = reply.suggestions().stream().map(s -> new SuggestedAction(s.title(), s.prompt())).toList();
  var messageId = conversations.appendAssistantMessage(request.userId(), request.conversationId(), request.id(),
   reply.text(), actions, request.responseMode().name(), reply.model(), usageJson(reply));
  conversations.suggestTitle(request.conversationId(), reply.title());
  usage.record(request.userId(), request.id(), reply.model(), reply.usage());
  requests.complete(request.id(), messageId, clock.instant());
  return true;
 }

 /** Transient failure with attempts left -> QUEUED after a backoff; otherwise -> FAILED. */
 @Transactional
 public void fail(AiRequest request, AiEngineException error) {
  Instant now = clock.instant();
  if (error.isTransient() && request.attemptCount() < settings.maxAttempts()) {
   // 2 s, 4 s, 8 s, ...
   Duration backoff = Duration.ofSeconds(1L << request.attemptCount());
   requests.requeue(request.id(), now.plus(backoff), error.code(), now);
   log.warn("Retrying aiRequestId={} attempt={} code={} in {}", request.id(), request.attemptCount(), error.code(), backoff);
  } else {
   requests.fail(request.id(), error.code(), now);
   log.error("Failed aiRequestId={} attempt={} code={}", request.id(), request.attemptCount(), error.code(), error);
  }
 }

 private String usageJson(AiReply reply) {
  if (reply.usage() == null) {
   return null;
  }
  Map<String, Object> tokens = new LinkedHashMap<>();
  tokens.put("inputTokens", reply.usage().inputTokens());
  tokens.put("cachedInputTokens", reply.usage().cachedInputTokens());
  tokens.put("cacheWriteTokens", reply.usage().cacheWriteTokens());
  tokens.put("outputTokens", reply.usage().outputTokens());
  return json.writeValueAsString(tokens);
 }
}
