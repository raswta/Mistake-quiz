-- =====================================================================
-- Mistake Notebook v2 : fresh Supabase schema (run the whole file once)
-- Supabase dashboard -> SQL Editor -> New query -> paste -> Run
-- This DELETES the old tables and all their data, then rebuilds them.
-- Admin password is already set below. Do NOT upload this file to GitHub.
-- =====================================================================

drop function if exists public.admin_update_prompt(text, text, text, text);
drop function if exists public.admin_check(text, text);
drop table if exists public.mistakes      cascade;
drop table if exists public.folders       cascade;
drop table if exists public.subjects      cascade;
drop table if exists public.prompts       cascade;
drop table if exists public.admin_secrets cascade;
drop table if exists public.app_users     cascade;

create extension if not exists pgcrypto with schema extensions;

-- ---------- Tables ----------
create table public.app_users (
  username   text primary key check (username ~ '^[a-z0-9_]{3,24}$'),
  created_at timestamptz not null default now()
);

create table public.subjects (
  id         uuid primary key default gen_random_uuid(),
  username   text not null references public.app_users(username) on delete cascade,
  name       text not null check (char_length(name) between 1 and 60),
  field      text not null default 'more' check (field in ('math','physics','biology','chemistry','more')),
  created_at timestamptz not null default now()
);
create index subjects_username_idx on public.subjects(username);

create table public.folders (
  id         uuid primary key default gen_random_uuid(),
  subject_id uuid not null references public.subjects(id) on delete cascade,
  username   text not null references public.app_users(username) on delete cascade,
  name       text not null check (char_length(name) between 1 and 60),
  created_at timestamptz not null default now()
);
create index folders_subject_idx on public.folders(subject_id);

create table public.mistakes (
  id         uuid primary key default gen_random_uuid(),
  folder_id  uuid not null references public.folders(id) on delete cascade,
  username   text not null references public.app_users(username) on delete cascade,
  content    text not null check (char_length(content) between 1 and 2000),
  note       text check (char_length(note) <= 2000),
  created_at timestamptz not null default now()
);
create index mistakes_folder_idx on public.mistakes(folder_id);

create table public.prompts (
  key         text primary key,
  title       text not null,
  description text not null default '',
  content     text not null,
  updated_at  timestamptz not null default now()
);

create table public.admin_secrets (
  username      text primary key,
  password_hash text not null
);

-- ---------- Row Level Security ----------
alter table public.app_users     enable row level security;
alter table public.subjects      enable row level security;
alter table public.folders       enable row level security;
alter table public.mistakes      enable row level security;
alter table public.prompts       enable row level security;
alter table public.admin_secrets enable row level security;

create policy "users read"    on public.app_users for select using (true);
create policy "users create"  on public.app_users for insert with check (true);
create policy "subjects all"  on public.subjects  for all using (true) with check (true);
create policy "folders all"   on public.folders   for all using (true) with check (true);
create policy "mistakes all"  on public.mistakes  for all using (true) with check (true);
create policy "prompts read"  on public.prompts   for select using (true);

revoke all on public.admin_secrets from anon, authenticated;
grant select, insert                 on public.app_users to anon, authenticated;
grant select, insert, update, delete on public.subjects  to anon, authenticated;
grant select, insert, update, delete on public.folders   to anon, authenticated;
grant select, insert, update, delete on public.mistakes  to anon, authenticated;
grant select                         on public.prompts   to anon, authenticated;

-- ---------- Admin functions ----------
create or replace function public.admin_check(p_username text, p_password text)
returns boolean
language sql
security definer
set search_path = public, extensions
as $$
  select exists (
    select 1 from public.admin_secrets
    where username = lower(p_username)
      and password_hash = crypt(p_password, password_hash)
  );
$$;

create or replace function public.admin_update_prompt(
  p_username text, p_password text, p_key text, p_content text)
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  if not public.admin_check(p_username, p_password) then
    raise exception 'Not allowed';
  end if;
  update public.prompts set content = p_content, updated_at = now() where key = p_key;
end;
$$;

grant execute on function public.admin_check(text, text)                      to anon, authenticated;
grant execute on function public.admin_update_prompt(text, text, text, text) to anon, authenticated;

-- ---------- Admin account ----------
insert into public.app_users (username) values ('rasta1387');
insert into public.admin_secrets (username, password_hash)
values ('rasta1387', crypt('Rastaroco1387', gen_salt('bf')));

-- ---------- Default prompts (admin edits them inside the site) ----------
-- Placeholders: {{subject}} {{count}} {{difficulty}} {{mistakes}}
insert into public.prompts (key, title, description, content) values

