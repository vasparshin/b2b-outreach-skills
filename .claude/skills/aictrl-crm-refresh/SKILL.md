---
name: aictrl-crm-refresh
description: Refresh the aictrl master CRM sheet (Log tab in spreadsheet <YOUR_CRM_SPREADSHEET_ID>) with current Apollo state for every contact in our H1/H2/H3 sequences. Reads contacts from the three active sequences via Apollo MCP, dedupes by apollo_contact_id, upserts location/email/sequence-step/sequence-status/apollo-status/last-step-sent/last-reply. NEVER overwrites column O (Our Grade). NEVER writes LinkedIn cols R–V. NEVER posts to the Telegram group (<YOUR_TEAM_GROUP_CHAT_ID>) — operator updates go to DM <YOUR_TELEGRAM_DM_CHAT_ID> only. TRIGGER on `/aictrl-crm-refresh`, "refresh the CRM", "pull latest Apollo state", "update the CRM sheet". SKIP for one-off contact lookups, qualifying/grading tasks, LinkedIn outreach (use aictrl-linkedin-outreach instead).
---

# aictrl CRM Refresh

Master-CRM refresh skill. Pulls live Apollo state for every contact in our active H1/H2/H3 sequences and upserts it into the `Log` tab of the master sheet.

This skill is **manual-trigger by default**. It can be scheduled via cron only after Vas explicitly approves it for autonomous execution.

## Critical safety rules

1. **Zero-credit budget.** Apollo lead credits must NOT be spent. The skill captures `num_lead_credits_used` before and after, and ABORTS if delta > 0.
2. **Never touch column O (Our Grade).** That column is owned by the qualifier skill / human. Even in dry-run mode, no write into column O.
3. **Never overwrite LinkedIn columns R–V** for existing rows. Those are owned by `aictrl-linkedin-outreach`.
4. **Never post to the aictrl-ops Telegram group `<YOUR_TEAM_GROUP_CHAT_ID>`.** All progress, alerts, and summaries go to DM `<YOUR_TELEGRAM_DM_CHAT_ID>` only. See `feedback_no_group_posts_without_instruction.md`.
5. **Dry-run mode** (`--dry-run` or natural language "dry-run only"): pull at most 5 contacts, perform all reads and credit checks, but write NOTHING to the sheet. Print what would have been written.

## Constants

| Thing | Value |
|---|---|
| Required Apollo account email | `<YOUR_APOLLO_ACCOUNT_EMAIL>` |
| Required Apollo user_id | `<YOUR_APOLLO_USER_ID>` |
| Master CRM spreadsheet_id | `<YOUR_CRM_SPREADSHEET_ID>` |
| Sheet tab | `Log` (post-rename — until rename, use `Log_v2`) |
| GWS account | `<YOUR_GWS_ACCOUNT_EMAIL>` |
| H1 sequence_id | `<YOUR_APOLLO_SEQUENCE_H1_ID>` |
| H2 sequence_id | `<YOUR_APOLLO_SEQUENCE_H2_ID>` |
| H3 sequence_id | `<YOUR_APOLLO_SEQUENCE_H3_ID>` |
| Telegram DM chat_id | `<YOUR_TELEGRAM_DM_CHAT_ID>` |
| Token env file | `/home/vas/projects/aictrl/.telegram/.env` |

## Sheet schema (22 columns A–V)

