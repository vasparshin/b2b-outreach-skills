---
name: aictrl-linkedin-followup
description: "'Research, ICP-check, draft, and send a personalised follow-up LinkedIn DM for an accepted aictrl connection. Called by aictrl-linkedin-status-tracker on first-detected accept, or invoked manually. Flow: ICP gate → post scrape → Apollo enrichment → draft in aictrl voice → self-vet → send (auto-send since 2026-08-03). TRIGGER on 'send follow-up to [name]', 'run followup for [slug]', 'personalised message for [name]', or when called by the tracker skill. SKIP for initial connection requests (use aictrl-linkedin-outreach) or acceptance polling (use aictrl-linkedin-status-tracker).'"
---

# aictrl LinkedIn Follow-up

Personalised DM skill for accepted LinkedIn connections. Handles the research-to-send pipeline in one place so both the tracker (automated) and operator (manual) can call it cleanly.

## Constants

| Thing | Value |
|---|---|
| Spreadsheet ID | `<YOUR_CRM_SPREADSHEET_ID>` |
| Sheet tab | `Log` |
| GWS account | `<YOUR_GWS_ACCOUNT_EMAIL>` |
| Telegram DM chat_id | `<YOUR_TELEGRAM_DM_CHAT_ID>` (NEVER group `<YOUR_TEAM_GROUP_CHAT_ID>`) |
| Mode | **auto-send** — Vas granted this explicitly on 2026-08-03 ("yes i give u permission") after directing on 2026-08-02 that the target is 10 follow-ups *sent* per day, not 10 evaluated. Send without a per-message approval round trip, but only after the self-vet in Step 5 passes. Do NOT flip this back, or loosen the self-vet, without Vas saying so. |

## Model routing — cost control (added 2026-07-24 per Vas)

Steps 1–3 below (ICP gate, post scrape, Apollo enrichment) are lookup/classification work, not creative writing — run them on a cheap model. Step 4 (drafting the actual DM) is what reply rates depend on — keep it on the caller's default/inherited model (Sonnet).

- **Steps 1–3 → dispatch via the Task tool as a subagent with `model: "haiku"`.** Feed it the slug/name/company/apollo_contact_id and have it return ONLY: the ICP verdict (+ one-line reason), the post hook (quote/paraphrase, or "none found"), and any Apollo enrichment notes. Do not let raw profile/post text leak back into the caller's context — that's also the point of doing this as a subagent.
- **Step 4 (drafting) → runs on the default/inherited model, not the Haiku subagent.** Feed it the Step 1–3 findings and have it write the message per the voice rules below.
- **Step 5 (approval) and Step 6 (send) → default/inherited model** — these are judgment/state-changing steps, not worth downgrading.
- This routing applies whether the skill is invoked interactively or as the tracker's Step-4 subagent (see "Relationship to other skills" below) — the split happens *inside* this skill regardless of caller.

## Column ownership

This skill writes **cols Y and Z only**. The tracker owns W and X. Never touch A–X.

| Col | Meaning | This skill |
|---|---|---|
| Y | Followup Sent At | write on successful send |
| Z | Followup Message | write ICP verdict + message text (or non-ICP reason) |

## Inputs

Receive from caller (tracker or operator):
- `linkedin_slug` — col H value (e.g. `arunkumar-kubendran`)
- `apollo_contact_id` — col I value (optional but use if available)
- `name` — col B (display name)
- `company` — col D
- `sheet_row` — row number in Log tab (for writing back Y/Z)

If called manually without a sheet row, skip the CRM write-back.

---

## Workflow

### Step 1 — ICP Fit Gate  *(run inside the Haiku subagent — see "Model routing" above)*

Before any research, determine whether this person is worth a personalised message.

#### 1a — HARD GATE: Company type check (run this first, no exceptions)

Look up what `<company>` does. Ask: **does this company's core product or service use AI as its main value proposition?**

