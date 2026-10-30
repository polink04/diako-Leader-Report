// 공공감성 그룹장 주간보고 메일 알림
// RESEND_API_KEY, REMINDER_FROM, REMINDER_CRON_SECRET는 Supabase Edge Function Secrets에만 저장합니다.
import { createClient } from "npm:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "https://polink04.github.io",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-reminder-secret",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const get = (name: string) => Deno.env.get(name) || "";
const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), {
  status,
  headers: { ...corsHeaders, "Content-Type": "application/json; charset=utf-8" },
});
const escapeHtml = (value: unknown) => String(value ?? "").replace(/[&<>"']/g, (char) => ({
  "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;",
}[char] || char));
const displayDate = (value: string) => new Intl.DateTimeFormat("ko-KR", {
  timeZone: "Asia/Seoul", year: "numeric", month: "long", day: "numeric", weekday: "short",
}).format(new Date(`${value}T00:00:00+09:00`));
const displayTime = (value: string) => {
  const [hour, minute] = value.split(":").map(Number);
  return `${hour < 12 ? "오전" : "오후"} ${hour % 12 || 12}:${String(minute).padStart(2, "0")}`;
};
const mailLayout = (title: string, body: string) => `<!doctype html><html lang="ko"><body style="margin:0;background:#f4f5f6;font-family:Arial,'Apple SD Gothic Neo',sans-serif;color:#17191d"><div style="max-width:620px;margin:0 auto;padding:32px 16px"><div style="background:#fff;border-radius:20px;padding:30px;border:1px solid #e5e7eb"><div style="color:#e51b23;font-size:12px;font-weight:800;letter-spacing:.12em">공공감성 · 그룹장 주간보고</div><h1 style="margin:12px 0 22px;font-size:25px;line-height:1.35">${escapeHtml(title)}</h1>${body}<a href="${escapeHtml(get("APP_URL") || "https://polink04.github.io/diako-Leader-Report/")}" style="display:inline-block;margin-top:24px;padding:13px 18px;border-radius:10px;background:#17191d;color:#fff;text-decoration:none;font-weight:700">주간보고 열기</a></div><p style="margin:14px 4px;color:#8a8f97;font-size:12px">이 메일은 공공감성 주간회의보고서에서 자동 발송되었습니다.</p></div></body></html>`;

async function sendEmail(to: string, subject: string, html: string) {
  const response = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: { "Content-Type": "application/json", Authorization: `Bearer ${get("RESEND_API_KEY")}` },
    body: JSON.stringify({ from: get("REMINDER_FROM"), to: [to], subject, html }),
    signal: AbortSignal.timeout(10000),
  });
  if (!response.ok) throw new Error(`메일 발송 실패 (${response.status})`);
}

