package com.aicopilot.usage;

import com.aicopilot.ai.AiEngine;
import com.aicopilot.config.CopilotProperties;
import com.aicopilot.usage.UsageRepository.Totals;
import java.math.BigDecimal;
import java.math.RoundingMode;
import java.time.Clock;
import java.time.Instant;
import java.time.LocalDate;
import java.time.ZoneId;
import java.util.Objects;
import java.util.UUID;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;

/**
 * AI spending control: records the tokens of every stored answer and reports them with an estimated cost.
 *
 * <p>Cost is computed when the report is read, from the configured prices (single place of configuration,
 * spec 33). KISS: one model, one price list; per-model prices are added only if the model is ever mixed.
 */
@Service
public class UsageService {

 private static final BigDecimal MILLION = BigDecimal.valueOf(1_000_000);

 private final UsageRepository ledger;
 private final CopilotProperties.Usage prices;
 private final Clock clock;

 UsageService(UsageRepository ledger, CopilotProperties properties, Clock clock) {
  this.ledger = ledger;
  this.prices = properties.usage();
  this.clock = clock;
 }

 /** Runs inside the transaction that stores the answer: an answer and its usage row exist together. */
 @Transactional(propagation = Propagation.MANDATORY)
 public void record(UUID userId, UUID aiRequestId, String model, AiEngine.Usage usage) {
  if (usage == null) {
   return;
  }
  ledger.insert(userId, aiRequestId, model, orZero(usage.inputTokens()), orZero(usage.cachedInputTokens()),
   orZero(usage.cacheWriteTokens()), orZero(usage.outputTokens()), clock.instant());
 }

 @Transactional(readOnly = true)
 public UsageReport report(UUID userId) {
  ZoneId zone = prices.timeZone();
  LocalDate today = LocalDate.now(clock.withZone(zone));
  return new UsageReport(
   prices.currency(),
   zone.getId(),
   period(ledger.totalsSince(userId, today.atStartOfDay(zone).toInstant())),
   period(ledger.totalsSince(userId, today.withDayOfMonth(1).atStartOfDay(zone).toInstant())),
   period(ledger.totalsSince(userId, Instant.EPOCH)));
 }

 /**
  * Cached and cache-write tokens are parts of the input tokens, billed at their own prices;
  * the rest of the input is billed at the normal input price.
  */
 private Period period(Totals t) {
  long regularInput = Math.max(0, t.inputTokens() - t.cachedInputTokens() - t.cacheWriteTokens());
  BigDecimal cost = price(regularInput, prices.inputPrice())
   .add(price(t.cachedInputTokens(), prices.cachedInputPrice()))
   .add(price(t.cacheWriteTokens(), prices.cacheWritePrice()))
   .add(price(t.outputTokens(), prices.outputPrice()))
   .setScale(6, RoundingMode.HALF_UP);
  return new Period(t.answers(), t.inputTokens(), t.cachedInputTokens(), t.outputTokens(), cost);
 }

 private static BigDecimal price(long tokens, BigDecimal perMillion) {
  return BigDecimal.valueOf(tokens).multiply(perMillion).divide(MILLION, 8, RoundingMode.HALF_UP);
 }

 private static long orZero(Long value) {
  return Objects.requireNonNullElse(value, 0L);
 }

 public record UsageReport(String currency, String timeZone, Period today, Period month, Period total) {
 }

 public record Period(int answers, long inputTokens, long cachedInputTokens, long outputTokens, BigDecimal cost) {
 }
}
