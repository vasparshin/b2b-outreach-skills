---
name: aictrl-linkedin-outreach-bulat
description: Daily autonomous LinkedIn InMail outreach batch for the aictrl pipeline — BULAT'S FORK, running under Bulat's own LinkedIn account/session (Premium, InMail-capable) and his own Apollo user_id, sharing the same CRM (Log tab) as Vas's aictrl-linkedin-outreach skill. Unlike Vas's connect-first flow, Bulat's flow is research → draft → operator approval → send a personalised InMail directly to H1 candidates scoped to him (col AO empty), with NO wait-for-acceptance gate — Premium InMail lets him message people he isn't connected to yet. Also fires a best-effort plain connect request (no note) alongside the InMail so the relationship can grow into a 1st-degree connection over time, reusing the existing shared R–V/W–X columns for that. NEVER touches Apollo cols A–Q. NEVER posts to the Telegram group (-5110011669). REQUIRES a working LinkedIn MCP server configured against Bulat's own authenticated Premium profile — do not run until that exists (see "Setup required before first run"). TRIGGER when Bulat (or someone running this on his behalf) types `/aictrl-linkedin-outreach-bulat`, says "run Bulat's daily aictrl LinkedIn batch", or when invoked by Bulat's own scheduled cron run. SKIP for Vas's own batch (use aictrl-linkedin-outreach), one-off connects to a named individual, or work on other projects.
---

# aictrl Daily LinkedIn InMail Outreach Batch — Bulat's Fork

**This is Bulat's stage-1 pipeline, redesigned 2026-07-24 around his LinkedIn Premium InMail capability.** It is no longer a simple "fire a bare connect request" batch like Vas's `aictrl-linkedin-outreach` — Bulat's pipeline is **research → draft → operator approval → send InMail**, all in one skill, because Premium InMail removes the "wait for the connection to be accepted before you can say anything personal" constraint that Vas's flow is built around.

## Key design decision — InMail-first, not connect-first

Vas's pipeline is 4 stages because a free/non-Premium LinkedIn account can't message someone until they've accepted a connection request: **connect (no note) → wait for accept → research/draft/approve/send follow-up → second-touch nudge.**

Bulat (Premium, ~99% confident InMail-capable per Vas 2026-07-24) doesn't have that constraint. His first-touch message can carry the same research-backed personalisation as Vas's *second* stage, sent on day one, to someone who isn't connected yet. So this skill **absorbs the research/draft/approve/send logic that lives in `aictrl-linkedin-followup` for Vas's pipeline** and runs it as Bulat's *first* touch, not his second. There's no separate "wait for accept" stage for the InMail — that gate doesn't exist for him.

He may still also become a 1st-degree connection with these people over time, so this skill **additionally fires a best-effort plain connect request (no note)** in the same pass, using the exact same mechanism and shared R–V/W–X columns as Vas's `aictrl-linkedin-outreach`. That's a fold-in, not a separate stage — if it fails or is skipped, the InMail send still proceeds independently. Don't gate the InMail on the connect request succeeding, or vice versa.

## What LinkedIn MCP tool sends the InMail

**`mcp__linkedin__send_message(linkedin_username, message, confirm_send, profile_urn?)`.** Its own tool description says: *"The recipient must be directly messageable from the profile page."* There is no separate InMail-specific tool in this MCP server — `send_message` is a thin wrapper around whatever "Message" button LinkedIn renders on the target's profile page. For a 1st-degree connection that's a normal DM; for a non-connection, LinkedIn only renders a Message button there **if the sender has InMail credits** (Premium/Sales Nav) or the target has "open profile" messaging on. So this same tool should work for Bulat's InMail sends *if* his account actually has InMail credits available — but this has **not been verified live**, because his LinkedIn MCP session doesn't exist yet (see Setup below).

**Do not assume this works without verification.** The first live run of this skill MUST treat "does `send_message` actually show/use a Message button on a non-connection's profile for Bulat's account" as an open question, not a given — see Step 3b (verification gate).

## Setup required before first run — DO NOT RUN until this is done

Same as before — nothing here has changed from the prior fork:

