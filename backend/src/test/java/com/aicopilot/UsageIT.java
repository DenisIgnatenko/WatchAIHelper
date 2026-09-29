package com.aicopilot;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;

import java.util.UUID;
import org.junit.jupiter.api.Test;
import tools.jackson.databind.JsonNode;

/** AI cost report: token sums per period and the estimated cost from the configured prices. */
class UsageIT extends ApiTestBase {

 @Test
 void reportsTokensAndCostPerPeriod() throws Exception {
  awaitTerminal(submit(home().at("/draft/id").asString(), "one", UUID.randomUUID(), 202).at("/id").asString());
  awaitTerminal(submit(home().at("/draft/id").asString(), "two", UUID.randomUUID(), 202).at("/id").asString());
  // An answer from 40 days ago: in the total only (always an earlier month).
  UUID userId = jdbc.sql("select id from users").query(UUID.class).single();
  jdbc.sql("""
    insert into ai_usage (id, user_id, ai_request_id, input_tokens, output_tokens, created_at)
    values (:id, :userId, :requestId, 1000000, 0, now() - interval '40 days')
    """)
   .param("id", UUID.randomUUID()).param("userId", userId).param("requestId", UUID.randomUUID())
   .update();

  JsonNode report = body(mvc.perform(authorized(get("/v1/usage"))).andReturn(), 200);

  assertThat(report.at("/currency").asString()).isEqualTo("USD");
  assertThat(report.at("/timeZone").asString()).isEqualTo("Europe/Copenhagen");
  // Fake answers: 10 input tokens (4 of them cached) and 5 output tokens each.
  assertThat(report.at("/today/answers").asInt()).isEqualTo(2);
  assertThat(report.at("/today/inputTokens").asLong()).isEqualTo(20);
  assertThat(report.at("/today/cachedInputTokens").asLong()).isEqualTo(8);
  assertThat(report.at("/today/outputTokens").asLong()).isEqualTo(10);
  // (12 x $2.00 + 8 x $0.20 + 10 x $10.00) / 1M = $0.0001256
  assertThat(report.at("/today/cost").asDouble()).isEqualTo(0.000126);
  assertThat(report.at("/month/answers").asInt()).isEqualTo(2);
  assertThat(report.at("/total/answers").asInt()).isEqualTo(3);
  assertThat(report.at("/total/cost").asDouble()).isEqualTo(2.000126);
 }
}
