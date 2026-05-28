# email-sequencer — aictrl project config

Loaded by the general `email-sequencer` skill. Drives the cold-email follow-up cadence for the aictrl outreach list. Pairs with `prospect-research` (which produces each lead's personalisation hook) and `reply-audit`.

## Stack

- **Mail:** Microsoft 365 (`mcp__ms365__*`), sender **vas@aictrl.dev**. Draft with `create-draft-email`, send with `send-draft-message`, reply-check with `list-mail-messages` / `search-query` (KQL, quoted).
- **CRM:** the unified **`Log` tab** of spreadsheet `1PQ1oaJPVs3GvWQMk9RBjlef-jcPdISswdD4zGv7QqRQ` (GWS `Info@boller.store`). One row per contact — Apollo-sourced and hand-picked alike (the old separate `Sequence`/`Prospects` tabs were merged in 2026-05-28; archived as `Sequence_archived_*` / `Research_staging`).
  - **Email-sequence state lives in cols AA–AF:** `AA Email Status · AB Email Step · AC Email Last Sent · AD Email Next Due · AE Email Reply? · AF Why / Hook`. Grade is **col O** (A/B/C/D); the personalisation hook is **AF**.
  - **Access via the direct-API helper, not the Sheets MCP** (the MCP can't auth headless): `python3 ~/.claude/scripts/aictrl-sheets.py due-steps [N]` lists grade-ordered due rows (excludes `Email Status` starting "skip", e.g. leads already in an Apollo email sequence — never double-email); `... email-update <row> <status> <step> <last_sent> <next_due> [reply]` advances a row after a send.
- **Approval channel:** Telegram DM **chat_id `6348453236`** (`mcp__plugin_telegram_telegram__reply`). Route every drafted step here for approve / edit / skip.

## Safety flags

- **`auto_send: false`** — NEVER send without explicit operator approval in the Telegram DM. (Vas's standing rule: outreach approval happens via Telegram, not the CC console.)
- Never post sequence activity to the group `-5110011669`.
- **Exclusions:** skip any lead already `replied`/`stopped`; skip addresses that bounced (run `bounce-diagnosis` on NDRs and `stop` them); never enrol an existing customer/partner.

## The offer + positioning (must match prospect-research config)

**aictrl.dev** — a governance + grounding layer for engineering teams running AI coding agents (Claude Code / Cursor) at scale: grounds agents in the codebase knowledge graph, plus session audit, policy controls, and cost/token visibility.

- **Positioning:** Vas is **helping build** aictrl.dev — never "I'm building" / "my company".
- **Hooks (weave in naturally):** free tokens to run AI code reviews; trial it in minutes by pointing it at a GitHub repo.
- **One link only: `app.aictrl.dev`.** Point straight to it. No "no pitch" disclaimers.
- Sign off as **Vas**.

## Cadence (business days, Tue–Thu preferred, business hours)

| Step | When | Subject |
|---|---|---|
| 1 — opener | at enrol (Next due = today) | `AI coding agents at {company}` |
| 2 — nudge | +3 business days after Step 1 sent | `re: AI coding agents at {company}` |
| 3 — close | +4 business days after Step 2 sent | `re: AI coding agents at {company}` |

After Step 3 sends with no reply → `Status=completed`.

## Step templates

`{opener}` = the personalised first 1–2 sentences, built from the lead's Hook line in Prospects col H (specific to THEM — a post, event, launch, metric). Never generic.

### Step 1 — opener
```
{opener}

I'm helping build aictrl.dev — a governance and grounding layer for engineering teams running AI coding agents (Claude Code, Cursor) at scale: it grounds agents in your codebase's knowledge graph, plus session audit, policy controls, and cost/token visibility.

We're giving teams free tokens to run AI code reviews — you can point it at a GitHub repo and see it work in a couple of minutes: app.aictrl.dev

Worth a look?
Vas
```

### Step 2 — nudge
```
Quick follow-up, {first_name} — figured the timing might be off rather than the idea.

The reason I reached out: once a team is past experimenting and agents are writing a real share of commits, the questions shift from "is this useful" to "what did the agent touch, was it grounded in our actual codebase, and what is it costing us?" That's the gap aictrl closes.

If it's worth ten minutes, the free-tokens trial is the quickest way to judge it: app.aictrl.dev
Vas
```

### Step 3 — close
```
Last one from me, {first_name}.

If governing AI coding agents is on the radar at {company}, the free-tokens trial is the fastest way to see for yourself whether it earns its place: app.aictrl.dev

If the timing's wrong I'll leave it there — good luck with what you're building.
Vas
```

## Voice

Founder-/builder-to-peer. Specific, confident, concise. Open on something true about THEM. One call-to-action, one link. No corporate filler, no neediness, no apologies. If a draft could have been sent to anyone, rewrite the opener.

## Related

`prospect-research.md` (hooks + ICP), `reply-audit.md` (reply detection), `bounce-diagnosis` (classify/remove bouncers), `inbox-triage.md`. Sequences also exist in Apollo (H1/H2/H3) for the LinkedIn track — this email track is separate and operator-approved per send.
