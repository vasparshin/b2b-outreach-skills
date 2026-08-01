---
name: aictrl-linkedin-status-tracker
description: Daily LinkedIn invitation-status tracker for the aictrl outreach pipeline. Reads the master CRM Log tab for rows with col W = "pending", polls each contact's LinkedIn profile via get_person_profile, detects acceptance, sends an H1 follow-up message via send_message on first-detected accept, and updates the CRM (cols W, X, Y, Z). Flags pending invitations older than 7 days for manual withdrawal and reports them via DM to operator 6348453236. NEVER touches Apollo cols A–Q. NEVER touches col O (Our Grade). NEVER touches cols R–V (owned by aictrl-linkedin-outreach). NEVER posts to the Telegram group (-5110011669). TRIGGER on `/aictrl-linkedin-status-tracker`, "check LinkedIn acceptances", "run the LinkedIn tracker", "poll pending invites". SKIP for one-off profile checks of named individuals, LinkedIn outreach (use aictrl-linkedin-outreach), CRM refresh (use aictrl-crm-refresh), or contact qualification.
---

# aictrl LinkedIn Status Tracker

Daily polling skill that keeps the master CRM (`Log` tab) up to date with current LinkedIn invitation state and triggers the H1 acceptance follow-up message. Reads the rows our `aictrl-linkedin-outreach` skill marked `W=pending`, queries the live profile state, writes back results, sends follow-ups on acceptance, and flags stale invitations.

This skill is the WRITER for cols W, X, Y, Z. It NEVER touches anything else.

## Constants

| Thing | Value |
|---|---|
| Required Apollo account email | `vasparshin@gmail.com` |
| Spreadsheet ID | `1PQ1oaJPVs3GvWQMk9RBjlef-jcPdISswdD4zGv7QqRQ` |
| Sheet tab | `Log` |
| GWS account | `Info@boller.store` |
| Telegram DM chat_id | `6348453236` (NEVER the group `-5110011669`) |
| Token env file | `/home/vas/projects/aictrl/.telegram/.env` |
| Profile poll cap per run | **50** (free-account profile-view safety) |
| Follow-up send cap per run | **10** (free-account DM safety) |
| Stale-invitation threshold | **7 days** since col R; relies on LinkedIn's built-in 3-week auto-expiry for the actual withdrawal until upstream issue stickerdaniel/linkedin-mcp-server#460 ships |
| Secondary (stray) poll cap per run | **12** (interim mitigation — see step 3b) |
| Secondary (stray) pass cadence | every **5th day of the month** (`day-of-month % 5 == 0`) — not every run |

## Column ownership reminder

| Cols | Owner | This skill |
|---|---|---|
| A–N | aictrl-crm-refresh | NEVER write |
| O | qualifier / manual | NEVER write |
| P–Q | aictrl-crm-refresh | NEVER write |
| R–V | aictrl-linkedin-outreach | NEVER write |
| **W Connect Status** | **THIS skill** | write |
| **X Status Updated At** | **THIS skill** | write |
| **Y Followup Sent At** | **THIS skill** | write |
| **Z Followup Message** | **THIS skill** | write |
| AA–AH | email-sequencer / followup2 | NEVER write |
| BA Followup Draft, BB Followup Approval | `aictrl-linkedin-followup` (the approval queue, added 2026-07-31) | NEVER write directly — the followup skill owns these; read BB only to decide whether a row still needs drafting |

## Follow-up message: personalized via prospect-research (approve-before-send)

There is NO static template anymore. On a new acceptance, the follow-up is researched, drafted, and **sent to the operator for approval before it goes out** (see step 4). The old generic placeholder was retired 2026-05-25 (operator feedback: too generic / inaccurate / "slop").

Mode: **approve-before-send** for now. Once the operator has approved the vast majority and the draft quality is trusted, this can flip to auto-send (raise it with the operator first — do NOT auto-send unilaterally).

## Workflow

### 1. Preflight: LinkedIn session check

Call `mcp__linkedin__get_my_profile`. On "No valid LinkedIn session was found" error: ABORT with the standard `uvx linkedin-scraper-mcp@latest --login` instruction. Do not proceed.

