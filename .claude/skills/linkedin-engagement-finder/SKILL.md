---
name: linkedin-engagement-finder
description: Finds and ranks LinkedIn posts worth liking or commenting on for a B2B social-selling / founder-led-growth motion, and drafts the comments in your configured voice. Use this skill proactively for ANY LinkedIn engagement task that is not a DM or a connection request, including "find posts to comment on", "find posts to like", "what should I engage with or react to today", "warm up my prospects or connections", "do my LinkedIn engagement for the day", "draft comments on posts in my space", "who has posted recently that I should react to", or "pull my feed and tell me what is worth liking" — even if the user does not say the word "skill". It pulls the operator's home feed AND (if a prospect source is configured) the recent posts of their tracked prospects, ranks everything by topic/thesis fit + relationship value, drafts on-brand comments, and optionally logs surfaced posts to a sheet for dedupe + history. READ-ONLY on LinkedIn — there is no like/comment API, so it surfaces + drafts and the human clicks. Reads an optional per-project config for voice, thesis, prospect source, and log target; falls back to feed-only with sensible B2B defaults. SKIP when the task is actually sending a connection request or a DM, or replying in the inbox; researching one specific person before outreach (use prospect-research); bulk-sourcing new candidates; writing an original post to publish; or reviewing code or PRs. NEVER sends DMs or connection requests.
---

# LinkedIn Engagement Finder

Find the LinkedIn posts where a like or a thoughtful comment does the most good for a B2B relationship-building motion, and hand back ready-to-post comment drafts. Engaging a prospect's own recent post (especially while a connection invite is pending) measurably lifts accept and reply rates, so tracked-prospect posts rank highest; on-topic feed posts build credibility with the wider audience you sell to.

**Hard reality this skill is built around:** the LinkedIn MCP can *read* (feed, a person's posts) but cannot *like* or *comment*. So this skill never claims to have engaged anything. It surfaces opportunities + drafts the comment text; the operator does the actual click (about two minutes by hand). Be honest in the output — never imply a post was liked or commented.

This skill is **generic and shareable**. All project-specific detail (voice, what topics matter, where prospects live, where to log) comes from a config file. With no config it still works: feed-only, B2B defaults, and it asks for the one or two things it genuinely needs.

## Project config

Look for a config in this order: (1) a path the operator passes in the invocation; (2) `.claude/linkedin-engagement-finder.md` in the working tree; (3) none → feed-only fallback. The config is plain markdown; read these fields (all optional except where noted):

```markdown
# linkedin-engagement-finder — <project> config

## Identity
expected_handle: <linkedin username/slug to verify via get_my_profile, e.g. "janedoe">

## Voice
<the comment voice spec, OR "see <other-config-path>" to reuse an existing voice file>
<the skill's built-in anti-AI-tell rules below always apply on top of this>

## Thesis / relevance
<1–3 sentences: what this person sells / builds, and the topics that make a post worth
engaging. Used to score feed posts. e.g. "We sell observability for data pipelines;
engage posts about data quality, dbt/CI, on-call, AI-assisted data work.">
soft_product_mention: <the one-line, low-key way to reference the product when natural>

## Prospect source (optional — omit for feed-only)
spreadsheet_id: <id>
tab: <tab name>
columns: { name: B, company: D, slug: H, status: W }     # A1 column letters
statuses_to_include: [pending, accepted]                  # which rows to warm
max_prospects_per_run: 15

## Engagement log (optional — omit to skip logging)
spreadsheet_id: <id>
tab: <tab name>            # created with the standard A–L header if missing

## Guards (optional)
extra_guards: <e.g. "do not post to any chat/Telegram channel">
```

If no config is found, tell the operator you're running feed-only and ask them for a one-line **thesis** (so relevance scoring isn't blind) and their **handle** (to verify identity). Don't block on the optional pieces.

## B2B defaults (baked in, override via config)

