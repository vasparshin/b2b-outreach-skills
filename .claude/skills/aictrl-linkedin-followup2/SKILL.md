# aictrl LinkedIn Second-Touch Follow-up

Daily skill that nudges accepted LinkedIn connections who got a first-touch follow-up message (via `aictrl-linkedin-followup`) but never replied. Built 2026-07-07 per Vas: most of the follow-ups sent over the last ~2 months got zero replies, and nothing was re-touching them.

This skill is the WRITER for cols AG, AH, AI. It NEVER touches anything else.

## Constants

| Thing | Value |
|---|---|
| Spreadsheet ID | `<YOUR_CRM_SPREADSHEET_ID>` |
| Sheet tab | `Log` |
| GWS account | `<YOUR_GWS_ACCOUNT_EMAIL>` |
| Telegram DM chat_id | `<YOUR_TELEGRAM_DM_CHAT_ID>` (NEVER the group `<YOUR_TEAM_GROUP_CHAT_ID>`) |
| Min age before nudge | **7 days** since col Y (Followup Sent At) |
| Max age (lookback window) | **90 days** since col Y — older than that, don't bother |
| Send cap per run | **5/day** — staggered, conservative; these are cold seconds-touches, not first contact |
| Auto-send | **Yes** — per Vas's explicit instruction 2026-07-07 ("send to everyone... don't need to keep checking with me"), this skill sends without a Telegram approval gate. If that trust erodes (bad drafts, complaints), flip back to approve-before-send and tell Vas why. |

## Model routing — cost control (added 2026-07-24 per Vas)

Step 3.1–3.3 (profile fetch, 1st-degree verify, activity/reply scan) are lookup/classification work — run them via the Task tool as a subagent with `model: "haiku"`, returning only: still-1st-degree (yes/no), any fresh hook found (or "none"), and any sign of an unlogged reply. Step 3.4 (drafting the nudge) and everything after stay on the default/inherited model — a bad second-touch draft still costs a real reply, not worth downgrading for a few cents.

## Column ownership reminder

| Cols | Owner | This skill |
|---|---|---|
| A–V | other skills (refresh / qualifier / outreach) | NEVER write |
| W–Z | aictrl-linkedin-status-tracker / aictrl-linkedin-followup | READ only (Y, Z), NEVER write |
| AA–AF | email-sequencer (Email Status/Last Sent/Reply/Why-Hook) | NEVER touch — confirmed 2026-07-07 this block is live email-sequencer state, not scratch space |
| **AG LI Followup2 Status** | **THIS skill** | write |
| **AH LI Followup2 Sent At** | **THIS skill** | write |
| **AI LI Followup2 Message** | **THIS skill** | write |

`AG` values: `sent`, `skipped — already replied`, `skipped — not 1st degree`, `error`.

## Why a formula-based read, not a raw range read

The CRM has 3,000+ rows. A raw `read_sheet_values` call on a wide, many-thousand-row range only *displays* the first ~50 rows in the tool result (with a "...and N more rows" note) even though you requested more — you will silently miss rows past #50 if you rely on that. Two ways to avoid this, both proven working 2026-07-07:

1. **Preferred since 2026-08-03 — read the whole range in ONE call via the shared REST reader and filter in Python:** `python3 ~/.claude/scripts/sheets-read.py <YOUR_CRM_SPREADSHEET_ID> 'Log!A2:AI3100' <your_gws_account_email> --json`. The account argument is **required** — omitting it exits 2 rather than silently reading someone else's sheet. Verified against this spreadsheet: 3,035 rows, one call, no truncation. Because it runs in a `Bash` call you print only the eligible rows, so the CRM body never enters the conversation.
2. **`QUERY()` scratch-cell filter** — still works and needs no script, but it writes to the sheet to read from it, so it carries the scratch-cell collision risk below. Use it only if the reader is unavailable.
3. **Chunking to ≤50 rows per call** — the old fallback. Correct but expensive (~60 calls here, each carried through the rest of the run); the fleet measured 1.28bn cache-read tokens and 48% of a day's spend from this pattern on 2026-08-03. Last resort only.

**Always clear the scratch cell immediately after reading its result.** Before writing to any scratch cell, `read_sheet_values` that exact cell/column first to confirm it's genuinely empty — columns AA–AF look free but are NOT (see table above). Designated scratch strip: `AK1`–`AN` per the authoritative column map in /home/vas/projects/aictrl/CLAUDE.md — use one cell, clear it, move on. NOTE (2026-08-01): the grid is now 74 columns through BV (an old note claiming it caps at AN/40 is stale), but AK–AN remains the ONLY scratch strip — AO onward are owned columns.

## Workflow

### 1. Preflight: LinkedIn session check

Call `mcp__linkedin__get_my_profile`. On "No valid LinkedIn session was found" error: ABORT with the standard `uvx linkedin-scraper-mcp@latest --login` instruction.

### 2. Find eligible rows via QUERY

