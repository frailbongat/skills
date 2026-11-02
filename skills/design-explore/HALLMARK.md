# Hallmark

Hallmark is pinned to commit `4f6a46c6dc325d40ab268c93e25c7b96676ebccd` of `nutlope/hallmark`. Leave `TOGETHER_API_KEY` unset, since image generation is the feature that sends data to Together AI. The check fails when the key is set.

## Install

Run these outside any repo. They need Node 22.20 or newer, because `skills@1.7.4` requires it.

```sh
env -u CLAUDE_CONFIG_DIR DISABLE_TELEMETRY=1 DO_NOT_TRACK=1 npx --yes skills@1.7.4 add "nutlope/hallmark#4f6a46c6dc325d40ab268c93e25c7b96676ebccd" -g -a claude-code universal -y </dev/null
npm i -g puppeteer-core@25.16.0
~/skills/hide-skills.sh
~/.claude/skills/design-explore/check-hallmark.sh
```

- `npx skills add nutlope/hallmark -g` alone installs the latest commit, so keep the `#<sha>`.
- `-a claude-code universal` puts the files in `~/.agents/skills/hallmark` with a link from `~/.claude/skills/hallmark`. `env -u CLAUDE_CONFIG_DIR` keeps a session's config folder from receiving a second copy.
- `--render` needs `puppeteer-core` and a browser, not one or the other. Install Chrome, or set `CHROME_PATH` to a Chrome or Chromium binary.
- `hide-skills.sh` stops Hallmark from firing on any design request. Run it after every install or update, since those wipe its stamp.

The check prints the Mac's name, one line per check, and `PASS` or `FAIL`. It exits 0 only on `PASS`.

## Score a variant

Run this from the scratch folder in step 7, because `--render` writes screenshots to `.hallmark/` under the current folder. Pass absolute paths. `<files>` is the variant's `<id>.<ext>` and every `<id>.<part>.<ext>`, or the view file for `current`. Use `--scope app` for a screen and `--scope component` for a component.

```sh
node ~/.agents/skills/hallmark/scripts/sloplint.mjs <files> --url "<page-url>?variant=<slug>:<id>" --scope app --json > <id>.json
```

- `--url` turns on `--render`. `--render` alone cannot reach a variant, because it renders only `.html` files.
- Exit 1 means the linter found a FAIL, which is a normal score. Exit 2 means a bad command, so fix the command.
- Read `summary.fails`, `summary.warns`, and `summary.render` from the JSON. Report one row per id with those 3 values.
- `summary.render` must read `ran`. Say so in the report when it reads anything else, because the counts then come from source alone.
- Expo has no page to render unless the app runs on Expo web. Drop `--url` when it does not, and report `render: off`.

The page around a variant adds the same findings to every id, so compare counts between ids. A score informs the pick, and the brand lock still wins over any finding.
