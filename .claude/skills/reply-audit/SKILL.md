---
name: reply-audit
description: General-purpose outreach reply-audit engine for any mailbox reachable via an email MCP (Microsoft 365 / ms365, or Gmail). Finds genuine prospect replies that have NOT been answered, and reconciles them against an outreach system (via a project-defined cross-reference) to catch mis-classifications — e.g. a sequence wrongly stopped on an auto-reply, or a contact paused on out-of-office with no resume. For each genuine unanswered reply it can optionally draft a threaded reply into Drafts (never sends). Writes findings to a project-defined task destination. ALWAYS previews the plan and waits for confirmation before creating drafts or tasks. Reads an optional per-project config file (.claude/reply-audit.md) for the reply sources, the cross-reference, the task destination, draft tone, and routing; runs mailbox-only when none exists. TRIGGER on `/reply-audit`, "audit my replies", "check for unanswered replies", "follow-up audit", "who hasn't been followed up". SKIP for sorting/cleaning the inbox (use inbox-triage), bounce diagnosis, sending mail, or reading a single named message.
---

# Reply Audit

Make sure no genuine reply slips through, and catch the cases where the outreach tool got it wrong (treated an auto-reply as a real reply, or paused someone and forgot to resume). Optionally drafts replies — but NEVER sends.

## Operating principles (non-negotiable)

1. **Drafts only, never send.** Any reply this skill composes lands in the Drafts folder, unsent. No exceptions.
2. **Read-only on the outreach/CRM system.** The cross-reference only READS. Never writes back to Apollo/CRM/etc.
3. **Preview, then execute.** Produce the full plan (tasks to write, drafts to create) and get explicit confirmation before any mutation. "dry-run"/"preview" stops after the plan.
4. **Idempotent.** Skip items already in the task destination; skip a thread that already has a draft. Re-running is safe.
5. **Never auto-bury a real reply.** When classification is uncertain between human and automated, treat it as a human reply needing a human.
6. **Respect project messaging rules.** Digest goes only to the configured target; never a group unless the config says so.

## Step 0 — Detect backend and load config

1. **Email backend.** ms365 (`mcp__ms365__*`) is primary. Key tools: `list-mail-folder-messages`, `get-mail-message`, `get-mail-message-mime`, `list-mail-messages` (search), `create-reply-draft` (threaded draft), `update-mail-message`. Gmail equivalent: `mcp__google_workspace__*`. If neither, STOP.
2. **Project config.** Read `.claude/reply-audit.md` from the cwd / project root. It supplies: the reply-source folders, the cross-reference procedure (which may reference another skill's config), the task destination + schema, whether drafting is enabled + the draft tone/blurb, and the digest target. If absent, run **mailbox-only**: find inbound replies with no outbound answer and just list them (no cross-reference, no drafts unless asked).

## Step 1 — Gather candidate replies

- From the mailbox: scan the configured reply-source folders (default: Inbox + any "Auto-Replies" folder) for **inbound messages from external people** (skip system senders and bulk/marketing).
- From the cross-reference (if configured): pull outreach contacts the system flags as replied / finished / paused, so the audit also covers replies the tool acted on. Match these back to mailbox messages by sender email + conversation.

## Step 2 — Classify each inbound: human vs automated

Use the same header-first heuristics as `inbox-triage`: `Auto-Submitted` / `X-Auto-Response-Suppress: OOF` / `Precedence: bulk` / null Return-Path / `multipart/report` mark a message automated (auto-reply, OOO, bounce, list). Anything with real threading (`In-Reply-To`/`References`), a personal sender, and a real body is a **human reply**. When unsure, treat as human.

## Step 3 — Answered?

For each candidate, decide whether a human has already responded: look in **Sent Items** (and the conversation thread, by `conversationId`) for an **outbound message to that contact dated after the inbound**. If found → answered (skip). If not → open.

## Step 4 — Categorize (project routing)

Combine `(human/auto × cross-reference status)` and apply the project's routing table. Engine defaults when no config:
- **needs-reply** — human reply, unanswered → task (+ draft if drafting enabled).
- **answered** — skip.

Project configs typically add: **false-positive-stop** (system marked replied/finished but the inbound was automated) and **ooo-resume** (paused on out-of-office with no scheduled resume).

## Step 5 — Actions

- **needs-reply:** write a task row to the configured destination. If drafting is enabled, create a **threaded draft reply** (ms365 `create-reply-draft` on the inbound message) whose body is built from the prospect's message + the config's value-prop blurb + tone. Leave it in Drafts, unsent.
- **false-positive-stop / ooo-resume:** write a task row with the suggested action (and a re-surface date for OOO). No draft unless the config says otherwise.
- Always: never modify the outreach system.

## Step 6 — Preview → confirm → execute → report

1. **Preview:** list planned task rows and planned drafts (recipient · subject · one-line gist of the draft). Send to the digest target.
2. Stop if dry-run. Else confirm.
3. **Execute:** create drafts, write tasks (dedupe first). 
4. **Report:** counts by category, drafts created, tasks written, skipped(answered/duplicate), errors → digest target.

## Failure modes

| Symptom | Action |
|---|---|
| No email MCP | Stop; tell the user to connect ms365/Gmail. |
| Cross-reference lookup fails for a contact | Treat status as unknown; still audit the mailbox side; never block the run. |
| Can't tell if answered (no thread data) | Treat as open but mark lower-confidence in the task. |
| `create-reply-draft` fails | Log it, still write the task, continue. |
| Draft body would be low-quality (too little context) | Write the task but skip the draft; note "draft skipped — needs manual reply". |

## Reuse / extension

Engine carries no project specifics. A project supplies `.claude/reply-audit.md` with reply sources, the cross-reference, the task destination, drafting on/off + tone/blurb, and the digest target. To change aictrl behaviour, edit `/home/vas/projects/aictrl/.claude/reply-audit.md` — not this skill.
