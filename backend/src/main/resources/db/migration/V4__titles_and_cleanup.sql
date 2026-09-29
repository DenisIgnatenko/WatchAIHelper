-- Phase 5: conversation titles chosen by the user or the AI, the AI usage ledger, and indexes for
-- conversation deletion and image retention.

-- Who set the current title:
--  PLACEHOLDER - derived by the backend (default, first line of the first question, "Photos");
--  AI          - suggested by the model with an answer; replaces PLACEHOLDER only;
--  USER        - renamed by the user; never overwritten automatically.
alter table conversations add column title_source text not null default 'PLACEHOLDER'
 check (title_source in ('PLACEHOLDER', 'AI', 'USER'));

-- One row per stored AI answer: tokens used, for the cost report.
-- Deliberately without foreign keys to conversations/messages: spending stays in the report after the
-- user deletes a conversation (privacy deletes the content, not the bill).
create table ai_usage (
 id uuid primary key,
 user_id uuid not null references users (id) on delete cascade,
 ai_request_id uuid not null unique,
 model text,
 input_tokens bigint not null default 0,
 -- Part of input_tokens read from the OpenAI prompt cache (cheaper).
 cached_input_tokens bigint not null default 0,
 -- Part of input_tokens written to the prompt cache (slightly more expensive).
 cache_write_tokens bigint not null default 0,
 -- Includes reasoning tokens.
 output_tokens bigint not null default 0,
 created_at timestamptz not null
);
create index ai_usage_user_created on ai_usage (user_id, created_at);

-- History before this migration: answers already carry input/output tokens (no cache details were recorded,
-- so their cost is an upper estimate).
insert into ai_usage (id, user_id, ai_request_id, model, input_tokens, output_tokens, created_at)
select m.id, m.user_id, m.ai_request_id, m.model,
       coalesce((m.usage ->> 'inputTokens')::bigint, 0),
       coalesce((m.usage ->> 'outputTokens')::bigint, 0),
       m.created_at
from messages m
where m.role = 'ASSISTANT' and m.ai_request_id is not null;

-- Retention job: uploaded images whose bytes are still stored, oldest first.
create index attachments_retention on attachments (uploaded_at) where state = 'UPLOADED' and blob_key is not null;

-- Deleting a conversation reads the blob keys of its drafts first.
create index drafts_conversation on drafts (conversation_id);

-- Cancel Send returns the draft to OPEN, and the same draft can be sent again. So "one request per draft"
-- now means one request that is not cancelled. Two concurrent Sends are still serialized by the draft row lock,
-- and the partial unique index remains the last line of defence (spec 37).
alter table ai_requests drop constraint ai_requests_draft_id_key;
create unique index ai_requests_one_live_per_draft on ai_requests (draft_id) where state <> 'CANCELLED';
