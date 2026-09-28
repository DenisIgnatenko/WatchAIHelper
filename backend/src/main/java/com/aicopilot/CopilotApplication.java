package com.aicopilot;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.boot.context.properties.ConfigurationPropertiesScan;
import org.springframework.scheduling.annotation.EnableScheduling;

/**
 * AI Copilot backend: the single source of truth for conversations, drafts and AI processing
 * (docs/architecture.md, section 4).
 */
@SpringBootApplication
@ConfigurationPropertiesScan
@EnableScheduling
public class CopilotApplication {

 public static void main(String[] args) {
  SpringApplication.run(CopilotApplication.class, args);
 }
}
