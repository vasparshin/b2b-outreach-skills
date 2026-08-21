---
name: aictrl-prospector
description: "Keeps the CRM's connect pipeline topped up. Finds new ICP-matched transformation-buyer contacts via Apollo, dedupes against the existing CRM, enriches, imports, and grades them, so the daily LinkedIn connect cron never runs dry. TRIGGER when the eligible pool drops below a threshold, on a scheduled prospecting cron run, or 'top up the prospect pool'. SKIP for grading an existing contact (use the qualifier) or one-off individual research (use prospect-research)."
---

# aictrl Prospector

Keeps the CRM's connect pipeline topped up. Finds new ICP-matched UK transformation-buyer contacts via Apollo, dedupes against the existing CRM, enriches, imports, and grades them — so the daily LinkedIn connect cron (aictrl-linkedin-cron.sh) never runs dry.

Built 2026-07-07 from the proven manual recipe run once before (2026-06-30, in-session, never packaged). This skill formalizes that recipe as a repeatable, safer, cost-capped automation.

## Why this exists

The connect cron ran on empty on 2026-07-06/07 (only 5/15 sent) not because ICP-qualified leads ran out, but because a scoped row restriction (from the 2026-07-02 ICP-correction resumption) blocked 2,000+ already-qualified contacts. That gate is being reopened in bands, but eventually the CRM's whole existing pool will be worked through — this skill is what refills it going forward.

## Constants

