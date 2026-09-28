-- Conversation type chosen at creation: general assistant or Danish exam preparation (with study materials).
alter table conversations add column mode text not null default 'GENERAL'
 check (mode in ('GENERAL', 'DANISH_EXAM'));
