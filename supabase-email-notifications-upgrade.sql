-- Diako Leader Report · 이메일 알림 발송 기록
-- 기존 보고서·회의 데이터는 변경하지 않습니다.

create table if not exists public.email_notification_log (
  id bigint generated always as identity primary key,
  event_key text not null unique,
  event_type text not null,
  recipient_count integer not null default 0,
  created_at timestamptz not null default now()
);

alter table public.email_notification_log enable row level security;
revoke all on public.email_notification_log from anon, authenticated;
create index if not exists idx_email_notification_log_created_at on public.email_notification_log(created_at desc);

-- 90일이 지난 발송 기록 정리는 선택 사항입니다. 데이터가 매우 작아 필수는 아닙니다.
