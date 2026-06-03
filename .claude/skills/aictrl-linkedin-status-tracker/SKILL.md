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

## Follow-up message: personalized via prospect-research (approve-before-send)

There is NO static template anymore. On a new acceptance, the follow-up is researched, drafted, and **sent to the operator for approval before it goes out** (see step 4). The old generic placeholder was retired 2026-05-25 (operator feedback: too generic / inaccurate / "slop").

Mode: **approve-before-send** for now. Once the operator has approved the vast majority and the draft quality is trusted, this can flip to auto-send (raise it with the operator first — do NOT auto-send unilaterally).

## Workflow

### 1. Preflight: LinkedIn session check

Call `mcp__linkedin__get_my_profile`. On "No valid LinkedIn session was found" error: ABORT with the standard `uvx linkedin-scraper-mcp@latest --login` instruction. Do not proceed.

### 2. Read pending rows from CRM

Call `mcp__google_workspace__read_sheet_values`:
- `user_google_email`: `Info@boller.store`
- `spreadsheet_id`: master CRM id
- `range_name`: `Log!A2:Z10000`

Filter to rows where col W (index 22) == "pending". Track sheet row number as `array_index + 2`. Sort by col R (LinkedIn Connect Date) ascending — oldest invitations checked first (most likely to have resolved, most urgent for stale flag).

Slice to first `poll_cap=50` rows. If more than 50 are pending, the rest will be picked up next run.

If 0 pending: print `No pending invitations to track.` then go straight to step 5 (summary) — still send the heartbeat DM.

### 3. Poll each pending row

For each candidate, in order:

1. Call `mcp__linkedin__get_person_profile(linkedin_username=<col H slug>)`.
2. Classify the response:
   - Profile text contains substring `· 1st` or `Connected` button label → **ACCEPTED**.
   - Profile text contains `Pending` button label → **STILL PENDING**.
   - Profile text contains `Connect` button label (no "Pending") or `· 2nd`/`· 3rd` degree → **WITHDRAWN OR EXPIRED** (LinkedIn dropped it; common after >3 weeks).
   - Any error (rate limit, not found, restricted) → **POLL_ERROR**. Skip the row, leave W untouched, do NOT advance.

Now in memory, accumulate per row:
- `new_W` (accepted / pending / withdrawn-or-expired)
- `new_X` (UTC now if status changed; keep existing X if pending stays pending)
- `is_stale` boolean = (today - parse(R)) > 7 days AND new_W == "pending"

### 4. Research → draft → approve → send (first-time accepts)

For rows whose status just changed to ACCEPTED (W: "pending" → "accepted"), cap at `send_cap=10` per run:

