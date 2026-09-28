package com.aicopilot.auth;

import java.time.Instant;
import java.util.Optional;
import java.util.UUID;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Repository;

/** Users and their devices. */
@Repository
class DeviceRepository {

 private final JdbcClient jdbc;

 DeviceRepository(JdbcClient jdbc) {
  this.jdbc = jdbc;
 }

 /** Owner of an active (not revoked) device with this token hash. */
 Optional<UUID> findUserIdByTokenHash(String tokenHash) {
  return jdbc.sql("select user_id from devices where token_hash = :hash and revoked_at is null")
   .param("hash", tokenHash)
   .query(UUID.class)
   .optional();
 }

 void touch(String tokenHash, Instant now) {
  jdbc.sql("update devices set last_seen_at = :now where token_hash = :hash")
   .param("now", java.sql.Timestamp.from(now))
   .param("hash", tokenHash)
   .update();
 }

 boolean existsByTokenHash(String tokenHash) {
  return jdbc.sql("select count(*) from devices where token_hash = :hash")
   .param("hash", tokenHash)
   .query(Integer.class)
   .single() > 0;
 }

 Optional<UUID> findFirstUserId() {
  return jdbc.sql("select id from users order by created_at limit 1").query(UUID.class).optional();
 }

 void insertUser(UUID userId) {
  jdbc.sql("insert into users (id) values (:id)").param("id", userId).update();
 }

 void insertDevice(UUID deviceId, UUID userId, String name, String tokenHash) {
  jdbc.sql("insert into devices (id, user_id, name, token_hash) values (:id, :userId, :name, :hash)")
   .param("id", deviceId)
   .param("userId", userId)
   .param("name", name)
   .param("hash", tokenHash)
   .update();
 }
}
