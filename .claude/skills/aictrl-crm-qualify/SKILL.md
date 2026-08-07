---
name: aictrl-crm-qualify
description: Score every aictrl CRM contact on fit + engagement and write a letter grade (A / B / C / D) into col O ("Our Grade"). Reads the Log tab in spreadsheet 1PQ1oaJPVs3GvWQMk9RBjlef-jcPdISswdD4zGv7QqRQ, runs a rule-based grading pass on title / company / sequence state, and writes col O only for rows where O is currently blank. NEVER touches Apollo cols A–N + P–Q (refresh-owned), R–V (outreach-owned), or W–Z (tracker-owned). NEVER posts to the Telegram group (-5110011669) — operator updates go to DM 6348453236 only. TRIGGER on `/aictrl-crm-qualify`, "grade the CRM", "qualify contacts", "score the leads", "run the qualifier". SKIP for one-off contact scoring of named individuals, CRM refresh (use aictrl-crm-refresh), LinkedIn outreach (use aictrl-linkedin-outreach), or status tracking (use aictrl-linkedin-status-tracker).
---

# aictrl CRM Qualifier

Grades each contact in the master CRM `Log` tab on H1 fit + engagement, writing a letter grade A–D into col O. This is the ONLY skill that writes col O. Other skills (`aictrl-crm-refresh`, `aictrl-linkedin-outreach`, `aictrl-linkedin-status-tracker`) are explicitly forbidden from touching it.

## Constants

| Thing | Value |
|---|---|
| Spreadsheet ID | `1PQ1oaJPVs3GvWQMk9RBjlef-jcPdISswdD4zGv7QqRQ` |
| Sheet tab | `Log` |
| GWS account | `Info@boller.store` |
| Telegram DM chat_id | `6348453236` (NEVER `-5110011669`) |
| Token env file | `/home/vas/projects/aictrl/.telegram/.env` |
| Default mode | rule-based only (no API calls) |
| LLM tiebreaker | optional, off by default; enable with `--with-llm` |
| Anthropic API key | encrypted store via `~/bin/secrets-env` (`ANTHROPIC_API_KEY`) — only loaded if `--with-llm` |
| Re-grade existing? | NO by default — only rows with blank col O. Add `--re-grade` to force overwrite. |

## Column ownership reminder

| Cols | Owner | This skill |
|---|---|---|
| A–N | aictrl-crm-refresh | NEVER write |
| **O Our Grade** | **THIS skill** | write |
| P–Q | aictrl-crm-refresh | NEVER write |
| R–V | aictrl-linkedin-outreach | NEVER write |
| W–Z | aictrl-linkedin-status-tracker | NEVER write |

## Grading rubric

**Canonical reference:** Google Doc "aictrl — CRM Grading Rubric" at https://docs.google.com/document/d/110fgpf8rBfePQ_Xx_lqJiq_Z1zkajSsbSaWzDRhaHjc/edit (lives in the `outreach/` Drive folder shared with Bulat). Edit there when ICP / weights change. The Doc + sheet tabs are the source of truth; the algorithm below is just the executor.

## Ideal Customer Profile (corrected 2026-06-02 — READ FIRST)

aictrl is **NOT** for AI-first companies or AI power users. They already understand AI coding agents and have their own governance figured out — they will not buy, and approaching them wastes outreach.

**TARGET (score company fit HIGH):** traditional / old-school software shops; enterprises on legacy stacks; companies in slow-moving, regulated, or niche industries (banking, insurance, manufacturing, logistics, healthcare, telecom, public sector); teams *just starting* with AI in software development who do not yet have a governance story. They adopt AI coding tools but lack the in-house expertise to keep agents under control — they NEED a leash.

**ANTI-ICP (auto-disqualify → D):** AI-first / "AI-native" companies; developer-tooling vendors; teams that publicly host AI/Claude Code events, run an "AI Ops" guild / AI Days, build AI tooling (e.g. an LLM framework or an MCP), demo/teach AI coding publicly, or won an AI showcase. These were exactly what the old prospecting surfaced — they are the OPPOSITE of fit. See [[project_icp_correction]].

Four dimensions, blended into a final letter grade. Each dimension scored 0–3.

### 1. Title fit (weight 20%)