Examples of AI-product companies (HARD SKIP):
- Legal AI (contract review, legal research, compliance AI)
- Medical AI (diagnostic AI, clinical decision support)
- Code AI / developer tools (Copilot competitors, AI code review, AI testing)
- AI assistant or chatbot platforms
- ML infrastructure, MLOps, LLM API providers
- Any company whose website headline is "AI for X"

**If YES → immediate hard skip. No exceptions.**
- Write `Z = "accepted — not ICP (no message): company sells AI as product (<company>)"`.
- Leave Y empty.
- STOP. Do NOT continue to general ICP evaluation.
- Do NOT reason "but their dev team might still benefit" — this logic is the source of false positives. The gate is hard.

**If NO → continue to 1b.**

#### 1b — General ICP evaluation

**Ideal Customer Profile (real ICP):** Traditional or lagging AI adopters — companies just starting to integrate AI coding tools (Claude Code, Cursor, Codex, Copilot), worried about agent reliability, governance, or not knowing what their team's AI is actually doing. Typically: mid-market tech firms, engineering leaders at non-AI-first companies, VPs/EMs/CTOs at companies where AI coding agents are deployed but oversight is thin.

**Additional skip signals:**
- Large enterprise (Oracle, Salesforce, Akamai, Microsoft, Google, Meta, Amazon, etc.)
- Role has no AI oversight surface (pure sales, pure design, pure finance — no contact with AI systems)
- No signals of AI adoption pain (no posts, no relevant role, company has no AI footprint)

**Action if non-ICP:**
- Do NOT draft or send.
- Record `Z = "accepted — not ICP (no message): <specific reason>"`, leave Y empty.
- Report in summary: `[Name] — skipped (non-ICP): <reason>`.
- Stop here.

**Action if ICP match (Moderate or Strong):**
- Continue to step 2.

### Step 2 — Post Scrape  *(run inside the Haiku subagent)*

Call `mcp__linkedin__get_person_profile(linkedin_username=<slug>, sections="posts", max_scrolls=3)`.

