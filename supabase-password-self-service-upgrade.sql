-- Diako Leader Report · 사용자 본인 비밀번호 변경 기능
-- 기존 그룹장 계정은 다음 로그인 때 새 비밀번호 설정을 안내합니다.

alter table public.allowed_report_users
  add column if not exists must_change_password boolean not null default false;

alter table public.allowed_report_users
  add column if not exists password_changed_at timestamptz;

update public.allowed_report_users
set must_change_password = true
where is_admin = false and password_changed_at is null;

create or replace function public.current_password_policy()
returns table(must_change_password boolean, password_changed_at timestamptz)
language sql
stable
security definer
set search_path = public, auth
as $$
  select u.must_change_password, u.password_changed_at
  from public.allowed_report_users u
  where auth.uid() is not null
    and lower(u.email) = lower(coalesce(auth.jwt() ->> 'email', ''));
$$;

create or replace function public.mark_password_changed()
returns boolean
language plpgsql
security definer
set search_path = public, auth
as $$
declare changed_count integer;
begin
  if auth.uid() is null then raise exception '로그인이 필요합니다.'; end if;
  update public.allowed_report_users
  set must_change_password = false, password_changed_at = now()
  where lower(email) = lower(coalesce(auth.jwt() ->> 'email', ''));
  get diagnostics changed_count = row_count;
  return changed_count = 1;
end;
$$;

revoke all on function public.current_password_policy() from public;
revoke all on function public.mark_password_changed() from public;
grant execute on function public.current_password_policy() to authenticated;
grant execute on function public.mark_password_changed() to authenticated;
