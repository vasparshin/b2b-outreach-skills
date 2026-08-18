#!/usr/bin/env bash
# aictrl daily LinkedIn outreach — cron wrapper.
# Runs the batch via `claude -p`, then GUARANTEES a Telegram DM summary via a
# plain shell curl, because claude -p's own notify step is unreliable in
# non-interactive (cron) mode. See ~/.claude/skills/aictrl-linkedin-outreach/SKILL.md
set -uo pipefail
export PATH="/home/vas/.local/bin:/usr/local/bin:/usr/bin:/bin"

LOG="/home/vas/.claude/logs/aictrl-linkedin-outreach.log"
CHAT_ID="<YOUR_TELEGRAM_DM_CHAT_ID>"
PROJECT="/home/vas/projects/aictrl"
CLAUDE="/home/vas/.local/bin/claude"

TMP="$(mktemp)"
cd "$PROJECT" || exit 1

# Run the batch, capturing this run's output in isolation (so the notify step
# only ever quotes THIS run, not earlier days appended to the shared log).
{
  echo "=== $(date '+%F %T %Z') cron run start ==="
  # Scoped, unattended pre-grants for the CONNECT batch only.
  # CRM I/O goes through the direct-API helper (aictrl-sheets.py) because the
  # Google Sheets MCP cannot complete its OAuth handshake in a headless cron.
  # Deliberately NO send tools (no linkedin__send_message, no ms365 send) — any
  # message send must stay gated behind Telegram approval, never auto-sent here.
  "$CLAUDE" -p 'Run the daily aictrl LinkedIn connect batch. IMPORTANT: do NOT use the Google Sheets MCP (it cannot authenticate in this headless context); use the helper script for ALL CRM access. Steps: (1) verify the LinkedIn session with mcp__linkedin__get_my_profile, and if invalid print "ABORT: LinkedIn session expired" and stop. (2) Run: python3 /home/vas/.claude/scripts/aictrl-sheets.py candidates  which prints a JSON array of up to 15 people, each with fields row, slug, task_id, acct, seq. (3) For each person call mcp__linkedin__connect_with_person(linkedin_username=slug) WITHOUT a note. (4) After each, write the result back by running: python3 /home/vas/.claude/scripts/aictrl-sheets.py update <row> "<UTC now YYYY-MM-DD HH:MM>" "<result: sent (no note) OR connect_unavailable OR the raw status>" "(no note)" "Vas Parshin" "<short note or blank>" "<pending if connected else n/a>" "<same UTC timestamp>"  passing each argument as its own quoted token. (5) Do NOT send any LinkedIn message and do NOT use any send tool. (6) Finally print exactly: a first line "🤖 H1 LinkedIn batch — <UTC date>", then "Sent: <N>", then "connect_unavailable: <N>", then "Other / failed: <N> — total attempts: <N>/15".' \
    --allowedTools \
      "mcp__linkedin__connect_with_person" \
      "mcp__linkedin__get_my_profile" \
      "Bash(python3:*)" "Bash(curl:*)" "Bash(jq:*)"
} >"$TMP" 2>&1
status=$?
echo "=== $(date '+%F %T %Z') cron run end (exit $status) ===" >>"$TMP"

# Persist to the shared log.
cat "$TMP" >>"$LOG"

# Build the message: the 🤖 summary block claude printed, else a fallback.
MSG="$(awk '/🤖/{p=1} p' "$TMP")"
if [ -z "$MSG" ]; then
  MSG="⚠️ aictrl LinkedIn cron ran $(date '+%F %H:%M %Z') but produced no 🤖 summary (exit $status). Check $LOG."
fi

# Guaranteed notify via the Telegram Bot API (independent of claude's own step).
set -a; . "$PROJECT/.telegram/.env"; set +a
curl -s --max-time 20 -X POST \
  "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
  --data-urlencode "chat_id=${CHAT_ID}" \
  --data-urlencode "text=${MSG}" >/dev/null

rm -f "$TMP"