**Source: `Fit_Titles` tab in the master spreadsheet.** Read columns A (Pattern, case-insensitive regex) and B (Tier 1/2/3). Test each title against the patterns in order; take the FIRST matching tier. If no pattern matches, default to tier 1 (low).

There is no tier 0 for title — empty/unknown titles default to 1, never disqualifying.

### 2. Company fit (weight 30%) — ICP company-type

This dimension now encodes the [[project_icp_correction]] ICP above. It is the primary lever for steering away from AI-first companies toward traditional/lagging adopters.

**Scoring (judge from company name + title + any known context; use the `--with-llm` Haiku step to classify when the name alone is ambiguous):**
- **0 (ANTI-ICP → auto-D):** AI-first / AI-native company, developer-tooling / LLM-infra vendor, or a contact whose public signal is AI thought-leadership (hosts AI/Claude Code events, builds AI tooling, ran an AI Ops guild / AI Days, launched an MCP, won an AI showcase). These are disqualified regardless of title fit.
- **3 (high):** clearly traditional / legacy-stack / slow-moving or regulated industry (banking, insurance, manufacturing, logistics, healthcare, telecom, public sector, retail), or a company plausibly *early* in AI adoption with no governance story.
- **2 (medium):** ordinary B2B software company with no strong signal either way.
- **1 (low):** unknown / cannot classify.

When `--with-llm` is set, classify ambiguous companies against the ICP definition above (target vs anti) before scoring. A confident ANTI-ICP classification sets this dimension to 0 → auto-D. A future `Fit_Companies` tab (enriched industry/size) can replace the heuristic with a lookup, but the ICP polarity (anti = 0, traditional = 3) stays the same.

### 3. Location fit (weight 20%)

**Source: `Fit_Locations` tab in the master spreadsheet.** Read columns A (Country, exact case-insensitive match) and B (Tier 1/2/3). Match against the country portion of CRM col E (Location — formatted as "City, Country"). Extract the country by splitting on the last comma.

If the country isn't in the tab, default to tier 1.

### 4. Engagement (weight 30%)

Combined signal across email + LinkedIn channels. Derived from CRM cols, not a tab.

| Engagement | Signal |
|---|---|
| **3 (high)** | Col Q (Last Reply At) populated — replied to a sequence email — OR Col W == "accepted" — LinkedIn 1st-degree connection. Either is a strong "they're paying attention" signal. |
| **2 (medium)** | Col M (Sequence Status) == "active" — sequence is running — OR Col W == "pending" — LinkedIn invite outstanding. In the pipeline, not yet engaged. |
| **1 (low)** | M == "paused" or unclear AND W has no positive signal (empty or "n/a"). Reachable but stalled. |
| **0 (disqualifying)** | M contains "bounced" / "failed" / "hard_bounce" / "spam_blocked" / "unsubscribed" / "finished" without reply. Email channel dead, no LinkedIn fallback strong enough to redeem. → auto-D. |

Order of evaluation: check disqualifiers first → reply → accepted → active → pending → paused → default. Take the FIRST matching tier.

Note: "active" with no first email sent yet still scores 2. We treat "in the pipeline" as a real engagement signal for prioritization.

### Final grade — weighted sum to letter

`score = 0.2*title + 0.3*company + 0.2*location + 0.3*engagement`

Range: 0 – 3.

| Score | Grade |
|---|---|
| `>= 2.3` | **A** — ready for sales call |
| `2.0 – 2.29` | **B** — strong candidate, prioritize |
| `1.5 – 1.99` | **C** — ok candidate, no clear signal yet |
| `< 1.5` | **D** — skip |

Any dimension at 0 → auto-D, regardless of other scores.

(A threshold is 2.3 — more generous than the original 2.5 — chosen to populate the A tier with high-fit + active-sequence + LinkedIn-pending rows. Tighten back to 2.5 once we have richer engagement signal AND company fit goes live.)

## Workflow

### 1. Preflight

Verify the spreadsheet is reachable and the header row matches the 26-col schema (`A:Z`). If header is shorter than 26 cols, ABORT — the CRM hasn't been migrated to the post-2026-05-21 schema yet, and our col O write would land in the wrong place.

### 2. Read all rows

**Truncation gotcha (fleet-wide, see `~/.claude/context/mcps.md`):** `read_sheet_values` silently truncates its returned row content to the first 50 rows of any range, no matter how large the range or how many rows it reports having read. A single `Log!A2:Z10000` call only ever surfaces rows 2–51 to the model. Confirmed 2026-07-27 against this exact spreadsheet.

