package com.aicopilot.ai;

import java.io.IOException;
import java.io.UncheckedIOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Map;
import java.util.Optional;
import java.util.concurrent.ConcurrentHashMap;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

/**
 * Study materials ("knowledge packs") that some response modes add to the model's instructions.
 *
 * <p>The texts are third-party documents, so they are not in git: tools/knowledge/fetch-*.sh builds them into
 * {@code knowledge/<pack>/corpus.md}, and deploy.sh copies them to the server. A missing pack is not fatal:
 * the mode still works with its exam guide, and a warning is logged.
 *
 * <p>Why the whole text instead of retrieval (RAG): the DU3 pack is ~20k tokens. Sent as a stable instruction
 * prefix it is prompt-cached by OpenAI (measured: no extra latency, ~$0.004 per cached request) and the model
 * sees everything - no retrieval misses, no vector store (docs/phase-3-image-benchmark.md, "Study materials").
 */
@Component
class KnowledgeLibrary {

 private static final Logger log = LoggerFactory.getLogger(KnowledgeLibrary.class);

 private final Path root;
 private final Map<String, Optional<String>> cache = new ConcurrentHashMap<>();

 KnowledgeLibrary(@Value("${copilot.knowledge.path}") String root) {
  this.root = Path.of(root).toAbsolutePath().normalize();
 }

 Optional<String> pack(String name) {
  return cache.computeIfAbsent(name, this::load);
 }

 private Optional<String> load(String name) {
  Path file = root.resolve(name).resolve("corpus.md").normalize();
  if (!file.startsWith(root) || !Files.isRegularFile(file)) {
   log.warn("Knowledge pack '{}' not found at {}; the mode runs without it", name, file);
   return Optional.empty();
  }
  try {
   String text = Files.readString(file, StandardCharsets.UTF_8);
   log.info("Loaded knowledge pack '{}' ({} chars)", name, text.length());
   return Optional.of(text);
  } catch (IOException e) {
   throw new UncheckedIOException(e);
  }
 }
}