| Col | Field | Source | Refresh writes? |
|---|---|---|---|
| A | Date (UTC) | refresh timestamp | YES (every run) |
| B | Name | Apollo | YES (only if blank or changed) |
| C | Title | Apollo | YES (only if blank or changed) |
| D | Company | Apollo | YES (only if blank or changed) |
| E | Location | Apollo (city + ", " + country) | YES |
| F | Email | Apollo | YES |
| G | LinkedIn URL | Apollo / LinkedIn skill | YES if Apollo has one and sheet is blank; never overwrite existing |
| H | LinkedIn slug | derived from G | YES if G filled; never overwrite existing |
| I | Apollo Contact ID | Apollo | YES (upsert key — written once, never changed) |
| J | Apollo Account | Apollo (sequence sender email) | YES |
| K | Apollo Sequence | Apollo (campaign name) | YES |
| L | Sequence Step | Apollo (max `step` in emailer_touches) | YES |
| M | Sequence Status | Apollo (contact_campaign_statuses.status) | YES |
| N | Apollo Status | Apollo (contact_stage display name) | YES |
| **O** | **Our Grade** | **manual / qualifier skill** | **NEVER** |
| P | Last Step Sent At | Apollo (max `sent_at` in emailer_touches) | YES |
| Q | Last Reply At | Apollo (max `replied_at` in emailer_touches) | YES |
| R | LinkedIn Connect Date | aictrl-linkedin-outreach skill | NEVER |
| S | LinkedIn Connect Result | aictrl-linkedin-outreach skill | NEVER |
| T | LinkedIn Note Sent | aictrl-linkedin-outreach skill | NEVER |
| U | LinkedIn Sender | aictrl-linkedin-outreach skill | NEVER |
| V | Notes / follow-up | manual + skills | NEVER (refresh doesn't touch) |

## Workflow

### 1. Preflight: Apollo account check

Call `apollo_users_api_profile` with `include_credit_usage: true`.

- If `email != "<YOUR_APOLLO_ACCOUNT_EMAIL>"`: ABORT. Print: `ABORT: Apollo MCP is on the wrong workspace (got <email>).` Do not proceed.
- Capture `START_CREDITS = num_lead_credits_used` and `START_BALANCE = num_credits_remaining`. Hold for the post-run delta check.

### 2. Read existing CRM rows

**Truncation gotcha (fleet-wide, see `~/.claude/context/mcps.md`):** `read_sheet_values` silently truncates its returned row content to the first 50 rows of any range, no matter how large the range or how many rows it reports having read. A single `Log!A2:V10000` call only ever surfaces rows 2–51 to the model — everything past row 51 is invisible even though the tool claims success. Confirmed 2026-07-27 against this exact spreadsheet.

**Do NOT window — use the REST route (changed 2026-08-03).** Windowing is correct but expensive: ~60 tool calls for this sheet, each carrying the whole conversation context. Measured fleet-wide the same day, one skill doing this burned 1.28bn cache-read tokens and 48% of a day's spend. Instead call the shared reader — one `GET` against the Sheets REST API, same user OAuth credentials the MCP already uses:

```
python3 ~/.claude/scripts/sheets-read.py <YOUR_CRM_SPREADSHEET_ID> 'Log!A2:V3100' <your_gws_account_email> --json
```

Verified 2026-08-03 against this spreadsheet: 3,035 rows in a single call, no truncation. Non-zero exit means "could not read", never "sheet is empty". Build the `apollo_contact_id → row_number` map inside that `Bash` call and print only the map, so the CRM body never enters the conversation. Keep the MCP for **writes**. Legacy fallback only if the script is unavailable: `Log!A2:V51`, `Log!A52:V101`, ... accumulating across windows.

For rows where col I is blank, key by LinkedIn slug (col H) as a fallback — this is how the 25 migrated LinkedIn rows get matched once Apollo gives us their contact_ids.

### 3. Pull active contacts from H1+H2+H3

For each of the three sequence IDs, call `apollo_contacts_search` with:
- `_rationale`: short non-PII description ("Refresh CRM state for H1/H2/H3 sequence members")
- `q_contact_email_status_v2[]`: optional — leave default to get all
- `contact_label_ids` / similar: don't filter, we want everyone
- `sort_by_field`: `contact_last_activity_date`
- `per_page`: `100`
- Iterate `page` until `pagination.total_pages` reached

Each search dumps a large response to a tool-results file; capture the file path from the error message and parse with `jq`.

For each contact in each page, filter to:
- has `linkedin_url` OR has `email` (skip totally bare records)
- has at least one `contact_campaign_statuses` entry whose `emailer_campaign_id` matches H1/H2/H3

After each page, immediately call `apollo_users_api_profile` with `include_credit_usage: true` and re-check `num_lead_credits_used`:
- If delta > START_CREDITS: ABORT, post DM, exit.

### 4. Build upsert rows

For each Apollo contact, compute the 22-col row:

```python
# Pseudocode
contact_id = c.id
email = c.email or ""
name = (c.first_name + " " + c.last_name).strip()
title = c.title or ""
company = c.organization_name or ""
location = ", ".join(filter(None, [c.city, c.country]))
linkedin_url = c.linkedin_url or ""
linkedin_slug = parse_slug(linkedin_url)

# Pick the campaign status matching one of our 3 sequences
status_entry = next((s for s in c.contact_campaign_statuses
                     if s.emailer_campaign_id in (H1, H2, H3)), None)
sequence_id = status_entry.emailer_campaign_id
sequence_name = SEQUENCE_NAMES[sequence_id]   # constants table
sequence_status = status_entry.status
sequence_account = status_entry.send_email_from_email_address or ""
touches = status_entry.emailer_touches or []
last_step = max((t.step for t in touches if t.sent_at), default="")
last_step_sent_at = max((t.sent_at for t in touches), default="")
last_reply_at = max((t.replied_at for t in touches if t.replied_at), default="")
apollo_status = c.contact_stage.display_name if c.contact_stage else ""
```

Then look up the row in the existing map:
- If `contact_id` matches an existing row: UPSERT — write only cols A, E, F, I, J, K, L, M, N, P, Q. Skip O, R, S, T, U, V. For B/C/D/G/H: only write if currently blank.
- If LinkedIn slug matches but contact_id is blank: BACKFILL — write contact_id (col I) and all refresh cols. Don't touch LinkedIn cols R–V.
- If neither match: APPEND as new row at the bottom. Fill A–Q (LinkedIn cols R–V blank).

### 5. Batched write

**NEVER assemble a multi-row range from a list and write it as one block.** This instruction previously read "collect all UPSERT updates per row range, then call `modify_sheet_values` once per contiguous block to keep API calls down", and that is what corrupted the CRM: if a single contact in the block is absent from the list — no email in Apollo, filtered out, omitted by the API — every value below it lands one row too high, and the sheet still looks perfectly well-formed. It is silent, and it survives every check that reads a row as a unit.

That is not hypothetical. The 2026-05-21 09:30 import shifted Location and Email up by one across sheet rows 15 and 18–23, so seven contacts carried a different real person's email address. The runs break at exactly the people whose email was blank, which is the signature of this bug. Found 2026-07-29, only because a send was being built on top of it. Corrected the same day; backup at `/home/vas/projects/aictrl/crm-backup-rows14-25-20260729.json`.

Required instead:
- **One write per row**, addressed by that row's own number, with the value taken from the record whose `apollo_contact_id` matched that row. The row number must come from the match, never from a position in a list.
- If you must batch for API-call reasons, build the block **positionally from the sheet**: start from the existing rows in the range and replace only the cells you matched, so an unmatched row keeps its current value instead of receiving its neighbour's.
- **Verify after writing.** Re-read the written range and confirm each row's email still corresponds to that row's person and company. A mismatch here means the write was misaligned — stop and report, do not continue to the next block.
- Then run `python3 ~/.claude/scripts/aictrl-scan-email-mismatch.py` and confirm the off-by-one section is empty before declaring the refresh clean.

Skip writes entirely in `--dry-run` mode — instead print a summary of what would have been written.

### 6. Post-run credit check

Call `apollo_users_api_profile` one final time. Compute:
- `LEAD_DELTA = num_lead_credits_used - START_CREDITS`
- `BALANCE_DELTA = num_credits_remaining - START_BALANCE`

If `LEAD_DELTA != 0`: post a high-priority alert to DM `<YOUR_TELEGRAM_DM_CHAT_ID>`:
```
ALERT: aictrl-crm-refresh spent <LEAD_DELTA> Apollo lead credits (balance now <num_credits_remaining>). Investigate before next run.
```

### 7. DM summary to Vas

Always send a one-message summary to DM `<YOUR_TELEGRAM_DM_CHAT_ID>` (never to the group):

```
aictrl-crm-refresh — <UTC timestamp>
Contacts pulled (H1/H2/H3): <N1>/<N2>/<N3> = <total>
Upserted: <U>  Backfilled: <B>  New rows: <NEW>
Lead credit delta: <LEAD_DELTA> (balance <num_credits_remaining>)
Dry-run: <yes/no>
Log: https://docs.google.com/spreadsheets/d/<YOUR_CRM_SPREADSHEET_ID>/edit
```

**Print the summary to stdout and STOP. Do not deliver it yourself.** The cron wrapper reads stdout and delivers via `tg-send.py` under the correct bot; it is the sole sender. The sheet remains the authoritative record either way.

**Removed 2026-07-31 — do not reinstate.** This step used to read `TELEGRAM_BOT_TOKEN` from `/home/vas/projects/aictrl/.telegram/.env` and `curl` the Telegram sendMessage API directly, which the fleet cron rule in `~/.claude/context/operations.md` explicitly forbids ("The LLM must NOT: curl the Telegram Bot API, source any `.telegram/.env`, read `TELEGRAM_BOT_TOKEN`"). The same block was removed from `aictrl-linkedin-outreach` on 2026-07-24 after it caused duplicate DMs, but the copies in this skill and in `aictrl-linkedin-status-tracker` were missed at the time and stayed live until a full sweep on 2026-07-31 caught them. Beyond the duplicate-message bug, delivering from inside the skill defaults to whichever token the session can see, which is how a cron ends up posting under the wrong bot.

## Failure-mode quick reference

| Symptom | Action |
|---|---|
| Apollo profile returns wrong email | Abort in step 1. |
| Mid-run credit delta > 0 | Abort immediately, post DM, exit. |
| `apollo_contacts_search` returns 0 for a sequence | Log a warning, continue with the other sequences. |
| Sheet write fails (GWS auth) | Follow `feedback_gws_auth_dedup_first.md` — dedup processes before re-auth. |
| Sheet read returns header only | Treat as empty CRM; every Apollo contact becomes a NEW row. |

## Why this skill exists

The old `aictrl-linkedin-outreach` skill only logged LinkedIn-touched contacts (~25 rows). The CRM needs full pipeline visibility: every contact in H1/H2/H3, with current sequence step, status, bounces, replies. Without this skill, we'd be flying blind on the email side and unable to make data-driven decisions about whom to prioritise for LinkedIn outreach next.

When this skill should be updated:
- A new sequence (H4, H5) is added — extend constants table + step-3 loop.
- Apollo adds a useful field (e.g., intent score) we want to track — add a column to the sheet schema AND this file's column table.
- The qualifier skill needs a new "Our Grade" value space — coordinate in [[project-aictrl-todo]], don't change this skill.

Related memory: `project_outreach_state.md`, `reference_apollo.md`, `feedback_no_group_posts_without_instruction.md`, `feedback_steps_use_numbers.md`.
