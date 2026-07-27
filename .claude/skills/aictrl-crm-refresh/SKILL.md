---
name: aictrl-crm-refresh
description: Refresh the aictrl master CRM sheet (Log tab in spreadsheet 1PQ1oaJPVs3GvWQMk9RBjlef-jcPdISswdD4zGv7QqRQ) with current Apollo state for every contact in our H1/H2/H3 sequences. Reads contacts from the three active sequences via Apollo MCP, dedupes by apollo_contact_id, upserts location/email/sequence-step/sequence-status/apollo-status/last-step-sent/last-reply. NEVER overwrites column O (Our Grade). NEVER writes LinkedIn cols R–V. NEVER posts to the Telegram group (-5110011669) — operator updates go to DM 6348453236 only. TRIGGER on `/aictrl-crm-refresh`, "refresh the CRM", "pull latest Apollo state", "update the CRM sheet". SKIP for one-off contact lookups, qualifying/grading tasks, LinkedIn outreach (use aictrl-linkedin-outreach instead).
---

# aictrl CRM Refresh

Master-CRM refresh skill. Pulls live Apollo state for every contact in our active H1/H2/H3 sequences and upserts it into the `Log` tab of the master sheet.

This skill is **manual-trigger by default**. It can be scheduled via cron only after Vas explicitly approves it for autonomous execution.

## Critical safety rules

1. **Zero-credit budget.** Apollo lead credits must NOT be spent. The skill captures `num_lead_credits_used` before and after, and ABORTS if delta > 0.
2. **Never touch column O (Our Grade).** That column is owned by the qualifier skill / human. Even in dry-run mode, no write into column O.
3. **Never overwrite LinkedIn columns R–V** for existing rows. Those are owned by `aictrl-linkedin-outreach`.
4. **Never post to the aictrl-ops Telegram group `-5110011669`.** All progress, alerts, and summaries go to DM `6348453236` only. See `feedback_no_group_posts_without_instruction.md`.
5. **Dry-run mode** (`--dry-run` or natural language "dry-run only"): pull at most 5 contacts, perform all reads and credit checks, but write NOTHING to the sheet. Print what would have been written.

## Constants

| Thing | Value |
|---|---|
| Required Apollo account email | `vasparshin@gmail.com` |
| Required Apollo user_id | `69fc6082065486001538f103` |
| Master CRM spreadsheet_id | `1PQ1oaJPVs3GvWQMk9RBjlef-jcPdISswdD4zGv7QqRQ` |
| Sheet tab | `Log` (post-rename — until rename, use `Log_v2`) |
| GWS account | `Info@boller.store` |
| H1 sequence_id | `69fde3942587c500119a8f10` |
| H2 sequence_id | `6a032c60fb3a7d0015fe647d` |
| H3 sequence_id | `6a04848c82740000159786ed` |
| Telegram DM chat_id | `6348453236` |
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

- If `email != "vasparshin@gmail.com"`: ABORT. Print: `ABORT: Apollo MCP is on the wrong workspace (got <email>).` Do not proceed.
- Capture `START_CREDITS = num_lead_credits_used` and `START_BALANCE = num_credits_remaining`. Hold for the post-run delta check.

### 2. Read existing CRM rows

**Truncation gotcha (fleet-wide, see `~/.claude/context/mcps.md`):** `read_sheet_values` silently truncates its returned row content to the first 50 rows of any range, no matter how large the range or how many rows it reports having read. A single `Log!A2:V10000` call only ever surfaces rows 2–51 to the model — everything past row 51 is invisible even though the tool claims success. Confirmed 2026-07-27 against this exact spreadsheet.

Read in `<=50`-row windows and accumulate instead: `Log!A2:V51`, `Log!A52:V101`, `Log!A102:V151`, ... up through the sheet's current last row (check via `get_spreadsheet_info` — do not assume the old ~3,000 row count still holds). Build the `apollo_contact_id → row_number` map incrementally as each window comes back, rather than issuing one big read and trusting it covers everything.

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

Collect all UPSERT updates per row range, then call `mcp__google_workspace__modify_sheet_values` once per contiguous block to keep API calls down.

Skip writes entirely in `--dry-run` mode — instead print a summary of what would have been written.

### 6. Post-run credit check

Call `apollo_users_api_profile` one final time. Compute:
- `LEAD_DELTA = num_lead_credits_used - START_CREDITS`
- `BALANCE_DELTA = num_credits_remaining - START_BALANCE`

If `LEAD_DELTA != 0`: post a high-priority alert to DM `6348453236`:
```
⚠️ aictrl-crm-refresh spent <LEAD_DELTA> Apollo lead credits (balance now <num_credits_remaining>). Investigate before next run.
```

### 7. DM summary to Vas

Always send a one-message summary to DM `6348453236` (never to the group):

```
🔄 aictrl-crm-refresh — <UTC timestamp>
Contacts pulled (H1/H2/H3): <N1>/<N2>/<N3> = <total>
Upserted: <U>  Backfilled: <B>  New rows: <NEW>
Lead credit delta: <LEAD_DELTA> (balance <num_credits_remaining>)
Dry-run: <yes/no>
Log: https://docs.google.com/spreadsheets/d/1PQ1oaJPVs3GvWQMk9RBjlef-jcPdISswdD4zGv7QqRQ/edit
```

```bash
TOKEN=$(grep -E "^TELEGRAM_BOT_TOKEN|^TOKEN|^BOT_TOKEN" /home/vas/projects/aictrl/.telegram/.env | head -1 | cut -d= -f2- | tr -d '"' | tr -d "'")
curl -s -X POST "https://api.telegram.org/bot${TOKEN}/sendMessage" \
  -H "Content-Type: application/json" \
  -d "$(jq -nc --arg chat "6348453236" --arg text "$SUMMARY" '{chat_id: ($chat | tonumber), text: $text, disable_web_page_preview: true}')" >/dev/null
```

Treat curl failure as non-fatal — the sheet is the authoritative record.

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