| Thing | Value |
|---|---|
| Spreadsheet ID | `<YOUR_CRM_SPREADSHEET_ID>` |
| Sheet tab | `Log` (contacts), `Fit_Titles` / `Fit_Locations` (grading rubric reference) |
| GWS account | `<YOUR_GWS_ACCOUNT_EMAIL>` |
| Apollo account | `<YOUR_APOLLO_ACCOUNT_EMAIL>` |
| Telegram DM chat_id | `<YOUR_TELEGRAM_DM_CHAT_ID>` (NEVER the group `<YOUR_TEAM_GROUP_CHAT_ID>`) |
| Pool health buffer | **200** — if fewer than 200 Grade A/B contacts have a blank LinkedIn connect date (col R), this skill runs a prospecting pass. Otherwise it's a no-op (cheap health check only, no Apollo spend). |
| Apollo credit cap per run | **60 credits** (1 credit per enriched contact) — hard stop mid-run if hit, write what's already enriched, report the rest as deferred to next run. |
| Search filters | UK only; titles: CTO/CIO/CDO/VP Engineering/Head of Engineering/Director/Head/VP of Digital Transformation and equivalents (same tier-3/tier-2 list as `Fit_Titles`); company size 50–1,000 employees |
| Healthcare exclusion | Company name/industry matching `nhs`, `hospital`, `clinic`, `health\s+(trust|authority)` is excluded from the search results before enrichment — formalized from the informal filter used in the 2026-06-30 manual run. (This is separate from `company_fit()`'s positive scoring of regulated/traditional industries — this exclusion is about which NEW prospects to go looking for, not how existing/other contacts are graded.) |
| Personal-email exclusion | Drop any enriched contact whose only email is a personal domain (gmail/yahoo/hotmail/outlook/icloud) — corporate email required. |

## Column ownership

| Cols | Owner | This skill |
|---|---|---|
| A–N | THIS skill (on import), aictrl-crm-refresh (on refresh) | write on import only |
| O (Our Grade) | aictrl-crm-qualify / `regrade-crm.py` | THIS skill triggers the grader immediately after import, but the grading logic itself lives in `regrade-crm.py` |
| P–Z | other skills | NEVER write |

## Workflow

### 1. Preflight

1. Check Apollo credit balance (`apollo_usage_stats_credit_usage_stats`). If fewer than 60 credits remain, abort with a clear message rather than partially running.
2. Check pool health: write a scratch `QUERY()` formula to a confirmed-empty cell (see "scratch cell" note below) counting rows where col O is 'A' or 'B' and col R is blank. **Read back, then immediately clear the scratch cell.**
3. If the count is ≥ 200: print `Pool healthy (N ≥ 200) — no prospecting needed this run.` and stop here (still send a short heartbeat DM). This keeps Apollo spend proportional to actual need instead of blind daily searching.

**Scratch cell rule**: before writing to any "unused" column, `read_sheet_values` it first to confirm it's genuinely empty. Designated scratch strip: `AK1` up to column AN, per the authoritative column map in /home/vas/projects/aictrl/CLAUDE.md. NOTE (2026-08-01): the grid is now 74 columns through BV — an old note here claimed it capped at AN/40 columns; that is stale. Columns beyond AN are NOT scratch — AO onward are owned (see the column map). Columns AA–AF are NOT scratch — that's live email-sequencer state. Clear scratch cells immediately after reading their result.

### 2. Search

Call `apollo_mixed_people_api_search` (or `apollo_mixed_people_api_search` equivalent) with:
- Location: United Kingdom
- Titles: pull the tier-3 and tier-2 patterns from `Fit_Titles!A1:B100` as a literal title list (not regex — Apollo's search takes plain title strings/keywords, so translate the top patterns: CTO, Chief Technology Officer, CIO, Chief Information Officer, Chief Digital Officer, VP Engineering, Head of Engineering, Director of Engineering, Director/Head/VP of Digital Transformation, etc.)
- Company size: 51–1,000 employees
- Pull 2–3x the number of contacts you actually need enriched, since dedup + healthcare exclusion + personal-email filtering will remove a chunk before you get to a clean list.

### 3. Filter before spending credits

Before enriching anything (enrichment costs credits, search does not):
1. **Dedup**: read a thin index of existing CRM emails (col F) and LinkedIn handles (col H) — chunk reads to ≤50 rows per call if you need to eyeball them (raw multi-thousand-row reads silently truncate display past ~50 rows). Drop any Apollo result whose email or LinkedIn handle exact-matches an existing row.
2. **Healthcare exclusion**: drop any result whose company name matches the healthcare exclusion pattern above.
3. **Secondary dedup flag (does not block)**: for the surviving candidates, do a rough name+company match against the CRM (case-insensitive). If a candidate's name+company loosely matches an existing row that did NOT exact-match on email/handle, don't drop it automatically — flag it in the DM summary as "possible duplicate, verify manually" and import it anyway. Exact-match dedup alone can miss the same person re-entering under a different email or LinkedIn slug; a human glance is cheaper than either silently duplicating or silently dropping a real new contact.

### 4. Enrich

`apollo_people_bulk_match` in batches of **10 or fewer** — larger batches return 100KB+ responses that overflow inline display and get written to files, which is unnecessary friction for an unattended cron. Stop enriching once you hit the 60-credit cap for this run; anything left over is picked up next run.

Drop any enriched contact with no corporate (non-personal-domain) email.

### 5. Import

Append the surviving, enriched, deduped contacts to the `Log` tab starting at the next empty row. Populate cols A–N (Date, Name, Title, Company, Location, Email, LinkedIn URL, LinkedIn slug, Apollo Contact ID, Apollo Account, Apollo Sequence, Sequence Step, Sequence Status, Apollo Status). Leave col O (Grade) and everything from P onward blank — those are owned by other steps/skills.

### 6. Grade

Run `python3 /home/vas/projects/aictrl/scripts/regrade-crm.py` (no `--full` flag — incremental mode grades only blank-col-O rows, which is exactly the newly imported batch plus anything else still ungraded). Requires the GWS refresh-token credential at `~/.google_workspace_mcp/credentials/<your_gws_account_email>.json` — already in place, no extra auth needed.

### 7. DM summary

POST to DM `<YOUR_TELEGRAM_DM_CHAT_ID>` (never the group):

```
**aictrl prospector — <UTC date>**
Pool health before: <N> eligible (Grade A/B, uncontacted)
Action: <ran search / skipped, pool healthy>
Apollo search: <N> results
Deduped out: <N> (exact match) | Healthcare excluded: <N> | No corporate email: <N>
Enriched & imported: <N> (credits used: <N>/60)
Grade distribution of new batch: A=<N> B=<N> C=<N> D=<N>
Possible duplicates flagged (verify manually): <list of name/company pairs, or "none">
Pool health after: <N> eligible
```

## Known limits

- **Apollo search title-matching is keyword-based, not regex** — periodically compare against `Fit_Titles` to make sure the search keyword list hasn't drifted from the grading rubric (if a new tier-3 pattern gets added to `Fit_Titles` for grading purposes, consider whether it should also be a search keyword here).
- **Healthcare exclusion is a blunt company-name filter**, not an industry-code filter — a company with "health" in its name that isn't actually clinical (e.g. a wellness SaaS) could get excluded incorrectly. Low-cost false negative (we just don't prospect them), not worth over-engineering.
- **The 200-contact buffer is a starting guess**, not tuned data. Revisit after a few weeks of real connect-cron throughput (15/day = ~450/month) to see if 200 is too low (pool gets thin between prospector runs) or too high (Apollo credits spent well before actually needed).

## Cron

`/home/vas/.claude/scripts/aictrl-prospector-cron.sh`, daily at 09:00 BST (before the 10:00 connect cron, so freshly graded contacts are available same day). Same jitter + guaranteed-DM pattern as the other aictrl crons.

Related memory: `project_unified_crm.md`, the 2026-06-30 manual prospecting session (Graphiti `aictrl` group, "Prospector automation scoped, not yet built"). Related skills/scripts: `aictrl-crm-qualify`, `aictrl-linkedin-outreach`, `scripts/regrade-crm.py`.
