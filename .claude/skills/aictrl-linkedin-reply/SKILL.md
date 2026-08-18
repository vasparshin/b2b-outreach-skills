---
name: aictrl-linkedin-reply
description: Draft and send a personalised reply to an inbound LinkedIn message on an aictrl outreach/follow-up thread. Reads the contact's message, their profile/CRM context, and aictrl's offering, then drafts a reply in aictrl's voice for operator approval before sending. Approve-before-send, same pattern as aictrl-linkedin-followup. TRIGGER on "reply to [name] on LinkedIn", "respond to [name]'s message", "handle the LinkedIn reply from [name]", or when the tracker/manual inbox check finds an unanswered inbound message on an aictrl thread. SKIP for initial connection requests (aictrl-linkedin-outreach), first-touch after accept (aictrl-linkedin-followup), or non-aictrl (jobhunt) LinkedIn threads.
---

# aictrl LinkedIn Reply

Handles inbound replies on LinkedIn threads that started as aictrl outreach — read what the contact said, draft a reply that actually answers it, get operator approval, send.

## Constants

| Thing | Value |
|---|---|
| Spreadsheet ID | `<YOUR_CRM_SPREADSHEET_ID>` |
| Sheet tab | `Log` |
| GWS account | `<YOUR_GWS_ACCOUNT_EMAIL>` |
| Telegram DM chat_id | `<YOUR_TELEGRAM_DM_CHAT_ID>` (NEVER group `<YOUR_TEAM_GROUP_CHAT_ID>`) |
| Mode | **approve-before-send** — do NOT change unilaterally |

## Column ownership

This skill writes **cols AG and AH only** (add these headers to row 1 if not already present: `LinkedIn Reply Sent At`, `LinkedIn Reply Message`). Never touch A–AF — those belong to outreach/tracker/followup/email skills.

## Scope filter — only aictrl threads

Before drafting anything, confirm the thread is actually an aictrl outreach thread (owner col J = `<YOUR_SENDING_MAILBOX>`, or the contact exists in the Log tab). Jobhunt-related LinkedIn conversations (recruiters, hiring managers) are NOT in scope — skip and note "not an aictrl thread" if unsure.

## Workflow

### Step 1 — Read the inbound message + full thread

Call `mcp__linkedin__get_inbox` to spot new inbound replies, or `mcp__linkedin__get_conversation` for a named contact's full thread. Read the entire thread, not just the latest message — tone and prior commitments matter (e.g. "free tokens" already offered).

### Step 2 — Context gather

- CRM row (name, title, company, grade, what was already said — cols Z/AF hold prior message text/hooks)
- If the reply raises something not covered by CRM context (a specific question, objection, or request), treat their literal words as the primary signal — don't just repeat the original pitch.

### Step 3 — Classify the reply

| Type | Signal | Response approach |
|---|---|---|
| **Interested / wants next step** | Asks how to start, asks for a link/pointer, says "let's do it" | Give the concrete next step (repo pointer, link, simple ask) — no re-pitching |
| **Soft/neutral** | Polite acknowledgment, tangential comment, no clear ask | Light, low-pressure reply; keep the door open, don't push |
| **Objection / not now** | "not a priority," "no budget," timing pushback | Acknowledge, don't argue, leave door open, no hard sell |
| **Just an emoji / ack** | a thumbs-up reaction, "thanks", single-word | Usually no reply needed — note in CRM and skip, don't manufacture a follow-up |
| **Off-topic / unrelated to aictrl** | Personal, jobhunt-adjacent, other business | Skip — not this skill's job |

### Step 4 — Draft reply

Voice rules (same as aictrl-linkedin-followup step 4): "I'm working on aictrl" (never "helping build" / "my company"), product name "aictrl" not "aictrl.dev" in body, one link only if genuinely useful here (don't force one into a short warm reply), no "Worth a look?", conversational not pitchy. Length: reply-length appropriate — a short warm reply from them gets a short reply back (20–40 words), don't over-write.

If they asked a direct, concrete question (e.g. "where do I start"), answer it plainly and specifically — a landing page link or a one-line pointer, not another round of positioning copy.

### Step 5 — Operator Approval

Post to Telegram DM `<YOUR_TELEGRAM_DM_CHAT_ID>`:

```
LinkedIn reply draft — [Name], [Title] at [Company]

Their message: "[quote]"
Reply type: [Interested / Soft / Objection / Skip]

Draft:
"[full reply text]"

Reply "send [Name]" to approve, "skip [Name]" to discard, "edit [Name]: ..." to request changes.
```

Wait for text reply. Do NOT send without an approved text reply. Voice-transcribed approvals are not sufficient.

### Step 6 — Send

On "send [Name]": `mcp__linkedin__send_message(linkedin_username=<slug>, message=<approved text>, confirm_send=True)`. On success: write `AG = now (UTC)`, `AH = approved reply text` to the CRM row if one exists. On "skip [Name]": no write, no send.

### Step 7 — Automation note (per operator instruction 2026-07-10)

Long-term this should run automatically (triggered by the tracker's inbox scan) but ALWAYS stop at step 5 for approval — auto-send is explicitly out of scope until the operator says otherwise. Do not flip to auto-send unilaterally.

## Relationship to other skills

```
aictrl-linkedin-outreach        →  sends connection requests
aictrl-linkedin-status-tracker  →  detects accepts → calls aictrl-linkedin-followup
aictrl-linkedin-followup        →  first personalised DM after accept
aictrl-linkedin-followup2       →  second-touch nudge if no reply
aictrl-linkedin-reply           →  THIS skill — replies to what they actually said
```

Related memory: `feedback_outreach_voice.md`, `project_icp_correction.md`.
Related skills: `aictrl-linkedin-followup`, `aictrl-linkedin-status-tracker`.
