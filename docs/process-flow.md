# aictrl Outreach — Process Flow

One unified CRM (the `Log` tab), one priority dial (**col O grade**), three daily weekday crons. Connects are the only fully-automatic step; every **message and email is drafted only and waits for approval in the operator's Telegram DM** (never the group, never auto-sent).

```mermaid
flowchart TD
    subgraph CRM["Unified CRM — Log tab (one row per contact)"]
      AP[Apollo contacts<br/>auto-synced by aictrl-crm-refresh]
      MAN[Hand-picked leads<br/>added manually, no Apollo ID]
      GR[col O = Grade A/B/C/D<br/>the dial that steers every cron]
    end

    QUAL[aictrl-crm-qualify<br/>grades contacts A–D] --> GR
    RES[prospect-research<br/>+ outreach-copy-review] -. promotes A leads .-> MAN

    subgraph HELPER["aictrl-sheets.py — direct Sheets API (works headless)"]
      H1[candidates]
      H2[pending / track-update]
      H3[due-steps / email-update]
    end

    CRM --> HELPER

    subgraph CRONS["Daily weekday crons"]
      C1["10:00 — Connect batch<br/>aictrl-linkedin-cron.sh"]
      C2["10:15 — Accept tracker<br/>aictrl-linkedin-tracker-cron.sh"]
      C3["10:30 — Email sequence<br/>aictrl-email-sequence-cron.sh"]
    end

    H1 --> C1
    C1 -->|"grade-A first, then Apollo backlog<br/>up to 15/day — AUTO SEND"| INV[LinkedIn connection requests]
    INV --> H2
    H2 --> C2
    C2 -->|"poll pending → detect accepts<br/>draft short follow-up DM"| TG1{{Telegram DM<br/>approve / edit / skip}}
    TG1 -->|approved| LMSG[LinkedIn DM sent]

    H3 --> C3
    C3 -->|"grade-A due steps, max 5/day<br/>draft personalised email"| TG2{{Telegram DM<br/>approve / edit / skip}}
    TG2 -->|approved| EMAIL[Email sent from <YOUR_SENDING_MAILBOX> via Outlook]

    REPLY[Prospect replies] -->|auto-stops that lead's sequence| CRM
    APOLLO[Apollo runs its own email sequence ~50/day<br/>for grade-B and ungraded contacts]
    GR -. "grade-A in an Apollo seq + not yet emailed<br/>→ pulled out, run through ours instead" .-> APOLLO
```

## Rules encoded
- **LinkedIn connect priority = grade A.** Our hand-picked A leads connect ahead of the Apollo task backlog; once connected, the cron falls through to Apollo's queue.
- **Our email cron = grade A only, ≤5/day** (Apollo handles ~50/day for B/ungraded). Never double-emails: rows whose `Email Status` starts "skip" (already in an Apollo email sequence) are excluded.
- **A-grade contact already in an Apollo email sequence:** if Apollo hasn't emailed them yet, remove from Apollo and run our personalised sequence; if Apollo already emailed, leave them with Apollo.
- **Approval:** LinkedIn follow-up DMs and all emails are drafted to the Telegram DM (`<YOUR_TELEGRAM_DM_CHAT_ID>`) for approve/edit/skip. Connects are the only auto step.
- **All CRM I/O goes through `aictrl-sheets.py`** (direct Sheets API) because the Google Sheets MCP can't authenticate in a headless cron.
