package com.aicopilot.conversation;

import static com.aicopilot.common.Db.instant;
import static com.aicopilot.common.Db.ts;

import java.time.Instant;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.springframework.jdbc.core.RowMapper;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Repository;

/** Conversations and the per-user active conversation. */
@Repository
class ConversationRepository {

 private static final RowMapper<Conversation> MAPPER = (rs, row) -> new Conversation(
  rs.getObject("id", UUID.class),
  rs.getObject("user_id", UUID.class),
  rs.getString("title"),
  Conversation.Mode.valueOf(rs.getString("mode")),
  instant(rs, "updated_at"));

 private final JdbcClient jdbc;

 ConversationRepository(JdbcClient jdbc) {
  this.jdbc = jdbc;
 }

 Optional<Conversation> find(UUID userId, UUID id) {
  return jdbc.sql("select * from conversations where id = :id and user_id = :userId")
   .param("id", id).param("userId", userId)
   .query(MAPPER).optional();
 }

 List<Conversation> listByUser(UUID userId) {
  return jdbc.sql("select * from conversations where user_id = :userId order by updated_at desc")
   .param("userId", userId)
   .query(MAPPER).list();
 }

 /** Idempotent by id: a repeated call with the same id is a no-op. */
 void insertIfAbsent(UUID id, UUID userId, String title, Conversation.Mode mode, Instant now) {
  jdbc.sql("""
    insert into conversations (id, user_id, title, mode, created_at, updated_at)
    values (:id, :userId, :title, :mode, :now, :now)
    on conflict (id) do nothing
    """)
   .param("id", id).param("userId", userId).param("title", title).param("mode", mode.name()).param("now", ts(now))
   .update();
 }

 /**
  * Row lock on the conversation. Serializes message appends so that {@code seq} values stay
  * unique and gapless without a separate sequence per conversation.
  */
 void lock(UUID id) {
  jdbc.sql("select id from conversations where id = :id for update").param("id", id).query(UUID.class).single();
 }

 void touch(UUID id, Instant now) {
  jdbc.sql("update conversations set updated_at = :now where id = :id")
   .param("id", id).param("now", ts(now)).update();
 }

 /** Replaces the initial default title only (first question), never a title that was already set. */
 void renameIfDefault(UUID id, String title) {
  jdbc.sql("""
    update conversations set title = :title
    where id = :id and title = :default and title_source = 'PLACEHOLDER'
    """)
   .param("id", id).param("title", title).param("default", Conversation.DEFAULT_TITLE)
   .update();
 }

 /** An AI-suggested title replaces a placeholder only: once set by the AI or the user, it stays. */
 void applyAiTitle(UUID id, String title) {
  jdbc.sql("update conversations set title = :title, title_source = 'AI' where id = :id and title_source = 'PLACEHOLDER'")
   .param("id", id).param("title", title)
   .update();
 }

 /** @return false when the conversation does not exist or belongs to another user */
 boolean renameByUser(UUID userId, UUID id, String title) {
  return jdbc.sql("update conversations set title = :title, title_source = 'USER' where id = :id and user_id = :userId")
   .param("id", id).param("userId", userId).param("title", title)
   .update() == 1;
 }

 /** Cascades to drafts, attachments, messages and AI requests (foreign keys). */
 void delete(UUID userId, UUID id) {
  jdbc.sql("delete from conversations where id = :id and user_id = :userId")
   .param("id", id).param("userId", userId)
   .update();
 }

 Optional<UUID> mostRecentlyUpdated(UUID userId) {
  return jdbc.sql("select id from conversations where user_id = :userId order by updated_at desc limit 1")
   .param("userId", userId)
   .query(UUID.class).optional();
 }

 Optional<UUID> activeConversationId(UUID userId) {
  return jdbc.sql("select active_conversation_id from user_settings where user_id = :userId")
   .param("userId", userId)
   .query((rs, row) -> rs.getObject("active_conversation_id", UUID.class))
   .optional()
   .flatMap(Optional::ofNullable);
 }

 void setActive(UUID userId, UUID conversationId) {
  jdbc.sql("""
    insert into user_settings (user_id, active_conversation_id) values (:userId, :conversationId)
    on conflict (user_id) do update set active_conversation_id = excluded.active_conversation_id
    """)
   .param("userId", userId).param("conversationId", conversationId)
   .update();
 }
}
