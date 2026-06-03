---
name: bounce-diagnosis
description: General-purpose email bounce / NDR (Non-Delivery Report) diagnosis engine for any mailbox reachable via an email MCP (Microsoft 365 / ms365, or Gmail). Reads bounce notifications, parses the machine-readable delivery-status part (RFC 3464/3463) to extract the SMTP enhanced status code, classifies each bounce (bad address vs mailbox vs routing vs policy/reputation vs transient), optionally cross-references the failed recipient against an outreach system, and checks the sending domain's SPF/DKIM/DMARC. Produces a categorized bounce report and surfaces list-hygiene vs sender-reputation actions separately. Read-only — never suppresses contacts and never changes DNS. ALWAYS previews before writing tasks. Reads an optional per-project config file (.claude/bounce-diagnosis.md) for the bounce source, sending domain, cross-reference, task destination, and digest. TRIGGER on `/bounce-diagnosis`, "why are emails bouncing", "diagnose bounces", "check deliverability", "analyze the NDRs". SKIP for sorting the inbox (use inbox-triage), reply follow-ups (use reply-audit), or sending mail.
---

# Bounce Diagnosis

Turn a pile of "Undeliverable" notices into a clear answer: which bounces are **bad addresses** (clean the list) versus **sender reputation / authentication** problems (fix us, NOT the addresses) — and whether the sending domain's email auth is actually configured. Read-only; it diagnoses and recommends, it never suppresses contacts or edits DNS.

## Why the distinction matters (the whole point)

- **5.1.x / 5.2.1 (bad address / no such user)** → the *address* is the problem. Suppress it, clean the list. Re-sending destroys reputation.
- **5.7.x (policy / reputation / auth)** → the *address is usually fine*; the problem is **us** (sender reputation, or SPF/DKIM/DMARC). Suppressing these is the wrong move — you fix the sender instead.
- **4.x.x** → transient (greylisting, throttling, queue timeout). The server will retry; usually no action.

Mis-handling this is the most common and most damaging mistake in cold outreach, so the skill keeps the two paths strictly separate.

## Operating principles

1. **Read-only.** Never suppress/modify contacts in the outreach system; never change DNS. Output is a report + recommended tasks only.
2. **Parse the machine part, not the prose.** Extract from `message/delivery-status` (`Status`, `Action`, `Diagnostic-Code`, `Final-Recipient`). The human "Undeliverable" text is localized and unreliable — only use it as a last resort.
3. **Preview, then execute.** Show the full report + planned task rows; write nothing until confirmed. "dry-run" stops after the report.
4. **Idempotent.** Skip bounces already represented in the task destination.

## Step 0 — Detect backend and load config

ms365 primary (`get-mail-message-mime` for raw MIME, `list-mail-folder-messages`). Read `.claude/bounce-diagnosis.md` for: bounce-source folder, sending domain(s), cross-reference, task destination, digest target. No config → run mailbox-only (parse + classify + report; no cross-reference, no domain check unless a domain is given).

## Step 1 — Collect NDRs

List messages in the configured bounce source (default: a "Bounces" folder, else search Inbox for `from:postmaster OR from:mailer-daemon OR subject:Undeliverable OR subject:"Delivery Status"`). For each, fetch **raw MIME** (`get-mail-message-mime`).

## Step 2 — Parse each NDR (RFC 3464/3463)

From the `message/delivery-status` MIME part, per failed recipient extract:
- `Final-Recipient` (strip the `rfc822;` prefix) — the address that bounced.
- `Action` — `failed` (hard), `delayed` (transient), `delivered`/`relayed`.
- `Status` — the enhanced code `class.subject.detail`, e.g. `5.1.1`. **Primary classification key.**
- `Diagnostic-Code` — raw remote reply, e.g. `smtp; 550 5.1.1 User unknown`. Use to recover the enhanced code if `Status` is missing (regex `\b[245]\.\d{1,3}\.\d{1,3}\b`), and to capture any named blocklist (e.g. `prs.proofpoint.com`, Cloudmark CSI).

Precedence: `Status` → enhanced code from `Diagnostic-Code` → basic 3-digit code → prose keywords (last resort).

> Note: this is a lightweight hand-parser, adequate for modest volume. If bounce volume grows large, prefer the battle-tested **Sisimai** library (BSD) over extending this.

## Step 3 — Classify (RFC 3463)

| Code | Meaning | Class | Action path |
|---|---|---|---|
| 5.1.1 / 5.1.10 | no such user / recipient not found | hard, **bad address** | suppress / clean list |
| 5.1.2 | bad destination domain | hard, **bad address** | suppress |
| 5.2.1 | mailbox disabled | hard, **bad address** | suppress |
| 5.2.2 | mailbox full | soft→hard | retry, then suppress |
| 5.4.x | routing / DNS / queue-expired | hard/soft | suppress if persistent |
| 5.7.1 | refused by policy | **policy/reputation** | investigate sender, do NOT suppress |
| 5.7.23 / 5.7.26 / 5.7.509 | SPF / unauthenticated / DMARC reject | **auth** | fix domain auth |
| 5.7.5xx | banned/blocked sender, spam-abuse | **reputation** | pause, warm up, reduce volume |
| 4.x.x | transient (greylist/throttle/timeout) | soft | none (auto-retry) |

## Step 4 — Cross-reference (if configured)

For each `Final-Recipient`, look it up in the outreach system (project-defined) → contact name, company, which sequence, current status. This tells you whether the bounce is a real pipeline contact.

## Step 5 — Domain authentication check (if a sending domain is configured)

Via Bash `dig` (read-only DNS):
- **SPF:** `dig TXT <domain> +short` → expect one `v=spf1 …` record, ≤10 lookups, includes the real senders, ends `-all`/`~all`.
- **DMARC:** `dig TXT _dmarc.<domain> +short` → expect `v=DMARC1; p=…`.
- **DKIM (M365):** `dig CNAME selector1._domainkey.<domain> +short` and `selector2._domainkey` → expect CNAMEs to `*.onmicrosoft.com`. **Gotcha:** the CNAMEs can resolve while DKIM signing is still *disabled* in the admin portal — if 5.7.x/DMARC bounces appear with DKIM CNAMEs present, flag "verify DKIM is *enabled*, not just published".

## Step 6 — Categorize → action, then report

- **bad-address bounces** → one task row per contact: suppress / remove from list.
- **policy/reputation/auth bounces** → a single *systemic* finding (don't suppress addresses); one task row: "deliverability: <reason> — investigate", plus the domain-auth verdict.
- **transient** → report count only, no task.

Build a **report**: counts by code class, a per-recipient table (recipient · code · class · sequence · action), the domain-auth verdict, and a one-line bottom line ("mostly bad addresses → clean list" vs "reputation/auth problem → fix sender"). Preview it (+ planned task rows) to the digest target, then on confirm write tasks (dedupe first) and send the report.

## Failure modes

| Symptom | Action |
|---|---|
| No `message/delivery-status` part (non-standard NDR) | Fall back to `Diagnostic-Code`/prose; mark lower-confidence. |
| Bounce wraps the original but no code | Report as "unknown bounce reason"; include the remote text. |
| `dig` unavailable | Skip domain check; note it; recommend MXToolbox/mail-tester manually. |
| Cross-reference fails | Still classify + report; mark recipient "not matched". |

## Reuse / extension

Engine carries no project specifics. A project supplies `.claude/bounce-diagnosis.md` with bounce source, sending domain(s), cross-reference, task destination, digest. Edit `/home/vas/projects/aictrl/.claude/bounce-diagnosis.md` for aictrl — not this skill.
