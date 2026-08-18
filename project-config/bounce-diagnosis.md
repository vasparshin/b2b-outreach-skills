# bounce-diagnosis — aictrl project config

Loaded by the general `bounce-diagnosis` skill when diagnosing bounces for the **<YOUR_SENDING_MAILBOX>** Microsoft 365 mailbox (also the Apollo cold-outreach sender, alongside <TEAMMATE_SENDING_MAILBOX>). Reads NDRs, splits bad-address from reputation/auth, checks `aictrl.dev` email auth, writes list-hygiene tasks. Read-only: never suppresses in Apollo, never edits DNS.

## Constants (shared with inbox-triage / reply-audit)

| Thing | Value |
|---|---|
| Mailbox | `<YOUR_SENDING_MAILBOX>` (ms365 MCP) |
| Apollo account email (must match) | `<YOUR_APOLLO_ACCOUNT_EMAIL>` |
| H1 / H2 / H3 sequence_ids | `<YOUR_APOLLO_SEQUENCE_H1_ID>` / `<YOUR_APOLLO_SEQUENCE_H2_ID>` / `<YOUR_APOLLO_SEQUENCE_H3_ID>` |
| CRM spreadsheet_id | `<YOUR_CRM_SPREADSHEET_ID>` |
| Task tab | `Tasks` (same 9-col schema) |
| GWS account (Sheets) | `<YOUR_GWS_ACCOUNT_EMAIL>` |
| Sending domain (for auth check) | `aictrl.dev` (covers both senders vas@ + bulat@) |
| Digest target | Telegram DM `<YOUR_TELEGRAM_DM_CHAT_ID>` ONLY — NEVER group `<YOUR_TEAM_GROUP_CHAT_ID>` |
| Telegram token file | `/home/vas/projects/aictrl/.telegram/.env` |

## Bounce source

The **Bounces** folder (populated by `inbox-triage`). Also acceptable to sweep Inbox for fresh NDRs (`from:mailer-daemon OR from:postmaster OR subject:Undeliverable OR subject:"Delivery Status" OR subject:"Delivery delayed"`).

## Cross-reference (Apollo) — READ ONLY

Use the Apollo lookup defined in `inbox-triage.md` (Stage B), but look up the **`Final-Recipient`** of each bounce (the address that failed, parsed from the NDR), not the NDR's From. Capture contact name, company, sequence (H1/H2/H3), and current `contact_campaign_statuses` (often `status: failed, inactive_reason: bounced`). Never use People-API / enrich tools.

## Domain authentication check (aictrl.dev)

Run via Bash `dig` (read-only):
```bash
dig TXT aictrl.dev +short            # SPF — expect one v=spf1, includes Outlook + Apollo, ends -all/~all
dig TXT _dmarc.aictrl.dev +short     # DMARC — expect v=DMARC1; p=...
dig CNAME selector1._domainkey.aictrl.dev +short   # DKIM selector 1
dig CNAME selector2._domainkey.aictrl.dev +short   # DKIM selector 2
```
Flag: missing/duplicate SPF, SPF >10 lookups, missing DMARC, missing DKIM CNAMEs. If DKIM CNAMEs resolve but 5.7.x/DMARC bounces are present → flag "confirm DKIM signing is ENABLED in the Microsoft Defender portal (publishing the CNAMEs is not enough)".

## Categorize → action

- **bad address** (5.1.x, 5.1.10, 5.1.2, 5.2.1) → one `Tasks` row per contact, type `bad-address`, suggested action "suppress / remove from sequence (bad address)".
- **reputation/policy/auth** (5.7.x) → ONE systemic `Tasks` row, type `deliverability`, suggested action summarizing the reason + named blocklist (e.g. Proofpoint prs / Cloudmark) + the domain-auth verdict. Do NOT write per-contact suppress rows for these — the addresses are usually fine.
- **transient** (4.x.x) → report count only, no task.

Dedupe: read `Tasks!A2:F`, skip (Sender/recipient + Subject) already present.

## Task destination — `Tasks` tab

Append via `mcp__google_workspace__modify_sheet_values` (GWS `<YOUR_GWS_ACCOUNT_EMAIL>`). 9-col schema: Date | Sender | Subject | Contact | Apollo status | Task type | Suggested action | Status | Owner. For bounce rows, put the **failed recipient** in the Sender column and the bounce code + class in the Apollo-status/Suggested-action cells. Task types: `bad-address`, `deliverability`.

## Report + digest

Build the bounce report (counts by code class · per-recipient table · domain-auth verdict · one-line bottom line) and send to Telegram DM `<YOUR_TELEGRAM_DM_CHAT_ID>` only (never the group):

```bash
TOKEN=$(grep -E "^TELEGRAM_BOT_TOKEN|^TOKEN|^BOT_TOKEN" /home/vas/projects/aictrl/.telegram/.env | head -1 | cut -d= -f2- | tr -d '"' | tr -d "'")
curl -s -X POST "https://api.telegram.org/bot${TOKEN}/sendMessage" -H "Content-Type: application/json" \
  -d "$(jq -nc --arg chat "<YOUR_TELEGRAM_DM_CHAT_ID>" --arg text "$MSG" '{chat_id: ($chat|tonumber), text:$text, disable_web_page_preview:true}')" >/dev/null
```

Related: `inbox-triage.md`, `reply-audit.md`, `project_email_tooling.md`, `reference_apollo.md`, `feedback_no_group_posts_without_instruction.md`.