('quiz_math', 'Quiz prompt: Math',
 'Used for subjects whose field is Math. Placeholders: {{subject}}, {{count}}, {{difficulty}}, {{mistakes}}.',
$q$You are an experienced math teacher. Below are problems and concepts a student got wrong in the subject "{{subject}}".
Write a quiz of {{count}} multiple-choice questions at {{difficulty}} difficulty that test the same skills and concepts. Do not copy the items; create new problems with different numbers.
Rules:
- Every question has exactly 4 options and exactly one correct answer. Wrong options should be common mistakes.
- Write formulas in plain text (for example x^2 + 3x - 4, sqrt(x), 3/4). Do not use LaTeX.
- Add a short explanation showing the key step.
- Return ONLY valid JSON, with no markdown and no extra text, in this exact shape:
[{"question":"...","options":["...","...","...","..."],"answer":0,"explanation":"..."}]
- "answer" is the index (0 to 3) of the correct option.

Student's mistakes:
{{mistakes}}$q$),

('quiz_physics', 'Quiz prompt: Physics',
 'Used for subjects whose field is Physics. Placeholders: {{subject}}, {{count}}, {{difficulty}}, {{mistakes}}.',
$q$You are an experienced physics teacher. Below are problems and concepts a student got wrong in the subject "{{subject}}".
Write a quiz of {{count}} multiple-choice questions at {{difficulty}} difficulty that test the same laws and concepts. Mix conceptual questions with short calculations. Do not copy the items.
Rules:
- Every question has exactly 4 options and exactly one correct answer.
- Include units in numeric answers. Write formulas in plain text, with no LaTeX.
- Add a short explanation that names the law or formula used.
- Return ONLY valid JSON, with no markdown and no extra text, in this exact shape:
[{"question":"...","options":["...","...","...","..."],"answer":0,"explanation":"..."}]
- "answer" is the index (0 to 3) of the correct option.

Student's mistakes:
{{mistakes}}$q$),

('quiz_biology', 'Quiz prompt: Biology',
 'Used for subjects whose field is Biology. Placeholders: {{subject}}, {{count}}, {{difficulty}}, {{mistakes}}.',
$q$You are an experienced biology teacher. Below are questions and concepts a student got wrong in the subject "{{subject}}".
Write a quiz of {{count}} multiple-choice questions at {{difficulty}} difficulty that test the same topics. Focus on understanding processes and relationships, not only on memorizing terms. Do not copy the items.
Rules:
- Every question has exactly 4 options and exactly one correct answer.
- Add a one or two sentence explanation.
- Return ONLY valid JSON, with no markdown and no extra text, in this exact shape:
[{"question":"...","options":["...","...","...","..."],"answer":0,"explanation":"..."}]
- "answer" is the index (0 to 3) of the correct option.

Student's mistakes:
{{mistakes}}$q$),

('quiz_chemistry', 'Quiz prompt: Chemistry',
 'Used for subjects whose field is Chemistry. Placeholders: {{subject}}, {{count}}, {{difficulty}}, {{mistakes}}.',
$q$You are an experienced chemistry teacher. Below are questions and concepts a student got wrong in the subject "{{subject}}".
Write a quiz of {{count}} multiple-choice questions at {{difficulty}} difficulty that test the same topics. Mix concepts with short calculations where it fits. Do not copy the items.
Rules:
- Every question has exactly 4 options and exactly one correct answer.
- Write chemical formulas in plain text (H2O, CO2, Fe2+). Do not use LaTeX.
- Add a short explanation.
- Return ONLY valid JSON, with no markdown and no extra text, in this exact shape:
[{"question":"...","options":["...","...","...","..."],"answer":0,"explanation":"..."}]
- "answer" is the index (0 to 3) of the correct option.

Student's mistakes:
{{mistakes}}$q$),

('quiz_more', 'Quiz prompt: More (other subjects)',
 'Used for subjects whose field is More, such as English or history. Placeholders: {{subject}}, {{count}}, {{difficulty}}, {{mistakes}}.',
$q$You are an experienced teacher of "{{subject}}". Below are items a student got wrong in class.
Write a quiz of {{count}} multiple-choice questions at {{difficulty}} difficulty that test the same topics. Do not simply copy the items; create new questions.
Rules:
- Every question has exactly 4 options and exactly one correct answer.
- Add a one-sentence explanation for the correct answer.
- Return ONLY valid JSON, with no markdown and no extra text, in this exact shape:
[{"question":"...","options":["...","...","...","..."],"answer":0,"explanation":"..."}]
- "answer" is the index (0 to 3) of the correct option.

Student's mistakes:
{{mistakes}}$q$),

('explain', 'Explain prompt (all subjects)',
 'Used by the Explain button on a mistake. Placeholders: {{subject}}, {{mistake}}.',
$q$You are a friendly teacher of "{{subject}}". A student got this wrong:

{{mistake}}

In at most 4 short sentences, explain why it is tricky and give the correct answer. Then add one extra example. Use simple English.$q$);
