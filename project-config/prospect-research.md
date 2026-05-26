# prospect-research — aictrl project config

Loaded by the general `prospect-research` skill. Supplies the aictrl offer, the outreach message voice spec, drafting toggle, and cost caps. Used standalone ("research this prospect") and by `aictrl-linkedin-status-tracker` when a LinkedIn invite is accepted.

## The offer (what we're selling)

**aictrl.dev** — a governance + grounding layer for engineering teams running AI coding agents (Claude / Cursor) at scale: grounds agents in your codebase knowledge graph, plus session audit, policy controls, and cost/token visibility.

**Positioning (get this right):** Vas is **helping build** aictrl.dev — NOT the sole founder. Always phrase as "helping build" / "part of the team building", never "I'm building" or "my company".

**Two hooks to work into outreach (at least one, naturally):**
1. **Free tokens for code-review sessions** — they get free usage to run AI code reviews.
2. **Trial it yourself in minutes by connecting a GitHub repo** — no setup, point it at a repo and see it work.

## Who's actually a buyer (ICP + fit gate)

aictrl is for **engineering teams whose own developers use AI coding agents (Claude Code / Cursor / Copilot) day-to-day, at enough scale that governance/grounding/cost becomes a real pain.** Fit signals: an eng org of meaningful size (~20+ devs and growing); DevEx / Platform-Engineering / "AI enablement" roles or job posts mentioning Cursor/Copilot/AI pair-programming; an eng blog or public dev presence about rolling out AI coding tools; a buyer who owns internal engineering process / standards / DevEx / eng-security.

**The trap (disqualify on this):** a company building its own AI *product* (an AI feature, agent, or model in their product) is NOT automatically a fit — that's their product, not their internal dev workflow. And a tiny eng team (<~15–20 devs) is premature: the governance/cost pain hasn't formed yet.

**Positive criterion (prefer this):** the best fit is a company whose engineers build *traditional* software — web apps, mobile apps, platforms, back-end / internal systems — and use AI coding tools (Claude Code/Cursor/Copilot) to do it. Normal software-dev shops (fintech, ecommerce, travel, SaaS, telecom, devtools) that happen to run AI coding agents, NOT AI-product shops. If the company's core product is AI (models/agents/AI features), lean Weak even at scale.

**Gate:** prospect-research must output an ICP fit verdict (§6). **Only draft a message for Moderate+ fits.** For Weak / Not-a-fit, return `skip: not ICP` with the reason — do NOT draft or send. A clear disqualification is a win; it saves a real person's attention and our sender reputation.

## Message voice spec (drafting = ON)

- **Tone:** founder-/builder-to-peer. Funny or thought-provoking — NOT generic, NOT corporate, NOT "slop". If it could've been sent to anyone, rewrite it.
- **Open on something specific to THEM** — a real hook from the research brief (a recent post, a launch, their stack, a hiring signal). One concrete, genuine observation beats any pitch.
- **Length:** short — 3–5 sentences. One clear, low-friction ask or offer (the GitHub trial or free review tokens), not a hard sell.
- **Accuracy:** never invent facts, pricing, mutual connections, or commitments. "helping build aictrl.dev". If the research is thin (low confidence), draft a lighter, curiosity-led message and flag it for heavier human editing.
- Sign off as **Vas**.

Reference shape (do NOT send verbatim — personalize the opener every time):
> [specific hook about them]. I'm helping build aictrl.dev — [one-line relevance to their world]. We're giving teams free tokens to run AI code reviews, and you can point it at a GitHub repo and see it in a couple of minutes. Worth a look? — Vas

## Cost + model

- Run each prospect's research as a **subagent on Sonnet** (capable enough for a non-slop draft, far cheaper than Opus; keeps raw LinkedIn/Apollo/web output out of the main session).
- **Caps:** research only NEW accepts; ≤10 per run (aligns with the tracker's send cap). Company posts top 3; one Firecrawl search; skip employee lists.
- Apollo lookups are zero-lead-credit (`apollo_people_match` / `organizations_enrich` / `organizations_job_postings` / `contacts_search`); never use People-API/bulk-enrich here.

## Apollo / LinkedIn context

Sequences H1 `69fde3942587c500119a8f10` / H2 `6a032c60fb3a7d0015fe647d` / H3 `6a04848c82740000159786ed`. CRM spreadsheet `1PQ1oaJPVs3GvWQMk9RBjlef-jcPdISswdD4zGv7QqRQ` (GWS `Info@boller.store`). LinkedIn slug is CRM col H. See `inbox-triage.md` for the shared Apollo lookup pattern.

## Output / handoff

Standalone: print the brief (+ draft) to the operator. Via the status-tracker: return brief + draft so the tracker can route it to Telegram DM `6348453236` for approve/edit/skip before sending. Never send from this skill. Never post to the group `-5110011669`.

Related: `inbox-triage.md`, `reply-audit.md`, `reference_linkedin_mcp.md`, `feedback_no_group_posts_without_instruction.md`. Related skills: `aictrl-linkedin-status-tracker`, `aictrl-linkedin-outreach`.
