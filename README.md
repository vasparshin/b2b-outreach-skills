# aictrl Team Skills — Marketing & Sales

Claude Code skills + project configs for the aictrl outreach pipeline (LinkedIn outreach, CRM, prospect research, and email triage/audit/bounce diagnosis). Shared so the team can run the same playbook.

## What's here

**`skills/`** — drop into `~/.claude/skills/`:
| Skill | What it does |
|---|---|
| `aictrl-crm-refresh` | Pulls live Apollo state for H1/H2/H3 sequence contacts into the master CRM (Log tab). |
| `aictrl-crm-qualify` | Scores each CRM contact A–D into col O (Our Grade). |
| `aictrl-linkedin-outreach` | Daily LinkedIn connect batch from CRM H1 candidates (auto-scopes to the running operator's Apollo tasks). |
| `aictrl-linkedin-status-tracker` | Polls pending invites; on accept → runs prospect-research → drafts a personalized message → **operator approves before send**. |
| `prospect-research` | General engine: person + company → research brief + **ICP-fit verdict** + outreach angle (LinkedIn MCP + Apollo + Firecrawl). |
| `inbox-triage` | Sorts a mailbox into folders + surfaces tasks (header-based + optional CRM cross-ref). |
| `reply-audit` | Finds unanswered prospect replies + outreach mis-classifications; drafts replies (never sends). |
| `bounce-diagnosis` | Parses NDRs (RFC 3463), splits bad-address vs reputation/auth, checks domain SPF/DKIM/DMARC. |

**`project-config/`** — drop into `<your-aictrl-project>/.claude/`: per-project config the general engines read (`inbox-triage.md`, `reply-audit.md`, `bounce-diagnosis.md`, `prospect-research.md`).

## Prerequisites (connect with YOUR OWN accounts)

These skills orchestrate MCP servers — you need them configured in your Claude Code:
- **LinkedIn** — `linkedin-scraper-mcp` (run `uvx linkedin-scraper-mcp@latest --login` once).
- **Apollo.io** — the Apollo MCP, logged into your Apollo account.
- **Mail** — Microsoft 365 (`@softeria/ms-365-mcp-server`) or a Gmail MCP, for inbox-triage / reply-audit / bounce-diagnosis.
- **Google Workspace** — Sheets/Drive (for the CRM).
- **Firecrawl** — web search, for prospect-research.

## Install

1. `cp -r skills/* ~/.claude/skills/`
2. `cp project-config/* <your-aictrl-project>/.claude/`
3. Restart Claude Code so the skills load. Trigger with `/skill-name` or natural language.

## ADAPT these per operator (search-and-replace before first run)

The files carry the original operator's values. Change:
- **Telegram DM chat_id** — currently `6348453236` (Vas's DM). Set to *your* DM chat_id.
- **Telegram token file** — `/home/vas/projects/aictrl/.telegram/.env` → your path.
- **Any `/home/vas/...` absolute paths** → your home / project paths.
- **Apollo** — no change needed: `aictrl-linkedin-outreach` auto-scopes to whoever's logged in (`apollo_users_api_profile`), so it only touches *your* contacts.

**Keep these as-is** (shared pipeline): the CRM spreadsheet ID and the H1/H2/H3 sequence IDs — they're the same team workspace.

## Security

No secrets are committed — the skills read `~/.claude/secrets.env` (Apollo key) and `.telegram/.env` (Telegram token) from your own machine at runtime. Never commit those files. Keep this repo private.