1. Bulat needs his own authenticated LinkedIn browser profile, separate from Vas's (`~/.linkedin-mcp/profile`). Suggested path: `~/.linkedin-mcp-bulat/profile`.
2. Log in once interactively: `uvx linkedin-scraper-mcp@latest --login --user-data-dir ~/.linkedin-mcp-bulat/profile`.
3. Register a SEPARATE MCP server entry (never reuse Vas's `linkedin` entry). This skill's tool calls assume an MCP server named `linkedin` inside Bulat's own Claude Code project/session — if he's instead added as a second identity inside Vas's `aictrl` session, the server needs a distinct name and every `mcp__linkedin__*` call in this file needs updating to match.
4. Verify with `--status`.
5. **NEW — confirm InMail credits exist.** Once logged in, have Bulat check his own LinkedIn Premium account for available InMail credits (Settings → Premium features, or just note the credit count shown when composing a message to a non-connection in the LinkedIn UI). If he has zero credits or Premium doesn't include InMail on his plan, Step 3b below will fail at the first live send and this skill's InMail step needs to be paused until credits are available — the connect-request fold-in still works regardless.
6. **NEW — sheet resize required.** This skill owns new columns AO–AQ (see schema below), which are past the current sheet's column cap. Followup2's scratch-cell note records the grid capping at column AN (40 columns) as of 2026-07-24. Someone with edit access must extend the `Log` tab to at least column AQ (`resize_sheet_dimensions` or manually via the Sheets UI) before this skill's write-back step will succeed. **This has not been done — do not run Step 7 until it has.**
7. Bulat's own Apollo identity confirmed — auto-captured at Step 2 below, same mechanism as before, no code change needed.

None of the above has been done — this remains a documentation/package prep task, not a live setup.

## Staggering — unchanged, still required before scheduling any cron

Vas's cron runs 10:00; this skill's cron, if/when scheduled, should run at a different time — suggest 14:00 — for the connect-request fold-in's sake (it still shares R–V/W–X with Vas's skill via first-write-wins on col R). The InMail step doesn't need staggering against Vas's runs since it writes to columns nothing else touches, but keep the same 14:00 slot for simplicity — one cron, one time, easier to reason about.

## Model routing

Same split as `aictrl-linkedin-followup`, reused directly here (2026-07-24 change, applies fleet-wide):
- **Steps 2–4 (ICP gate, post scrape, Apollo enrichment) → Haiku subagent** via the Task tool. Feed slug/name/company/apollo_contact_id, return only: ICP verdict + reason, post hook (or "none"), enrichment notes. Don't let raw profile text leak into this skill's context.
- **Step 5 (drafting the InMail) → default/inherited model.** This is what reply rates depend on.
- **Steps 6–8 (approval, send, connect fold-in) → default/inherited model.**

## Column ownership — new columns, do not collide with existing owners

