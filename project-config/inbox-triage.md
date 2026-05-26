# inbox-triage — aictrl project config

Loaded by the general `inbox-triage` skill when triaging the **vas@aictrl.dev** Microsoft 365 mailbox. Supplies aictrl's folders, the Apollo cross-reference (Stage B enrichment), the routing table, the task destination, and the digest target. The general engine carries none of this.

This mailbox is also the Apollo cold-outreach sender, so the Inbox mixes: real sequence bounces, real prospect replies, prospect auto-replies, Apollo product/marketing mail, and warmup chatter. The Apollo cross-reference is what tells them apart.

## Constants

| Thing | Value |
|---|---|
| Mailbox | `vas@aictrl.dev` (ms365 MCP) |
| Apollo account email (must match) | `vasparshin@gmail.com` |
| Apollo user_id | `69fc6082065486001538f103` |
| H1 sequence_id | `69fde3942587c500119a8f10` |
| H2 sequence_id | `6a032c60fb3a7d0015fe647d` |
| H3 sequence_id | `6a04848c82740000159786ed` |
| CRM spreadsheet_id | `1PQ1oaJPVs3GvWQMk9RBjlef-jcPdISswdD4zGv7QqRQ` |
| Task tab | `Tasks` |
| GWS account (Sheets) | `Info@boller.store` |
| Digest target | Telegram DM `6348453236` ONLY — NEVER group `-5110011669` |
| Telegram token file | `/home/vas/projects/aictrl/.telegram/.env` |
| Apollo product/marketing senders | `support@tryapollo.io`, `hello@mail.apollo.io`, `*@mail.apollo.io` |

## Folders (create on approval if missing)

`Bounces` · `Auto-Replies` · `Apollo Notifications` · `Updates` · `Apollo Mailwarming` (already exists). Any message moved to `Updates` is marked read (`update-mail-message` isRead:true).

## Stage B — Apollo cross-reference (READ ONLY)

For each message whose sender is an external person (skip system senders: mailer-daemon, postmaster, and the Apollo product/marketing senders above), look the sender up in Apollo:

1. `apollo_contacts_search` with `q_keywords: <sender email>`, `per_page: 5`, a non-PII `_rationale`, and a stable `_conversation_ref`. (Contact search does NOT spend lead credits — but never call People-API / enrich tools here.)
2. From the matched contact, read `contact_campaign_statuses`. Annotate the message with:
   - `in_sequence`: true if any status's `emailer_campaign_id` ∈ {H1,H2,H3}.
   - `seq_status`: that entry's `status` (e.g. `active`, `finished`, `failed`) and `inactive_reason` (e.g. `replied`, `bounced`).
   - `contact`: name + `organization_name`.
3. If no contact matches → annotate `in_sequence: false` (treat as non-sequence / likely warmup or cold).

For a `BOUNCE` message, the bounced recipient is in the **original message** the NDR wraps, not the From — pull the failed recipient from the bounce body/`Final-Recipient` and look THAT up.

## Routing table  (base category × enrichment → action)

| Base category | Enrichment | Folder | Task? |
|---|---|---|---|
| `BOUNCE` | any | `Bounces` | No (the bounce skill owns diagnosis). Count by sequence for the summary. |
| `AUTO_REPLY` | in_sequence AND seq_status finished/inactive_reason=replied | `Auto-Replies` | **YES — `false-positive-stop`**: Apollo stopped this live contact on an auto-reply; needs manual review. |
| `AUTO_REPLY` | body contains a referral (names/points to another person or email) | `Auto-Replies` | **YES — `referral`**: capture the referred name/email. |
| `AUTO_REPLY` | other | `Auto-Replies` | No |
| `BULK`/`NOTIFICATION` | Apollo product/marketing sender | `Apollo Notifications` | No (Apollo "Tasks Due" already live in Apollo). |
| `BULK`/`NOTIFICATION` | other automated (non-Apollo, e.g. Microsoft) | `Updates` (mark read) | No |
| `HUMAN_REPLY` | in_sequence | leave in Inbox + tag `Sequence Reply` | **YES — `reply-needed`**: reply to <contact> (<company>) — <sequence>. |
| `HUMAN_REPLY` | not in_sequence | leave in Inbox | **YES — `reply-needed-unknown`** (lower priority). |
| `SECURITY` | any | `Updates` (mark read) | **YES — `security`** (action tracked via the Sheet, not inbox clutter). |
| `UNKNOWN` | looks like a personal human reply | leave in Inbox + flag | No (never auto-bury a possible real reply). |
| `UNKNOWN` | impersonal / notification-like | `Updates` (mark read) | No |

Warmup token rule: any message whose subject contains the token `wbx ` followed by a short code (e.g. "…- wbx gne") is Apollo mail-warming network traffic — move it to `Apollo Mailwarming`. This is a reliable warmup signal regardless of sender. (Note: Apollo's own inbox rule often moves these automatically, so they may already be gone.)

Self-send rule: a message where both From and To are the mailbox owner (`vas@aictrl.dev`) with no matching Apollo contact is a test/preview send — move it to `Archive` (no action, no task).

Conservative rule: aside from the `wbx` token above, never move a message to `Apollo Mailwarming` automatically unless it is unambiguously warmup-network chatter (generic subject, sender not in Apollo, not a reply/bounce/notification). When in doubt, leave it in the Inbox flagged.

## Task destination — `Tasks` tab

Append one row per task-worthy item via `mcp__google_workspace__append_table_rows` / `modify_sheet_values` (GWS account `Info@boller.store`, spreadsheet above). Columns:

| Col | Field |
|---|---|
| A | Date (UTC, run timestamp) |
| B | Sender (email) |
| C | Subject |
| D | Contact (name + company, from Apollo if matched) |
| E | Apollo status (in_sequence + seq_status/inactive_reason, or "not in Apollo") |
| F | Task type (`reply-needed` / `referral` / `false-positive-stop` / `security` / `reply-needed-unknown`) |
| G | Suggested action |
| H | Status (`open` on write) |
| I | Owner (blank → Vas) |

Idempotency: before appending, read existing `Tasks!A2:C` and skip any row whose (Sender + Subject) already exists.

## Digest

Send the preview plan and the post-run summary to Telegram DM `6348453236` only (never the group). Use the token from the file above:

```bash
TOKEN=$(grep -E "^TELEGRAM_BOT_TOKEN|^TOKEN|^BOT_TOKEN" /home/vas/projects/aictrl/.telegram/.env | head -1 | cut -d= -f2- | tr -d '"' | tr -d "'")
curl -s -X POST "https://api.telegram.org/bot${TOKEN}/sendMessage" -H "Content-Type: application/json" \
  -d "$(jq -nc --arg chat "6348453236" --arg text "$MSG" '{chat_id: ($chat|tonumber), text:$text, disable_web_page_preview:true}')" >/dev/null
```

Related memory: `project_email_tooling.md`, `project_ms365.md`, `reference_apollo.md`, `feedback_no_group_posts_without_instruction.md`.
