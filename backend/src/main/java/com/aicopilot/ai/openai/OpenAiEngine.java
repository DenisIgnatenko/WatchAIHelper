package com.aicopilot.ai.openai;

import com.aicopilot.ai.AiEngine;
import com.aicopilot.ai.AiEngineException;
import com.aicopilot.config.CopilotProperties;
import com.fasterxml.jackson.annotation.JsonPropertyDescription;
import com.openai.client.OpenAIClient;
import com.openai.client.okhttp.OpenAIOkHttpClient;
import com.openai.errors.InternalServerException;
import com.openai.errors.OpenAIException;
import com.openai.errors.OpenAIIoException;
import com.openai.errors.OpenAIServiceException;
import com.openai.errors.RateLimitException;
import com.openai.models.Reasoning;
import com.openai.models.ReasoningEffort;
import com.openai.models.responses.EasyInputMessage;
import com.openai.models.responses.ResponseCreateParams;
import com.openai.models.responses.ResponseInputImage;
import com.openai.models.responses.ResponseInputItem;
import com.openai.models.responses.StructuredResponse;
import com.openai.models.responses.StructuredResponseCreateParams;
import java.util.Base64;
import java.util.List;
import java.util.Objects;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Component;

/**
 * OpenAI Responses API adapter (docs/architecture.md, section 15). The only class that knows the SDK.
 *
 * <p>Decisions:
 * <ul>
 *  <li>{@code store=false}: the backend replays the conversation itself and stays the source of truth;</li>
 *  <li>Structured Outputs (strict JSON Schema generated from {@link ReplyFormat}): the Watch never parses
 *   model JSON, it receives validated fields (spec 51);</li>
 *  <li>model, reasoning effort, timeout, retries come from configuration only (spec 33).</li>
 * </ul>
 */
@Component
class OpenAiEngine implements AiEngine {

 private static final Logger log = LoggerFactory.getLogger(OpenAiEngine.class);
 private static final int MAX_SUGGESTIONS = 3;

 private final CopilotProperties.OpenAi settings;
 private final OpenAIClient client;

 OpenAiEngine(CopilotProperties properties) {
  this.settings = properties.openai();
  this.client = OpenAIOkHttpClient.builder()
   // An empty key still builds a client; requests then fail with 401, which is reported as a permanent error.
   .apiKey(Objects.requireNonNullElse(settings.apiKey(), ""))
   .timeout(settings.timeout())
   .maxRetries(settings.maxRetries())
   .build();
 }

 @Override
 public AiReply generate(AiContext context) {
  StructuredResponseCreateParams<ReplyFormat> params = ResponseCreateParams.builder()
   .model(settings.model())
   .instructions(context.instructions())
   .inputOfResponse(context.turns().stream().map(this::toInputItem).toList())
   .store(settings.store())
   .reasoning(Reasoning.builder().effort(ReasoningEffort.of(settings.reasoningEffort())).build())
   .text(ReplyFormat.class)
   .build();
  try {
   StructuredResponse<ReplyFormat> response = client.responses().create(params);
   ReplyFormat reply = response.output().stream()
    .flatMap(item -> item.message().stream())
    .flatMap(message -> message.content().stream())
    .flatMap(content -> content.outputText().stream())
    .findFirst()
    .orElseThrow(() -> AiEngineException.permanent("empty_output", "The model returned no text output", null));
   Usage usage = response.usage()
    .map(u -> {
     // Cache details are optional in practice: missing fields count as 0 instead of failing the answer.
     var details = u._inputTokensDetails().asKnown();
     long cached = details.flatMap(d -> d._cachedTokens().asKnown()).orElse(0L);
     long cacheWrite = details.flatMap(d -> d._cacheWriteTokens().asKnown()).orElse(0L);
     return new Usage(u.inputTokens(), cached, cacheWrite, u.outputTokens());
    })
    .orElse(new Usage(null, null, null, null));
   return validate(reply, usage);
  } catch (RateLimitException e) {
   throw AiEngineException.transientFailure("rate_limited", "OpenAI rate limit", e);
  } catch (InternalServerException e) {
   throw AiEngineException.transientFailure("provider_error", "OpenAI server error " + e.statusCode(), e);
  } catch (OpenAIIoException e) {
   throw AiEngineException.transientFailure("provider_unreachable", "OpenAI network error or timeout", e);
  } catch (OpenAIServiceException e) {
   // 400/401/403/404/422: the same request will fail again.
   throw AiEngineException.permanent("provider_rejected_" + e.statusCode(), "OpenAI rejected the request", e);
  } catch (OpenAIException e) {
   // Includes invalid structured output that could not be parsed into ReplyFormat.
   throw AiEngineException.permanent("invalid_output", "Unexpected OpenAI response", e);
  }
 }

