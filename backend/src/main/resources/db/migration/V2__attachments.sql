-- Phase 3: images attached to drafts (docs/architecture.md, sections 5 and 8).
-- Bytes live in BlobStorage (blob_key); the database keeps only metadata (spec 48).

create table attachments (
 id uuid primary key,
 user_id uuid not null references users (id) on delete cascade,
 draft_id uuid not null references drafts (id) on delete cascade,
 -- Order inside the message (spec 27). Assigned by the backend in registration order; gaps after removal are fine.
 position int not null,
 source text not null check (source in ('CAMERA', 'PHOTO_LIBRARY')),
 mime_type text not null check (mime_type in ('image/jpeg', 'image/png')),
 byte_size bigint not null check (byte_size > 0),
 -- Expected SHA-256 (hex), declared at registration; the upload must match it.
 sha256 text not null,
 width int,
 height int,
 -- PENDING: registered, bytes not yet received. UPLOADED: stored and verified. FAILED: see failure_reason.
 state text not null check (state in ('PENDING', 'UPLOADED', 'FAILED')),
 failure_reason text,
 blob_key text,
 created_at timestamptz not null default now(),
 uploaded_at timestamptz,
 -- Set when the retention job deletes the bytes (Phase 5); metadata stays for the conversation history.
 purged_at timestamptz,
 unique (draft_id, position)
);
create index attachments_draft on attachments (draft_id, position);
create index attachments_pending on attachments (created_at) where state = 'PENDING';
