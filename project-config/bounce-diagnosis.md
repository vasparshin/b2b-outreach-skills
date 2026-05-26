# bounce-diagnosis — aictrl project config

Loaded by the general `bounce-diagnosis` skill when diagnosing bounces for the **vas@aictrl.dev** Microsoft 365 mailbox (also the Apollo cold-outreach sender, alongside bulat@aictrl.dev). Reads NDRs, splits bad-address from reputation/auth, checks `aictrl.dev` email auth, writes list-hygiene tasks. Read-only: never suppresses in Apollo, never edits DNS.

## Constants (shared with inbox-triage / reply-audit)

| Thing | Value |
|---|---|
| Mailbox | `vas@aictrl.dev` (ms365 MCP) |
| Apollo account email (must match) | `vasparshin@gmail.com` |
| H1 / H2 / H3 sequence_ids | `69fde3942587c500119a8f10` / `6a032c60fb3a7d0015fe647d` / `6a04848c82740000159786ed` |
| CRM spreadsheet_id | `1PQ1oaJPVs3GvWQMk9RBjlef-jcPdISswdD4zGv7QqRQ` |
| Task tab | `Tasks` (same 9-col schema) |
| GWS account (Sheets) | `Info@boller.store` |
| Sending domain (for auth check) | `aictrl.dev` (covers both senders vas@ + bulat@) |
| Digest target | Telegram DM `6348453236` ONLY — NEVER group `-5110011669` |
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

Append via `mcp__google_workspace__modify_sheet_values` (GWS `Info@boller.store`). 9-col schema: Date | Sender | Subject | Contact | Apollo status | Task type | Suggested action | Status | Owner. For bounce rows, put the **failed recipient** in the Sender column and the bounce code + class in the Apollo-status/Suggested-action cells. Task types: `bad-address`, `deliverability`.

## Report + digest

Build the bounce report (counts by code class · per-recipient table · domain-auth verdict · one-line bottom line) and send to Telegram DM `6348453236` only (never the group):

```bash
TOKEN=$(grep -E "^TELEGRAM_BOT_TOKEN|^TOKEN|^BOT_TOKEN" /home/vas/projects/aictrl/.telegram/.env | head -1 | cut -d= -f2- | tr -d '"' | tr -d "'")
curl -s -X POST "https://api.telegram.org/bot${TOKEN}/sendMessage" -H "Content-Type: application/json" \
  -d "$(jq -nc --arg chat "6348453236" --arg text "$MSG" '{chat_id: ($chat|tonumber), text:$text, disable_web_page_preview:true}')" >/dev/null
```

Related: `inbox-triage.md`, `reply-audit.md`, `project_email_tooling.md`, `reference_apollo.md`, `feedback_no_group_posts_without_instruction.md`.
