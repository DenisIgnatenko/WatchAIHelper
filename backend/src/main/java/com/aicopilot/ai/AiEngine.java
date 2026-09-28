package com.aicopilot.ai;

import java.util.List;

/**
 * Port to the AI provider (docs/architecture.md, section 15).
 *
 * <p>Dependency Inversion with a concrete payoff: production uses the OpenAI adapter, tests use a fake,
 * and no test ever calls the real API (spec 58). Only the adapter package imports the OpenAI SDK.
 */
public interface AiEngine {

 /**
  * Produces one answer. Blocking call (runs on a virtual thread).
  *
  * @throws AiEngineException with {@link AiEngineException#isTransient()} telling whether a retry may help
  */
 AiReply generate(AiContext context);

 /** Everything the model needs for one answer, already assembled by {@link ContextBuilder}. */
 record AiContext(String instructions, List<Turn> turns) {
 }

 /** One message of the conversation as the model sees it. */
 record Turn(Role role, String text) {

  public enum Role { USER, ASSISTANT }
 }

 /** A validated answer: plain text plus at most three follow-ups (spec 16, 51). */
 record AiReply(String text, List<Suggestion> suggestions, String model, Usage usage) {
 }

 record Suggestion(String title, String prompt) {
 }

 /** Token usage for logging/cost tracking (spec 33); null fields when the provider did not report them. */
 record Usage(Long inputTokens, Long outputTokens) {
 }
}
