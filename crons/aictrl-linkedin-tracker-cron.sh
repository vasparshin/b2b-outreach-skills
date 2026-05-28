#!/usr/bin/env bash
# aictrl LinkedIn acceptance tracker — cron wrapper (DRAFT-ONLY).
# Polls pending invites, detects acceptances, updates the CRM (W/X/Y/Z via the
# direct-API helper), and for each NEW accept composes a follow-up DM draft and
# posts it to the operator's Telegram DM for approve/edit/skip.
# It NEVER sends a LinkedIn message — no send tools are in the allowlist, so the
# approve-before-send rule is enforced by construction. Runs right after the
# connect cron. The GWS MCP can't auth headless, so CRM I/O goes via aictrl-sheets.py.
set -uo pipefail
export PATH="/home/vas/.local/bin:/usr/local/bin:/usr/bin:/bin"

LOG="/home/vas/.claude/logs/aictrl-linkedin-tracker.log"
CHAT_ID="6348453236"
PROJECT="/home/vas/projects/aictrl"
CLAUDE="/home/vas/.local/bin/claude"

TMP="$(mktemp)"
cd "$PROJECT" || exit 1

{
  echo "=== $(date '+%F %T %Z') tracker run start ==="
  "$CLAUDE" -p 'Run the aictrl LinkedIn acceptance tracker in DRAFT-ONLY mode. Do NOT use the Google Sheets MCP; use the helper for ALL CRM access. Do NOT send any LinkedIn message and do NOT use any send tool — drafts only; the operator approves in Telegram. Steps: (1) verify the session with mcp__linkedin__get_my_profile, and if invalid print "ABORT: LinkedIn session expired" and stop. (2) Run: python3 /home/vas/.claude/scripts/aictrl-sheets.py pending 30  which prints a JSON array of pending invites, each with row, slug, name, title, company, connect_date. (3) For each, call mcp__linkedin__get_person_profile(linkedin_username=slug) and classify the profile text: "1st" degree or a Message/Connected button means ACCEPTED; a Pending button means still PENDING; a Connect button or 2nd/3rd degree means WITHDRAWN-OR-EXPIRED. (4) For every row write the CRM via: python3 /home/vas/.claude/scripts/aictrl-sheets.py track-update <row> "<accepted OR pending OR withdrawn-or-expired>" "<UTC now YYYY-MM-DD HH:MM if the status changed, else leave blank>" "" ""  passing each argument as its own quoted token, leaving the last two (Y, Z) empty because nothing is sent. (5) For each NEWLY accepted person compose a VERY SHORT LinkedIn follow-up DM draft: MAXIMUM 2 sentences and about 40 words total, casual and human (not a pitch), referencing their role or company in just a few words, positioned as HELPING BUILD aictrl.dev (a governance and grounding layer for engineering teams running AI coding agents at scale) — use the exact phrase "helping build" and NEVER "I am building", "I built", or "my company"; offer the free code-review tokens or the connect-a-GitHub-repo trial; include exactly ONE link, app.aictrl.dev. Do NOT send it. (6) Finally print exactly: a first line "🤖 LinkedIn tracker — <UTC date>", then "Polled: <N>", "Accepted (new): <N>", "Still pending: <N>", "Withdrawn/expired: <N>", then for each new acceptance a block headed "DRAFT — <name>, <company> (<slug>):" followed by the draft text, and end with "Reply approve / edit <slug> / skip <slug> to action these."' \
    --allowedTools \
      "mcp__linkedin__get_person_profile" \
      "mcp__linkedin__get_my_profile" \
      "Bash(python3:*)" "Bash(curl:*)" "Bash(jq:*)"
} >"$TMP" 2>&1
status=$?
echo "=== $(date '+%F %T %Z') tracker run end (exit $status) ===" >>"$TMP"

cat "$TMP" >>"$LOG"

MSG="$(awk '/🤖/{p=1} p' "$TMP")"
if [ -z "$MSG" ]; then
  MSG="⚠️ aictrl LinkedIn tracker ran $(date '+%F %H:%M %Z') but produced no 🤖 summary (exit $status). Check $LOG."
fi

set -a; . "$PROJECT/.telegram/.env"; set +a
curl -s --max-time 20 -X POST \
  "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
  --data-urlencode "chat_id=${CHAT_ID}" \
  --data-urlencode "text=${MSG}" >/dev/null

rm -f "$TMP"
