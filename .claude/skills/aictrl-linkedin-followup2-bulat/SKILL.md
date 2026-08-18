---
name: aictrl-linkedin-followup2-bulat
description: Second-touch nudge for Bulat's InMail outreach fork — BULAT'S FORK of aictrl-linkedin-followup2. Nudges contacts Bulat InMail'd (col AO="sent") who never replied (col AR empty or "none") after a cooldown period. Unlike Vas's followup2 (auto-send, trust earned over months), this fork is approve-before-send since Bulat's InMail pipeline is brand new and unproven. Writes cols AU–AW only. NEVER touches anything else. NEVER posts to the Telegram group (<YOUR_TEAM_GROUP_CHAT_ID>). TRIGGER on `/aictrl-linkedin-followup2-bulat`, "nudge Bulat's InMail contacts", "run Bulat's second-touch". SKIP for Vas's own second-touch (use aictrl-linkedin-followup2) or Bulat's first-touch/reply-tracking (use aictrl-linkedin-outreach-bulat / aictrl-linkedin-status-tracker-bulat).
---

# aictrl LinkedIn Second-Touch Follow-up — Bulat's Fork

Fork of `aictrl-linkedin-followup2`, scoped to Bulat's InMail contacts instead of Vas's accepted-connection follow-ups. Nudges people Bulat messaged (via `aictrl-linkedin-outreach-bulat`) who went quiet.

## Column ownership

| Cols | Owner | This skill |
|---|---|---|
| A–V, W–X, Y–Z | other skills (see the other Bulat-fork files) | NEVER write |
| AA–AN | email-sequencer / Vas's followup2 | NEVER touch |
| AO–AQ | aictrl-linkedin-outreach-bulat | READ only (AO, AP, AQ), NEVER write |
| AR–AS | aictrl-linkedin-status-tracker-bulat | READ only (AR), NEVER write |
| AT | *(reserved, unused)* | NEVER write |
| **AU** | **THIS skill** | Second-Touch Status: `sent` / `skipped — already replied` / `skipped — not eligible` / `error` |
| **AV** | **THIS skill** | Second-Touch Sent At |
| **AW** | **THIS skill** | Second-Touch Message |

## Constants

| Thing | Value |
|---|---|
| Spreadsheet ID | `<YOUR_CRM_SPREADSHEET_ID>` |
| Sheet tab | `Log` |
| GWS account | `<YOUR_GWS_ACCOUNT_EMAIL>` — **[BULAT]** confirm write access |
| Telegram DM chat_id | **[BULAT]** placeholder — his own chat_id, do NOT reuse Vas's `<YOUR_TELEGRAM_DM_CHAT_ID>` |
| Min age before nudge | **7 days** since col AP (InMail Sent At) |
| Max age (lookback window) | **90 days** since col AP |
| Send cap per run | **5/day** — same conservative cap as Vas's fork |
| Auto-send | **No — approve-before-send.** Vas's `aictrl-linkedin-followup2` auto-sends because that trust was earned over ~2 months of reviewed drafts (his explicit 2026-07-07 instruction). Bulat's whole pipeline is new and unlaunched — default to the safer gate until an equivalent trust decision is made. Do not flip to auto-send without an explicit instruction from Bulat or Vas. |

## Model routing

Same split as Vas's fork: verification/lookup work (profile fetch, still-messageable check, activity scan for an unlogged reply) → Haiku subagent. Drafting the nudge → default/inherited model.

## Why a formula-based read for the eligible-rows query

Same 3,000+ row / 50-row-display caveat as Vas's fork applies identically here — push the filter into a `QUERY()` formula on a scratch cell rather than a raw wide read. **Do not reuse `AK1` as the scratch cell** — that's already claimed by Vas's `aictrl-linkedin-followup2` (confirmed-safe scratch range `AK1` onward as of 2026-07-24). The sheet has been resized (74 columns through BV as of 2026-08-01), and AU–AW belong to this skill per the column map in /home/vas/projects/aictrl/CLAUDE.md. Pick a scratch cell in the free strip **AX–AZ** (e.g. `AY1`; BA–BB are owned by the follow-up approval queue — not scratch) — confirm it's empty with a `read_sheet_values` check immediately before every use, same discipline as Vas's fork, and clear it immediately after reading the result.

