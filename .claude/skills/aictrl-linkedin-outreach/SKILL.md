---
name: aictrl-linkedin-outreach
description: Daily autonomous LinkedIn-connect batch for the aictrl outreach pipeline — reads the master CRM Log tab for H1 candidates that have NOT yet been LinkedIn-connected (col R empty), fires up to 15 no-note connection requests via the LinkedIn MCP, and updates each candidate's row in place (cols R–V). NEVER touches Apollo cols A–Q. NEVER posts to the Telegram group (<YOUR_TEAM_GROUP_CHAT_ID>) — operator updates go to DM <YOUR_TELEGRAM_DM_CHAT_ID> only. TRIGGER when the user types `/aictrl-linkedin-outreach`, says "run the daily aictrl LinkedIn batch", "send today's LinkedIn outreach", "fire H1 connects", or when invoked by a scheduled cron run. SKIP for one-off connects to a named individual, LinkedIn questions unrelated to the H1 pipeline, work on other projects, or when the user is asking about outreach state rather than running the batch.
---

# aictrl Daily LinkedIn Outreach Batch

You are running the autonomous daily LinkedIn-connect batch for the **aictrl** outreach pipeline. The entire workflow runs without confirmation prompts unless a preflight check fails. Be terse — the user (or cron job log reader) only needs the final summary.

**Architecture (post 2026-05-21 refactor):** The master CRM (`Log` tab) is now populated by `aictrl-crm-refresh`. This skill no longer pulls from Apollo — it reads candidates directly from the CRM where col R (LinkedIn Connect Date) is empty, fires connects, and writes the result back to that row's cols R–V. Apollo cols A–Q are owned by the refresh skill; column O (Our Grade) is owned by the qualifier skill. This skill MUST NOT write anywhere outside R–V.

## Constants

