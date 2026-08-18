#!/usr/bin/env bash
# aictrl daily email sequence — cron wrapper (DRAFT-ONLY).
# Finds Sequence-tab leads whose next email step is due, drafts each step, and
# posts the drafts to the operator's Telegram DM for approve/edit/skip.
# It NEVER sends email — no mail send tool is in the allowlist, so the
# approve-before-send rule is enforced by construction. Sending happens in a
# live session after approval. CRM I/O via the direct-API helper.
set -uo pipefail
export PATH="/home/vas/.local/bin:/usr/local/bin:/usr/bin:/bin"

LOG="/home/vas/.claude/logs/aictrl-email-sequence.log"
CHAT_ID="<YOUR_TELEGRAM_DM_CHAT_ID>"
PROJECT="/home/vas/projects/aictrl"
CLAUDE="/home/vas/.local/bin/claude"

TMP="$(mktemp)"
cd "$PROJECT" || exit 1

{
  echo "=== $(date '+%F %T %Z') email-sequence run start ==="
  "$CLAUDE" -p 'Run the aictrl daily email sequence in DRAFT-ONLY mode. Do NOT send any email and do NOT use any mail send tool — draft the due steps and post them to the operator for approval. Steps: (1) Run: python3 /home/vas/.claude/scripts/aictrl-sheets.py due-steps 5  which prints a JSON array of leads whose next email step is due, each with row, first, last, company, email, tier, step_done (0/1/2 = steps already sent), why (the personalisation hook), goal. (2) For each lead compose the NEXT step email, step number = step_done + 1. Positioning rule for ALL steps: use the exact phrase "helping build aictrl.dev", NEVER "I am building" or "my company"; include exactly ONE link, app.aictrl.dev; sign off "Vas". Templates: STEP 1 (step_done 0) subject "AI coding agents at <company>", body = a 1 to 2 sentence personalised opener built strictly from the why-hook (specific and accurate, invent nothing), then a blank line, then "I am helping build aictrl.dev — a governance and grounding layer for engineering teams running AI coding agents (Claude Code, Cursor) at scale: it grounds agents in your codebase knowledge graph, plus session audit, policy controls, and cost/token visibility.", then "We are giving teams free tokens to run AI code reviews — point it at a GitHub repo and see it work in a couple of minutes: app.aictrl.dev", then "Worth a look?", then "Vas". STEP 2 (step_done 1) subject "re: AI coding agents at <company>", a short 3-sentence nudge: the timing may be off rather than the idea; once agents write a real share of commits the question becomes what did it touch, was it grounded in our codebase, what does it cost — the gap aictrl closes; one link app.aictrl.dev; sign Vas. STEP 3 (step_done 2) subject "re: AI coding agents at <company>", a short 2 to 3 sentence close: last note; if governing AI coding agents is on the radar the free trial is the quickest way to judge it (app.aictrl.dev); good luck either way; sign Vas. (3) Do NOT write to the sheet and do NOT send. (4) Finally print: a first line "🤖 Email sequence — <UTC date> (drafts for approval)", then "Due: <N>", then for each lead a block: "— <first> <last>, <company> [<email>] · Step <n>" then "Subject: <subject>" then the body. End with "Reply: approve all / approve <names> / edit <name>: <text> / skip <name>."' \
    --allowedTools "Bash(python3:*)" "Bash(curl:*)" "Bash(jq:*)"
} >"$TMP" 2>&1
status=$?
echo "=== $(date '+%F %T %Z') email-sequence run end (exit $status) ===" >>"$TMP"

cat "$TMP" >>"$LOG"

MSG="$(awk '/🤖/{p=1} p' "$TMP")"
if [ -z "$MSG" ]; then
  MSG="⚠️ aictrl email sequence ran $(date '+%F %H:%M %Z') but produced no 🤖 summary (exit $status). Check $LOG."
fi

set -a; . "$PROJECT/.telegram/.env"; set +a
curl -s --max-time 20 -X POST \
  "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
  --data-urlencode "chat_id=${CHAT_ID}" \
  --data-urlencode "text=${MSG}" >/dev/null

rm -f "$TMP"