### 2. Read pending rows from CRM — narrow index read, THEN targeted hydrate (never one giant read)

**Do this as exactly two reads. Never read all 26 columns for all rows — the CRM has 3,000+ rows and a full `A2:Z10000` read is what caused the 2026-07-01 runaway (the session tried to improvise sub-agent chunking mid-run instead of just doing a normal two-step read; that spawned a background delegation chain that hit the harness's 10-minute ceiling and had to be force-killed). Follow this exact pattern instead — it needs no delegation at all.**

**CRITICAL — `read_sheet_values`'s returned text silently truncates to the first 50 data rows of ANY range, no matter how many rows the range covers or how many the tool claims to have "successfully read".** Confirmed 2026-07-27: a `Log!W2:W3040` call reports "Successfully read 3035 rows" but the row-by-row content stops at row 50 with a bare `... and 2985 more rows` note — no values for anything past row 50 ever reach the model. This is almost certainly the real root cause of the chronic tracker backlog (600–900+ rows stuck pending for weeks): every prior run's "thin index, all rows" read only ever actually saw rows 2–51 of the sheet, silently, while believing it had scanned the full column.

**Fix — read the index in windows of ≤50 rows and accumulate, never trust one big range:** Loop `Log!W<start>:W<start+49>` (and the matching `Log!R<start>:R<start+49>`) for `start = 2, 52, 102, ...` up through the sheet's last row (check current row count via `get_spreadsheet_info` or the last known extent — as of 2026-07-27 real data ends around row ~3036, described as row ~823 in one earlier run's note; re-verify, don't assume). Each window's response will show all of its ≤50 rows with no truncation (confirmed at 40 and 119-row test reads — only ranges yielding >50 rows in one call truncate). Accumulate row indices where col W is `"pending"` OR `"stale (pending >7d, withdraw manually)"` across every window before moving on.

This is more tool calls than the old single-read assumption (roughly one pair of calls per 50 sheet rows, ~60 pairs for 3,000 rows) but each call is cheap (one column, 50 cells) and it's the only way to actually see the whole backlog instead of only ever rediscovering the same first ~50 rows. If a full sweep in one run is too slow, split it across runs (e.g. windows 1–20 today, 21–40 tomorrow) but track which windows were covered so the sweep actually completes instead of restarting at row 2 every day.

From the accumulated pending/stale row indices, convert to sheet row numbers (`array_index + 2` within each window, offset by the window's start). Sort by col R ascending (oldest first). Slice to first `poll_cap=50` row numbers. If more than 50 qualify, the rest will be picked up next run.

If 0 qualify: print `No pending invitations to track.` then go straight to step 5 — still send the heartbeat DM.

**Read 2 — targeted hydrate, matched rows only:** Now that you have ≤50 specific row numbers, read only those rows' needed columns (name, company, title, slug = cols B/D/C/H, plus R) — e.g. one call per contiguous block of matched rows, or individual `Log!B<row>:H<row>` reads if they're scattered. Do NOT re-read the whole sheet at this point; you already know exactly which rows you need.

**Hard rule: no sub-agents, no Task/Agent-tool delegation, no ad-hoc chunking strategy for this step, ever.** If a read call feels too slow or too large, that means the index-first pattern above wasn't followed — go back to Read 1, not to spawning agents. This step should complete as 2 (or 3, if the thin reads are split) simple tool calls, full stop.

### 3. Poll each pending row

For each candidate, in order:

1. Call `mcp__linkedin__get_person_profile(linkedin_username=<col H slug>)`.
2. Classify the response:
   - Profile text contains `· 1st` OR a `Connected` button → **ACCEPTED**. **CRITICAL: a `Message` button alone is NOT sufficient** — LinkedIn shows Message on InMail-able 2nd/3rd degree profiles too. You MUST see `· 1st` or `Connected` explicitly.
   - Profile text contains `Pending` button (with or without Message) → **STILL PENDING**.
   - Profile text contains `Connect` (no Pending) or `· 2nd`/`· 3rd` degree, AND (today − col R) > 21 days → **WITHDRAWN OR EXPIRED** (past LinkedIn's actual ~3-week auto-expiry).
   - Profile text contains `Connect` or `· 2nd`/`· 3rd` degree, but (today − col R) ≤ 21 days → **STILL PENDING**. Scraped degree is unreliable before the invite expires; default conservative.
   - Any error (rate limit, not found, restricted) → **POLL_ERROR**. Skip the row, leave W untouched, do NOT advance.

Now in memory, accumulate per row:
- `new_W` (accepted / pending / withdrawn-or-expired)
- `new_X` (UTC now if status changed; keep existing X if pending stays pending)
- `is_stale` boolean = (today - parse(R)) > 7 days AND new_W == "pending"

### 3b. Secondary pass: stray 1st-degree detection (interim mitigation, low cadence)

**Why this exists:** step 2/3 only ever look at rows where col W = `"pending"`. That misses contacts who became 1st-degree connections some other way — they connected to us first, or the connection happened outside the tracked invite flow (the "Thomas/Varun" gap flagged in the aictrl Todo tab). There is no upstream "list recently added connections" tool to fix this properly (see Known issues below), so this is a cheap, capped, low-frequency mitigation — not a real fix.

**Cadence gate — run this step only if `day-of-month % 5 == 0` (e.g. the 5th, 10th, 15th, 20th, 25th, 30th).** On every other day, skip straight to step 4. This keeps it out of the daily hot path while still sweeping the CRM every ~5 days.

1. If the cadence gate says skip, print `Secondary stray pass: skipped (not a scheduled day).` and go to step 4.
2. Otherwise, read col H (LinkedIn slug) and col W (Connect Status) for all rows — reuse the windowed thin-read pattern from step 2 (≤50-row chunks of `Log!H<start>:H<start+49>` / `Log!W<start>:W<start+49>`, accumulated across the full sheet; never a full-row read, and never a single `H2:H10000`-style call — see step 2's truncation note).
3. Candidate rows = col H is non-empty AND col W is **NOT** `"pending"` (i.e. blank, `"accepted"` already-known-but-worth-a-recheck-rarely, `"withdrawn or expired"`, or `"stale (pending >7d, withdraw manually)"`). In practice this mostly targets blank-W rows (never entered the tracked invite flow) — those are the actual stray candidates.
4. Slice to the first `secondary_poll_cap=12` candidate rows (oldest-added first, or any stable deterministic order — this is a slow sweep, order doesn't need to be optimal).
5. For each candidate, call `mcp__linkedin__get_person_profile(linkedin_username=<col H slug>)` and classify exactly as in step 3 (`· 1st` or `Connected` → accepted; anything else → leave alone, do NOT write "pending" or "withdrawn" for a row that was never in the tracked flow — only write when we found a genuine 1st-degree match).
6. For any row that classifies as **ACCEPTED**: treat it exactly like a first-time accept from step 3 — write `new_W = "accepted"`, `new_X = now` via the normal step 5 write path, and feed it into step 4 (research → draft → approve → send) alongside the primary pass's new accepts. Note in the row's eventual Z entry or the DM summary that it was caught via the secondary sweep, e.g. append `(found via stray-connection sweep)` to context passed to the followup skill, so the operator summary is honest about how it was found.
7. For candidates that are still not 1st-degree, make no CRM write at all — leave W/X exactly as they were. This pass only ever adds information, never overwrites existing pending-flow state.

**Known limitation of this mitigation (say so plainly in any related reporting):** this only catches strays who are **already in the CRM with a LinkedIn slug in col H**. It cannot find people who accepted a connection but were never added to the CRM, or people outside the Apollo pipeline entirely. The real fix is a dedicated "list recently added / 1st-degree connections" LinkedIn MCP tool, tracked upstream at stickerdaniel/linkedin-mcp-server#453 (open, unfilled as of 2026-07-24). Do not present this step as closing the gap — it narrows it.

### 4. Research → draft → approve → send (first-time accepts)

**Delegate to `aictrl-linkedin-followup` skill.** For each row whose status just changed to ACCEPTED — whether found in step 3 (primary pending-poll) or step 3b (secondary stray sweep, when it ran) — invoke the `aictrl-linkedin-followup` skill with inputs: `linkedin_slug` (col H), `apollo_contact_id` (col I), `name` (col B), `company` (col D), `sheet_row`. Cap at `send_cap=10` per run, combined across both sources.

The followup skill handles the full pipeline:
- Step 1: ICP fit gate — if Weak/Not-a-fit, writes `Z = "accepted — not ICP (no message): <reason>"`, leaves Y empty, returns.
- Step 2: Post scrape — recent LinkedIn posts for personalisation hook.
- Step 3: Apollo enrichment.
- Step 4: Draft in aictrl voice.
- Step 5: Persist the draft to CRM cols `BA`/`BB`, THEN post to operator Telegram DM `6348453236` for approval.
- Step 6: Send on explicit approval.

**Cron vs interactive split:**
- When running via cron (`aictrl-linkedin-tracker-cron.sh`): `mcp__linkedin__send_message` is NOT in the cron's `--allowedTools`. The followup skill runs steps 1–5 only — it drafts, **saves the draft to cols BA/BB**, and posts to Telegram. It cannot send. The saved draft is what makes the approval survive the end of the run; the operator approves later from the queue.
- When running interactively: full flow including send.

On success: `new_Y = now`, `new_Z = sent message text`, `BB = sent <date>`.
On drafted-but-unapproved: Y/Z stay empty, but `BA` holds the draft and `BB = pending <date>`.
On send failure: leave Y/Z empty, `BB = send-failed <date>`, keep `BA`, log in summary, keep W=accepted.

**Re-surfacing rule (corrected 2026-07-31).** A row must only be re-drafted if it has NO live draft and NO decision — i.e. `Y` empty AND `BB` empty. Rows with `BB` = `pending`, `approved`, `skipped` or `send-failed` must NOT be fed to the followup skill again: pending/approved are waiting on the operator, skipped is a decision already taken, and send-failed keeps its draft for retry. This step previously said "leave Y/Z empty — re-surfaces next run", which combined with a draft that only ever lived in a Telegram message meant the same contacts were researched and re-drafted every single run, and the result thrown away every single time. On 2026-07-31 that had left 49 of 77 accepted connections with no follow-up ever sent, the oldest accepted 2026-06-03.

`--dry-run`: invoke followup skill in dry-run mode (research + draft + show, no send). If more than `send_cap` accepts in one run, defer the rest.

### 5. Write updates back to CRM

For each row that changed, write to that row's `W<n>:Z<n>` via `modify_sheet_values`:
- Range: `Log!W<row>:Z<row>`
- Values: `[[new_W, new_X, new_Y_or_existing, new_Z_or_existing]]`

For stale rows (W still pending but >7 days old), update W to `"stale (pending >7d, withdraw manually)"` and X to now — keeps the manual-review queue self-documenting without lying about the underlying state.

Batch contiguous-row updates where possible.

### 6. Check inbox for replies from messaged contacts

After updating CRM statuses, scan the LinkedIn inbox for replies from contacts we already DM'd (i.e., rows where W=accepted AND Y is non-empty).

1. Call `mcp__linkedin__get_inbox` to load the current inbox.
2. For each conversation in the inbox where the **last message is NOT from "Vas Parshin"** (i.e., they replied):
   a. Check if the person's name matches any CRM row where W=accepted AND Y is populated.
   b. If match found: call `mcp__linkedin__get_conversation` on that thread to read the reply text.
   c. Classify the reply:
      - **Interested**: asks a question about aictrl, wants to see more, asks for a call/demo, positive engagement → notify operator
      - **Rejected**: "no thanks", "not interested", "not now", "pass", short one-word decline → silent CRM update
      - **Question**: asks what aictrl does, asks for a link, requests clarification → notify operator
      - **Other**: out of office, automated response, spam → ignore, no CRM update
   d. Update CRM col Z: first READ the current col Z value for that row (`read_sheet_values`), then WRITE BACK the plain-text concatenation `<existing Z value> | Reply [YYYY-MM-DD]: [classification] — [≤15 word quote]` via `modify_sheet_values` with `value_input_option: RAW`. NEVER write a formula like `=Z38&"..."` — a formula placed in Z38 that references Z38 is a circular self-reference and corrupts the cell to `#REF!`, destroying the original text with no way to recover it via the Sheets API (this happened on 2026-07-19, rows 38 and 115 — original text was permanently lost). Always resolve the concatenation to a static string in memory before writing.
   e. For **Interested** or **Question**: add to the operator DM summary (step 7) with full reply quote. Do NOT send a reply yourself — operator handles responses manually.

**Match on name, not slug**: inbox shows display names, not slugs. Match by `col B` (CRM name field). If ambiguous (two contacts named "John Smith"), skip — don't risk the wrong update.

**Inbox cap**: only process the first 20 conversations shown (one inbox page). Replies older than 7 days are likely already handled; skip them.

**Cron mode**: this step is included in cron runs. No send tools needed — only inbox read + CRM write.

### 7. DM summary to operator

POST to DM `6348453236` (NEVER the group). Format:

```
LinkedIn tracker — <UTC date>
Polled: <N>
Accepted (new): <N>
Followups sent: <N>
Still pending: <N>
Stale (>7d, withdraw manually): <N>
Withdrawn / expired: <N>
Poll errors: <N>
Replies found: <N> (<N> interested/question, <N> rejected, <N> other)
```

**Naming rule — mandatory, applies to every named contact in this summary (new accepts, followups sent, stale list, replies):** never name a contact from memory of the polling loop or from general context. For each name you print, look up the row's `name`/`company` directly from the in-memory update record you built for THIS row in step 3/3b/5 (or, for replies, the row you matched in step 6) and quote it from there — not from a mental list of "who got accepted recently." A contact only belongs in "Accepted (new)" if `new_W == "accepted"` was set to that row **during this run** (i.e. `new_X` is this run's timestamp) — a row that was already `accepted` before this run started (stale from a prior run) must never be listed as a new accept, regardless of how prominent it was in the poll order. This applies identically to accepts found via step 3b — quote name/company from that row's own record, and label them `(via stray sweep)` in the summary so the operator can tell the two sources apart. If listing "Accepted (new)" by name, build the list explicitly as `[(row_number, name, company, source) for each row where new_W was just set to accepted this run]` before writing the message — do not reconstruct it from recollection after the fact.

For each **Interested** or **Question** reply, append:

```
Reply from [Name] ([Company]):
"[full reply text]"
→ Needs your response — handle manually in LinkedIn inbox.
```

If stale_count > 0, append the list of (Name, Company, days_pending, profile_url) so the operator can withdraw them in the LinkedIn UI. Cap at 20 names to keep the message readable.

**Print the summary to stdout and STOP. Do not deliver it yourself.**

`aictrl-linkedin-tracker-cron.sh` reads this skill's stdout and delivers it via `tg-send.py` under the correct bot. That wrapper is the sole sender.

**Removed 2026-07-31 — do not reinstate.** This step used to end with a `bash` block that read `TELEGRAM_BOT_TOKEN` out of `/home/vas/projects/aictrl/.telegram/.env` and `curl`ed the Telegram sendMessage API directly. That is the exact violation the fleet cron rule in `~/.claude/context/operations.md` names ("The LLM must NOT: curl the Telegram Bot API, source any `.telegram/.env`, read `TELEGRAM_BOT_TOKEN`"), and the exact bug removed from `aictrl-linkedin-outreach` on 2026-07-24 for causing duplicate DMs — the skill sent one copy and the wrapper sent a second from the same stdout. The outreach skill was fixed then; this copy in the tracker was missed and stayed live until now. If a summary needs to reach Telegram, it goes to stdout and the wrapper delivers it.

## Dry-run mode

If the invocation says `--dry-run` or "dry-run only" / "don't send messages": skip step 4 (no `send_message` calls) but still update W/X. This is useful right after a fresh aictrl-linkedin-outreach batch — gives us a status snapshot without firing premature follow-ups.

## Known issues / limits

**Acceptance signal is heuristic.** LinkedIn doesn't expose a stable "is invitation accepted" API; we infer from public profile button text. The MCP's `get_person_profile` returns the raw scraped text, so we look for `· 1st` or `Pending` or `Connect` or `Connected` strings. False positives are possible (e.g., a withdrawn invite followed by an org-mate accepting a different request); audit periodically.

**No upstream withdraw tool.** Filed as stickerdaniel/linkedin-mcp-server#460. Until that lands, stale invitations (>7d) are flagged in the DM summary but not withdrawn programmatically. LinkedIn auto-expires unaccepted invitations at ~3 weeks, so the worst case is 3 weeks of an invitation slot tied up.

**Rate / detection risk.** Profile polling is heavier than outreach — every row triggers a real browser navigation. Cap of 50/run keeps daily exposure well under the ~80/day soft limit on free accounts. If we ever need to poll more, batch across multiple runs spaced apart. The secondary sweep (step 3b) adds at most 12 more, only once every 5 days, so combined exposure stays well under the limit even on sweep days (≤62 profile views vs the ~80/day soft cap).

**Pending-only polling misses out-of-flow acceptances (KNOWN GAP, interim mitigation in place).** The primary pass (steps 2–3) only ever looks at rows with `W = "pending"`, so a contact who becomes a 1st-degree connection some other way — they accepted/sent the connection outside our tracked invite (e.g. via a mutual, an event, or LinkedIn's own "people you may know" surface) — is invisible to it. This was flagged as the "Thomas/Varun" gap in the aictrl Todo tab. Step 3b (secondary stray sweep) is a **cheap, imperfect, interim mitigation**: it only catches strays who are already in the CRM with a LinkedIn slug in col H, on a slow 5-day cadence, capped at 12/run — it does NOT catch anyone outside the CRM entirely, and it is not a substitute for a real fix. The real fix is a dedicated "list recently added / 1st-degree connections" LinkedIn MCP tool, which does not exist upstream today — tracked at stickerdaniel/linkedin-mcp-server#453 (open, unfilled as of 2026-07-24). Once that tool ships, step 3b should be retired in favor of directly diffing the connections list.

## Failure-mode quick reference

| Symptom | Action |
|---|---|
| `get_my_profile` returns no session | Abort, print login instructions, exit. |
| `get_person_profile` returns error for one row | Skip that row (no W change), continue. Don't break the whole run on a single bad slug. |
| Acceptance detection is ambiguous (no `· 1st` and no `Pending`) | Default to `pending` (safer than false-positive accept that triggers an unwanted DM). |
| `send_message` fails | Leave Y/Z blank, mark in the summary. Operator can retry manually. |
| Sheet auth fails | Follow `feedback_gws_auth_dedup_first.md` — dedup MCP processes first. |
| About to write outside W:Z | STOP. Cols A–V are NOT this skill's territory. |
| Telegram message about to go to group `-5110011669` | STOP. Per `feedback_no_group_posts_without_instruction.md` — DM only. |
| Inbox name match is ambiguous | Skip that conversation — don't risk writing to the wrong CRM row. |
| `get_conversation` fails for a reply | Skip that reply, note in summary. Don't block the rest of the run. |

## Why this skill exists

The `aictrl-linkedin-outreach` skill fires connection requests but is fire-and-forget. Without acceptance tracking we'd never know which leads warmed up and never trigger the second-touch follow-up that converts the lead. This skill closes that loop:

```
outreach skill sends invite → tracker detects accept → tracker sends H1 message → reply lands in inbox → tracker classifies reply → operator notified if interested → email sequence
```

Update this file when:
- Upstream withdraw tool (stickerdaniel/linkedin-mcp-server#460) ships — wire it in to step 5 for stale rows.
- Upstream "list recently added connections" tool (stickerdaniel/linkedin-mcp-server#453) ships — retire step 3b's slug-by-slug sweep in favor of directly diffing the real connections list; that is the actual fix for the out-of-flow-acceptance gap, step 3b is only an interim mitigation.
- The qualifier skill is built and col O is populated — replace the default message with per-contact personalisation.
- LinkedIn changes its profile-state DOM (acceptance heuristics in step 3 may need updating).
- Poll / send caps need to change because we've moved to a paid LinkedIn plan with higher limits.

Related memory: `reference_linkedin_mcp.md`, `feedback_linkedin_targeting.md`, `feedback_no_group_posts_without_instruction.md`, `feedback_steps_use_numbers.md`, `project_outreach_state.md`. Related skills: `aictrl-linkedin-outreach`, `aictrl-crm-refresh`, future `aictrl-crm-qualify`.