- **Relevance = topic/thesis fit × relationship value.** A post is worth engaging if it's on the operator's thesis topics, OR the author is someone they're building a relationship with (tracked prospect > 1st-degree connection > cold 2nd/3rd).
- **Caps:** ~20 feed posts, ~15 tracked prospects, surface ~8–12 opportunities. A short sharp list beats a long one.
- **Comment rules (this is where the value lives):**
  - Add a real point — react to the specific claim, extend it, or respectfully push back. Never "Great post!" or a paraphrase.
  - Keep it short, 2–4 sentences. A comment longer than the post reads as hijacking.
  - At most one soft product mention, and only where it's genuinely natural. On most posts, say something smart and *don't* mention the product — credibility compounds, pitching in comments repels.
  - Ending on a real question often earns a reply. Use it when you actually want their answer.
- **Anti-AI-tell rules (always on — bot-sounding comments defeat the purpose):** no em-dashes in the comment body (use commas/periods/parentheses); use contractions; vary sentence length (mix a 3–5 word sentence with a longer one); no "leverage/foster/delve/robust/cutting-edge/game-changing"; no "not X but Y" parallelism; no greeting filler; no exclamation marks; pick one spelling convention and hold it. If a phrase could sit on a SaaS landing page, rewrite it.

## Cost discipline

Raw scrape output (feed HTML, per-person post dumps) is the expensive part, not the ranking. Keep it out of the caller's context:
- **Scrape in subagents.** One subagent for the feed, batched subagents for prospect posts (≤5 prospects each), each returning a compact JSON list of candidate posts. The caller stays lean.
- A mid model (Sonnet) is the right default for these subagents — capable enough to judge relevance and pull a clean snippet.
- Stop once you have enough good candidates; don't scroll forever.

## Sheets MCP family (only if a sheet source/log is configured)

Prefer `mcp__google_workspace__*` (`read_sheet_values`, `modify_sheet_values`); if only `mcp__google-sheets__*` is loaded, the equivalents are `get_sheet_data` (read), `update_cells` / `batch_update_cells` (write), `create_sheet` (new tab), `list_sheets`. Detect which is present; if a sheet is configured but neither family is available, warn and degrade to feed-only.

## Workflow

### 0. Preflight
1. **Load config** (per the order above). If none, announce feed-only mode and collect the thesis + handle.
2. **Identity** — `get_my_profile`; confirm it matches the configured `expected_handle`. If it's someone else, ABORT: the engagement must run on the intended account.
3. **Log tab** — if an engagement log is configured, `list_sheets`; create the tab with the §7 header if missing.

### 1. Build the prospect set (if a prospect source is configured)
Read the configured sheet/columns. Select rows whose status is in `statuses_to_include`. Rank **accepted/connected first** (stay visible to a live relationship), then **pending** (engagement nudges the invite). Take the top `max_prospects_per_run` by most-recent activity. Keep each prospect's slug + source row number. If no source is configured, skip to the feed only.

### 2. Build the dedupe set (if a log is configured)
Read the log's Post URL column → `engaged_urls`. Drop any candidate already there so each run is fresh. Normalise URLs (strip query strings) before comparing.

### 3. Scrape candidate posts (subagents)
**Feed subagent** (one): `get_feed num_posts=20`. Return compact JSON per post: `{author, headline, degree, posted_age, snippet (≤300 chars), url, raw_relevance(high/med/low to the thesis topics)}`. Drop obvious noise (engagement bait, unrelated personal, generic motivational, ads) and posts with no usable URL.

**Prospect subagents** (batched, ≤5 each): for each, `get_person_profile(linkedin_username=slug, sections="posts", max_scrolls=3)`; return the most recent post within ~30 days: `{name, slug, source_row, status, post_age, snippet, url, url_is_permalink(bool)}`, or `recent_post: null`. **URL caveat:** the posts section often does NOT expose a clean per-post permalink. When none is available, return `https://www.linkedin.com/in/<slug>/recent-activity/all/` with `url_is_permalink=false`. Never fabricate an activity id.

