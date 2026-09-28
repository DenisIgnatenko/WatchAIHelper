package com.aicopilot.draft;

import static com.aicopilot.common.Db.ts;

import com.aicopilot.draft.Draft.State;
import java.time.Instant;
import java.util.Optional;
import java.util.UUID;
import org.springframework.jdbc.core.RowMapper;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Repository;

@Repository
class DraftRepository {

 private static final RowMapper<Draft> MAPPER = (rs, row) -> new Draft(
  rs.getObject("id", UUID.class),
  rs.getObject("user_id", UUID.class),
  rs.getObject("conversation_id", UUID.class),
  rs.getString("text"),
  State.valueOf(rs.getString("state")));

 private final JdbcClient jdbc;

 DraftRepository(JdbcClient jdbc) {
  this.jdbc = jdbc;
 }

 Optional<Draft> find(UUID draftId) {
  return jdbc.sql("select * from drafts where id = :id").param("id", draftId).query(MAPPER).optional();
 }

 Optional<Draft> findOpen(UUID conversationId) {
  return jdbc.sql("select * from drafts where conversation_id = :id and state = 'OPEN'")
   .param("id", conversationId)
   .query(MAPPER).optional();
 }

 /** Creates an OPEN draft unless another request created one concurrently (partial unique index). */
 void insertOpenIfAbsent(UUID id, UUID userId, UUID conversationId, Instant now) {
  jdbc.sql("""
    insert into drafts (id, user_id, conversation_id, state, created_at, updated_at)
    values (:id, :userId, :conversationId, 'OPEN', :now, :now)
    on conflict do nothing
    """)
   .param("id", id).param("userId", userId).param("conversationId", conversationId).param("now", ts(now))
   .update();
 }

 /** Row lock: serializes concurrent submits of the same draft (Watch vs iPhone, spec 37). */
 Optional<Draft> lock(UUID userId, UUID draftId) {
  return jdbc.sql("select * from drafts where id = :id and user_id = :userId for update")
   .param("id", draftId).param("userId", userId)
   .query(MAPPER).optional();
 }

 void freeze(UUID draftId, String text, Instant now) {
  jdbc.sql("""
    update drafts set state = 'FROZEN', text = :text, version = version + 1, updated_at = :now
    where id = :id and state = 'OPEN'
    """)
   .param("id", draftId).param("text", text).param("now", ts(now))
   .update();
 }

 void consume(UUID draftId, Instant now) {
  jdbc.sql("update drafts set state = 'CONSUMED', updated_at = :now where id = :id and state = 'FROZEN'")
   .param("id", draftId).param("now", ts(now))
   .update();
 }
}
