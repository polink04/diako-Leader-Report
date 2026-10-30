-- Diako Leader Report · 주간회의 일정/회의록 기능 추가
-- 기존 데이터는 변경하거나 삭제하지 않습니다.
-- Supabase SQL Editor에서 이 파일 전체를 한 번 실행하세요.

create extension if not exists pgcrypto;

create table if not exists public.weekly_meetings (
  id uuid primary key default gen_random_uuid(),
  meeting_date date not null,
  meeting_time time not null,
  place text not null check (char_length(place) between 1 and 200),
  memo text not null default '' check (char_length(memo) <= 2000),
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.weekly_meeting_files (
  id uuid primary key default gen_random_uuid(),
  meeting_id uuid not null references public.weekly_meetings(id) on delete cascade,
  storage_path text not null unique,
  file_name text not null check (char_length(file_name) between 1 and 255),
  mime_type text not null check (mime_type in ('application/pdf', 'image/jpeg', 'image/png', 'image/webp')),
  file_size bigint not null check (file_size > 0 and file_size <= 15728640),
  created_at timestamptz not null default now()
);

create index if not exists idx_weekly_meetings_date on public.weekly_meetings(meeting_date desc, meeting_time desc);
create index if not exists idx_weekly_meeting_files_meeting on public.weekly_meeting_files(meeting_id);

alter table public.weekly_meetings enable row level security;
alter table public.weekly_meeting_files enable row level security;
revoke all on public.weekly_meetings from anon, authenticated;
revoke all on public.weekly_meeting_files from anon, authenticated;

create or replace function public.list_weekly_meetings()
returns table(
  id uuid, meeting_date date, meeting_time time, place text, memo text,
  created_at timestamptz, updated_at timestamptz, files jsonb
)
language plpgsql
stable
security definer
set search_path = public, auth
as $$
begin
  if not public.is_allowed_report_user() then raise exception '허용되지 않은 계정입니다.'; end if;
  return query
  select m.id, m.meeting_date, m.meeting_time, m.place, m.memo,
    m.created_at, m.updated_at,
    coalesce((select jsonb_agg(jsonb_build_object(
      'id', f.id, 'storage_path', f.storage_path, 'file_name', f.file_name,
      'mime_type', f.mime_type, 'file_size', f.file_size, 'created_at', f.created_at
    ) order by f.created_at desc) from public.weekly_meeting_files f where f.meeting_id = m.id), '[]'::jsonb)
  from public.weekly_meetings m
  order by m.meeting_date desc, m.meeting_time desc, m.created_at desc;
end;
$$;

create or replace function public.admin_save_weekly_meeting(
  p_meeting_id uuid,
  p_meeting_date date,
  p_meeting_time time,
  p_place text,
  p_memo text default ''
)
returns uuid
language plpgsql
security definer
set search_path = public, auth
as $$
declare saved_id uuid;
begin
  if not public.is_report_admin() then raise exception '관리자 권한이 없습니다.'; end if;
  if p_meeting_date is null or p_meeting_time is null or trim(coalesce(p_place, '')) = '' then
    raise exception '회의 날짜, 시간, 장소를 모두 입력해 주세요.';
  end if;

  if p_meeting_id is null then
    insert into public.weekly_meetings(meeting_date, meeting_time, place, memo, created_by)
    values (p_meeting_date, p_meeting_time, trim(p_place), trim(coalesce(p_memo, '')), auth.uid())
    returning id into saved_id;
  else
    update public.weekly_meetings set
      meeting_date = p_meeting_date,
      meeting_time = p_meeting_time,
      place = trim(p_place),
      memo = trim(coalesce(p_memo, '')),
      updated_at = now()
    where id = p_meeting_id
    returning id into saved_id;
    if saved_id is null then raise exception '수정할 회의 일정을 찾을 수 없습니다.'; end if;
  end if;
  return saved_id;
end;
$$;

create or replace function public.admin_add_weekly_meeting_file(
  p_meeting_id uuid,
  p_storage_path text,
  p_file_name text,
  p_mime_type text,
  p_file_size bigint
)
returns uuid
language plpgsql
security definer
set search_path = public, auth
as $$
declare saved_id uuid;
begin
  if not public.is_report_admin() then raise exception '관리자 권한이 없습니다.'; end if;
  if p_mime_type not in ('application/pdf', 'image/jpeg', 'image/png', 'image/webp') then
    raise exception 'PDF, JPG, PNG, WEBP 파일만 첨부할 수 있습니다.';
  end if;
  if p_file_size <= 0 or p_file_size > 15728640 then raise exception '파일은 15MB 이하여야 합니다.'; end if;
  if not exists (select 1 from public.weekly_meetings where id = p_meeting_id) then
    raise exception '회의 일정을 먼저 저장해 주세요.';
  end if;

  insert into public.weekly_meeting_files(meeting_id, storage_path, file_name, mime_type, file_size)
  values (p_meeting_id, p_storage_path, left(trim(p_file_name), 255), p_mime_type, p_file_size)
  returning id into saved_id;
  return saved_id;
end;
$$;

create or replace function public.admin_delete_weekly_meeting_file(p_file_id uuid)
returns table(storage_path text)
language plpgsql
security definer
set search_path = public, auth
as $$
begin
  if not public.is_report_admin() then raise exception '관리자 권한이 없습니다.'; end if;
  return query delete from public.weekly_meeting_files f where f.id = p_file_id returning f.storage_path;
end;
$$;

revoke all on function public.list_weekly_meetings() from public;
revoke all on function public.admin_save_weekly_meeting(uuid, date, time, text, text) from public;
revoke all on function public.admin_add_weekly_meeting_file(uuid, text, text, text, bigint) from public;
revoke all on function public.admin_delete_weekly_meeting_file(uuid) from public;
grant execute on function public.list_weekly_meetings() to authenticated;
grant execute on function public.admin_save_weekly_meeting(uuid, date, time, text, text) to authenticated;
grant execute on function public.admin_add_weekly_meeting_file(uuid, text, text, text, bigint) to authenticated;
grant execute on function public.admin_delete_weekly_meeting_file(uuid) to authenticated;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'weekly-meeting-files', 'weekly-meeting-files', false, 15728640,
  array['application/pdf', 'image/jpeg', 'image/png', 'image/webp']
)
on conflict (id) do update set
  public = false,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "weekly meeting files read" on storage.objects;
drop policy if exists "weekly meeting files insert" on storage.objects;
drop policy if exists "weekly meeting files delete" on storage.objects;

create policy "weekly meeting files read" on storage.objects
for select to authenticated
using (bucket_id = 'weekly-meeting-files' and public.is_allowed_report_user());

create policy "weekly meeting files insert" on storage.objects
for insert to authenticated
with check (bucket_id = 'weekly-meeting-files' and public.is_report_admin());

create policy "weekly meeting files delete" on storage.objects
for delete to authenticated
using (bucket_id = 'weekly-meeting-files' and public.is_report_admin());
