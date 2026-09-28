package com.aicopilot.ai;

import java.util.List;
import java.util.Optional;

/**
 * How the AI should answer (spec 34): instruction files plus an optional knowledge pack (study materials).
 *
 * <p>Open/Closed: a new mode (LANGUAGE_TUTOR, SOFTWARE_ENGINEERING, ...) is a new constant plus prompt files;
 * transport, storage and processing code do not change.
 */
public enum ResponseMode {
 /** General assistant with answers optimised for the Watch. */
 WATCH_CONCISE(List.of("prompts/watch_concise.md"), null),
 /** Danish exam preparation: exam guide + full official DU3 materials (knowledge pack "danish-du3"). */
 DANISH_EXAM(List.of("prompts/watch_concise.md", "prompts/danish_exam.md"), "danish-du3");

 private final List<String> promptResources;
 private final String knowledgePack;

 ResponseMode(List<String> promptResources, String knowledgePack) {
  this.promptResources = promptResources;
  this.knowledgePack = knowledgePack;
 }

 /** Classpath prompt files, concatenated in this order. */
 public List<String> promptResources() {
  return promptResources;
 }

 /** Folder name under the knowledge directory, if this mode uses study materials. */
 public Optional<String> knowledgePack() {
  return Optional.ofNullable(knowledgePack);
 }
}
