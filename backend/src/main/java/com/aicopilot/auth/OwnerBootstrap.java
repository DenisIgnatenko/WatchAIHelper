package com.aicopilot.auth;

import com.aicopilot.config.CopilotProperties;
import java.util.UUID;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.ApplicationArguments;
import org.springframework.boot.ApplicationRunner;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;

/**
 * Registers the owner's first device from {@code CLIENT_API_TOKEN} at startup, so a fresh installation
 * works without any admin UI (YAGNI: no registration flow for a single-user app).
 * Idempotent: does nothing if a device with this token already exists.
 */
@Component
class OwnerBootstrap implements ApplicationRunner {

 private static final Logger log = LoggerFactory.getLogger(OwnerBootstrap.class);

 private final DeviceRepository devices;
 private final CopilotProperties properties;

 OwnerBootstrap(DeviceRepository devices, CopilotProperties properties) {
  this.devices = devices;
  this.properties = properties;
 }

 @Override
 @Transactional
 public void run(ApplicationArguments args) {
  String token = properties.clientApiToken();
  if (token == null || token.isBlank()) {
   log.warn("CLIENT_API_TOKEN is not set: no client can authenticate");
   return;
  }
  String hash = TokenHasher.sha256Hex(token.trim());
  if (devices.existsByTokenHash(hash)) {
   return;
  }
  UUID userId = devices.findFirstUserId().orElseGet(() -> {
   UUID id = UUID.randomUUID();
   devices.insertUser(id);
   return id;
  });
  devices.insertDevice(UUID.randomUUID(), userId, "bootstrap", hash);
  log.info("Registered bootstrap device for user {}", userId);
 }
}