| Cols | Owner | This skill |
|---|---|---|
| A–Q | aictrl-crm-refresh | NEVER write |
| O | qualifier / manual | NEVER write |
| R–V | shared: aictrl-linkedin-outreach / aictrl-linkedin-outreach-bulat | write (connect-request fold-in only, `U="Bulat"`) |
| W–X | shared: aictrl-linkedin-status-tracker / aictrl-linkedin-status-tracker-bulat | write once on connect fold-in send (same as before), tracker owns thereafter |
| Y–Z | aictrl-linkedin-status-tracker / aictrl-linkedin-followup (Vas's accepted-connection path) | NEVER write — this is Vas's post-accept pipeline, not Bulat's |
| AA–AF | email-sequencer | NEVER touch |
| AG–AI | aictrl-linkedin-followup2 (Vas's) | NEVER touch |
| **AO** | **THIS skill** | InMail Status: `sent` / `skipped — not ICP` / `skipped — not messageable` / `error` |
| **AP** | **THIS skill** | InMail Sent At (UTC) |
| **AQ** | **THIS skill** | InMail Message text (or non-ICP reason) |
| AR–AT | aictrl-linkedin-status-tracker-bulat | NEVER write (reply tracking) |
| AU–AW | aictrl-linkedin-followup2-bulat | NEVER write (second-touch nudge) |

**Cols AO–AW require the sheet to be resized past its current column-AN cap — see Setup step 6. Do not attempt to write there until that's confirmed done, or the write will fail/silently truncate depending on the Sheets API's behavior on out-of-bounds columns.**

## Constants

| Thing | Value |
|---|---|
| Required Apollo account email | **[BULAT]** placeholder — confirm with Bulat, NOT `vasparshin@gmail.com` |
| Required Apollo user_id | captured automatically at Step 1 |
| Target Apollo sequence column value | `H1 — Security/Data Risk` (substring match on col K) |
| Outreach log spreadsheet_id | `1PQ1oaJPVs3GvWQMk9RBjlef-jcPdISswdD4zGv7QqRQ` — same shared sheet |
| Sheet tab | `Log` |
| GWS account | `Info@boller.store` — **[BULAT]** confirm Bulat's environment has write access |
| Daily cap (per run) | **10** — lower than Vas's 15, since each row here also costs a research pass + an approval round-trip, not just a bare connect click |
| Telegram DM chat_id | **[BULAT]** placeholder — needs Bulat's own chat_id; do NOT reuse Vas's `6348453236` |
| Sender name to log (col U, connect fold-in) | **[BULAT]** placeholder — confirm exact string |
| Mode | **approve-before-send**, same as Vas's `aictrl-linkedin-followup` — do not flip to auto-send unilaterally |

## Workflow

### 1. Preflight: Apollo + LinkedIn session checks

Identical to the prior fork's Steps 2–3: call `apollo_users_api_profile`, verify it resolves to Bulat's account (abort otherwise); call `mcp__linkedin__get_my_profile` against Bulat's LinkedIn MCP server (abort with login instructions on session error).

### 2. Read CRM candidates scoped to Bulat

Same thin-index-then-hydrate pattern as the other skills (never a full `A:Z` read on 3,000+ rows). Read `Log!H2:H10000` (slug), `Log!K2:K10000` (sequence), `Log!O2:O10000` (grade), `Log!AO2:AO10000` (this skill's own gate column — the InMail dedup key, NOT col R). Filter to rows where col H is non-empty, **col AO is empty** (not yet InMail'd by this skill), col K matches H1/H2/H3 or blank, and Apollo-task scoping (see prior fork's Step 4) confirms the row belongs to Bulat's Apollo user_id. Prioritize Grade A then B then ungraded. Take top 10, hydrate only matched rows (name, title, company, slug, apollo_contact_id).

**Col AO empty is the dedup key for this skill — not col R.** Col R tracks the connect-request fold-in (shared with Vas), which is a separate, non-blocking side effect. A row can have R filled (already connected, e.g. by Vas) and AO empty (never InMail'd by Bulat) — that's fine, still process it.

### 3. Research (Haiku subagent — ICP gate, post scrape, Apollo enrichment)

Identical to `aictrl-linkedin-followup` Steps 1–3 — reuse that logic verbatim (hard ICP gate on AI-product companies, general ICP evaluation against the real ICP, post scrape for a personalisation hook, Apollo enrichment). Dispatch as a Haiku subagent per candidate.

If non-ICP: write `AO = "skipped — not ICP"`, `AQ = "<reason>"`, leave AP empty. Do not draft, do not approach step 3b/4.

### 3b. Verification gate — confirm InMail is actually available for this candidate

Before drafting, check whether Bulat can actually message this specific non-connection. From the Step 1 `get_my_profile`/profile-scrape data, or by attempting the send in Step 6 and checking the response: if `send_message` errors with something indicating no Message button / not messageable (as opposed to a network/rate error), write `AO = "skipped — not messageable"`, `AQ = "<error detail>"`, and move to the connect-request fold-in (Step 7) only. **The very first live run of this skill is the actual test of whether InMail send works at all for Bulat's account — treat any failure pattern here as a signal to report back, not silently retry.**

### 4. Draft the InMail (default/inherited model)

Same voice rules as `aictrl-linkedin-followup` Step 4 (genuine opener, "I'm on the founding team at aictrl" phrasing — or Bulat's own equivalent first-person framing if he prefers different wording, confirm with him — product name "aictrl" not "aictrl.dev", one LP link matched to role, no "Worth a look?", 40–60 words). Hard-validate the LP link is present before proceeding, same as the original.

### 5. Operator approval

Post to Telegram DM **[BULAT'S chat_id — placeholder]** (never the group):

```
📨 LinkedIn InMail draft — [Name], [Title] at [Company]

ICP fit: [Strong / Moderate] — [one-line reason]
Post hook: "[brief quote or paraphrase]"

Draft:
"[full message text]"

Reply "send [Name]" to approve, "skip [Name]" to discard.
```

Wait for text reply. Do not send without an approved text reply.

### 6. Send InMail

On "send [Name]": call `mcp__linkedin__send_message(linkedin_username=<slug>, message=<approved text>, confirm_send=True, profile_urn=<if available from Step 1 profile scrape>)`.

- Success → `AO = "sent"`, `AP = now (UTC)`, `AQ = approved message text`.
- Failure (not-messageable pattern) → `AO = "skipped — not messageable"`, `AQ = "<error detail>"`, `AP` empty.
- Failure (other) → `AO = "error"`, `AQ = "<error detail>"`, `AP` empty.

On "skip [Name]": leave AO/AP/AQ empty — re-surfaces next run.

### 7. Connect-request fold-in (best-effort, independent of InMail outcome)

Regardless of the InMail outcome above, also attempt a plain connect request (no note — bug stickerdaniel/linkedin-mcp-server#455 workaround, same as Vas's skill): `mcp__linkedin__connect_with_person(linkedin_username=<slug>)`. Only do this if col R is currently empty for the row (don't re-connect someone already connected/pending, whether by Bulat or Vas).

Write to R–V/W–X exactly as the original connect-first fork did: R=now, S=result, T="(no note)", **U="Bulat"** (confirm exact string), V=brief note, W="pending"/"n/a — connect unavailable", X=now.

If col R is already filled: skip this step silently, no write.

### 8. Write results back to CRM

Batch-write `Log!AO<row>:AQ<row>` for the InMail result, and separately `Log!R<row>:X<row>` for the connect fold-in if it ran. Never touch A–Q, Y–Z, AA–AI.

### 9. Mark Apollo task complete (best-effort)

Same as the prior fork, for Apollo-task-matched candidates only.

### 10. Print summary

```
InMail sent: <N>
InMail skipped (not ICP): <N>
InMail skipped (not messageable): <N>
InMail errors: <N>
Connect fold-in sent: <N> / already connected: <N>
Total attempts: <N>/10
Log: https://docs.google.com/spreadsheets/d/1PQ1oaJPVs3GvWQMk9RBjlef-jcPdISswdD4zGv7QqRQ/edit
```

### 11. Do NOT post to Telegram yourself outside the approval step

Same fleet-wide rule — Step 5's DM is the one exception (it's the approval gate, not a broadcast). No cron wrapper exists yet for this fork.

## Known issues — read once at startup

- **Bug #455 (LinkedIn MCP):** applies to the connect-request fold-in only — omit `note`.
- **InMail availability is unverified.** See "What LinkedIn MCP tool sends the InMail" above — this is the single biggest open risk in this design. If the first live run shows `send_message` cannot reach non-connections at all (e.g. it silently fails or the underlying browser automation can't find a Message button on a 2nd/3rd-degree profile), this skill's core premise breaks and it degrades to Vas's connect-first pattern — report that back rather than guessing around it.
- **Sender mismatch / detection risk:** same caveats as the prior fork.

## Failure-mode quick reference

| Symptom | Action |
|---|---|
| `apollo_users_api_profile` / LinkedIn session resolves to Vas's identity | Abort — wrong credentials wired up. |
| `send_message` fails on every non-connection candidate in the same pattern | Stop after 2–3 failures in a run, don't burn through the batch guessing; report "InMail send appears non-functional for Bulat's account — verify InMail credits / Premium plan" rather than marking every remaining row as individually failed. |
| Sheet write to AO/AP/AQ fails with an out-of-range error | Sheet hasn't been resized past column AN yet — see Setup step 6. Stop, don't retry with a different column. |
| About to write to Y/Z or AG–AI | STOP. Those belong to Vas's accepted-connection pipeline / his second-touch skill, not this one. |

## Why this design

Bulat's Premium InMail collapses what is 3 separate stages in Vas's pipeline (connect → wait → research/draft/send) into one, because the "wait for accept" gate that necessitates splitting research from the initial outreach touch doesn't apply to him. Rather than build a 4-stage mirror of Vas's pipeline with an artificial waiting stage, this skill directly reuses `aictrl-linkedin-followup`'s research/draft/approve/send logic as Bulat's *first* touch, and treats the plain connect request as a minor, non-blocking fold-in rather than a separate gating stage. This keeps the design proportional to what Bulat's account can actually do, rather than over-engineering a "wait for InMail acceptance" concept that doesn't exist on LinkedIn.

Related: `aictrl-linkedin-followup/SKILL.md` (source of the research/draft voice logic — keep in sync), `aictrl-linkedin-status-tracker-bulat/SKILL.md` (stage 2 — reply tracking for these InMail sends), `aictrl-linkedin-followup2-bulat/SKILL.md` (stage 4 — second-touch nudge). Related memory: `reference_linkedin_mcp.md`, `feedback_outreach_voice.md`, `project_icp_correction.md`, `feedback_linkedin_targeting.md`, `feedback_no_group_posts_without_instruction.md`, `feedback_steps_use_numbers.md`.
