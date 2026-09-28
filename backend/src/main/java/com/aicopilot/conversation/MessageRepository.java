package com.aicopilot.conversation;

import static com.aicopilot.common.Db.instant;
import static com.aicopilot.common.Db.ts;

import com.aicopilot.conversation.Message.Role;
import com.aicopilot.conversation.Message.SuggestedAction;
import java.time.Instant;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.springframework.jdbc.core.RowMapper;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Repository;
import tools.jackson.core.type.TypeReference;
import tools.jackson.databind.ObjectMapper;

/** Append-only message storage. There is deliberately no update method (immutability, spec 8). */
@Repository
class MessageRepository {

 private static final TypeReference<List<SuggestedAction>> ACTIONS = new TypeReference<>() {
 };

 private final JdbcClient jdbc;
 private final ObjectMapper json;
 private final RowMapper<Message> mapper;

 MessageRepository(JdbcClient jdbc, ObjectMapper json) {
  this.jdbc = jdbc;
  this.json = json;
  this.mapper = (rs, row) -> new Message(
   rs.getObject("id", UUID.class),
   rs.getObject("conversation_id", UUID.class),
   rs.getInt("seq"),
   Role.valueOf(rs.getString("role")),
   rs.getString("text"),
   // Phase 3 replaces this with the number of attachments of the message's draft.
   0,
   json.readValue(rs.getString("suggested_actions"), ACTIONS),
   instant(rs, "created_at"));
 }

 List<Message> listByConversation(UUID conversationId) {
  return jdbc.sql("select * from messages where conversation_id = :id order by seq")
   .param("id", conversationId)
   .query(mapper).list();
 }

 /** The last {@code limit} messages up to and including {@code maxSeq}, in conversation order. */
 List<Message> recent(UUID conversationId, int maxSeq, int limit) {
  return jdbc.sql("""
    select * from (
     select * from messages where conversation_id = :id and seq <= :maxSeq order by seq desc limit :limit
    ) recent order by seq
    """)
   .param("id", conversationId).param("maxSeq", maxSeq).param("limit", limit)
   .query(mapper).list();
 }

 Optional<Message> find(UUID id) {
  return jdbc.sql("select * from messages where id = :id").param("id", id).query(mapper).optional();
 }

 Optional<Message> lastAssistant(UUID conversationId) {
  return jdbc.sql("""
    select * from messages where conversation_id = :id and role = 'ASSISTANT' order by seq desc limit 1
    """)
   .param("id", conversationId)
   .query(mapper).optional();
 }

 /** Next seq; the caller must hold the conversation row lock. */
 int nextSeq(UUID conversationId) {
  return jdbc.sql("select coalesce(max(seq), 0) + 1 from messages where conversation_id = :id")
   .param("id", conversationId)
   .query(Integer.class).single();
 }

 void insert(NewMessage m) {
  jdbc.sql("""
    insert into messages (id, user_id, conversation_id, seq, role, text, draft_id, ai_request_id,
                          suggested_actions, response_mode, model, usage, created_at)
    values (:id, :userId, :conversationId, :seq, :role, :text, :draftId, :aiRequestId,
            cast(:actions as jsonb), :responseMode, :model, cast(:usage as jsonb), :createdAt)
    """)
   .param("id", m.id())
   .param("userId", m.userId())
   .param("conversationId", m.conversationId())
   .param("seq", m.seq())
   .param("role", m.role().name())
   .param("text", m.text())
   .param("draftId", m.draftId())
   .param("aiRequestId", m.aiRequestId())
   .param("actions", json.writeValueAsString(m.suggestedActions()))
   .param("responseMode", m.responseMode())
   .param("model", m.model())
   .param("usage", m.usageJson())
   .param("createdAt", ts(m.createdAt()))
   .update();
 }

 /** Insert parameters; only the repository needs this shape. */
 record NewMessage(
  UUID id, UUID userId, UUID conversationId, int seq, Role role, String text,
  UUID draftId, UUID aiRequestId, List<SuggestedAction> suggestedActions,
  String responseMode, String model, String usageJson, Instant createdAt
 ) {
 }
}