| Thing | Value |
|---|---|
| Required Apollo account email | `<YOUR_APOLLO_ACCOUNT_EMAIL>` |
| Required Apollo user_id | `<YOUR_APOLLO_USER_ID>` |
| Target Apollo sequence column value | `H1 — Security/Data Risk` (matched as substring on col K) |
| Outreach log spreadsheet_id | `<YOUR_CRM_SPREADSHEET_ID>` |
| Sheet tab | `Log` |
| GWS account to use | `<YOUR_GWS_ACCOUNT_EMAIL>` |
| Daily cap (per run) | **15** |
| Note parameter | **omit** (workaround for bug stickerdaniel/linkedin-mcp-server#455) |
| Sender name to log | `Vas Parshin` |
| Telegram DM chat_id | `<YOUR_TELEGRAM_DM_CHAT_ID>` (NOT group — see `feedback_no_group_posts_without_instruction.md`) |
| Apollo enrollment status | **PAUSED as of 2026-07-01** (operator directive: focus on LinkedIn, revisit email/Apollo automation later). While paused, new CRM imports are NOT being enrolled into Apollo sequences, so Apollo's task queue will legitimately return zero `linkedin_step_connect` tasks even when good candidates exist in the CRM. Source directly from the CRM (Step 5 CRM-direct path) as PRIMARY until Vas says Apollo enrollment has resumed — do not treat "zero Apollo tasks" as "zero candidates." |

## Sheet schema (26 columns A–Z — owned by which skill)

| Col | Field | Owner |
|---|---|---|
| A | Date (UTC) | aictrl-crm-refresh |
| B-D | Name, Title, Company | aictrl-crm-refresh |
| E-F | Location, Email | aictrl-crm-refresh |
| G | LinkedIn URL | aictrl-crm-refresh |
| H | LinkedIn slug | aictrl-crm-refresh |
| I | Apollo Contact ID | aictrl-crm-refresh |
| J | Apollo Account | aictrl-crm-refresh |
| K | Apollo Sequence | aictrl-crm-refresh |
| L-N | Sequence Step / Status, Apollo Status | aictrl-crm-refresh |
| O | Our Grade | qualifier skill / manual |
| P-Q | Last Step Sent At, Last Reply At | aictrl-crm-refresh |
| **R** | **LinkedIn Connect Date** | **THIS skill** |
| **S** | **LinkedIn Connect Result** | **THIS skill** |
| **T** | **LinkedIn Note Sent** | **THIS skill** |
| **U** | **LinkedIn Sender** | **THIS skill** |
| **V** | **Notes / follow-up** | **THIS skill** (LinkedIn-related notes only) |
| **W** | **Connect Status — initial value** | **THIS skill writes once: "pending" on send, "n/a — connect unavailable" on fail. aictrl-linkedin-status-tracker updates thereafter.** |
| **X** | **Status Updated At — initial value** | **THIS skill writes once = R (same timestamp). tracker updates thereafter.** |
| Y | Followup Sent At | aictrl-linkedin-status-tracker |
| Z | Followup Message | aictrl-linkedin-status-tracker |

## Workflow

### 1. Preflight: PyPI version check

The LinkedIn MCP has the known bug #455 (note path broken). Poll PyPI to detect when a fix release ships, alert via DM (NOT group).

```bash
KNOWN_BUGGY_VERSION="4.13.0"
LATEST=$(curl -s https://pypi.org/pypi/linkedin-scraper-mcp/json | jq -r '.info.version')
if [ "$LATEST" != "$KNOWN_BUGGY_VERSION" ]; then
  echo "PYPI_VERSION_ALERT: linkedin-scraper-mcp PyPI version is now ${LATEST} (was pinned at ${KNOWN_BUGGY_VERSION}). Verify bug #455 fix is in this release, then update SKILL.md to re-enable note-sending in Step 6 and bump KNOWN_BUGGY_VERSION."
fi
```

Non-blocking — continue regardless. Do NOT curl the Telegram Bot API here (fleet-wide cron rule — see Step 9). Print the alert line to stdout only; if it needs to reach Vas immediately rather than waiting for the next Step 9 summary, that is a wrapper-level enhancement, not something this skill should do itself.

### 2. Preflight: Apollo account check + capture operator user_id

Call `apollo_users_api_profile` (no parameters). Capture the response:
- `email` — verify it's `<YOUR_APOLLO_ACCOUNT_EMAIL>`. If not: ABORT with `ABORT: Apollo workspace is wrong (got <email>).`
- `id` — save this as `MY_APOLLO_USER_ID`. We need it in Step 4 to filter tasks to "only the ones assigned to whoever is running this skill" so that Vas's LinkedIn outreach only touches Vas-owned contacts and Bulat's outreach only touches his.

For Vas (the canonical operator), `id` should equal `<YOUR_APOLLO_USER_ID>`. If Bulat installs this skill, his `apollo_users_api_profile` will return his own id and the same filter will scope to his Bulat-owned contacts. No code changes needed when sharing the skill — it auto-scopes to whoever's running it.

### 3. Preflight: LinkedIn session check

Call `mcp__linkedin__get_my_profile`. If error contains "No valid LinkedIn session was found": ABORT with `ABORT: LinkedIn MCP session expired. Run \`uvx linkedin-scraper-mcp@latest --login\` in a terminal, sign in, then retry.`

### 4. Pull Apollo scheduled LinkedIn tasks (the queue) — SKIP while Apollo enrollment is paused

**Check the "Apollo enrollment status" constant above first.** While it says PAUSED: skip this entire step (don't bother calling the Apollo tasks API — it will legitimately return zero, and that is NOT the same as "no candidates") and go straight to Step 5, which sources directly from the CRM as the PRIMARY path in that mode. Re-enable this step as primary once Vas confirms Apollo enrollment has resumed.

When Apollo enrollment is active, its task queue is the authoritative source of "who should we LinkedIn-connect next" — every contact in H1/H2/H3 has a scheduled `linkedin_step_connect` task with a `due_at` set by Apollo's sequence pacing. Pull these via the REST API (the MCP wrapper doesn't expose this endpoint):

```bash
eval "$(~/bin/secrets-env --export)"  # loads APOLLO_API_KEY (master key; plaintext secrets.env was retired 2026-07-23, encrypted store only)
curl -s -X POST 'https://api.apollo.io/api/v1/tasks/search' \
  -H "X-Api-Key: $APOLLO_API_KEY" -H 'Content-Type: application/json' -H 'Cache-Control: no-cache' \
  --data '{
    "per_page": 100,
    "page": 1,
    "task_priority_status_cd": "scheduled",
    "emailer_campaign_ids": ["<YOUR_APOLLO_SEQUENCE_H1_ID>", "<YOUR_APOLLO_SEQUENCE_H2_ID>", "<YOUR_APOLLO_SEQUENCE_H3_ID>"],
    "open_factor_names": ["task_types"]
  }'
```

- Filters to scheduled tasks in H1 + H2 + H3.
- Default ordering is `due_at` ascending — earliest-due first, which is what we want.
- Page through until `total_pages` reached or we have 50 candidates accumulated (more than enough headroom over the 15/day cap).

In each task, the fields we care about:
- `task.contact_id` — match against the master sheet's "Apollo Contact ID" column (column I)
- `task.due_at` — overdue and earliest-due go first
- `task.emailer_campaign_id` — for the sequence label
- `task.type` — should be `linkedin_step_connect` for our purposes; filter out other task types
- `task.user_id` — who in Apollo owns the task (the email sender). Must equal `MY_APOLLO_USER_ID` captured in Step 2.
- `task.id` — for marking the task complete after firing (Step 7b)

Take only tasks where ALL of the following are true:
1. `type == "linkedin_step_connect"`
2. `status == "scheduled"`
3. `user_id == MY_APOLLO_USER_ID` (the operator running the skill)

The user_id filter is critical: if Vas's LinkedIn skill fires connects for contacts that Bulat owns (because Bulat is the email sender on those rows), Vas's LinkedIn invite goes to a contact who's receiving emails from a totally different person. That mismatch confuses the contact and steps on Bulat's outreach. Each operator's LinkedIn skill should ONLY touch contacts whose email sequence THEY are running. Apollo's `task.user_id` is the source of truth for that.

Apollo's REST API does NOT honour the `task_user_ids` query parameter for master keys (confirmed by testing — it returns identical totals regardless of filter value). So we filter client-side after fetching.

If the API call fails (network, 401, etc.) while Apollo enrollment is otherwise active — fall back to the CRM-direct path below so the cron doesn't die. Mark in the run summary that we fell back.

### 5. Read CRM candidates — PRIMARY path while Apollo is paused, fallback path otherwise

**CRM-direct sourcing (use this whenever Step 4 was skipped or failed):**

Call `mcp__google_workspace__read_sheet_values` with a narrow index slice first — do NOT pull all 26 columns for all rows.

**Truncation gotcha (fleet-wide, see `~/.claude/context/mcps.md`):** even a thin one-column read of `Log!H2:H10000` silently truncates its returned content to the first 50 rows regardless of range size or reported row count — a single big call only ever surfaces rows 2–51. Confirmed 2026-07-27. Read each of the four thin columns (`H` slug, `K` Apollo Sequence, `O` Our Grade, `R` Connect Date) in `<=50`-row windows — `H2:H51`, `H52:H101`, ... — and accumulate across windows instead of trusting one `...2:...10000` call.

Find candidate row numbers (`array_index + 2`) where:
- col H (slug) is non-empty, AND
- col R (Connect Date) is empty, AND
- col K contains "H1"/"H2"/"H3" **OR** col K is blank (freshly-imported contacts not yet enrolled in a sequence — expected while Apollo is paused), AND
- col O (Our Grade) is "A" or "B" if populated (prioritize these); if col O is blank, include but rank after graded rows.

Sort: Grade A first, then Grade B, then ungraded, then by row number ascending within each group (oldest imports first). Take top 15.

Only THEN do a second, targeted read of just those matched rows' full data (name/title/company/slug — `Log!B<row>:H<row>` per row, or a batch covering the contiguous block if the matches cluster together) to build the candidate list. Never re-read the whole sheet just to hydrate a handful of rows.

**Apollo-task-matching (use this only when Step 4 actually ran, i.e. Apollo enrollment is active):**

Build a lookup map: `apollo_contact_id (col I, index 8) → sheet_row_number` from a targeted read of the CRM. Then walk the Apollo tasks list IN ORDER (already due_at asc) and match each task to its CRM row:

- If task.contact_id is NOT in the CRM map: skip (contact not yet imported — next CRM refresh will pick them up).
- If matched but col R (index 17) is non-empty: skip — already LinkedIn-connected, Apollo's task is stale.
- If matched but col H (index 7) is empty: skip — no LinkedIn slug available.
- If matched but col S (index 18) starts with "sent": skip — defensive.
- Otherwise: include as a candidate, carrying through the slug from col H, the row number, AND the Apollo task ID (for Step 7b).

Slice to top 15 (or fewer). If empty, print `No new candidates today.` and skip to Step 8.

### 6. Send each connect, prepare row updates

For each candidate, in order:

1. Call `mcp__linkedin__connect_with_person(linkedin_username=<col H slug>)`. **Do not pass `note`.** This is intentional — see "Known issues" below.
2. Inspect the response `status` and prepare the row update (R-S-T-U-V owned here; W-X seeded here, then handed off to the tracker; Y-Z stay blank — tracker territory):
   - `connected` → R=now (UTC YYYY-MM-DD HH:MM), S=`"sent (no note)"`, T=`"(no note)"`, U=`"Vas Parshin"`, V=brief note (e.g., degree info from response), W=`"pending"`, X=now (= R)
   - `connect_unavailable` → R=now, S=`"connect_unavailable"`, T=`"(no note)"`, U=`"Vas Parshin"`, V=`"new gating dialog or restricted profile"` + any specific reason, W=`"n/a — connect unavailable"`, X=now
   - anything else → R=now, S=raw status, T=`"(no note)"`, U=`"Vas Parshin"`, V=full response message, W=`"n/a — error"`, X=now
3. Track each candidate's sheet row number alongside the new R–X values.

### 7. Write LinkedIn results back to CRM

For each candidate, write to that specific row's cols R:X via `modify_sheet_values`:
- `range_name`: `Log!R<row_number>:X<row_number>`
- `values`: `[[<R>, <S>, <T>, <U>, <V>, <W>, <X>]]`

Write one range per row, always. Do NOT batch several rows into one range, even when they are adjacent: if a single row in that span is missing from your update list, every value below it lands one row too high and the sheet still looks well-formed. That is exactly how the 2026-05-21 CRM import put seven contacts' email addresses on the wrong people (found and fixed 2026-07-29; see the batched-write section of `aictrl-crm-refresh`). At 15 rows there is nothing to optimise here anyway.

**CRITICAL:** never write to cols A–Q (Apollo-owned), col O (Our Grade), or cols Y–Z (tracker-owned). The range must be exactly `R<n>:X<n>`.

### 7b. Mark Apollo task complete (best-effort, ONLY for Apollo-task-matched candidates)

Skip this step entirely for candidates sourced via CRM-direct (Step 5's primary path while Apollo is paused) — they have no Apollo task ID to mark complete.

For each Apollo-task-matched candidate whose connect was `connected` (NOT `connect_unavailable` — those tasks should stay scheduled so we can retry later), call Apollo's update-task endpoint to mark it completed:

```bash
curl -s -X PUT "https://api.apollo.io/api/v1/tasks/${TASK_ID}" \
  -H "X-Api-Key: $APOLLO_API_KEY" -H 'Content-Type: application/json' \
  --data '{"status":"completed","completed_at":"<UTC now ISO>"}'
```

Treat any non-2xx response as non-fatal — log it but continue. Apollo's task list is the queue we're working from; if we can't mark a task complete it'll just resurface next run, where the CRM-side dedupe (col R non-empty) will skip it. Best-effort completion keeps the Apollo UI honest without making us depend on it.

### 8. Print summary

Exactly four lines, no preamble:

```
Sent: <N>
connect_unavailable: <N>
Other / failed: <N> — total attempts: <N>/15
Log: https://docs.google.com/spreadsheets/d/<YOUR_CRM_SPREADSHEET_ID>/edit
```

### 9. Do NOT post to Telegram yourself

Per the fleet-wide cron rule (`~/.claude/context/operations.md`): this skill prints Step 8's four-line summary to stdout ONLY. It must never call the Telegram Bot API, curl `api.telegram.org`, or source `.telegram/.env` — the cron WRAPPER (`aictrl-linkedin-cron.sh`) is solely responsible for parsing that stdout and delivering exactly one DM to `<YOUR_TELEGRAM_DM_CHAT_ID>`. (Fixed 2026-07-24: this step used to also POST directly, causing a duplicate notification alongside the wrapper's own guaranteed-delivery send — see `feedback-cron-telegram-isolation` memory / operations.md.)

If the run produced no candidates (Step 5 exited early), still print `Sent: 0 / connect_unavailable: 0 / Other / failed: 0 — total attempts: 0/15` (or equivalent) so the wrapper has a summary to parse — do not send anything yourself.

## Known issues — read once at startup

**Bug #455 (LinkedIn MCP):** LinkedIn rolled out a new two-step "Add a note to your invitation?" gating dialog. The MCP's note-sending path waits for the textarea directly, never sees it (textarea only mounts after clicking "Add a note"), and returns `connect_unavailable` with `note_sent: false`. **This is why this skill never passes a `note` parameter.** When the maintainer ships a fix, change step 6 to pass an H1-aligned note (≤200 chars, first-person, don't name the sender). See: https://github.com/stickerdaniel/linkedin-mcp-server/issues/455

**Sender mismatch:** Apollo H1 emails are sent from `<TEAMMATE_SENDING_MAILBOX>` (and `<YOUR_SENDING_MAILBOX>` for some H1 leads). LinkedIn outreach is from `Vas Parshin`. Recipients receive emails from one identity and connects from another — acknowledged, not currently a blocker.

**LinkedIn detection risk:** unofficial automation. Cap of 15/run keeps daily volume under the ~100/week free-account invite limit.

## Failure-mode quick reference

| Symptom | Action |
|---|---|
| `apollo_users_api_profile` returns different email | Abort with the message in step 2; do not proceed. |
| LinkedIn `No valid LinkedIn session was found` | Abort with the message in step 3; do not proceed. |
| `connect_with_person` returns `connect_unavailable` repeatedly | Log each, continue. Expected for restricted-invite profiles. If 100% of attempts fail in a row, stop early. |
| CRM read returns 0 H1 candidates with empty R | Print `No new H1 candidates today.` and exit — likely we've LinkedIn-touched everyone in H1 OR the refresh skill hasn't been run yet. |
| Sheet read/write fails (GWS auth) | Follow `feedback_gws_auth_dedup_first.md` — kill duplicate MCP processes first; only re-auth if that doesn't fix it. |
| Accidentally about to write outside R:V | STOP. The Apollo cols A–Q and the qualifier col O are NOT this skill's to touch. |

## Why this skill exists (and changed)

Originally this skill pulled from Apollo, deduped against an append-only LinkedIn log (12 cols), and appended a new row per connect. After the 2026-05-21 CRM refactor:
- All H1/H2/H3 contacts live in the master CRM (Log tab, 22 cols) populated by `aictrl-crm-refresh`.
- This skill is now a writer only: pick from existing CRM rows, fire connects, update R–V in place.
- No more dedupe-against-history; the "empty col R" filter naturally selects un-touched candidates.
- No more append; we always update existing rows.

Update this file when:
- The MCP bug #455 gets fixed (re-enable notes in step 6).
- Daily cap, sender, or sheet location changes.
- A new target sequence (H2, H3 outbound from LinkedIn too) is added — update the col-K substring filter in step 5.
- Telegram DM/group policy changes.

Related memory: `reference_linkedin_mcp.md`, `feedback_linkedin_targeting.md`, `reference_apollo.md`, `feedback_no_group_posts_without_instruction.md`, `feedback_steps_use_numbers.md` in `~/.claude/projects/-home-vas-projects-aictrl/memory/`.
