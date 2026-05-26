---
name: prospect-research
description: General-purpose B2B prospect research engine. Given a person (a LinkedIn profile slug/URL and/or a name + company, optionally an Apollo contact), it orchestrates whatever research tools are available — LinkedIn MCP (mcp__linkedin__*), Apollo MCP (people/org enrich + job postings), and Firecrawl/Exa web search — into a compact, structured research brief to feed a personalized outreach message. Optionally drafts that message when a project config defines the offer + voice. Read-only; never sends anything. Designed to run cheaply: heavy raw tool output is kept out of the caller's context. TRIGGER on `/prospect-research`, "research this prospect", "build a research brief on X", "who is X before I reach out", or when another skill needs a per-person brief. SKIP for bulk list-building, qualifying/grading an existing list (use the qualifier), or sending mail/DMs.
---

# Prospect Research

Turn a name + LinkedIn profile into a short, high-signal brief a human can act on — and (optionally) a personalized first message grounded in that brief. Read-only: it gathers and writes a brief; it never sends a message or modifies the outreach system.

## Cost discipline (read first)

The expensive part is **raw tool output** (LinkedIn profile text, Apollo JSON, scraped pages), not model cleverness.
- **When researching more than one person (a batch), run each person in a subagent.** The subagent ingests the bulky raw tool output in *its* context and returns only the compact brief (+ draft). The caller's context stays lean. This is the single biggest cost lever.
- A mid model (Sonnet) is the right default for the gather+synthesize+draft work — capable enough for a non-generic draft, far cheaper than the top model. Don't use a tiny model for the *drafting* step — that's where quality (the whole point) lives.
- **Trim the gather:** cap company posts to the top ~3, run at most one targeted web search, and skip low-value calls (e.g. full employee lists) unless the task needs them. Stop gathering once the six sections can be filled with reasonable confidence.

## Step 0 — Detect tools + load config

Detect which research tools are present: `mcp__linkedin__*` (person/company/posts/search), Apollo (`apollo_people_match`, `apollo_organizations_enrich`, `apollo_organizations_job_postings`, `apollo_contacts_search`), Firecrawl/Exa (web search). Use whatever exists; degrade gracefully. Read optional `.claude/prospect-research.md` for: the offer/value-prop (what we're selling — sharpens pain-points and hooks), the message voice spec + drafting on/off, model + caps.

## Step 1 — Gather (priority order, stop when enough)

1. **Person** — LinkedIn `get_person_profile(slug)`: current role, tenure, headline, and **recent activity/posts** (the best personalization hook). If an Apollo contact is supplied, `apollo_people_match` for title/seniority.
2. **Company** — LinkedIn `get_company_profile` + `get_company_posts` (top ~3); Apollo `organizations_enrich` for size/funding/industry.
3. **Tech / AI-tooling signals** — Apollo `organizations_job_postings` (hiring for AI/ML/platform/eng roles = AI-tooling adoption signal) + a Firecrawl/Exa search on the company site/careers/news for stack & AI initiatives.
4. **News hooks** — one Firecrawl/Exa search: `<company> funding OR launch OR AI OR leadership 2026`.

## Step 2 — Synthesize the brief (6 sections, compact)

1. **Quick Facts** — name, role, tenure, location, career arc.
2. **Company Panel** — what they do, size, funding/stage, industry.
3. **Tech / AI-tooling signals** — stack, AI initiatives, relevant hiring.
4. **Recent Activity / News hooks** — recent posts, launches, funding, leadership changes (with the specific hook to reference).
5. **Connection points + 3 conversation starters + 3 likely pain points** — tied to the offer if config provides one.
6. **ICP fit verdict** — given the project's ICP (from config), is this person/company actually a *buyer*? **Strong / Moderate / Weak / Not-a-fit** + one-line rationale + confidence. **Watch the trap:** a company that builds its own AI *product* is NOT automatically a fit — judge whether *their own engineers/users* would feel the pain the offer solves, at enough scale to matter, and whether THIS person owns/champions that area. Be willing to say "not a fit" — a clear disqualification is more valuable than a forced pitch.
7. **Research confidence** — high/medium/low per section, so the message-writer knows how much to trust each field. Never invent facts; mark gaps as "unknown".

## Step 3 — Draft, GATED on fit (if config enables it)

Only draft if drafting is on AND the **ICP fit verdict (§6) is Moderate or better.** If fit is **Weak / Not-a-fit, do NOT draft** — return the brief with a `skip: not ICP` recommendation and the one-line reason, so the caller can log it and move on. Don't waste a personalized message (or a real person's attention) on a non-buyer.

When you do draft: write ONE personalized message grounded in the brief — open on a specific hook from §4/§5, follow the voice spec exactly, weave in the configured offer hooks, stay concise. Output the brief + the draft. **Do not send.**

## Step 4 — Return

Return a compact result: the 6-section brief and (if drafted) the message. Nothing is sent and nothing in the outreach system is modified — the caller decides what to do (e.g. route the draft for human approval).

## Failure modes

| Symptom | Action |
|---|---|
| LinkedIn session invalid | Note it; proceed with Apollo + web only; lower confidence. |
| A tool/MCP missing | Use what's present; mark affected sections lower-confidence. |
| Rate limit hit | Respect the config cap; return a partial brief rather than hammering. |
| Thin/no public data | Return a short brief marked low-confidence; flag "manual research recommended" and skip the draft. |

## Reuse / extension

Carries no project specifics. A project supplies `.claude/prospect-research.md` with the offer, voice spec, drafting toggle, model + caps. Edit `/home/vas/projects/aictrl/.claude/prospect-research.md` for aictrl — not this skill. Optional upgrade: add the Exa MCP if Firecrawl news relevance proves weak.
