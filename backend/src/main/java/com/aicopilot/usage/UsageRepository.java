package com.aicopilot.usage;

import static com.aicopilot.common.Db.ts;

import java.time.Instant;
import java.util.UUID;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Repository;

/** The AI usage ledger (table ai_usage): append-only token counts, one row per stored answer. */
@Repository
class UsageRepository {

 private final JdbcClient jdbc;

 UsageRepository(JdbcClient jdbc) {
  this.jdbc = jdbc;
 }

 /** Idempotent per AI request: a request has at most one stored answer. */
 void insert(UUID userId, UUID aiRequestId, String model, long input, long cachedInput, long cacheWrite, long output,
  Instant now) {
  jdbc.sql("""
    insert into ai_usage (id, user_id, ai_request_id, model, input_tokens, cached_input_tokens, cache_write_tokens,
                          output_tokens, created_at)
    values (:id, :userId, :requestId, :model, :input, :cached, :cacheWrite, :output, :now)
    on conflict (ai_request_id) do nothing
    """)
   .param("id", UUID.randomUUID()).param("userId", userId).param("requestId", aiRequestId).param("model", model)
   .param("input", input).param("cached", cachedInput).param("cacheWrite", cacheWrite).param("output", output)
   .param("now", ts(now))
   .update();
 }

 /** Sums since the given moment (inclusive). */
 Totals totalsSince(UUID userId, Instant since) {
  return jdbc.sql("""
    select count(*) as answers,
           coalesce(sum(input_tokens), 0) as input,
           coalesce(sum(cached_input_tokens), 0) as cached,
           coalesce(sum(cache_write_tokens), 0) as cache_write,
           coalesce(sum(output_tokens), 0) as output
    from ai_usage where user_id = :userId and created_at >= :since
    """)
   .param("userId", userId).param("since", ts(since))
   .query((rs, row) -> new Totals(rs.getInt("answers"), rs.getLong("input"), rs.getLong("cached"),
    rs.getLong("cache_write"), rs.getLong("output")))
   .single();
 }

 record Totals(int answers, long inputTokens, long cachedInputTokens, long cacheWriteTokens, long outputTokens) {
 }
}