 private ResponseInputItem toInputItem(Turn turn) {
  if (!turn.images().isEmpty()) {
   // Images first, in their original order (spec 27), then the text: one logical user message.
   var message = ResponseInputItem.Message.builder().role(ResponseInputItem.Message.Role.USER);
   for (Image image : turn.images()) {
    message.addContent(ResponseInputImage.builder()
     .detail(ResponseInputImage.Detail.of(settings.imageDetail()))
     .imageUrl("data:" + image.mimeType() + ";base64," + Base64.getEncoder().encodeToString(image.bytes()))
     .build());
   }
   message.addInputTextContent(turn.text());
   return ResponseInputItem.ofMessage(message.build());
  }
  EasyInputMessage.Role role = switch (turn.role()) {
   case USER -> EasyInputMessage.Role.USER;
   case ASSISTANT -> EasyInputMessage.Role.ASSISTANT;
  };
  return ResponseInputItem.ofEasyInputMessage(EasyInputMessage.builder().role(role).content(turn.text()).build());
 }

 /** The model's output is untrusted input: check it before it reaches storage and the Watch. */
 private AiReply validate(ReplyFormat reply, Usage usage) {
  if (reply.text == null || reply.text.isBlank()) {
   throw AiEngineException.permanent("empty_answer", "The model returned an empty answer", null);
  }
  List<Suggestion> suggestions = reply.suggestedActions == null ? List.of() : reply.suggestedActions.stream()
   .filter(a -> a != null && a.title != null && !a.title.isBlank() && a.prompt != null && !a.prompt.isBlank())
   .limit(MAX_SUGGESTIONS)
   .map(a -> new Suggestion(a.title.strip(), a.prompt.strip()))
   .toList();
  String title = reply.title == null || reply.title.isBlank() ? null : reply.title.strip();
  log.info("OpenAI answer model={} inputTokens={} cachedInputTokens={} outputTokens={}", settings.model(),
   usage.inputTokens(), usage.cachedInputTokens(), usage.outputTokens());
  return new AiReply(reply.text.strip(), suggestions, title, settings.model(), usage);
 }

 /**
  * Shape of the structured output. The SDK derives a strict JSON Schema from these public fields;
  * descriptions become part of the schema and guide the model.
  */
 public static class ReplyFormat {

  @JsonPropertyDescription("The answer shown on the watch. Plain text, no Markdown.")
  public String text;

  @JsonPropertyDescription("0 to 3 useful follow-up actions.")
  public List<SuggestedActionFormat> suggestedActions;

  @JsonPropertyDescription("A short title for the whole conversation so far, 2-5 words, naming its topic "
   + "(e.g. the exercise or text being worked on). In the language of the conversation. No quotes, no emoji.")
  public String title;
 }

 public static class SuggestedActionFormat {

  @JsonPropertyDescription("Button title, 1-2 words.")
  public String title;

  @JsonPropertyDescription("The follow-up request sent when the button is pressed.")
  public String prompt;
 }
}
