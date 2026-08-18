---
name: aictrl-event-prospecting
description: Finds AI-safety / AI-governance-themed hackathons and events (starting from the "Translating AI Safety" hackathon Vas is registering for 22 Aug 2026), tracks which ones Vas registers for, pulls attendee lists where public, enriches attendees via Apollo, and feeds qualifying ones into the standard aictrl outreach pipeline tagged by source event. Registration is drafted for approval, never auto-submitted — see "Why registration is approval-gated" below. TRIGGER on "find AI safety hackathons", "similar events to X", "/aictrl-event-prospecting", or a scheduled weekly cron. SKIP for general (non-AI-safety) hackathon discovery — that's secretary's hackathon-finder skill — and for the actual LinkedIn/email send, which is the existing aictrl-linkedin-outreach / email-sequencer pipeline once a lead is in the CRM.
---

# aictrl Event Prospecting

Built 2026-08-07 per Vas, after he registered for "Translating AI Safety" (LIaiSE + Frame Fellowship, 22 Aug 2026, Central London). The insight: hackathon/event attendees in this niche are an unusually warm audience for aictrl — self-selected as engaged with AI safety/governance, exactly the mindset aictrl's pitch (governance layer for AI coding agents) needs no warm-up for. This is a distinct lead source from the existing Apollo/LinkedIn-cold-search pipeline, not a replacement for it.

## Why this is a separate skill from `hackathon-finder`

Secretary's `hackathon-finder` finds hardware/robotics/general hackathons for Vas's personal calendar — different theme, different purpose (things for him to attend), owned by secretary. This skill is themed specifically to AI safety/governance/control and exists to source outreach leads for aictrl, owned by aictrl. Geography/venue matter for `hackathon-finder`; audience quality matters here — a fully remote AI safety sprint is still a good target for this skill even though secretary's skill wouldn't care about it.

## Pipeline

### 1. Discovery — find AI-safety-themed events

Generic Luma discovery (the `api.lu.ma/discover/get-paginated-events` geo endpoint documented in `hackathon-finder/SKILL.md`) returns mostly unrelated local events — confirmed 2026-08-07, zero AI-safety matches in the first 47 nearby entries. This niche lives on its own aggregators, not general event discovery:

1. **Apart Research sprints page** — `https://apartresearch.com/sprints` (readable via WebFetch). Lists upcoming AI safety hackathons/sprints with dates, "Online & In-Person" flags, and links. The primary recurring organizer in this space; check every run.
2. **AI Safety Events & Training substack** — `https://aisafetyeventsandtraining.substack.com` — a weekly-updated aggregator specifically for this niche (posts titled "AI Safety Events and Training <year> week N update"). Read the latest post each run.
3. **Web search fallback** — `"AI safety hackathon" London <month/year>` and `"AI governance hackathon" <year>` — catches one-off events (like LIaiSE's, which wasn't on either aggregator above) run by smaller/newer orgs.
4. **Luma organizer pages once known** — once an organizer (LIaiSE, Frame Fellowship, BlueDot Impact) is confirmed active, check their Luma calendar directly the way `hackathon-finder` step 2 watches specific calendars — add to `/home/vas/projects/aictrl/data/watched_event_orgs.json` (create on first use) so future runs don't have to rediscover them via search.

Filter to: genuinely upcoming (confirmed future date, not a stale past listing — same verification rule as `hackathon-finder`), and either in-person UK/London or remote/online (remote counts — the audience quality is what matters, not travel).

### 2. Registration — DRAFT ONLY, never auto-submit

**Why this is approval-gated, unlike LinkedIn connects/follow-ups:** a LinkedIn connect is reversible and low-stakes if wrong. Registering Vas for an event is not — it can commit him to a real-world time block (often a full day), and most forms ask for personal, judgment-laden answers ("what's a project you're proud of", "what do people get wrong about AI risk") that read as his own words to a room full of strangers he may end up talking to face to face. Getting one of those wrong or registering him for an event he can't actually attend is a materially different kind of mistake than a bad cold DM. This is the "fork where the paths lead to outcomes he'd actually care about choosing between" case from the fleet autonomy rule, not routine execution.

So: draft the form answers (reusing his own framing — reference aictrl, reference genuine AI safety engagement, keep the tone he actually used for the LIaiSE form on 2026-08-07 as the style reference) and calendar-check the date, then send the draft to DM `<YOUR_TELEGRAM_DM_CHAT_ID>` for a one-line yes/no before submitting anything. Do not re-ask on a second identical event type once he's approved the general pattern once or twice — ask again only if a form asks something materially new (e.g. a video submission, a team-formation question) the existing draft style doesn't cover.

### 3. Attendee discovery — where the guest list is public

Luma event pages often expose a public guest list (name + avatar, sometimes a linked X/Twitter or Instagram icon) even before you're registered — confirmed 2026-08-07 on the LIaiSE event (18 names visible). This is the raw attendee pool.

