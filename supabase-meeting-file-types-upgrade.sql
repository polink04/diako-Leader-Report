-- Diako Leader Report · 사전 참고자료/회의록 구분 기능 추가
-- 기존 첨부파일은 회의록(minutes)으로 보존됩니다.
-- Supabase SQL Editor에서 이 파일 전체를 한 번 실행하세요.

alter table public.weekly_meeting_files
  add column if not exists file_kind text not null default 'minutes';

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'weekly_meeting_files_file_kind_check'
      and conrelid = 'public.weekly_meeting_files'::regclass
  ) then
    alter table public.weekly_meeting_files
      add constraint weekly_meeting_files_file_kind_check
      check (file_kind in ('reference', 'minutes'));
  end if;
end $$;

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
      'mime_type', f.mime_type, 'file_size', f.file_size, 'file_kind', f.file_kind,
      'created_at', f.created_at
    ) order by f.created_at desc) from public.weekly_meeting_files f where f.meeting_id = m.id), '[]'::jsonb)
  from public.weekly_meetings m
  order by m.meeting_date desc, m.meeting_time desc, m.created_at desc;
end;
$$;

drop function if exists public.admin_add_weekly_meeting_file(uuid, text, text, text, bigint);

create or replace function public.admin_add_weekly_meeting_file(
  p_meeting_id uuid,
  p_storage_path text,
  p_file_name text,
  p_mime_type text,
  p_file_size bigint,
  p_file_kind text default 'minutes'
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
  if p_file_kind not in ('reference', 'minutes') then raise exception '올바르지 않은 첨부 구분입니다.'; end if;
  if p_file_size <= 0 or p_file_size > 15728640 then raise exception '파일은 15MB 이하여야 합니다.'; end if;
  if not exists (select 1 from public.weekly_meetings where id = p_meeting_id) then
    raise exception '회의 일정을 먼저 저장해 주세요.';
  end if;

  insert into public.weekly_meeting_files(meeting_id, storage_path, file_name, mime_type, file_size, file_kind)
  values (p_meeting_id, p_storage_path, left(trim(p_file_name), 255), p_mime_type, p_file_size, p_file_kind)
  returning id into saved_id;
  return saved_id;
end;
$$;

revoke all on function public.admin_add_weekly_meeting_file(uuid, text, text, text, bigint, text) from public;
grant execute on function public.admin_add_weekly_meeting_file(uuid, text, text, text, bigint, text) to authenticated;