1. **Research + fit-gate (subagent, Sonnet).** For each new accept, dispatch a subagent running the `prospect-research` skill (which loads `/home/vas/projects/aictrl/.claude/prospect-research.md`) on that person's LinkedIn slug (col H) + Apollo contact_id (col I). The subagent returns a compact brief, an **ICP fit verdict**, and — **only if fit is Moderate+** — a drafted message in aictrl's voice (helping-build positioning; funny/specific, not slop; works in the free-code-review-tokens + connect-a-GitHub-repo hooks). Running it as a subagent keeps the raw LinkedIn/Apollo/web output out of this run's context — the cost lever.
   - If fit is **Weak / Not-a-fit:** do NOT draft or message. Record `new_Z = "accepted — not ICP (no message): <reason>"`, leave `new_Y` empty, and include it in the summary as a skipped non-fit. (Connection stays; we just don't burn a message on a non-buyer.)
2. **Approve.** Post the briefs + drafts (fits only) to the operator on Telegram DM `6348453236` (NEVER the group) and WAIT for approve / edit / skip. Do NOT send unapproved. (Batch: present all drafts, collect decisions.)
3. **Send on approval.** `mcp__linkedin__send_message(recipient_username=<slug>, message=<approved text>)`.
4. On success: `new_Y = now`, `new_Z = approved message text`.
5. On skip/no-approval: leave Y/Z empty — re-surfaces next run (W=accepted, Y empty).
6. On send failure: leave Y/Z empty, log in summary, keep W=accepted.

`--dry-run`: do steps 1–2 (research + draft + show) but never send (step 3 skipped). If more than `send_cap` accepts in one run, defer the rest.

### 5. Write updates back to CRM

For each row that changed, write to that row's `W<n>:Z<n>` via `modify_sheet_values`:
- Range: `Log!W<row>:Z<row>`
- Values: `[[new_W, new_X, new_Y_or_existing, new_Z_or_existing]]`

For stale rows (W still pending but >7 days old), update W to `"stale (pending >7d, withdraw manually)"` and X to now — keeps the manual-review queue self-documenting without lying about the underlying state.

Batch contiguous-row updates where possible.

### 6. DM summary to operator

POST to DM `6348453236` (NEVER the group). Format:

```
🤖 LinkedIn tracker — <UTC date>
Polled: <N>
Accepted (new): <N>
Followups sent: <N>
Still pending: <N>
Stale (>7d, withdraw manually): <N>
Withdrawn / expired: <N>
Poll errors: <N>
```

If stale_count > 0, append the list of (Name, Company, days_pending, profile_url) so the operator can withdraw them in the LinkedIn UI. Cap at 20 names to keep the message readable.

```bash
TOKEN=$(grep -E "^TELEGRAM_BOT_TOKEN|^TOKEN|^BOT_TOKEN" /home/vas/projects/aictrl/.telegram/.env | head -1 | cut -d= -f2- | tr -d '"' | tr -d "'")
curl -s -X POST "https://api.telegram.org/bot${TOKEN}/sendMessage" \
  -H "Content-Type: application/json" \
  -d "$(jq -nc --arg chat "6348453236" --arg text "$SUMMARY" '{chat_id: ($chat | tonumber), text: $text, disable_web_page_preview: true}')" >/dev/null
```

Treat curl failure as non-fatal.

## Dry-run mode

If the invocation says `--dry-run` or "dry-run only" / "don't send messages": skip step 4 (no `send_message` calls) but still update W/X. This is useful right after a fresh aictrl-linkedin-outreach batch — gives us a status snapshot without firing premature follow-ups.

## Known issues / limits

**Acceptance signal is heuristic.** LinkedIn doesn't expose a stable "is invitation accepted" API; we infer from public profile button text. The MCP's `get_person_profile` returns the raw scraped text, so we look for `· 1st` or `Pending` or `Connect` or `Connected` strings. False positives are possible (e.g., a withdrawn invite followed by an org-mate accepting a different request); audit periodically.

**No upstream withdraw tool.** Filed as stickerdaniel/linkedin-mcp-server#460. Until that lands, stale invitations (>7d) are flagged in the DM summary but not withdrawn programmatically. LinkedIn auto-expires unaccepted invitations at ~3 weeks, so the worst case is 3 weeks of an invitation slot tied up.

**Rate / detection risk.** Profile polling is heavier than outreach — every row triggers a real browser navigation. Cap of 50/run keeps daily exposure well under the ~80/day soft limit on free accounts. If we ever need to poll more, batch across multiple runs spaced apart.

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

## Why this skill exists

The `aictrl-linkedin-outreach` skill fires connection requests but is fire-and-forget. Without acceptance tracking we'd never know which leads warmed up and never trigger the second-touch follow-up that converts the lead. This skill closes that loop:

```
outreach skill sends invite → tracker detects accept → tracker sends H1 message → reply lands in inbox → manual qualification → email sequence
```

Update this file when:
- Upstream withdraw tool (stickerdaniel/linkedin-mcp-server#460) ships — wire it in to step 5 for stale rows.
- The qualifier skill is built and col O is populated — replace the default message with per-contact personalisation.
- LinkedIn changes its profile-state DOM (acceptance heuristics in step 3 may need updating).
- Poll / send caps need to change because we've moved to a paid LinkedIn plan with higher limits.

Related memory: `reference_linkedin_mcp.md`, `feedback_linkedin_targeting.md`, `feedback_no_group_posts_without_instruction.md`, `feedback_steps_use_numbers.md`, `project_outreach_state.md`. Related skills: `aictrl-linkedin-outreach`, `aictrl-crm-refresh`, future `aictrl-crm-qualify`.
