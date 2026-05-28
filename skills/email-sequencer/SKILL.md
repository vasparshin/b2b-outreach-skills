---
name: email-sequencer
description: General-purpose, approval-gated cold-email follow-up sequencer. Runs a multi-step email cadence over time for a list of leads, personalising each message from research, auto-terminating a lead's sequence the moment they reply, and logging every step to a spreadsheet CRM. Read/draft by default — it NEVER sends an email without explicit human approval routed through a chat channel (e.g. Telegram). Orchestrates a mail MCP (Microsoft 365 / Gmail) + a Sheets CRM + an approval channel; degrades gracefully. TRIGGER on `/email-sequencer`, "advance the sequence", "enrol these leads", "send the next follow-ups", or from a daily cron. SKIP for one-off single emails (just draft+send directly), for list-building (use the prospector), or for inbound reply triage (use reply-audit). Adapted from the ShapeScale `campaign-orchestrator` pattern: state-in-CRM instead of JSON, mail-MCP instead of Gmail/Dialpad, reply-detection by inbox search instead of a webhook, and approve-before-send instead of fire-and-forget.
---

# Email Sequencer

Run a personalised, multi-step cold-email cadence for a list of leads — safely. The expensive mistakes here are irreversible and outward-facing (a wrong/duplicate/ill-timed email to a real prospect), so the core discipline is: **state lives in the CRM, replies stop the sequence, and nothing sends without a human approving it in chat.**

## Operating rules (read first)

1. **Approve-before-send is mandatory by default.** Every outbound email is created as a *draft* and routed to the approval channel for **approve / edit / skip** before it sends. Do NOT auto-send unless the project config explicitly sets `auto_send: true` AND the operator has said so this session.
2. **One lead = one live sequence.** Never enrol the same person twice; never send two steps to the same lead on the same day.
3. **A reply terminates the sequence.** Before drafting any step for a lead, check for an inbound reply since the last send. If they replied → set status `replied`, stop, and flag the operator. Never follow-up over a reply.
4. **Never sequence existing customers / opted-out / bounced addresses.** Check the exclusion signals (config) before enrolling or sending.
5. **Respect the cadence and sending window.** Space steps per the config (typically 3 then 7 days); only queue sends for business hours, Tue–Thu preferred (per `email-marketing` deliverability guidance).

## Step 0 — Detect tools + load config

Detect: a mail MCP (`mcp__ms365__*` create-draft / send-draft / search; or a Gmail MCP), a Sheets MCP (`mcp__google_workspace__*`), and an approval channel (e.g. `mcp__plugin_telegram_telegram__reply`). Read the project `.claude/email-sequencer.md` for: the CRM spreadsheet id + Sequence-tab schema, the step templates + cadence, the sender identity, the approval chat id, exclusion rules, and the `auto_send` flag (default false). If any piece is missing, degrade and tell the operator what's unavailable.

## State model — the "Sequence" CRM tab

One row per enrolled lead. Canonical columns (the config may extend):

`Enrolled · First · Last · Company · Email · LinkedIn · Tier · Status · Step · Last sent · Next due · Reply? · Notes`

- **Status**: `queued` (enrolled, nothing sent) → `active` (≥1 step sent, more pending) → `completed` (all steps sent, no reply) | `replied` (stopped — they answered) | `stopped` (manual / bounced / opted-out).
- **Step**: integer 0–N = how many steps have been sent.
- **Next due**: date the next step may be drafted (set when a step is sent, using the cadence). A step is "due" when `Next due <= today` and `Status in (queued, active)`.

The personalisation hook for each lead is pulled at draft time from the research already in the CRM (e.g. the Prospects-tab fit/notes column) — keep the Sequence tab lean rather than duplicating it.

## The commands (what to do when invoked)

### `enrol` — add leads to the sequence
For each lead: run the exclusion check; if clean, append a row with `Status=queued`, `Step=0`, `Next due=today`. Report who was enrolled / skipped and why. **Enrolling sends nothing.**

### `advance` — the daily heartbeat (what the cron calls)
For every row with `Status in (queued, active)`:
1. **Reply check first.** Search the mailbox for an inbound message from that lead's address since `Last sent` (skip if Step=0). If found → set `Status=replied`, write the reply gist to `Notes`, and add them to the operator alert. Do not draft.
2. **Due check.** If `Next due <= today` and not replied → this lead has a step due.
3. **Draft, don't send.** Build the step email from the template + the lead's personalisation hook (Step 1 = the personalised opener; later steps reference it). Create it as a *draft* via the mail MCP.
4. **Route for approval.** Post the drafted subject+body to the approval channel with the lead's name, step number, and approve/edit/skip instructions. Collect all the day's drafts into one digest message rather than spamming.
5. **Do not advance state yet** — `Step`/`Last sent`/`Next due` only update after the operator approves and the send succeeds (see `send`). A cron run therefore ends at "drafts are waiting for your approval"; the actual send happens in a live session when the operator replies.

### `send` — after the operator approves (live session)
For each approved draft: send it via the mail MCP, then update that row: `Step += 1`, `Last sent = today`, `Next due = today + cadence[next step]` (or `Status=completed` if that was the last step). For `edit`, apply the operator's wording then send. For `skip`, leave state unchanged and note it.

### `status` / `stop`
`status`: summarise the tab — counts by status, what's due, who replied. `stop <lead> --reason`: set `Status=stopped`, note the reason (manual, bounced, opted-out).

## Pre-send checklist (MANDATORY, per email, before routing for approval)

- **Reply re-check** — confirm no reply landed since the advance run.
- **No duplicate / wrong-day** — this lead has no other step sent today; not already `replied`/`stopped`.
- **Formatting** — renders as clean paragraphs (2–4 sentences each, blank line between); no orphan single-sentence paragraphs; no mid-paragraph hard breaks; one clear call-to-action; one link only.
- **Tone** — confident peer-to-peer, not needy. No apologies ("sorry to bother"), no easy-outs ("if not relevant, no worries"). Personalised opener is specific to THEM, not generic.
- **Accuracy** — never invent facts, pricing, mutual connections, or commitments. Honour the project's positioning exactly.

## Deliverability guardrails (from `email-marketing`)

Low daily volume from a warmed domain; keep bounce <2% and spam-complaint <0.1% (remove bouncers immediately — `bounce-diagnosis` can classify them); authenticate the sending domain (SPF/DKIM/DMARC). Subjects ~40–50 chars, no spam-trigger words. Plain-text style outperforms heavy HTML for 1:1-style cold mail.

## Scheduling

`advance` is meant to run daily via cron (`claude -p '… advance the email sequence …'`), using the same notify-wrapper pattern as other aictrl crons so the "drafts awaiting approval" digest reliably reaches the operator. The cron only ever *drafts + notifies*; it can't approve sends itself (that's the human in chat), which is exactly the safety property we want. **Test `advance` manually once before wiring the cron.**

## Reuse / extension

Carries no project specifics. A project supplies `.claude/email-sequencer.md` with the spreadsheet id + tab schema, the step templates + cadence, sender identity, approval chat id, exclusions, and `auto_send`. Related: `prospect-research` (produces the personalisation hook), `reply-audit` (richer reply/again-no-reply detection), `bounce-diagnosis` (classify bouncers to remove), `inbox-triage`. Pattern origin: OpenClaw `campaign-orchestrator`.
