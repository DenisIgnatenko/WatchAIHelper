-- Initial schema (docs/architecture.md, section 5). Phase 2 scope: no attachments table yet (Phase 3).
-- Every row carries user_id: the model is ready for more users without a migration of existing data.

create table users (
 id uuid primary key,
 created_at timestamptz not null default now()
);

-- Client devices. Only the SHA-256 hash of a device token is stored.
create table devices (
 id uuid primary key,
 user_id uuid not null references users (id) on delete cascade,
 name text not null,
 token_hash text not null unique,
 created_at timestamptz not null default now(),
 last_seen_at timestamptz,
 revoked_at timestamptz
);

create table conversations (
 id uuid primary key,
 user_id uuid not null references users (id) on delete cascade,
 title text not null,
 status text not null default 'ACTIVE' check (status in ('ACTIVE', 'ARCHIVED')),
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);
create index conversations_user_updated on conversations (user_id, updated_at desc);

-- The active conversation is shared by all devices of a user (spec 6).
create table user_settings (
 user_id uuid primary key references users (id) on delete cascade,
 active_conversation_id uuid references conversations (id) on delete set null
);

-- OPEN: editable. FROZEN: submitted, waiting for attachments. CONSUMED: turned into a user message.
create table drafts (
 id uuid primary key,
 user_id uuid not null references users (id) on delete cascade,
 conversation_id uuid not null references conversations (id) on delete cascade,
 text text,
 state text not null check (state in ('OPEN', 'FROZEN', 'CONSUMED')),
 version int not null default 0,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);
-- At most one editable draft per conversation. A FROZEN draft belongs to its AI request, so a new
-- question can be started while the previous one still waits for uploads.
create unique index drafts_one_open_per_conversation on drafts (conversation_id) where state = 'OPEN';

create table messages (
 id uuid primary key,
 user_id uuid not null references users (id) on delete cascade,
 conversation_id uuid not null references conversations (id) on delete cascade,
 -- Stable order inside a conversation (1, 2, 3, ...).
 seq int not null,
 role text not null check (role in ('USER', 'ASSISTANT')),
 text text,
 -- A user message is created from exactly one draft.
 draft_id uuid unique references drafts (id),
 ai_request_id uuid,
 suggested_actions jsonb not null default '[]',
 response_mode text,
 model text,
 usage jsonb,
 created_at timestamptz not null default now(),
 unique (conversation_id, seq)
);

create table ai_requests (
 id uuid primary key,
 user_id uuid not null references users (id) on delete cascade,
 conversation_id uuid not null references conversations (id) on delete cascade,
 -- One AI request per draft: two Sends of the same draft cannot both win (spec 37).
 draft_id uuid not null unique references drafts (id),
 idempotency_key uuid not null,
 state text not null check (state in
  ('WAITING_FOR_ATTACHMENTS', 'BLOCKED', 'QUEUED', 'PROCESSING', 'COMPLETED', 'FAILED', 'CANCELLED')),
 user_message_id uuid references messages (id),
 -- One assistant message per request, even if a crashed attempt is retried.
 assistant_message_id uuid unique references messages (id),
 response_mode text not null,
 attempt_count int not null default 0,
 -- QUEUED: do not start before this time (retry backoff).
 not_before timestamptz,
 -- PROCESSING: lease; after it expires the request is considered abandoned.
 locked_until timestamptz,
 last_error_code text,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 started_at timestamptz,
 completed_at timestamptz,
 unique (user_id, idempotency_key)
);
create index ai_requests_claimable on ai_requests (created_at) where state in ('QUEUED', 'PROCESSING');
create index ai_requests_conversation on ai_requests (conversation_id, created_at desc);