**Known limitation, confirmed 2026-08-07:** the guest-list view often shows first-names-only or partial names with no company/title, which is too thin for reliable Apollo enrichment on its own (Apollo people-match needs at least a full name, ideally + company or LinkedIn). Two ways to get richer data:
- If any attendee has a linked X/Twitter icon, that handle is a stronger identity signal than a bare first name — worth a manual profile check before enrichment.
- Luma sometimes shows fuller attendee profiles (full name, one-line bio) once you're registered and viewing your own event page rather than the pre-registration guest-list teaser — re-check after Vas's registration is confirmed for events where this skill is doing outreach.

Do not force an enrichment match on a thin signal (single first name, no other context) — a wrong match means outreach lands on the wrong person's profile, which is worse than skipping them. Skip and note "insufficient identity signal" rather than guessing.

### 4. Enrichment

For attendees with enough signal (full name + company, or a linked social profile): run the same Apollo people-match / LinkedIn search used by `prospect-research`. Do not re-invent enrichment logic here — call into the existing helper.

### 5. Outreach — feed the existing pipeline, don't build a new one

Qualifying attendees (real identity match + fits the aictrl ICP — traditional/lagging AI adopters, not AI-safety researchers themselves, since researchers aren't the buyer) get added to the CRM `Log` tab exactly like an Apollo-sourced lead, with a Notes-column tag `source: <event name> attendee, <date>` so the existing `aictrl-linkedin-outreach` / `aictrl-crm-qualify` / `email-sequencer` cron pipeline picks them up on its normal schedule — this skill does not send anything itself. The event-source tag is what lets a human message reference the shared event authentically ("saw you were at the LIaiSE hackathon too") rather than reading as generic outreach, which is a genuinely different and better hook than the existing post-scrape technique.

**Important ICP nuance for this source:** most hackathon attendees ARE the AI-safety-native audience aictrl's ICP correction (2026-07-23) explicitly steers away from — the ICP is "traditional/lagging adopters", not people already deep in AI safety. Only attendees whose day job is at a company that fits the existing ICP (an engineering leader at a non-AI-first company who happens to personally care about AI safety) are real leads; a full-time AI safety researcher or someone job-hunting in the space is not. Run the normal `aictrl-crm-qualify` gate on every event-sourced candidate — do not skip the ICP check just because the source felt warm.

## Digest format — hyperlink rule (added 2026-08-08, Vas)

Every digest this skill prints (interactive or cron) must follow the global no-raw-links rule in style.md: **never** print a bare URL — wrap the descriptive text in the link. Specifically for event digests:
- Each event's line leads with its name **as the hyperlink** to its primary listing page: `[Hackathon | Translating AI Safety](https://luma.com/b4myja5u)`, not the name followed by a separate bare URL.
- When an event has a **second, distinct page** — e.g. a separate application/registration form from its main listing — give that second link its own short anchor inline, e.g. `([apply](https://...))` or `([register](https://...))`, right after the name. Never leave a second URL bare either.
- Caught 2026-08-08: a run correctly hyperlinked one event (the AI safety hackathon) and printed the other two as name-then-bare-URL — apply this to every event in a digest, not just the first.

## Digest formatting — HTML, not markdown (added 2026-08-09, Vas)

This skill's digests go out via the Telegram MCP `reply` tool (default `parse_mode: HTML`), NOT via a cron wrapper's `tg-send.py` — so the markdown auto-render that tg-send.py does (`**bold**` → bold) does not apply here, and literal `**Events found**` renders as literal asterisks. Every digest must use real HTML per the fleet style rules:
- Section headers: `<b>Events found</b>`, not `**Events found**`.
- List items: `•` bullets, not `-`.
- Every event name is the hyperlink itself: `<a href="https://...">Hackathon | Translating AI Safety</a>`, per the existing hyperlink rule above — this replaces the markdown `[text](url)` form shown in that section, which is also not valid in HTML mode.
- Close with a short "what this means" line synthesizing the batch (new vs. previously-seen, anything time-sensitive), not just a bare list — matches the digest-synthesis rule applied to the PostHog and other daily digests.

## Cron

Not yet wired to crontab — first live run should be manual/interactive so the discovery quality and the registration-approval flow can be checked against a real form before it's unattended. Once validated on 2-3 events, add a weekly cron (Monday, alongside the config-drift-check slot) invoking this skill via `claude -p --allowedTools Skill` per the fleet cron rule, discovery + enrichment + CRM-append only — no send tools, no registration-submit tools in the cron's allowlist, ever.

## Known state as of 2026-08-07 (first build)

- Discovery run confirmed two genuinely upcoming Apart Research sprints: **Digital Minds Research Sprint** (14-16 Aug 2026, online + in-person) and **AI Incident Response Sprint** (11-13 Sep 2026, online + in-person) — https://apartresearch.com/sprints. In-person venue city not yet confirmed for either; check the linked Notion calendar before registering.
- LIaiSE "Translating AI Safety" (22 Aug 2026) form drafted, sent to Vas for the two fields only he can answer (dietary requirements, how he heard about it) — not yet submitted, awaiting his go/no-go per the approval-gate above.
- Attendee list for LIaiSE pulled (18 names) but not yet enriched — mostly first-names-only, needs the richer-profile re-check post-registration per step 3.

Related skills: `hackathon-finder` (secretary, general/hardware hackathons — different purpose), `prospect-research`, `aictrl-crm-qualify`, `aictrl-linkedin-outreach`, `email-sequencer`.