## Workflow

### 1. Preflight: LinkedIn session check

Call `mcp__linkedin__get_my_profile` against Bulat's session. Abort with login instructions on session error.

### 2. Find eligible rows via QUERY

Cutoffs: `cutoff_recent` = today − 7 days, `cutoff_old` = today − 90 days, computed from current-date awareness.

Eligible = col AO (InMail Status) = `"sent"`, AND col AP (InMail Sent At) between cutoff_old and cutoff_recent, AND col AR (Reply Status, written by `aictrl-linkedin-status-tracker-bulat`) is empty or `"none"`, AND col AU (this skill's own status) is empty (not already nudged once).

Write the `QUERY()` formula to the scratch cell (see above), read back the result, clear the scratch cell immediately.

If zero rows: print `No contacts eligible for a second-touch nudge.`, skip to Step 6 (still send heartbeat DM).

Slice to first `send_cap=5`.

### 3. For each candidate, verify + draft (Haiku subagent for 3.1–3.3, default model for 3.4)

1. *(Haiku)* `mcp__linkedin__get_person_profile(linkedin_username=<slug>)`.
2. *(Haiku)* Confirm still messageable (Message button present, or now 1st-degree if the connect fold-in was accepted since). If neither, write `AU = "skipped — not eligible"`, `AV = now`, skip send.
3. *(Haiku)* Scan visible activity/messages for any sign of an unlogged reply (belt-and-braces on top of the AR filter). If ambiguous, err toward sending — the DM summary surfaces it either way.
4. *(default model)* Draft a short nudge (2–3 sentences): reference the earlier InMail without repeating it verbatim, pull a fresh hook if visible, keep aictrl voice (warm, research-led, "keep agents on a leash" where natural, never "Worth a look?").

### 4. Operator approval

Post to Bulat's DM chat_id (never the group):

```
LinkedIn second-touch draft — [Name], [Company]

Original InMail sent: [date from AP]
Draft nudge:
"[message text]"

Reply "send [Name]" to approve, "skip [Name]" to discard.
```

Wait for text reply. Do not send without it.

### 5. Send

On "send [Name]": `mcp__linkedin__send_message(linkedin_username=<slug>, message=<approved text>, confirm_send=true)`.

- Success → `AU = "sent"`, `AV = now (UTC)`, `AW = <message text>`.
- Failure → `AU = "error"`, `AV = now`, `AW = "<error detail>"`.

On "skip [Name]": `AU = "skipped — not eligible"`, `AV = now`, `AW` empty.

### 6. Write back

Batch-write `Log!AU<row>:AW<row>`.

### 7. DM summary

```
Bulat's LinkedIn second-touch — <UTC date>
Eligible pool: <N>
Nudged: <N>
Skipped: <N>
Errors: <N>
```

One line per nudge sent: `• <Name> (<Company>) — <first 60 chars>...`

## Known limits

Same as Vas's fork: reply detection is heuristic (depends on `aictrl-linkedin-status-tracker-bulat`'s inbox scan catching it first), one nudge only for now, 90-day hard cutoff.

## Failure-mode quick reference

| Symptom | Action |
|---|---|
| `get_my_profile` no session | Abort, print login instructions. |
| Scratch cell not confirmed empty | Do not write to it — pick a different column past AW, or wait for the sheet resize. |
| About to send without text approval | STOP. This fork does NOT auto-send. |
| About to write outside AU:AW | STOP. Not this skill's territory. |

## Relationship to other skills

```
aictrl-linkedin-outreach-bulat        →  sends InMail (AO/AP/AQ)
aictrl-linkedin-status-tracker-bulat  →  detects replies (AR/AS)
aictrl-linkedin-followup2-bulat       →  THIS skill: nudges the silent ones (AU/AV/AW)
```

Related: `aictrl-linkedin-followup2/SKILL.md` (Vas's original — same structure, auto-send instead of approve-before-send), `aictrl-linkedin-outreach-bulat/SKILL.md`, `aictrl-linkedin-status-tracker-bulat/SKILL.md`. Related memory: `reference_linkedin_mcp.md`, `feedback_outreach_voice.md`, `feedback_no_group_posts_without_instruction.md`.
