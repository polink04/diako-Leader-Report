-- Diako Leader Report · Supabase schema (email/password login)
-- Supabase SQL Editor에서 이 파일 전체를 실행하세요.
-- 기존 익명 테스트 보고서는 자동으로 삭제되며, 로그인 계정의 보고서는 보존됩니다.

create extension if not exists pgcrypto;

drop function if exists public.create_report(date, text, text, text, text, text, text);
drop function if exists public.update_report(uuid, date, text, text, text, text, text, text);
drop function if exists public.get_my_reports(uuid[]);
drop function if exists public.admin_list_reports();
drop function if exists public.admin_add_comment(uuid, text);
drop function if exists public.admin_delete_report(uuid);
drop function if exists public.is_report_admin();
drop function if exists public.current_report_profile();
drop function if exists public.list_my_reports();

create table if not exists public.allowed_report_users (
  email text primary key,
  display_name text not null check (char_length(display_name) between 1 and 80),
  is_admin boolean not null default false,
  created_at timestamptz not null default now()
);

create table if not exists public.reports (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users(id) on delete cascade,
  owner_email text,
  meeting_date date not null,
  leader_name text not null check (char_length(leader_name) between 1 and 80),
  group_name text not null check (char_length(group_name) between 1 and 80),
  decisions text not null check (char_length(decisions) between 1 and 10000),
  action_plan text not null check (char_length(action_plan) between 1 and 10000),
  executed text not null default '' check (char_length(executed) <= 10000),
  discoveries text not null default '' check (char_length(discoveries) <= 10000),
  status text not null default 'planned' check (status in ('planned', 'completed')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.report_comments (
  id bigint generated always as identity primary key,
  report_id uuid not null references public.reports(id) on delete cascade,
  body text not null check (char_length(body) between 1 and 2000),
  author_name text not null default '곽길영 대표',
  created_at timestamptz not null default now()
);

alter table public.reports add column if not exists user_id uuid references auth.users(id) on delete cascade;
alter table public.reports add column if not exists owner_email text;
delete from public.reports where user_id is null;
alter table public.reports alter column user_id set not null;
alter table public.reports alter column owner_email set not null;
alter table public.reports drop column if exists edit_token;

drop index if exists public.idx_reports_edit_token;
create index if not exists idx_reports_user_id on public.reports(user_id);
create index if not exists idx_reports_meeting_date on public.reports(meeting_date desc);
create index if not exists idx_report_comments_report_id on public.report_comments(report_id);

alter table public.allowed_report_users enable row level security;
alter table public.reports enable row level security;
alter table public.report_comments enable row level security;
revoke all on public.allowed_report_users from anon, authenticated;
revoke all on public.reports from anon, authenticated;
revoke all on public.report_comments from anon, authenticated;

create or replace function public.is_allowed_report_user()
returns boolean
language sql
stable
security definer
set search_path = public, auth
as $$
  select auth.uid() is not null and exists (
    select 1 from public.allowed_report_users u
    where lower(u.email) = lower(coalesce(auth.jwt() ->> 'email', ''))
  );
$$;

create or replace function public.is_report_admin()
returns boolean
language sql
stable
security definer
set search_path = public, auth
as $$
  select auth.uid() is not null and exists (
    select 1 from public.allowed_report_users u
    where lower(u.email) = lower(coalesce(auth.jwt() ->> 'email', '')) and u.is_admin = true
  );
$$;

create or replace function public.current_report_profile()
returns table(email text, display_name text, is_admin boolean)
language sql
stable
security definer
set search_path = public, auth
as $$
  select u.email, u.display_name, u.is_admin
  from public.allowed_report_users u
  where auth.uid() is not null
    and lower(u.email) = lower(coalesce(auth.jwt() ->> 'email', ''));
$$;

create or replace function public.create_report(
  p_meeting_date date,
  p_leader_name text,
  p_group_name text,
  p_decisions text,
  p_action_plan text,
  p_executed text default '',
  p_discoveries text default ''
)
returns table(id uuid, created_at timestamptz)
language plpgsql
security definer
set search_path = public, auth
as $$
begin
  if not public.is_allowed_report_user() then raise exception '허용되지 않은 계정입니다.'; end if;
  if trim(coalesce(p_leader_name, '')) = '' or trim(coalesce(p_group_name, '')) = ''
     or trim(coalesce(p_decisions, '')) = '' or trim(coalesce(p_action_plan, '')) = '' then
    raise exception '필수 항목을 모두 입력해 주세요.';
  end if;

  return query
  insert into public.reports as new_report (
    user_id, owner_email, meeting_date, leader_name, group_name,
    decisions, action_plan, executed, discoveries, status
  ) values (
    auth.uid(), lower(auth.jwt() ->> 'email'), p_meeting_date,
    trim(p_leader_name), trim(p_group_name), trim(p_decisions), trim(p_action_plan),
    trim(coalesce(p_executed, '')), trim(coalesce(p_discoveries, '')),
    case when trim(coalesce(p_executed, '')) <> '' and trim(coalesce(p_discoveries, '')) <> ''
      then 'completed' else 'planned' end
  )
  returning new_report.id, new_report.created_at;
end;
$$;

create or replace function public.update_report(
  p_report_id uuid,
  p_meeting_date date,
  p_leader_name text,
  p_group_name text,
  p_decisions text,
  p_action_plan text,
  p_executed text default '',
  p_discoveries text default ''
)
returns boolean
language plpgsql
security definer
set search_path = public, auth
as $$
declare changed_count integer;
begin
  if not public.is_allowed_report_user() then raise exception '허용되지 않은 계정입니다.'; end if;
  if trim(coalesce(p_leader_name, '')) = '' or trim(coalesce(p_group_name, '')) = ''
     or trim(coalesce(p_decisions, '')) = '' or trim(coalesce(p_action_plan, '')) = '' then
    raise exception '필수 항목을 모두 입력해 주세요.';
  end if;

  update public.reports set
    meeting_date = p_meeting_date,
    leader_name = trim(p_leader_name),
    group_name = trim(p_group_name),
    decisions = trim(p_decisions),
    action_plan = trim(p_action_plan),
    executed = trim(coalesce(p_executed, '')),
    discoveries = trim(coalesce(p_discoveries, '')),
    status = case when trim(coalesce(p_executed, '')) <> '' and trim(coalesce(p_discoveries, '')) <> ''
      then 'completed' else 'planned' end,
    updated_at = now()
  where id = p_report_id and user_id = auth.uid();

  get diagnostics changed_count = row_count;
  return changed_count = 1;
end;
$$;

create or replace function public.list_my_reports()
returns table(
  id uuid, meeting_date date, leader_name text, group_name text,
  decisions text, action_plan text, executed text, discoveries text, status text,
  owner_email text, created_at timestamptz, updated_at timestamptz, comments jsonb
)
language plpgsql
stable
security definer
set search_path = public, auth
as $$
begin
  if not public.is_allowed_report_user() then raise exception '허용되지 않은 계정입니다.'; end if;
  return query
  select r.id, r.meeting_date, r.leader_name, r.group_name,
    r.decisions, r.action_plan, r.executed, r.discoveries, r.status,
    r.owner_email, r.created_at, r.updated_at,
    coalesce((select jsonb_agg(jsonb_build_object(
      'id', c.id, 'body', c.body, 'author_name', c.author_name, 'created_at', c.created_at
    ) order by c.created_at) from public.report_comments c where c.report_id = r.id), '[]'::jsonb)
  from public.reports r
  where r.user_id = auth.uid()
  order by r.meeting_date desc, r.created_at desc;
end;
$$;

create or replace function public.admin_list_reports()
returns table(
  id uuid, meeting_date date, leader_name text, group_name text,
  decisions text, action_plan text, executed text, discoveries text, status text,
  owner_email text, created_at timestamptz, updated_at timestamptz, comments jsonb
)
language plpgsql
stable
security definer
set search_path = public, auth
as $$
begin
  if not public.is_report_admin() then raise exception '관리자 권한이 없습니다.'; end if;
  return query
  select r.id, r.meeting_date, r.leader_name, r.group_name,
    r.decisions, r.action_plan, r.executed, r.discoveries, r.status,
    r.owner_email, r.created_at, r.updated_at,
    coalesce((select jsonb_agg(jsonb_build_object(
      'id', c.id, 'body', c.body, 'author_name', c.author_name, 'created_at', c.created_at
    ) order by c.created_at) from public.report_comments c where c.report_id = r.id), '[]'::jsonb)
  from public.reports r
  order by r.meeting_date desc, r.created_at desc;
end;
$$;

create or replace function public.admin_add_comment(p_report_id uuid, p_body text)
returns table(id bigint, report_id uuid, body text, author_name text, created_at timestamptz)
language plpgsql
security definer
set search_path = public, auth
as $$
begin
  if not public.is_report_admin() then raise exception '관리자 권한이 없습니다.'; end if;
  if trim(coalesce(p_body, '')) = '' then raise exception '코멘트를 입력해 주세요.'; end if;
  return query
  insert into public.report_comments as new_comment(report_id, body, author_name)
  values (p_report_id, trim(p_body), '곽길영 대표')
  returning new_comment.id, new_comment.report_id, new_comment.body,
    new_comment.author_name, new_comment.created_at;
end;
$$;

create or replace function public.admin_delete_report(p_report_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public, auth
as $$
declare deleted_count integer;
begin
  if not public.is_report_admin() then raise exception '관리자 권한이 없습니다.'; end if;

  delete from public.reports where id = p_report_id;
  get diagnostics deleted_count = row_count;
  return deleted_count = 1;
end;
$$;

revoke all on function public.is_allowed_report_user() from public;
revoke all on function public.is_report_admin() from public;
revoke all on function public.current_report_profile() from public;
revoke all on function public.create_report(date, text, text, text, text, text, text) from public;
revoke all on function public.update_report(uuid, date, text, text, text, text, text, text) from public;
revoke all on function public.list_my_reports() from public;
revoke all on function public.admin_list_reports() from public;
revoke all on function public.admin_add_comment(uuid, text) from public;
revoke all on function public.admin_delete_report(uuid) from public;

grant execute on function public.is_allowed_report_user() to authenticated;
grant execute on function public.is_report_admin() to authenticated;
grant execute on function public.current_report_profile() to authenticated;
grant execute on function public.create_report(date, text, text, text, text, text, text) to authenticated;
grant execute on function public.update_report(uuid, date, text, text, text, text, text, text) to authenticated;
grant execute on function public.list_my_reports() to authenticated;
grant execute on function public.admin_list_reports() to authenticated;
grant execute on function public.admin_add_comment(uuid, text) to authenticated;
grant execute on function public.admin_delete_report(uuid) to authenticated;

-- 로그인 허용 목록은 Supabase SQL Editor에서 별도로 입력합니다.
