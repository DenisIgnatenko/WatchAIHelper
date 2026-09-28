package com.aicopilot.config;

import java.time.Clock;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

/**
 * A single {@link Clock} for all "now" decisions (leases, backoff). Tests replace it to control time
 * instead of sleeping.
 */
@Configuration
public class TimeConfig {

 @Bean
 public Clock clock() {
  return Clock.systemUTC();
 }
}