**Do NOT window — use the REST route (changed 2026-08-03).** Windowing is correct but expensive: ~60 tool calls for this sheet, each dragging the whole conversation context along. Measured fleet-wide the same day, one skill doing this burned 1.28bn cache-read tokens and 48% of a day's spend. Instead call the shared reader, which does one `GET` against the Sheets REST API with the same user OAuth credentials the MCP already uses:

```
python3 ~/.claude/scripts/sheets-read.py 1PQ1oaJPVs3GvWQMk9RBjlef-jcPdISswdD4zGv7QqRQ 'Log!A2:Z3100' info@boller.store --json
```

**Pass `--json` (or `--plain`), never the bare default, for anything doing field-position logic.** The default output prefixes each line with a row number, which shifts every column one field right — so a naive `cut -f2` returns column A, not column B. The account argument is required; omitting it exits 2 rather than silently reading a different account's sheet.

Verified 2026-08-03 against this spreadsheet: 3,035 rows in a single call, no truncation. It prints numbered TSV (`--json` for JSON), and a non-zero exit means "could not read", never "sheet is empty" — a silent empty result is how the original truncation bug hid. Because it runs inside a `Bash` call you can filter in Python and print only the gradable rows, so the bulk of the CRM never enters the conversation at all — that saving is larger than the call-count one. Keep using the MCP for **writes**, which are small and targeted. Legacy fallback only if the script is unavailable: `Log!A2:Z51`, `Log!A52:Z101`, ... accumulating, tracking each row's sheet number as `array_index + 2` offset by the window start.

### 3. Filter to gradable rows

Keep rows where:
- Col O (index 14) is empty (default) — OR `--re-grade` mode is set.
- Col B (Name) is non-empty (skip totally bare rows).

Skip rows that look like diagnostic / test entries (Col K contains "diagnostic" or "test").

### 4. Apply rubric (rule-based)

For each row, compute ALL FOUR dimensions defined in the rubric above — the formula here must stay byte-identical to the one under "Final grade", and both must list four terms:
- `title` ∈ {1, 2, 3} per the `Fit_Titles` tiers (section 1). No tier 0.
- `company` ∈ {0, 1, 2, 3} per the ICP company-type scoring (section 2). **This is the dimension that carries the ICP correction — it is the only thing that keeps anti-ICP companies out of the A pool. It is NOT optional and NOT `--with-llm`-only.** In rule-based mode score it from the company name + title using section 2's definitions; use 1 (unknown) only when the name genuinely gives no signal, never as a blanket default.
- `location` ∈ {1, 2, 3} per the `Fit_Locations` tiers (section 3).
- `engagement` ∈ {0, 1, 2, 3} per the engagement/channel-state table (section 4).
- `score = 0.2*title + 0.3*company + 0.2*location + 0.3*engagement`
- If any dimension == 0 → grade = D. In particular a company scored 0 (anti-ICP) is an auto-D regardless of how strong the title, location or engagement are.
- Else map score to A/B/C/D per the table above.

**Regression guard (added 2026-07-31 — do not remove).** This step previously read `score = 0.4*fit + 0.3*engagement + 0.3*channel`, which silently dropped BOTH `company` and `location`. Because this step — not the rubric section — is what actually executes, the effect was that the ICP correction never reached the default grading path at all: every grade in col O was computed with no company-ICP term. Worked example of the failure: an AI-first developer-tooling vendor (anti-ICP, company = 0 → should be auto-D) whose contact is a US-based CTO on an active sequence scored `0.4*3 + 0.3*2 + 0.3*2 = 2.4` → **grade A**, and the `--with-llm` leg could not catch it either, because that leg only tiebreaks scores in the 1.8–2.3 band and 2.4 sits above it. Anti-ICP contacts were therefore unreachable by the ICP filter in BOTH modes, specifically at the top of the pool. If you ever edit this formula, change the rubric section in the same commit and re-read both.

### 5. Optional LLM tiebreaker (`--with-llm`)

For rows where the rule-based score is between 1.8 and 2.3 (the B/C borderline), and `--with-llm` is set, call the Anthropic API (Claude Haiku 4.5 — fast and cheap) with a tight prompt:

```
You are grading a sales lead for an AI engineering governance product (aictrl.dev — control layer for teams running Claude/Cursor at scale).
Lead:
- Name: {B}
- Title: {C}
- Company: {D}
- Location: {E}
- Apollo Sequence: {K}
- Sequence Status: {M}
- Apollo Status: {N}
- Last reply at: {Q}
- LinkedIn connect status: {W}
Rule-based score was {score}. Return ONE LETTER: A, B, C, or D. Nothing else. Reason briefly in one sentence after the letter on a new line.
```

If the LLM disagrees with the rule-based grade by more than one letter (e.g., rule said B, LLM said D), flag the row for manual review — don't blindly override. Log both grades + reasoning to a side file `~/.claude/logs/aictrl-crm-qualify-llm-disagreements.log`.

Cap LLM calls at 100 per run to keep cost predictable (Haiku 4.5: ~$0.001/call → max ~$0.10/run).

### 6. Dry-run mode

If invocation says `--dry-run` or "dry-run only" / "don't write": compute grades, print distribution + a sample of 30 (10 each of A, B, D), but write NOTHING to col O.

This is mandatory the FIRST time we run the rubric on real data — show Vas the distribution before scaling.

### 7. Batched write

Collect all `(row_number, grade)` pairs. Write to col O via `batchUpdate`:
- Each update is `Log!O<row>:O<row>` with value `[[grade]]`.
- Batches of up to 500 rows per call.
- **CRITICAL:** the range must be exactly `O<n>:O<n>`. NEVER write outside col O.

### 8. DM summary

POST to DM `6348453236` (NEVER the group):

```
aictrl-crm-qualify — <UTC date>
Rows graded: <N>  (skipped: <SKIPPED>)
Distribution: A=<N>  B=<N>  C=<N>  D=<N>
LLM tiebreakers: <N>  (disagreements logged: <N>)
Dry-run: <yes/no>
Log: https://docs.google.com/spreadsheets/d/1PQ1oaJPVs3GvWQMk9RBjlef-jcPdISswdD4zGv7QqRQ/edit
```

Treat curl failure as non-fatal.

## Re-grading

By default, the skill SKIPS rows where col O is already populated. To force a fresh grade across everyone (e.g., after iterating the rubric), pass `--re-grade`. This overwrites all O values. Use sparingly — operators have likely hand-tuned some grades.

A safer middle ground: `--re-grade-d-only` — only re-grade rows currently graded D, in case they've moved up since the last run (e.g., sequence advanced, LinkedIn accepted).

## Failure-mode quick reference

| Symptom | Action |
|---|---|
| Sheet header doesn't have 26 cols | Abort — schema migration hasn't run. |
| Cell write fails | Follow `feedback_gws_auth_dedup_first.md` — dedup MCP processes first. |
| Anthropic API key missing | Run without `--with-llm`; rule-based pass only. |
| LLM returns non-letter response | Fall back to rule-based grade for that row, log the bad response. |
| Title is empty AND sequence membership clear | Grade based on engagement + channel only (fit dimension scored 1, default Medium-Low). |
| About to write to anything other than col O | STOP. Col O is this skill's only territory. |

## Why this skill exists

Without a grade, the LinkedIn outreach skill currently picks the next 15 candidates by `Last Step Sent At` descending — which is just "most-recently-active in the sequence". That's a weak proxy for ICP fit. With col O populated, the outreach skill (or a sort filter in the sheet) can prioritize A-graded candidates first, then B, then C, ignoring D. The personalize skill (TBD) will also condition its message tone on the grade — A-graded leads get a more direct CTA, D-graded leads aren't messaged at all.

Update this file when:
- The ICP shifts (rubric tiers need new keywords).
- A new sequence (H4 etc.) is added — the title-fit lookup may need adjustment.
- The LLM tiebreaker proves consistently better than rules — promote it from "borderline only" to primary.
- The personalize skill is built — sync the grade values it consumes.

Related memory: `project_outreach_state.md`, `reference_apollo.md`, `feedback_no_group_posts_without_instruction.md`, `feedback_steps_use_numbers.md`. Related skills: `aictrl-crm-refresh`, `aictrl-linkedin-outreach`, `aictrl-linkedin-status-tracker`, future `aictrl-linkedin-personalize`.