Collect all candidates; drop any whose url is in `engaged_urls`.

### 4. Score and rank into tiers
- **Tier 1 — Connected/accepted prospects' recent posts.** Highest value; always draft a comment.
- **Tier 2 — Pending prospects' recent posts.** Draft a comment (or like-only if thin/off-topic).
- **Tier 3 — On-thesis feed posts.** Strong topic fit, 1st-degree weighted up over cold. Draft for the best few; mark the rest like-only.

Drop anything that's neither a tracked person nor genuinely on-thesis.

### 5. Draft comments
For Tier 1–2 and the strongest Tier 3 items, draft ONE comment each, following the configured voice + the always-on anti-AI-tell rules + the B2B comment rules above. Mark worth-a-touch-but-not-words items as **like-only**.

### 6. Output to terminal
Lead with the honest framing (manual click), then the ranked list, Tier 1 first:
```
[Tier N] <Author> (<prospect status / degree>) — <one-line why it matters>
  Post: <url>   (<age>)
  Action: comment | like-only
  Draft: <comment text, or "—" for like-only>
```
When `url_is_permalink=false`, append `(most recent post — open their recent-activity and grab the top one)`. End with a one-line reminder that the like/comment is manual.

### 7. Log (if a log is configured)
Append one row per surfaced opportunity (dedupe + history). Header / schema:

| Col | Field |
|---|---|
| A | Date (UTC) |
| B | Author Name |
| C | Company (blank for feed authors) |
| D | Author Type (`accepted` / `pending` / `feed-1st` / `feed-cold`) |
| E | Source Row (prospect row number, else blank) |
| F | Post URL (dedupe key) |
| G | Post Summary (≤200 chars) |
| H | Suggested Action (`comment` / `like`) |
| I | Tier |
| J | Relevance reason (short) |
| K | Drafted Comment (blank for like-only) |
| L | Status (`surfaced`; operator can later edit to `posted` / `skipped`) |

Append after the last non-empty row. Write only to the configured log tab.

### 8. Summary
Print counts by tier, comments-drafted vs like-only, prospects with no recent post, and the log link if used.

## Known issues / failure modes

| Symptom | Action |
|---|---|
| Not logged in as the configured handle | Abort — engagement must run on the intended account |
| No config found | Run feed-only; ask for thesis + handle; skip prospect-source and logging |
| Feed is mostly noise | Normal — keep only on-thesis + tracked-person posts; surface fewer rather than padding |
| A prospect has no recent posts | Fine — return null, move on; most people post rarely |
| Prospect post has no clean permalink | Expected — return the `/in/<slug>/recent-activity/all/` URL with `url_is_permalink=false` and label it; don't fabricate an activity id |
| Sheet configured but no sheets MCP | Warn, degrade to feed-only (no source, no logging) |
| Tempted to "like"/"comment" via a tool | STOP — there is no such tool; surface + draft only |
| About to draft a salesy comment on an unrelated post | STOP — at most one soft mention, only where natural; default to value without pitching |
| About to send a DM / connection request | STOP — not this skill's job |

## Why this skill exists

B2B selling works through presence, not just direct messages: showing up thoughtfully on a prospect's posts before and after a connection request lifts accept and reply rates, and consistent on-topic commenting builds the operator's credibility with the audience they sell to. Doing this by hand means scrolling a noisy feed daily and re-checking who's posted. This skill encodes the find-rank-draft loop, prioritises the people already in the pipeline, and keeps drafts in a configured voice — while being honest that the click stays human.

Configure it per project with a `linkedin-engagement-finder` config (voice, thesis, prospect source, log target). Related: `prospect-research` (per-person briefs + outreach drafts) is the natural sibling — same read-only, config-driven, subagent-cost-discipline design.