Compute today's date cutoffs from your own current-date awareness (no shell `date` needed — you know today's date from context):
- `cutoff_recent` = today − 7 days (rows with Y after this are too fresh, skip)
- `cutoff_old` = today − 90 days (rows with Y before this are too stale, skip)

Write to `Log!AK1` (after confirming it's empty):

```
=QUERY(B2:AI3035,"select Col1,Col3,Col7,Col24,Col25 where Col24 <> '' and Col24 <= '<cutoff_recent>T23:59:59Z' and Col24 >= '<cutoff_old>T00:00:00Z' and (Col32 = '' or Col32 is null) and Col25 not matches '.*eply.*'",0)
```

(Col1=B/Name, Col3=D/Company, Col7=H/Slug, Col24=Y/FollowupSentAt, Col25=Z/FollowupMessage. Col32=AG, the col this skill owns — filtering for blank means "not yet second-touched." The `Col25 not matches '.*eply.*'` clause excludes anyone whose col Z already shows a logged reply.)

Read back `AK1:AO200` (more than enough headroom), then **immediately clear `AK1`**.

If zero rows: print `No contacts eligible for a second-touch nudge.`, skip to step 6 (still send heartbeat DM).

Slice to the first `send_cap=5` rows (order doesn't matter much here — pick the first 5 the query returns).

### 3. For each candidate, verify + draft

1. *(Haiku subagent — see "Model routing" above)* Call `mcp__linkedin__get_person_profile(linkedin_username=<slug>)`.
2. *(Haiku subagent)* **Confirm still 1st-degree** (`· 1st` or a `Connected`/`Message`-only state with no `Connect` button). If not 1st degree (rare — e.g. they disconnected), write `AG = "skipped — not 1st degree"`, `AH = now`, skip send.
3. *(Haiku subagent)* **Scan the profile's visible activity/messages for any sign they already replied that the CRM missed.** This is a belt-and-braces check on top of the col Z filter from step 2. If genuinely ambiguous, err toward sending rather than silently dropping them — the DM summary will surface it either way.
4. *(default/inherited model)* Draft a short second-touch message using the subagent's findings:
   - **Open `Hi <FirstName> — ` before anything else (mandatory, added 2026-08-03, Vas).** First name only, as they present it on LinkedIn; `Hi`, never `Hey`/`Hello`/`Dear`. Same rule and same reason as step 4.1 of `aictrl-linkedin-followup`: an audit that morning found 36 of 43 sent follow-ups opened cold with no greeting, which reads as a broadcast.
   - Reference that this is a follow-up to an earlier note, don't repeat the first message verbatim.
   - Pull a fresh, current hook if one is visible (a new post, job change, etc.) — falls back to a light, low-pressure bump if nothing fresh is available.
   - Keep the aictrl voice: warm, research-led, "keep agents on a leash" framing where it fits naturally, never "Worth a look?" (see `feedback_outreach_voice.md`).
   - Short. 2–3 sentences max.

### 4. Send

Call `mcp__linkedin__send_message(linkedin_username=<slug>, message=<draft>, confirm_send=true)`.

On success: `AG = "sent"`, `AH = now (UTC ISO)`, `AI = <message text>`.
On failure: `AG = "error"`, `AH = now`, `AI = "<error detail>"`. Don't retry within the same run.

### 5. Write back

Batch-write `Log!AG<row>:AI<row>` for every processed row (contiguous rows can be batched; scattered rows go one call each).

### 6. DM summary

POST to DM `<YOUR_TELEGRAM_DM_CHAT_ID>` (never the group):

```
**LinkedIn second-touch — <UTC date>**
Eligible pool: <N> (7–90 days since first touch, no reply logged)
Nudged: <N>
Skipped (not 1st degree): <N>
Errors: <N>
```

For each nudge sent, append one line: `• <Name> (<Company>) — <first 60 chars of message>...`

## Known limits

- **Reply detection is heuristic**, same caveat as the first-touch tracker — col Z's reply log depends on the status-tracker's inbox scan catching it. A false negative here (they replied but it wasn't logged) means an unwanted second nudge; the profile activity scan in step 3.3 is a partial mitigation, not a guarantee.
- **One nudge only, for now.** This skill doesn't do a third touch. If a contact goes through this once (AG populated) they won't be picked up again even 90+ days later — re-eligibility would need a deliberate design decision (raise with Vas before adding a loop here).
- **90-day lookback is a hard cutoff.** Contacts whose first touch was sent longer ago never get nudged by this skill. That's deliberate (very old cold contacts are lower-value) but worth revisiting if the backlog clears out.

## Cron wrapper

`/home/vas/.claude/scripts/aictrl-linkedin-followup2-cron.sh`, scheduled daily after the tracker/first-followup crons. Uses the same jitter + guaranteed-DM pattern as the other LinkedIn crons. `--allowedTools` includes `mcp__linkedin__send_message` (unlike the tracker cron) since this skill auto-sends by design.

Related memory: `reference_linkedin_mcp.md`, `feedback_outreach_voice.md`, `feedback_no_group_posts_without_instruction.md`. Related skills: `aictrl-linkedin-status-tracker`, `aictrl-linkedin-followup`.
