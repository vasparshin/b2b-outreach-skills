# reply-audit — aictrl project config

Loaded by the general `reply-audit` skill when auditing the **vas@aictrl.dev** Microsoft 365 mailbox against our Apollo outreach. Surfaces unanswered prospect replies and Apollo mis-classifications, writes tasks to the CRM `Tasks` tab, and drafts (never sends) replies into Outlook Drafts.

## Constants (shared with inbox-triage)

| Thing | Value |
|---|---|
| Mailbox | `vas@aictrl.dev` (ms365 MCP) |
| Apollo account email (must match) | `vasparshin@gmail.com` |
| H1 / H2 / H3 sequence_ids | `69fde3942587c500119a8f10` / `6a032c60fb3a7d0015fe647d` / `6a04848c82740000159786ed` |
| CRM spreadsheet_id | `1PQ1oaJPVs3GvWQMk9RBjlef-jcPdISswdD4zGv7QqRQ` |
| Task tab | `Tasks` (same schema as inbox-triage) |
| GWS account (Sheets) | `Info@boller.store` |
| Digest target | Telegram DM `6348453236` ONLY — NEVER group `-5110011669` |
| Telegram token file | `/home/vas/projects/aictrl/.telegram/.env` |

## Reply sources (mailbox)

Scan **Inbox** + **Auto-Replies** folders for inbound external messages. (Genuine human replies are left in the Inbox by `inbox-triage`; auto-replies/OOO sit in Auto-Replies.)

## Cross-reference (Apollo) — READ ONLY

Use the Apollo lookup defined in `inbox-triage.md` (Stage B) for per-sender enrichment. **Additionally**, pull the audit population: for each of H1/H2/H3, `apollo_contacts_search` (zero lead-credit; never use People-API/enrich) and keep contacts whose `contact_campaign_statuses` entry for that sequence has:
- `inactive_reason` ∈ {`replied`, `out of office`}, OR
- `status` ∈ {`finished`, `paused`}, OR
- a non-null `replied_at` in `emailer_touches`.

For each, capture `status`, `inactive_reason`, `paused_at`, `auto_unpause_at`, contact name + `organization_name` + email.

## Answered detection

A reply is **answered** if Sent Items contains an outbound message to that contact's email whose `receivedDateTime`/`sentDateTime` is after the inbound reply (match by `conversationId` when available, else recipient + date). Otherwise it is **open**.

## Routing table → action

| Inbound class | Apollo status | Category | Action |
|---|---|---|---|
| human reply, unanswered | any | **needs-reply** | Task (`reply-needed`) **+ draft a threaded reply** in Drafts |
| human reply, answered | any | answered | Skip |
| auto-reply / OOO | finished AND inactive_reason=`replied` | **false-positive-stop** | Task (`false-positive-stop`); suggest re-activating the sequence. No draft. |
| auto-reply / OOO | paused, `auto_unpause_at` null | **ooo-resume** | Task (`ooo-resume`) + re-surface date (paused_at + 14 days). No draft. |
| auto-reply / OOO | other | — | Skip (already filed by inbox-triage) |

Dedupe: before writing, read `Tasks!A2:F` and skip any (Sender + Subject) already present (covers referrals/items inbox-triage already logged). Skip drafting for a thread that already has a draft.

## Task destination — `Tasks` tab

Append via `mcp__google_workspace__append_table_rows` / `modify_sheet_values` (GWS `Info@boller.store`). Same 9-column schema as inbox-triage: Date | Sender | Subject | Contact | Apollo status | Task type | Suggested action | Status | Owner. Task types here: `reply-needed`, `false-positive-stop`, `ooo-resume`. For `reply-needed` where a draft was created, append " (draft ready in Outlook Drafts)" to the suggested action.

## Drafting (enabled)

For each `needs-reply`, create a threaded draft with `mcp__ms365__create-reply-draft` on the inbound message, then set the body via `update-mail-message`. **Never send.**

Draft guidance:
- **Tone:** founder-to-peer, concise, no fluff, no hard pitch. Acknowledge their specific point first, then one clear next step (offer a short call / answer their question). 3–6 sentences. Sign off as "Vas".
- **Value-prop blurb (for context, weave in only if relevant):** aictrl.dev is a governance + grounding layer for AI coding agents — it grounds agents in your codebase knowledge graph, controls token/context costs, prevents drift from team standards, and gives an audit trail when agents act.
- Match the prospect's language/seniority. If their reply is a question, answer it directly. If it's a soft "not now", propose a lightweight follow-up later. Do NOT invent facts, pricing, or commitments.

## Digest

Preview plan and post-run summary to Telegram DM `6348453236` only (never the group). Token via:

```bash
TOKEN=$(grep -E "^TELEGRAM_BOT_TOKEN|^TOKEN|^BOT_TOKEN" /home/vas/projects/aictrl/.telegram/.env | head -1 | cut -d= -f2- | tr -d '"' | tr -d "'")
curl -s -X POST "https://api.telegram.org/bot${TOKEN}/sendMessage" -H "Content-Type: application/json" \
  -d "$(jq -nc --arg chat "6348453236" --arg text "$MSG" '{chat_id: ($chat|tonumber), text:$text, disable_web_page_preview:true}')" >/dev/null
```

Related: `inbox-triage.md`, `project_email_tooling.md`, `reference_apollo.md`, `feedback_no_group_posts_without_instruction.md`.
