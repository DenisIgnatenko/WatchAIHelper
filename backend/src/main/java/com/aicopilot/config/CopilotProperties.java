package com.aicopilot.config;

import java.math.BigDecimal;
import java.time.Duration;
import java.time.ZoneId;
import org.springframework.boot.context.properties.ConfigurationProperties;

/**
 * Typed view of the {@code copilot.*} settings from application.yml / environment.
 * The model name and every OpenAI knob live here only (spec 33: no model names scattered in code).
 */
@ConfigurationProperties("copilot")
public record CopilotProperties(
 String clientApiToken,
 OpenAi openai,
 Processing processing,
 Attachments attachments,
 Usage usage
) {

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
  int contextMessages,
  int contextImages
 ) {
 }

 /**
  * @param uploadTimeout a registered image whose bytes do not arrive within this time becomes FAILED
  * @param retention     image bytes are deleted this long after upload (spec 47); the message stays
  */
 public record Attachments(Duration uploadTimeout, Duration retention) {
 }
 /**
  * Prices for the cost report, per 1M tokens in {@code currency}.
  *
  * @param timeZone defines the boundaries of "today" and "this month"
  */
 public record Usage(
  String currency,
  BigDecimal inputPrice,
  BigDecimal cachedInputPrice,
  BigDecimal cacheWritePrice,
  BigDecimal outputPrice,
  ZoneId timeZone
 ) {
 }
}