function tomorrowInKorea() {
  const parts = new Intl.DateTimeFormat("en-CA", { timeZone: "Asia/Seoul", year: "numeric", month: "2-digit", day: "2-digit" }).formatToParts(new Date());
  const values = Object.fromEntries(parts.map((part) => [part.type, part.value]));
  const date = new Date(`${values.year}-${values.month}-${values.day}T00:00:00+09:00`);
  date.setDate(date.getDate() + 1);
  return new Intl.DateTimeFormat("en-CA", { timeZone: "Asia/Seoul" }).format(date);
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  const required = ["SUPABASE_URL", "SUPABASE_SERVICE_ROLE_KEY", "SUPABASE_ANON_KEY", "RESEND_API_KEY", "REMINDER_FROM"];
  if (required.some((name) => !get(name))) return json({ error: "Mail configuration missing" }, 503);

  try {
    const body = await req.json();
    const type = String(body?.type || "");
    const admin = createClient(get("SUPABASE_URL"), get("SUPABASE_SERVICE_ROLE_KEY"), { auth: { persistSession: false } });

    if (type === "meeting_reminder") {
      if (!get("REMINDER_CRON_SECRET") || req.headers.get("x-reminder-secret") !== get("REMINDER_CRON_SECRET")) return json({ error: "Unauthorized" }, 401);
    } else {
      const authorization = req.headers.get("Authorization") || "";
      const userClient = createClient(get("SUPABASE_URL"), get("SUPABASE_ANON_KEY"), { global: { headers: { Authorization: authorization } }, auth: { persistSession: false } });
      const { data: userData, error: userError } = await userClient.auth.getUser();
      if (userError || !userData.user?.email) return json({ error: "Unauthorized" }, 401);
      const { data: profile } = await admin.from("allowed_report_users").select("is_admin").ilike("email", userData.user.email).maybeSingle();
      if (!profile?.is_admin) return json({ error: "관리자 권한이 없습니다." }, 403);
    }

    const { data: recipients, error: recipientError } = await admin.from("allowed_report_users").select("email, display_name, is_admin");
    if (recipientError) throw recipientError;

    const sendOnce = async (eventKey: string, mails: Array<{ to: string; subject: string; html: string }>) => {
      const { data: exists } = await admin.from("email_notification_log").select("event_key").eq("event_key", eventKey).maybeSingle();
      if (exists) return { skipped: true, count: 0 };
      await Promise.all(mails.map((mail) => sendEmail(mail.to, mail.subject, mail.html)));
      const { error } = await admin.from("email_notification_log").insert({ event_key: eventKey, event_type: type, recipient_count: mails.length });
      if (error && error.code !== "23505") throw error;
      return { skipped: false, count: mails.length };
    };

    if (type === "comment_created") {
      const commentId = Number(body.comment_id);
      const reportId = String(body.report_id || "");
      const [{ data: report, error: reportError }, { data: comment, error: commentError }] = await Promise.all([
        admin.from("reports").select("id, owner_email, leader_name, group_name, meeting_date").eq("id", reportId).single(),
        admin.from("report_comments").select("id, body, author_name").eq("id", commentId).eq("report_id", reportId).single(),
      ]);
      if (reportError || commentError) throw reportError || commentError;
      const subject = `[공공감성] ${report.leader_name}님의 주간보고에 대표 코멘트가 등록되었습니다`;
      const html = mailLayout("대표 코멘트가 등록되었습니다", `<p style="margin:0 0 16px;color:#5f646c;line-height:1.7">${escapeHtml(report.group_name)} · ${escapeHtml(displayDate(report.meeting_date))}</p><div style="border-left:4px solid #e51b23;background:#fff6f6;border-radius:8px;padding:16px 18px;white-space:pre-wrap;line-height:1.7">${escapeHtml(comment.body)}</div><p style="margin:12px 0 0;color:#8a8f97;font-size:13px">${escapeHtml(comment.author_name)}</p>`);
      return json({ ok: true, ...(await sendOnce(`comment-${comment.id}`, [{ to: report.owner_email, subject, html }])) });
    }

    const sendMeeting = async (meeting: Record<string, string>, reminder: boolean) => {
      const label = reminder ? "내일 주간회의가 있습니다" : "주간회의 일정이 등록·변경되었습니다";
      const subject = `[공공감성] ${label} · ${displayDate(meeting.meeting_date)} ${displayTime(meeting.meeting_time)}`;
      const html = mailLayout(label, `<div style="display:grid;gap:10px"><div style="padding:13px 15px;border-radius:10px;background:#f4f5f6"><strong>일시</strong><br>${escapeHtml(displayDate(meeting.meeting_date))} ${escapeHtml(displayTime(meeting.meeting_time))}</div><div style="padding:13px 15px;border-radius:10px;background:#f4f5f6"><strong>장소</strong><br>${escapeHtml(meeting.place)}</div>${meeting.memo ? `<div style="padding:13px 15px;border-radius:10px;background:#fff6f6;white-space:pre-wrap"><strong>안내</strong><br>${escapeHtml(meeting.memo)}</div>` : ""}</div>`);
      const mails = (recipients || []).map((recipient) => ({ to: recipient.email, subject, html }));
      const key = reminder ? `meeting-reminder-${meeting.id}-${meeting.meeting_date}` : `meeting-saved-${meeting.id}-${meeting.updated_at}`;
      return sendOnce(key, mails);
    };

    if (type === "meeting_saved") {
      const { data: meeting, error } = await admin.from("weekly_meetings").select("id, meeting_date, meeting_time, place, memo, updated_at").eq("id", String(body.meeting_id || "")).single();
      if (error) throw error;
      return json({ ok: true, ...(await sendMeeting(meeting, false)) });
    }

    if (type === "meeting_reminder") {
      const tomorrow = tomorrowInKorea();
      const { data: meetings, error } = await admin.from("weekly_meetings").select("id, meeting_date, meeting_time, place, memo, updated_at").eq("meeting_date", tomorrow);
      if (error) throw error;
      const results = [];
      for (const meeting of meetings || []) results.push(await sendMeeting(meeting, true));
      return json({ ok: true, meetings: results.length, results });
    }

    return json({ error: "Unknown notification type" }, 400);
  } catch (error) {
    return json({ error: error instanceof Error ? error.message : "Notification failed" }, 500);
  }
});
