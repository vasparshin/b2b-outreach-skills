# aictrl Team Skills — Marketing & Sales

Claude Code skills + a small helper + cron wrappers for the aictrl outreach pipeline: one **unified CRM**, grade-driven, three daily crons (LinkedIn connect, accept-tracker, email sequence), all **approve-before-send** except the connects. Shared so the team can run the same playbook.

> **See `docs/process-flow.md`** for the end-to-end flow diagram (renders on GitHub).

## The model (read this first)

- **One CRM = the `Log` tab** of the shared sheet. One row per contact — Apollo-sourced (auto-synced) and hand-picked alike. Column blocks:
  - **A–Q** Apollo state (synced by `aictrl-crm-refresh`; never hand-edit)
  - **O** `Our Grade` (A/B/C/D) — *the dial that steers every cron* (set by `aictrl-crm-qualify` or by hand)
  - **R–V** LinkedIn outreach · **W–Z** LinkedIn accept-tracker
  - **AA–AF** OUR email sequence: `Email Status · Email Step · Email Last Sent · Email Next Due · Email Reply? · Why/Hook`
- **Grade A = priority.** Connect cron does grade-A leads first (then the Apollo backlog); our email cron emails grade-A only, ≤5/day. B/ungraded are left to Apollo's own sequences (~50/day).
- **Never double-email:** a row whose `Email Status` starts `skip` (already in an Apollo email sequence) is excluded. If an A-grade lead is in an Apollo sequence but not yet emailed, pull them out of Apollo and run ours instead.
- **Approve-before-send:** LinkedIn follow-up DMs and all emails are *drafted* to the operator's Telegram DM for approve/edit/skip. Connects are the only auto step.

## What's here

**`skills/`** → drop into `~/.claude/skills/`:
| Skill | What it does |
|---|---|
| `aictrl-crm-refresh` | Upserts live Apollo state for H1/H2/H3 contacts into the Log (non-destructive). |
| `aictrl-crm-qualify` | Grades each contact A–D into col O. |
| `aictrl-linkedin-outreach` | Daily connect batch (interactive form). |
| `aictrl-linkedin-status-tracker` | Polls accepts → researches → drafts follow-up → **approve before send**. |
| `email-sequencer` | General approval-gated cold-email cadence engine. |
| `prospect-research` | Person → research brief + ICP-fit verdict + outreach angle. |
| `outreach-copy-review` | Critiques a draft vs the research + intended outcome; flags slop/unverifiable claims. |
| `inbox-triage` / `reply-audit` / `bounce-diagnosis` | Inbox sort / unanswered-reply audit / NDR diagnosis. |

**`scripts/aictrl-sheets.py`** → `~/.claude/scripts/`. The CRM helper: direct Google Sheets API (works in a headless cron, unlike the Sheets MCP). Subcommands: `candidates` (connect, grade-A first then Apollo), `pending`/`track-update` (accepts), `due-steps`/`email-update` (email).

**`crons/`** → `~/.claude/scripts/`. The three wrappers (`aictrl-linkedin-cron.sh` 10:00, `aictrl-linkedin-tracker-cron.sh` 10:15, `aictrl-email-sequence-cron.sh` 10:30). Each runs `claude -p` headless with a scoped `--allowedTools` (NO send tools — sends stay behind your approval) and posts results/drafts to your Telegram DM.

**`project-config/`** → `<your-aictrl-project>/.claude/`. Per-project config the engines read.

## Install

1. `cp -r skills/* ~/.claude/skills/`
2. `cp scripts/* ~/.claude/scripts/ && chmod +x ~/.claude/scripts/*.sh ~/.claude/scripts/aictrl-sheets.py`
3. `cp project-config/* <your-aictrl-project>/.claude/`
4. Add the three cron lines (weekdays) — `crontab -e`:
   ```
   0  10 * * 1-5 ~/.claude/scripts/aictrl-linkedin-cron.sh          >> ~/.claude/logs/aictrl-linkedin-cron-wrapper.err 2>&1
   15 10 * * 1-5 ~/.claude/scripts/aictrl-linkedin-tracker-cron.sh  >> ~/.claude/logs/aictrl-linkedin-tracker-wrapper.err 2>&1
   30 10 * * 1-5 ~/.claude/scripts/aictrl-email-sequence-cron.sh    >> ~/.claude/logs/aictrl-email-sequence-wrapper.err 2>&1
   ```
5. Restart Claude Code so the skills load.

## ⚙️ ADAPT THESE before first run (the scripts carry Vas's values)

In **`scripts/aictrl-sheets.py`**:
- `CREDS` path → your own google-workspace-mcp OAuth creds file (must have **edit access to the shared sheet** — ask Vas to share it with your Google account).
- `VAS_USER_ID` → **your** Apollo user_id (from `apollo_users_api_profile`); this scopes the connect queue to *your* Apollo tasks.
- `SID` (spreadsheet) + the H1/H2/H3 `SEQS` → **keep as-is** (shared team CRM + sequences).

In **`crons/*.sh`**:
- All `/home/vas/...` paths → your home/project paths.
- `CHAT_ID="<YOUR_TELEGRAM_DM_CHAT_ID>"` → **your** Telegram DM chat_id.
- `"Vas Parshin"` sender label (connect cron) → your name.
- The MS365 sender (email cron prompt, `<YOUR_SENDING_MAILBOX>`) → your aictrl address.

Prereqs (your own accounts): LinkedIn MCP (`uvx linkedin-scraper-mcp@latest --login`), Apollo MCP, MS365 (`@softeria/ms-365-mcp-server`), Google Workspace MCP, Firecrawl.

## Security

No secrets are committed — scripts read `~/.claude/secrets.env` (Apollo key), `.telegram/.env` (Telegram token), and the GWS creds file from your own machine at runtime. The crons deliberately exclude all *send* tools so nothing is sent without your Telegram approval. Keep this repo private.
