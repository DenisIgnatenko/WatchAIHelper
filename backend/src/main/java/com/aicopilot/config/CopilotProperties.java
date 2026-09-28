package com.aicopilot.config;

import java.time.Duration;
import org.springframework.boot.context.properties.ConfigurationProperties;

/**
 * Typed view of the {@code copilot.*} settings from application.yml / environment.
 * The model name and every OpenAI knob live here only (spec 33: no model names scattered in code).
 */
@ConfigurationProperties("copilot")
public record CopilotProperties(String clientApiToken, OpenAi openai, Processing processing) {

 public record OpenAi(
  String apiKey,
  String model,
  String reasoningEffort,
  String imageDetail,
  boolean store,
  Duration timeout,
  int maxRetries
 ) {
 }

 public record Processing(
  Duration pollInterval,
  Duration lease,
  int maxAttempts,
  int maxConcurrency,
  int contextMessages
 ) {
 }
}
