package com.aicopilot.ai;

/**
 * How the AI should answer (spec 34). Each mode is just an instruction file.
 *
 * <p>Open/Closed: a new mode (LANGUAGE_TUTOR, SOFTWARE_ENGINEERING, ...) is a new constant plus a new
 * prompt file; transport, storage and processing code do not change.
 */
public enum ResponseMode {
 WATCH_CONCISE("prompts/watch_concise.md");

 private final String promptResource;

 ResponseMode(String promptResource) {
  this.promptResource = promptResource;
 }

 public String promptResource() {
  return promptResource;
 }
}
