package com.aicopilot.submission;

import static com.aicopilot.common.Db.ts;

import com.aicopilot.ai.ResponseMode;
import com.aicopilot.submission.AiRequest.State;
import java.time.Instant;
import java.util.Optional;
import java.util.UUID;
import org.springframework.jdbc.core.RowMapper;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Repository;

/**
 * AI requests. State changes are single SQL statements guarded by the expected current state
 * ({@code where state = ...}), so a stale caller can never move a request backwards.
 */
@Repository
public class AiRequestRepository {

 private static final RowMapper<AiRequest> MAPPER = (rs, row) -> new AiRequest(
  rs.getObject("id", UUID.class),
  rs.getObject("user_id", UUID.class),
  rs.getObject("conversation_id", UUID.class),
  rs.getObject("draft_id", UUID.class),
  State.valueOf(rs.getString("state")),
  rs.getObject("user_message_id", UUID.class),
  rs.getObject("assistant_message_id", UUID.class),
  ResponseMode.valueOf(rs.getString("response_mode")),
  rs.getInt("attempt_count"),
  rs.getString("last_error_code"));

 private final JdbcClient jdbc;

 AiRequestRepository(JdbcClient jdbc) {
  this.jdbc = jdbc;
 }

 public Optional<AiRequest> find(UUID id) {
  return jdbc.sql("select * from ai_requests where id = :id").param("id", id).query(MAPPER).optional();
 }

 Optional<AiRequest> findForUser(UUID userId, UUID id) {
  return jdbc.sql("select * from ai_requests where id = :id and user_id = :userId")
   .param("id", id).param("userId", userId)
   .query(MAPPER).optional();
 }

 Optional<AiRequest> findByIdempotencyKey(UUID userId, UUID key) {
  return jdbc.sql("select * from ai_requests where user_id = :userId and idempotency_key = :key")
   .param("userId", userId).param("key", key)
   .query(MAPPER).optional();
 }

 Optional<AiRequest> findByDraft(UUID draftId) {
  return jdbc.sql("select * from ai_requests where draft_id = :draftId")
   .param("draftId", draftId)
   .query(MAPPER).optional();
 }

 Optional<AiRequest> latestForConversation(UUID conversationId) {
  return jdbc.sql("select * from ai_requests where conversation_id = :id order by created_at desc limit 1")
   .param("id", conversationId)
   .query(MAPPER).optional();
 }

 void insertWaiting(UUID id, UUID userId, UUID conversationId, UUID draftId, UUID key, ResponseMode mode, Instant now) {
  jdbc.sql("""
    insert into ai_requests (id, user_id, conversation_id, draft_id, idempotency_key, state, response_mode,
                             created_at, updated_at)
    values (:id, :userId, :conversationId, :draftId, :key, 'WAITING_FOR_ATTACHMENTS', :mode, :now, :now)
    """)
   .param("id", id).param("userId", userId).param("conversationId", conversationId)
   .param("draftId", draftId).param("key", key).param("mode", mode.name()).param("now", ts(now))
   .update();
 }

 void markQueued(UUID id, UUID userMessageId, Instant now) {
  jdbc.sql("""
    update ai_requests set state = 'QUEUED', user_message_id = :messageId, updated_at = :now
    where id = :id and state = 'WAITING_FOR_ATTACHMENTS'
    """)
   .param("id", id).param("messageId", userMessageId).param("now", ts(now))
   .update();
 }

 /**
  * Atomically takes the oldest request that is ready to run: QUEUED (after its backoff) or PROCESSING
  * with an expired lease (its worker crashed). {@code skip locked} lets several workers run safely.
  */
 public Optional<AiRequest> claimNext(Instant now, Instant leaseUntil) {
  return jdbc.sql("""
    update ai_requests
    set state = 'PROCESSING', attempt_count = attempt_count + 1, locked_until = :leaseUntil,
        started_at = coalesce(started_at, :now), updated_at = :now
    where id = (
     select id from ai_requests
     where (state = 'QUEUED' and (not_before is null or not_before <= :now))
        or (state = 'PROCESSING' and locked_until < :now)
     order by created_at
     limit 1
     for update skip locked
    )
    returning *
    """)
   .param("now", ts(now)).param("leaseUntil", ts(leaseUntil))
   .query(MAPPER).optional();
 }

 /** Locks a request row inside the caller's transaction. */
 public Optional<AiRequest> lock(UUID id) {
  return jdbc.sql("select * from ai_requests where id = :id for update").param("id", id).query(MAPPER).optional();
 }

 public void complete(UUID id, UUID assistantMessageId, Instant now) {
  jdbc.sql("""
    update ai_requests
    set state = 'COMPLETED', assistant_message_id = :messageId, locked_until = null, last_error_code = null,
        completed_at = :now, updated_at = :now
    where id = :id and state = 'PROCESSING'
    """)
   .param("id", id).param("messageId", assistantMessageId).param("now", ts(now))
   .update();
 }

 public void requeue(UUID id, Instant notBefore, String errorCode, Instant now) {
  jdbc.sql("""
    update ai_requests
    set state = 'QUEUED', not_before = :notBefore, locked_until = null, last_error_code = :code, updated_at = :now
    where id = :id and state = 'PROCESSING'
    """)
   .param("id", id).param("notBefore", ts(notBefore)).param("code", errorCode).param("now", ts(now))
   .update();
 }

 public void fail(UUID id, String errorCode, Instant now) {
  jdbc.sql("""
    update ai_requests
    set state = 'FAILED', locked_until = null, last_error_code = :code, completed_at = :now, updated_at = :now
    where id = :id and state = 'PROCESSING'
    """)
   .param("id", id).param("code", errorCode).param("now", ts(now))
   .update();
 }
}
