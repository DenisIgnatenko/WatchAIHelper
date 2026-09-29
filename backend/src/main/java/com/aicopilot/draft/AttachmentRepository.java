package com.aicopilot.draft;

import static com.aicopilot.common.Db.ts;

import com.aicopilot.draft.Attachment.Source;
import com.aicopilot.draft.Attachment.State;
import java.time.Instant;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.springframework.jdbc.core.RowMapper;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Repository;

@Repository
class AttachmentRepository {

 private static final RowMapper<Attachment> MAPPER = (rs, row) -> new Attachment(
  rs.getObject("id", UUID.class),
  rs.getObject("user_id", UUID.class),
  rs.getObject("draft_id", UUID.class),
  rs.getInt("position"),
  Source.valueOf(rs.getString("source")),
  rs.getString("mime_type"),
  rs.getLong("byte_size"),
  rs.getString("sha256"),
  State.valueOf(rs.getString("state")),
  rs.getString("failure_reason"),
  rs.getString("blob_key"));

 private final JdbcClient jdbc;

 AttachmentRepository(JdbcClient jdbc) {
  this.jdbc = jdbc;
 }

 Optional<Attachment> find(UUID userId, UUID id) {
  return jdbc.sql("select * from attachments where id = :id and user_id = :userId")
   .param("id", id).param("userId", userId)
   .query(MAPPER).optional();
 }

 Optional<Attachment> lock(UUID id) {
  return jdbc.sql("select * from attachments where id = :id for update").param("id", id).query(MAPPER).optional();
 }

 List<Attachment> listByDraft(UUID draftId) {
  return jdbc.sql("select * from attachments where draft_id = :draftId order by position")
   .param("draftId", draftId)
   .query(MAPPER).list();
 }

 /** Next position; the caller holds the draft row lock, so concurrent registrations cannot collide. */
 int nextPosition(UUID draftId) {
  return jdbc.sql("select coalesce(max(position), 0) + 1 from attachments where draft_id = :draftId")
   .param("draftId", draftId)
   .query(Integer.class).single();
 }

 void insert(Attachment a, Integer width, Integer height, Instant now) {
  jdbc.sql("""
    insert into attachments (id, user_id, draft_id, position, source, mime_type, byte_size, sha256,
                             width, height, state, created_at)
    values (:id, :userId, :draftId, :position, :source, :mimeType, :byteSize, :sha256,
            :width, :height, 'PENDING', :now)
    """)
   .param("id", a.id()).param("userId", a.userId()).param("draftId", a.draftId())
   .param("position", a.position()).param("source", a.source().name()).param("mimeType", a.mimeType())
   .param("byteSize", a.byteSize()).param("sha256", a.sha256())
   .param("width", width, java.sql.Types.INTEGER).param("height", height, java.sql.Types.INTEGER)
   .param("now", ts(now))
   .update();
 }

 void markUploaded(UUID id, String blobKey, Instant now) {
  jdbc.sql("""
    update attachments set state = 'UPLOADED', blob_key = :key, failure_reason = null, uploaded_at = :now
    where id = :id
    """)
   .param("id", id).param("key", blobKey).param("now", ts(now))
   .update();
 }

 /**
  * Moves all images of one draft to the end of another, keeping their order. The new positions start after the
  * target's last one, so {@code unique (draft_id, position)} cannot collide.
  */
 void moveAll(UUID fromDraftId, UUID toDraftId) {
  jdbc.sql("""
    update attachments
    set draft_id = :to,
        position = position + (select coalesce(max(position), 0) from attachments where draft_id = :to)
    where draft_id = :from
    """)
   .param("from", fromDraftId).param("to", toDraftId)
   .update();
 }

 /** Ids of all images of a conversation (any draft state). */
 List<UUID> idsByConversation(UUID conversationId) {
  return jdbc.sql("""
    select a.id from attachments a join drafts d on d.id = a.draft_id where d.conversation_id = :id
    """)
   .param("id", conversationId)
   .query(UUID.class).list();
 }

 /** Uploaded images older than the retention period whose bytes are still stored. */
 List<Attachment> expired(Instant uploadedBefore, int limit) {
  return jdbc.sql("""
    select * from attachments
    where state = 'UPLOADED' and blob_key is not null and uploaded_at < :before
    order by uploaded_at limit :limit
    """)
   .param("before", ts(uploadedBefore)).param("limit", limit)
   .query(MAPPER).list();
 }

 /** The bytes are gone; the row stays, so the history still shows "📷 3" and the AI gets a note instead. */
 void markPurged(UUID id, Instant now) {
  jdbc.sql("update attachments set blob_key = null, purged_at = :now where id = :id")
   .param("id", id).param("now", ts(now))
   .update();
 }

 void delete(UUID id) {
  jdbc.sql("delete from attachments where id = :id").param("id", id).update();
 }

 /** PENDING longer than the timeout -> FAILED. Returns the affected drafts. */
 List<UUID> failStalePending(Instant olderThan) {
  return jdbc.sql("""
    update attachments set state = 'FAILED', failure_reason = 'upload_timeout'
    where state = 'PENDING' and created_at < :olderThan
    returning draft_id
    """)
   .param("olderThan", ts(olderThan))
   .query(UUID.class).list().stream().distinct().toList();
 }

 Counts counts(UUID draftId) {
  return jdbc.sql("""
    select count(*) as total,
           count(*) filter (where state = 'UPLOADED') as uploaded,
           count(*) filter (where state = 'FAILED') as failed
    from attachments where draft_id = :draftId
    """)
   .param("draftId", draftId)
   .query((rs, row) -> new Counts(rs.getInt("total"), rs.getInt("uploaded"), rs.getInt("failed")))
   .single();
 }

 record Counts(int total, int uploaded, int failed) {
 }
}
