---
name: inbox-triage
description: General-purpose inbox triage engine for any mailbox reachable via an email MCP (Microsoft 365 / ms365, or Gmail). Fetches inbox messages, classifies each one deterministically by headers first (bounce/NDR, auto-reply/out-of-office, bulk/marketing, automated notification) then by content, optionally enriches each via a project-defined cross-reference step, files messages into folders, and surfaces genuinely action-worthy items. ALWAYS previews the full plan and waits for explicit confirmation before moving any mail — move-only, never deletes. Reads an optional per-project config file (.claude/inbox-triage.md) for folder names, the task destination, the enrichment step, and routing rules; runs header/content-only when none exists. TRIGGER on `/inbox-triage`, "triage my inbox", "sort my email", "clean up my inbox", "sort the mail into folders". SKIP for sending/drafting email, one-off reading of a single named message, or calendar/contacts work.
---

# Inbox Triage

A backend-agnostic engine that turns a noisy inbox into a clean one: classify every message, file the noise into folders, and surface only what genuinely needs a human. It NEVER deletes and NEVER acts without showing you the plan first.

## Operating principles (non-negotiable)

1. **Preview, then execute.** Always produce the full plan (what moves where, what becomes a task) and get explicit confirmation BEFORE any mutation. A run invoked with "dry-run" / "preview" stops after the plan and mutates nothing.
2. **Move-only, never delete.** Messages are only moved between folders. No deletion, ever.
3. **Read-only on enrichment systems.** The cross-reference step (CRM/outreach lookup) only READS. This skill never writes back to Apollo/CRM/etc.
4. **Idempotent.** Re-running is safe: a message already in its destination folder is skipped. Never move a message out of the Inbox twice.
5. **Respect project messaging rules.** If the project config names a chat/DM for digests, use exactly that target. Never broadcast to a group unless the project config explicitly says to.

## Step 0 — Detect backend and load project config

1. **Email backend.** Detect which email MCP is available:
   - Microsoft 365 → `mcp__ms365__*` (primary; this is what aictrl uses). Key tools: `list-mail-folders`, `list-mail-folder-messages`, `get-mail-message`, `get-mail-message-mime` (raw headers), `move-mail-message`, `create-mail-folder`, `update-mail-message` (categories/flags).
   - Gmail → `mcp__google_workspace__*` mail tools (`search_gmail_messages`, `get_gmail_messages_content_batch`, `modify_gmail_message_labels`, etc.). Folders = labels.
   - If neither is present, STOP and tell the user no email MCP is connected.
2. **Project config.** Look for `.claude/inbox-triage.md` in the current working directory (and its parent project root). If found, read it fully — it supplies: folder names, the enrichment/cross-reference procedure, the task destination + schema, the routing table, and the digest target. If absent, run in **generic mode**: header/content classification only, no enrichment, propose folders by category name, and print the task list to the user instead of writing it anywhere.

## Step 1 — Fetch inbox

- ms365: `list-mail-folder-messages` with `mailFolderId: inbox`, `orderby: receivedDateTime desc`, `select: subject,from,receivedDateTime,isRead,bodyPreview`. Page until the configured scope is covered (default: the entire Inbox; honor a "last N days" instruction if given).
- For any message that needs header inspection (Step 2), pull raw headers with `get-mail-message-mime` (ms365) — the machine-readable headers are far more reliable than the visible body.

## Step 2 — Stage A: deterministic header/sender pre-classification

Assign a **base category** using cheap, high-precision signals before any LLM judgement. Check in this order; first match wins:

| Base category | Signals (any match) |
|---|---|
| `BOUNCE` | `Return-Path: <>` (null sender); From contains `mailer-daemon` / `postmaster` / `Mail Delivery`; `Content-Type: multipart/report; report-type=delivery-status`; subject starts `Undeliverable` / `Delivery Status Notification` / `Delivery delayed`. |
| `AUTO_REPLY` | `Auto-Submitted:` present and ≠ `no`; `X-Auto-Response-Suppress:` contains `OOF`/`AutoReply`/`All`; `X-Autoreply: yes`; subject matches `Automatic reply` / `Auto Reply` / `Out of Office`. |
| `BULK` | `Precedence: bulk`; `List-Unsubscribe` / `List-Id` present; `Feedback-ID` present. (Marketing, newsletters.) |
| `NOTIFICATION` | Known automated/product senders defined by the project config (e.g. SaaS product mail), or `no-reply`/`donotreply` From with transactional content. |
| `SECURITY` | Sender/subject indicates account, security, sign-in, billing, or domain/DNS alerts. |
| `HUMAN_REPLY` | None of the above; has `In-Reply-To`/`References` threading and a real text body; From is a person, not `noreply`. |
| `UNKNOWN` | Nothing matched confidently. |

Do not rely on a single header — layer them. When unsure between `HUMAN_REPLY` and an automated class, prefer the automated class only if a hard header (Auto-Submitted, multipart/report, List-*) is present; otherwise treat as `HUMAN_REPLY`/`UNKNOWN` so real people are never buried.

## Step 3 — Stage B: enrichment hook (project-defined, optional)

If the project config defines an enrichment step, run it for each message whose sender is an external address (skip pure system/bulk senders unless the config says otherwise). The enrichment annotates each message with project facts (e.g. "is this sender a real outreach contact? what's their pipeline status?"). In generic mode this step is skipped entirely.

## Step 4 — Stage C: final bucket + action

Combine `(base category × enrichment annotation)` and apply the project's **routing table** to decide, per message: (a) destination folder (or "leave in Inbox"), and (b) whether it is **task-worthy** and what the task says. In generic mode, use these defaults: BOUNCE→`Bounces`, AUTO_REPLY→`Auto-Replies`, BULK→`Bulk`, NOTIFICATION→`Notifications`, SECURITY→leave + task, HUMAN_REPLY→leave + task, UNKNOWN→leave + flag. Create any missing destination folder (`create-mail-folder`) only after the user approves the plan.

## Step 5 — Stage D: preview → confirm → execute

1. **Preview.** Print a plan grouped by action:
   - Moves: `N → <Folder>` with a one-line list (sender · subject · why).
   - Tasks: each task-worthy item with its suggested action.
   - Left in Inbox: count + reasons.
   Send the same plan to the project's digest target if one is configured.
2. **Stop here if dry-run/preview.** Otherwise ask for explicit confirmation.
3. **Execute on confirm:**
   - Create approved folders if missing.
   - Move messages (`move-mail-message`), skipping any already in their destination (idempotency).
   - Write task-worthy items to the configured task destination (Step from project config). In generic mode, just print them.
   - Optionally tag left-in-Inbox items with a category/flag if the config requests it.
4. **Report.** One summary: moved per folder, tasks written, left in Inbox, errors. Send to the digest target.

## Failure modes

| Symptom | Action |
|---|---|
| No email MCP detected | Stop; tell the user to connect ms365 or a Gmail MCP. |
| `get-mail-message-mime` fails for a message | Fall back to sender + subject + bodyPreview heuristics; mark the item lower-confidence. |
| Enrichment lookup fails for a sender | Treat enrichment as "unknown" for that message; never block the whole run. |
| A move fails | Log it, continue the rest, report failures at the end. |
| Project config references a missing folder/sheet | Surface it in the preview; create folders on approval, but never auto-create external task stores without the config's instructions. |

## Reuse / extension

The engine carries no project specifics. Each project supplies a `.claude/inbox-triage.md` with: folder names, the enrichment procedure, the routing table, the task destination + schema, and the digest target. To use this in a new project, write that file; to change aictrl's behaviour, edit `/home/vas/projects/aictrl/.claude/inbox-triage.md` — not this skill.
