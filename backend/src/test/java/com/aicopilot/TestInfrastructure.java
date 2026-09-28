package com.aicopilot;

import com.aicopilot.ai.AiEngine;
import com.aicopilot.ai.AiEngineException;
import java.util.List;
import java.util.concurrent.ConcurrentLinkedQueue;
import java.util.concurrent.CopyOnWriteArrayList;
import java.util.function.Supplier;
import org.springframework.boot.test.context.TestConfiguration;
import org.springframework.boot.testcontainers.service.connection.ServiceConnection;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Primary;
import org.testcontainers.postgresql.PostgreSQLContainer;

/**
 * Test wiring: a real PostgreSQL in Docker (same SQL, locks and constraints as production) and a fake AI engine.
 * Tests never call the real OpenAI API (spec 58).
 */
@TestConfiguration(proxyBeanMethods = false)
public class TestInfrastructure {

 /** {@code @ServiceConnection} points the datasource at the container automatically. */
 @Bean
 @ServiceConnection
 PostgreSQLContainer postgres() {
  return new PostgreSQLContainer("postgres:17-alpine");
 }

 @Bean
 @Primary
 FakeAiEngine fakeAiEngine() {
  return new FakeAiEngine();
 }

 /**
  * Records every context it receives and answers from a script (default: a fixed Russian answer).
  * {@link #script} entries may throw to simulate provider failures.
  */
 public static class FakeAiEngine implements AiEngine {

  public final List<AiContext> calls = new CopyOnWriteArrayList<>();
  public final ConcurrentLinkedQueue<Supplier<AiReply>> script = new ConcurrentLinkedQueue<>();

  @Override
  public AiReply generate(AiContext context) {
   calls.add(context);
   Supplier<AiReply> next = script.poll();
   return next != null ? next.get() : reply("4 — B. «Mens» означает одновременность.");
  }

  public void reset() {
   calls.clear();
   script.clear();
  }

  public static AiReply reply(String text) {
   return new AiReply(text, List.of(new Suggestion("Подробнее", "Объясни подробнее.")), "fake-model",
    new Usage(10L, 5L));
  }

  public static Supplier<AiReply> failing(boolean transientFailure) {
   return () -> {
    throw new AiEngineException("test_failure", transientFailure, "simulated", null);
   };
  }
 }
}
