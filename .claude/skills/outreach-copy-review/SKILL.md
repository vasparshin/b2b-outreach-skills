---
name: outreach-copy-review
description: Critique engine for cold outreach copy (cold emails, LinkedIn DMs, sequence steps). Given a draft plus the prospect research it was built from and the intended outcome, it scores the draft on four axes — personalisation/accuracy, pull toward the intended response, voice, and deliverability — flags anything unverifiable or slop, and returns a tightened rewrite. Read-only; never sends. Use it as a quality gate between drafting (prospect-research / email-sequencer) and sending. TRIGGER on `/outreach-copy-review`, "critique this opener", "review the copy", "is this message any good", "tighten this outreach". SKIP for writing the draft from scratch (use prospect-research / email-sequencer), code review, or general prose editing.
---

# Outreach Copy Review

A second pair of eyes on outreach copy *before it goes out*. It does not write from scratch — it judges an existing draft against the research it claims to be grounded in and the response it is trying to provoke, then proposes a tighter version. The goal is to kill generic "slop" and unverifiable claims, and to make every line earn its place toward the intended reply.

## Inputs (ask for whatever's missing)

1. **The draft(s)** — subject + body.
2. **The research / hook** — what we actually know about this person/company (e.g. the CRM "Why" column or a prospect-research brief).
3. **The intended outcome** — what response are we trying to get? (e.g. "a reply that opens a conversation", "book a demo", "try the trial").
4. **The voice spec + offer** — from the project config if present (`.claude/email-sequencer.md` / `prospect-research.md`).

## The four axes (score each 1–5, with a one-line reason)

1. **Personalisation & accuracy** — Is the opener specific to THIS person, drawn from the research, and *true*? **Flag any claim we can't back from the research** (e.g. "your name keeps coming up", invented mutual connections, guessed metrics). Unverifiable flattery is worse than none — it reads as a mail-merge guess and can be wrong to their face. A line that could be sent to anyone scores ≤2.
2. **Pull toward the intended response** — Does the message make the desired reply easy and likely? One clear, low-friction ask; the value lands in the first two sentences; the CTA matches the outcome (don't ask for a demo when the goal is just a reply).
3. **Voice** — Matches the spec (here: founder-/builder-to-peer, specific, confident, not corporate, not needy). No apologies, no easy-outs ("if not relevant, no worries"), no hype words. Honours positioning exactly (for aictrl: "helping build", never "my company").
4. **Deliverability & form** — Subject ~40–50 chars, no spam-trigger words; body skimmable (short paragraphs); exactly one CTA and one link; plain-text feel. (Mirrors the `email-marketing` rules.)

## Output

For each draft:
- The four scores + one-line reasons, and an overall verdict: **ship as-is / ship with edits / rework**.
- **Specific flags** — quote the exact offending phrase and say why (esp. unverifiable claims — these are blocking).
- **A tightened rewrite** — only change what needs changing; if the draft is already strong, say so and make minimal edits rather than rewriting for its own sake (over-editing research-grounded copy usually makes it worse).
- If research is thin, recommend going lighter/curiosity-led rather than fabricating specificity.

Never send, never enrol, never modify the outreach system — hand the review + rewrite back to the operator (or the calling skill) to act on.

## Reuse

Carries no project specifics; reads the voice/offer from the project config when present. Pairs with `prospect-research` (produces the hook), `email-sequencer` (the cadence it gates), and `email-marketing` (deliverability rules).