Identify the **most recent substantive post** (within ~4 weeks, not a certificate/congrats/reshare of someone else's generic content). Look for:
- Any mention of AI agents, automation, LLMs, MCP, Claude, ChatGPT, Copilot
- Pain points around reliability, oversight, decision-making, production readiness
- Technical challenges with AI integration
- "We're exploring AI" / "deploying agents" type signals

If no recent relevant post found: note this; the message will be lighter on personalisation but can still reference their role/company context.

### Step 3 — Apollo Enrichment (optional but valuable)  *(run inside the Haiku subagent)*

If `apollo_contact_id` is available, check the person's title, seniority, and recent job changes for additional context. Work history is useful — a VP who moved from a large enterprise to a mid-market firm recently is more likely to be in an AI adoption phase.

Use: the Apollo MCP contact lookup, or the data already in cols A–Q of the CRM row.

### Step 4 — Draft Personalised Message  *(default/inherited model — NOT the Haiku subagent)*

Write a DM in aictrl's voice, using the ICP verdict / post hook / enrichment notes returned by the Step 1–3 subagent. Rules:

1. **Greet them by first name, then hook. Both, in that order — mandatory (added 2026-08-03, Vas).** Start the message `Hi <FirstName> — ` and then go straight into the genuine hook. Lead the hook with something specific about them: a post they wrote, a tension in their role, a real observation about their company. Don't open with "I saw your profile" or immediately introduce aictrl.
   - Use the first name only, as they present it on LinkedIn (a profile reading "Siddharth (Sid) Parakh" gets `Hi Sid`). Never the full name, never the title.
   - `Hi` only — not `Hey`, not `Hello`, not `Dear`.
   - **Why this is a rule now:** a CRM audit on 2026-08-03 found only 7 of 43 sent follow-ups opened with any greeting; the other 36 started cold on the hook. Vas flagged it the same morning. A greeting-less DM reads as a broadcast, which is the opposite of what the personalised hook is for. This costs one line of the word budget — take it out of the hook, not the CTA.
2. **Voice: "I'm working on aictrl" or "I'm on the founding team at aictrl."** Never "helping build", "I built", or "my company."
3. **Product name in body: "aictrl" — NOT "aictrl.dev"** (the .dev suffix becomes a clickable link, creating a second URL).
4. **No link and no product name in the first follow-up — this is the live experiment, approved by Vas 2026-08-03.** Say the specific thing you noticed and ask a real question about it. Do not name aictrl, do not include any URL, do not describe the product. aictrl comes up only if they reply.
   - **Why:** 939 connects, 78 accepts, 54 first follow-ups and 40 second-touch nudges had produced 2 replies. Every message named the product and carried a landing-page link in first contact, which reads as a broadcast however good the research behind it is. Vas: "fine try it but dont abandon and learn from findings."
   - **Tag every message so the experiment is measurable.** Prefix what you write into col `Z` with `[v2-nolink] ` (the tag stays in the CRM only — never in the message sent to the person). Messages sent before this change are untagged and are the control group. Reply rate for either arm = rows whose `Z` carries the tag (or not) with `AX` non-empty, over rows in that arm with `Y` non-empty.
   - **Report the comparison, don't quietly keep it running.** Once the tagged arm reaches 30 sent messages, put the two reply rates side by side in the daily DM and say which is winning. If the no-link arm is clearly worse, say so and propose reverting — the instruction was to learn from it, not to prove it right.
   - The landing pages still exist for use *after* a reply, matched to role: Engineering Managers and VPs of Engineering → `aictrl.dev/lp/observability` (team AI usage analytics + ROI dashboards across Claude Code, Cursor, Codex); CTOs and senior engineers focused on code quality → `aictrl.dev/lp/code-review` (senior-grade PR review grounded in the knowledge graph); default `aictrl.dev/lp/observability`.
   - **Tag the URL itself with UTM params (added 2026-08-07) — mandatory whenever a link is sent, post-reply or otherwise.** A 2026-08-07 PostHog check found zero LinkedIn-attributable traffic in the last 14 days despite real send volume — because no link we've ever sent carries a UTM tag, so a click is indistinguishable from `$direct` traffic. Append `?utm_source=linkedin&utm_medium=dm&utm_campaign=followup` to the base landing-page URL, e.g. `aictrl.dev/lp/observability?utm_source=linkedin&utm_medium=dm&utm_campaign=followup`. This is what lets the daily PostHog digest (see `aictrl-posthog-digest` skill) actually attribute a visit to LinkedIn outreach instead of counting it as unattributed direct traffic.
5. **Attention-grabbing but genuine** — conversational, curious tone. Not a pitch. The goal is a reply, not a close.
6. **No "Worth a look?"** — never end with this.
7. **Length: 40–60 words.** Tight. No paragraph breaks.
8. **Never pitch features / pricing.**

Example structure:
> [Genuine opener: post quote, role tension, or company observation] — [bridge to the problem they face] — [aictrl as the natural answer, lightly] — [curious/conversational CTA + LP link].

**Hard validation before proceeding to Step 5 (rewritten 2026-08-03 for the no-link experiment — this rule is now the inverse of what it was):** confirm the draft contains **no** URL of any kind and **no** occurrence of "aictrl". If it contains either, rewrite it. Also confirm it opens `Hi <FirstName> — `. The previous version of this rule *required* the `/lp/` link; it was correct for the linked variant and is wrong for this one, so do not reinstate it without reverting rule 4 as well.

### Step 5 — Self-vet, persist, send

**Mode is auto-send as of 2026-08-03. The approval round trip below is gone; the self-vet replaces it.** Persist first regardless — the ordering is the whole point of the step, see the failure note below.

**5-vet. The self-vet, run before every send. All of these must pass or the message does not go:**
1. Step 1's ICP gate passed (hard company-type gate first, then general fit).
2. The live profile shows `· 1st` or `Connected` and does NOT show `Pending` — the Step 6 connection re-check, run *before* sending, not after a failure.
3. The draft opens `Hi <FirstName> — ` with their real first name.
4. The draft contains no URL and no occurrence of "aictrl" (the no-link experiment).
5. The draft is 40–60 words, one paragraph, and doesn't end with "Worth a look?".
6. The row has no existing `Y` and no existing `BB` — never send twice.
Any failure: do not send, record the reason, and surface it in the run summary. A failed vet is a normal outcome, not an error to work around.

**Still ask Vas, rather than sending, when:** the contact has already replied to us at any point (`AX` non-empty), the message would reference anything sensitive or personal, or the ICP verdict was genuinely borderline rather than clear. Auto-send covers the routine case he asked to stop approving one by one — it is not permission to send anything unusual unseen.

**5a. Write the draft to the CRM before doing anything else.** For the contact's row:
- `BA` (Followup Draft (pending approval)) = the full draft message text
- `BB` (Followup Approval) = `pending <YYYY-MM-DD>`

Only cols BA/BB (and later Y/Z on send) may be written here — never A–X, never O.

**5b. Send it** (Step 6), then report it after the fact. One line per contact in the run summary DM to `<YOUR_TELEGRAM_DM_CHAT_ID>` (NEVER the group):

```
**LinkedIn follow-ups sent — [YYYY-MM-DD]**

• [Name], [Title] at [Company] (row [N]) — [Strong/Moderate], hook: "[brief quote]"
  "[full message text as sent]"

Held back: [Name] — [which vet check failed]
Sent N | held N | remaining in queue N
```

Vas reads these to keep an eye on quality, not to approve them. Anything held back by the vet is listed with the specific check that failed, so a systematic drafting problem shows up as a pattern rather than as silence.

**5c. A cron run behaves identically** — vet, persist, send, report. There is no "awaiting approval" state any more for the routine case; the only rows that end a run undecided are the ones the vet held back or the exceptions listed above, which stay `BB = pending <date>` with the draft in `BA` and are surfaced every run until Vas answers.

**Why 5a exists (added 2026-07-31 — do not remove).** This step previously posted the draft to Telegram and then said "Wait for text reply". Under cron there is nobody to reply to, so the run ended and the draft was destroyed — it existed only in a Telegram message that scrolled away. Y/Z stayed empty, the row re-surfaced on the next tracker run, and the whole research → draft cycle was paid for again and thrown away again, indefinitely. Measured effect on 2026-07-31: **49 of 77 accepted connections (64%) had never received a follow-up**, the oldest accepted 2026-06-03, nearly two months earlier. These are the warmest contacts in the pipeline — people who accepted the invite — and the pipeline was silently dropping all of them. Persisting to BA/BB before asking is what makes an approval survive the end of the run.

### Step 6 — Send

Runs automatically once the Step 5 self-vet passes. Also triggered by a live "send [Name]" reply or by working the queue of held-back rows (`BB` starting with `approved`).

0. **If this row was found via a global/stuck-queue BB scan rather than this run's own Steps 1–5: read the row's full current `Z` and `Y` FIRST, before anything else.** A non-empty `Y` means a follow-up already went out — the queued draft is a stale duplicate; correct `BB` and stop. A `Z` note recording a deliberate hold (borderline ICP, "left for Vas", or similar) overrides a bare `BB = pending`/`approved`: set `BB = held <date>`, do not send, report it. Learned 2026-08-10 when a sheet-wide BB scan re-drafted and sent CRM row 2210 whose Z carried an explicit 2026-08-04 human-judgment hold that the BB status alone didn't show.

1. Re-read the draft from `BA` for that row and send THAT text — never a re-drafted or remembered version.
2. **Connection re-check, mandatory (added 2026-08-03 — do not remove).** Call `mcp__linkedin__get_person_profile(linkedin_username=<slug>)` and read the top card. Send ONLY if it shows `· 1st` (or a `Connected` button) AND does NOT show `Pending`. If it shows `Pending`, or a 2nd/3rd degree marker, the CRM's `W = accepted` is a **false accept** — the invite was never accepted:
   - Do NOT send, and do NOT record a send failure.
   - Correct the tracker state: `W = "stale (pending >7d, withdraw manually)"` if the invite in col R is older than 7 days, otherwise `W = "pending"`; `X = now (UTC)`.
   - Clear `BA` and `BB` so the row leaves the approval queue and can be re-drafted if it is ever genuinely accepted.
   - Report it in the summary as `[Name] — false accept corrected (still Pending)`.
3. `mcp__linkedin__send_message(linkedin_username=<slug>, profile_urn=<if available>, message=<approved text>, confirm_send=True)`
4. On success: `Y = now (UTC)`, `Z = `[v2-nolink] ` + the sent message text` (the tag is CRM-only, never sent), `BB = sent <YYYY-MM-DD>`. Clear `BA`.
5. On failure: leave Y/Z empty, set `BB = send-failed <YYYY-MM-DD>`, keep `BA` so the draft is not lost. Report in summary. **Attempt each failed send at most twice, and never twice the same way** — one plain retry, then one retry passing `profile_urn` from the step-2 profile call. If both fail, stop and report; do not queue it for another blind attempt on a later run.

**Send-transport failure statuses, and what each actually means (measured 2026-08-03):**
- `composer_unavailable` — LinkedIn exposed no message composer. In every case seen so far this meant the recipient was **not** a 1st-degree connection, i.e. a false accept. Step 2 above is what stops these from ever reaching the send call.
- `recipient_resolution_failed` — a compose page opened but the visible recipient did not match. Seen on a genuine 1st-degree connection (Siddharth Parakh, Medable, CRM row 892), and it reproduced with `profile_urn` supplied, so it is a defect in the MCP's compose flow, not a connection-state problem. Leave `BB = send-failed`, keep the draft, and report it — do not keep retrying.

On "skip [Name]": leave Y/Z empty, set `BB = skipped <YYYY-MM-DD>`, clear `BA`. The row must NOT re-surface for re-drafting — a skip is a decision, and re-drafting it burns research budget on a contact the operator already declined.

**Approval-queue states for `BB`:** `pending <date>` (drafted, waiting), `approved <date>` (operator said send, not yet sent), `sent <date>`, `skipped <date>`, `send-failed <date>`, `held <date>` (deliberate human-judgment hold, reason recorded in col Z — never send, never re-draft, waits for Vas's explicit word; introduced 2026-08-10). Anything else is unrecognised — leave the row alone and flag it.

---

## Batch cron mode (daily morning drafting run — added 2026-08-01)

Invoked headless by `aictrl-linkedin-followup-cron.sh` with the instruction "run the aictrl-linkedin-followup skill in batch cron mode". Purpose since 2026-08-03: every morning the day's follow-ups are researched, vetted and **sent**, and Vas gets told what went out. The pipeline must never sit on accepted connections with nothing sent — the target is 10 sends a day.

1. **Get the queue:** `~/.claude/channels/venv/bin/python /home/vas/.claude/scripts/aictrl-followup-queue.py` — prints a JSON object `{"queue": [...], "diagnostics": {...}}`. `queue` is eligible contacts (W=accepted, Y/Z/BB all empty), oldest accept first. `diagnostics` (added 2026-08-08) distinguishes "nobody is waiting" from "the upstream connect pipeline hasn't produced new accepts" — read it every run, not only when the queue is empty. Do NOT select contacts via `read_sheet_values` — it truncates to 50 rows.
2. **Take the first 10** (hard cap per run — keeps profile-scrape volume safe alongside the other LinkedIn crons).
3. For each contact run Steps 1–5 exactly as above: Haiku subagent for ICP gate + post scrape + enrichment, draft on the inherited model, **persist to BA/BB first** (`BB = pending <date>`). Non-ICP contacts get the usual Z skip record instead of a draft.
4. **Send each one that passes the vet** (`mcp__linkedin__send_message`, now in the cron's allowlist). Do not post to Telegram — print to stdout only; the wrapper delivers.
5. **Print a digest to stdout** starting with the header line `**LinkedIn follow-ups sent — <YYYY-MM-DD>**` (the wrapper greps for the inner text, and tg-send renders `**...**` as bold — house digest style since 2026-08-02), then per contact: name, title, company, CRM row, ICP fit, post hook, and the message text as sent; then anything held back with the vet check that failed; then a summary: sent N, held N, skipped-non-ICP N, errors N, remaining in queue N.
6. If `queue` is empty, print the header plus "Queue empty — every accepted connection has a sent follow-up or a recorded skip.", then **always** append one diagnostic line built from `diagnostics.grade_A_or_B_never_connect_requested` and `diagnostics.connect_requests_sent_total`, e.g. `Upstream: <N> Grade A/B prospects have never been connect-requested yet (connect pipeline capped at 15/day) — this is not a queue bug, it's the accept rate.` This is what stops a healthy "nobody is waiting" day from reading identically to a day where the real bottleneck (connect volume, acceptance rate) needs attention — a bare "queue empty" answers "did the script work" but not "is the pipeline actually moving," and those are different questions. **Only print the empty-queue message at all if `aictrl-followup-queue.py` actually exited 0 and returned parsed JSON.** If it errored, timed out, or returned unparseable output, print `Queue: NOT CHECKED — <reason>` instead. "Nobody is waiting" and "I could not find out who is waiting" are opposite facts that look identical in a digest, and the second one silently stalls the pipeline for a day while reporting success.
7. If the LinkedIn session is dead, print `ABORT: LinkedIn session` plus the header and stop — do not burn the queue.

Only held-back rows and the explicit exceptions in Step 5 wait for Vas; he replies "send [Name]" / "skip [Name]" in the DM and the interactive session runs Step 6 for those.

---

## Manual invocation

Operator can call this skill directly with: "send follow-up to [name]" or "run personalised message for [slug]".

Steps are identical. If the person is not in the CRM or sheet_row is unknown, skip the CRM write-back but still draft, get approval, and send.

---

## Non-ICP tracking

When a contact is skipped (non-ICP), always write a reason to col Z so the pattern is visible over time. This builds the "anti-ICP" record that sharpens the qualifier rubric. Do not leave Z empty on a skip — the reason is the data.

---

## Failure-mode quick reference

| Symptom | Action |
|---|---|
| `get_person_profile` fails | Note in summary; no draft; leave Y/Z empty |
| No recent posts found | Still draft; use role/company context instead of post hook; note "(no recent posts)" in ICP summary |
| Apollo enrichment unavailable | Skip step 3; continue with LinkedIn data only |
| `send_message` fails | Leave Y/Z empty; report to operator; retry manually |
| About to send without text approval | STOP. Wait for text "send [Name]". |
| About to write outside Y:Z | STOP. Not this skill's territory. |
| About to post to group `<YOUR_TEAM_GROUP_CHAT_ID>` | STOP. DM only. |

---

## Relationship to other skills

```
aictrl-linkedin-outreach  →  sends connection requests
aictrl-linkedin-status-tracker  →  detects accepts  →  calls THIS skill
aictrl-linkedin-followup  →  researches, drafts, sends follow-up DM
```

The tracker's step 4 delegates to this skill. When running the tracker, it should invoke this skill as a subagent for each new accept rather than doing the research inline.

Related memory: `reference_linkedin_mcp.md`, `feedback_outreach_voice.md`, `project_icp_correction.md`, `feedback_linkedin_targeting.md`.
Related skills: `aictrl-linkedin-status-tracker`, `aictrl-linkedin-outreach`, `prospect-research`.
