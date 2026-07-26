---
name: aictrl-linkedin-status-tracker-bulat
description: Daily LinkedIn reply tracker for Bulat's InMail outreach fork — BULAT'S FORK of aictrl-linkedin-status-tracker, running under Bulat's own LinkedIn MCP session. Unlike Vas's tracker (which polls for connection ACCEPTANCE, since Vas's first touch requires an accepted connection before he can message), this tracker polls for REPLIES to InMail messages Bulat already sent (col AO="sent"), because his first touch doesn't require a prior acceptance. Also polls the connect-request fold-in from aictrl-linkedin-outreach-bulat for acceptance (reusing the same shared R–V/W–X columns as Vas's tracker). Writes cols AR–AT only. NEVER touches Apollo cols A–Q, col O, R–V/W–X beyond the fold-in poll, Y–Z, AA–AI, or AU–AW. NEVER posts to the Telegram group (-5110011669). TRIGGER on `/aictrl-linkedin-status-tracker-bulat`, "check Bulat's InMail replies", "run Bulat's LinkedIn tracker". SKIP for Vas's own tracker (use aictrl-linkedin-status-tracker) or Bulat's outreach batch (use aictrl-linkedin-outreach-bulat).
---

# aictrl LinkedIn Reply Tracker — Bulat's Fork

**Fork of `aictrl-linkedin-status-tracker`, redesigned for InMail.** Vas's tracker exists to detect connection *acceptance* because his first-touch message can't be sent until then. Bulat's first touch (InMail, via `aictrl-linkedin-outreach-bulat`) is already sent regardless of connection state, so there is nothing to "wait for" before messaging — the thing worth tracking for Bulat is whether the person **replied**, so a second-touch nudge (`aictrl-linkedin-followup2-bulat`) knows who's still silent.

This skill also does one small piece of acceptance polling — for the plain connect-request fold-in that `aictrl-linkedin-outreach-bulat` fires alongside the InMail — reusing exactly the same R–V/W–X mechanism and column ownership as Vas's tracker, scoped to rows where col U="Bulat". That part is copy-pasted logic, not new design; keep it in sync with the original if it changes.

## Column ownership

| Cols | Owner | This skill |
|---|---|---|
| A–Q, O | aictrl-crm-refresh / qualifier | NEVER write |
| R–V | aictrl-linkedin-outreach / aictrl-linkedin-outreach-bulat | NEVER write |
| **W–X (rows where U="Bulat" only)** | shared: aictrl-linkedin-status-tracker (Vas's rows) / **THIS skill (Bulat's rows)** | write — acceptance state for the connect-request fold-in, Bulat's rows only |
| Y–Z | aictrl-linkedin-status-tracker / aictrl-linkedin-followup (Vas's pipeline) | NEVER touch |
| AA–AI | email-sequencer / aictrl-linkedin-followup2 (Vas's) | NEVER touch |
| AO–AQ | aictrl-linkedin-outreach-bulat | READ only, NEVER write |
| **AR** | **THIS skill** | InMail Reply Status: `none` / `interested` / `question` / `rejected` / `other` |
| **AS** | **THIS skill** | InMail Reply Detail (quote + date, plain-text append — never a formula, see the circular-reference lesson below) |
| AT | *(reserved, unused for now — leave blank; do not repurpose without checking with Vas/Bulat)* | — |
| AU–AW | aictrl-linkedin-followup2-bulat | NEVER touch |

**Same circular-formula lesson as Vas's tracker applies here:** when appending to AS, first `read_sheet_values` the existing AS cell, concatenate the new line onto it **as a plain string in memory**, then write that resolved string with `value_input_option: RAW`. Never write a `=AS<row>&"..."` formula — that corrupted two of Vas's rows on 2026-07-19 and is unrecoverable via the Sheets API.

## Constants

Same shared sheet as the rest of the pipeline.

| Thing | Value |
|---|---|
| Spreadsheet ID | `1PQ1oaJPVs3GvWQMk9RBjlef-jcPdISswdD4zGv7QqRQ` |
| Sheet tab | `Log` |
| GWS account | `Info@boller.store` — **[BULAT]** confirm write access |
| Telegram DM chat_id | **[BULAT]** placeholder — needs his own chat_id, do NOT reuse Vas's `6348453236` |
| Reply-scan lookback | first 20 inbox conversations, replies older than 7 days skipped — same caps as Vas's tracker |
| Acceptance-poll cap (fold-in) | **20/run** — lower than Vas's 50, since the fold-in is a minor side effect, not the primary flow |

## Workflow

### 1. Preflight: LinkedIn session check

Call `mcp__linkedin__get_my_profile` against Bulat's LinkedIn MCP server. Abort with the standard login instructions on "No valid LinkedIn session" error.

### 2. Reply scan — the primary purpose of this skill

Read `Log!AO2:AO10000` (thin index) to find rows where **col AO = "sent"** (InMail was sent by Bulat's outreach skill). For each match, hydrate `B` (name), `H` (slug), `AR` (existing reply status — skip if already `interested`/`question`/`rejected`, only re-check rows where AR is empty or `none`, capped at 20/run to bound inbox scan cost).

1. Call `mcp__linkedin__get_inbox` (Bulat's session).
2. For each conversation where the last message is **not** from Bulat's own name (i.e. they replied):
   a. Match against the AO="sent" candidate list by name (col B) — same ambiguity rule as Vas's tracker: if two candidates share a name, skip rather than risk a wrong write.
   b. On match: `mcp__linkedin__get_conversation` to read the reply.
   c. Classify: **interested** (question/demo/positive) / **rejected** (explicit no) / **question** (asks what aictrl does) / **other** (OOO, automated, spam — no write).
   d. Write `AR = <classification>`, `AS = "<existing AS>" + " | Reply [date]: <classification> — <≤15 word quote>"` (resolved string, RAW input, per the circular-formula rule above).
   e. For **interested** or **question**: flag for the DM summary with full quote — operator handles the actual reply manually, this skill never replies.

### 3. Connect-request fold-in acceptance poll (secondary, copy of Vas's tracker logic scoped to Bulat's rows)

Read `Log!W2:W10000` and `Log!U2:U10000` (thin index). Find rows where `U="Bulat"` AND `W="pending"`. Cap at 20/run, oldest-R first. For each, call `mcp__linkedin__get_person_profile` and classify exactly as Vas's tracker does (`· 1st`/`Connected` → accepted; `Pending` → still pending; `Connect` + >21 days since R → withdrawn/expired; otherwise still pending). Write back `W<row>:X<row>` only.

**No follow-up send is triggered on acceptance here** — unlike Vas's pipeline, Bulat's first-touch message already went out via InMail regardless of connection state, so there's nothing further to fire when the fold-in connect gets accepted. This step exists purely to keep W/X accurate for Bulat's rows.

### 4. Write updates back to CRM

Batch-write `Log!AR<row>:AS<row>` for reply-scan results, and separately `Log!W<row>:X<row>` for fold-in acceptance results. Never touch A–V (beyond the W/X exception above), Y–Z, AA–AQ, AU–AW.

### 5. DM summary

POST to Bulat's DM chat_id (never the group):

```
🤖 Bulat's LinkedIn tracker — <UTC date>
InMail replies found: <N> (<N> interested/question, <N> rejected, <N> other)
Connect fold-in polled: <N> — accepted: <N>, still pending: <N>, withdrawn/expired: <N>
```

For each interested/question reply: `💬 Reply from [Name] ([Company]): "[quote]" → needs a response, handle manually.`

## Failure-mode quick reference

| Symptom | Action |
|---|---|
| `get_my_profile` no session | Abort, print login instructions. |
| Inbox name match ambiguous | Skip that conversation, don't guess. |
| About to write a formula to AS | STOP — resolve to a plain string first, see the 2026-07-19 lesson. |
| About to write outside AR/AS (or the W/X fold-in exception) | STOP — not this skill's territory. |

## Relationship to other skills

```
aictrl-linkedin-outreach-bulat   →  research/draft/approve → sends InMail (AO/AP/AQ) + best-effort connect fold-in (R–V)
aictrl-linkedin-status-tracker-bulat  →  THIS skill: scans for replies (AR/AS) + polls fold-in acceptance (W/X)
aictrl-linkedin-followup2-bulat  →  nudges InMail contacts who never replied (AR empty/none after N days)
```

Related: `aictrl-linkedin-status-tracker/SKILL.md` (Vas's original — the fold-in acceptance-poll logic in Step 3 is copied from there, keep in sync), `aictrl-linkedin-outreach-bulat/SKILL.md` (writes the AO="sent" rows this skill reads). Related memory: `reference_linkedin_mcp.md`, `feedback_no_group_posts_without_instruction.md`.
