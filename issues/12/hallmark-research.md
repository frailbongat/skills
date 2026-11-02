# Hallmark (usehallmark.com) for /design-explore: research (Nov 2, 2026, UTC+8)

## Verdict
Yes, as a trial. Add it as one more variant source (the theme deck), and add its `sloplint --render` as a check in the scoring step. It's free, MIT-licensed, needs no key, and runs locally. Main risks: it targets landing and marketing pages more than app screens, and it changes fast (my take).

## Best links
- https://github.com/nutlope/hallmark: README, install, MIT license, scripts (the primary source)
- https://www.usehallmark.com/: site, FAQ on keys, redesign and design.md support (vendor, slanted)
- https://readmodelmag.com/stories/hallmark-v2-design-skill: independent write-up with the per-harness caveats

## 5 answers
1. **What it is:** an agent skill, not an MCP server or an API. Install with `npx skills add nutlope/hallmark -g` (Node 18+). It works in Claude Code, Codex, Cursor and OpenCode, and there's also a Claude Code plugin. Verbs: build, `/hallmark redesign <path>`, `/hallmark audit <path>`. The `sloplint.mjs` linter runs from the CLI on its own. (README)
2. **Price and license:** free, MIT. There's no paid tier: /pricing returns 404, and no price was found anywhere (no source for any paid tier).
3. **What it adds over impeccable, taste, emil and awwwards:**
   - Generation: 50 themes ("a paper, type, palette and a way with photographs"). It deals three per prompt, and layouts change on every build. It logs past builds in `.hallmark/log.json` and fails a run that repeats recent structures (README; HN comment).
   - Checking: a mechanical linter that renders the page at eight widths, with tiered gates (Floor, Reflex, Finish), plus a fresh-context reviewer (README, MODEL). As far as I know, our current sources are mostly style guidance, so a runnable linter is the new part (my take, no source on how each one checks).
   - It reads your tokens and `design.md` first (site FAQ), which fits "lock one plus steals" (my take).
4. **Risks:**
   - Key: none needed. An optional `TOGETHER_API_KEY` turns on image generation, which sends prompts to Together AI (repo scripts/imagegen.mjs).
   - Other outbound calls I saw in the scripts: Wikimedia photos, Google Fonts and Fontshare links on pages, and a local Chrome via puppeteer-core. I saw no upload of code or screenshots, but I only ran a quick grep, not a full audit (my take).
   - Lock-in: low. It's plain HTML and CSS plus markdown rules.
   - Fit: "not for app UIs" (andrew.ooo, slanted, and some of its numbers don't match HN). It's built for pages, not dashboards (my take).
   - Parity across tools: the edit-time hook is Claude Code only. Codex and OpenCode get only the final sloplint sweep (MODEL).
5. **Maturity:**
   - Made by Hassan El Mghari (@nutlope) at Together AI (README, MODEL).
   - Repo created Apr 28, 2026 (UTC+8). Last push Oct 30, 2026, 12:50 AM UTC+8. 45,545 stars, 2,420 forks, 75 open issues (GitHub API, Nov 2).
   - v2.0.0. #2 AI repo on GitHub's weekly trending for Oct 27 to Nov 2, behind impeccable (X post by @kd_reraflow).
   - Reviews: HN (7 points, 9 comments) is mixed. Some say results "still look like slop" unless the prompt is very specific.

## Fit in /design-explore (my take)
- As a variant source: one variant per run from `theme.mjs deal`, or a "custom" run.
- As a check: run `sloplint --render` on every variant and fold its fail/warn counts into the design-rule score.
- Pin a commit, because the theme and gate counts have changed across versions (20 → 48 → 50 per sources).
- Keep the optional image key off.

## Link check (curl -sIL, Nov 2, 2026)
- 200:
  - usehallmark.com
  - github.com/nutlope/hallmark
  - SKILL.md on GitHub
  - readmodelmag.com story
  - andrew.ooo review
  - x.com/WakeAlen post
  - x.com/kd_reraflow post
- news.ycombinator.com/item?id=49058547: 405 on HEAD, 200 on GET. Kept.
- 404, dropped: usehallmark.com /pricing, /docs, /llms.txt, /terms, /privacy, /sitemap.xml, /robots.txt. The site has no terms or privacy page.
