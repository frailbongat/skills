# skills

The skills I wrote myself. Every coding agent on this machine reads them from here through a symlink.

## Layout

```
skills/<name>/SKILL.md      the skill itself
install.sh                  links each skill into every agent's skills directory
reference-skill-lock.json   copy of ~/.agents/.skill-lock.json, see "skills I did not write"
```

## Install

```bash
git clone git@github.com:frailbongat/skills.git ~/skills
cd ~/skills && ./install.sh
```

`install.sh` creates one symlink per skill in each of these directories, and skips any that does not exist on the machine:

- `~/.agents/skills` (Codex, pi, and anything else reading the shared location)
- `~/.pi/agent/skills`
- `~/.claude/skills`
- `~/.config/crush/skills`
- `~/.config/devin/skills`

Re-running it is safe. It replaces its own symlinks and leaves real folders alone unless you pass `--force`.

## Skills I did not write

Twenty five other skills sit in `~/.agents/skills` and are not in this repo, because their upstream repos own them:

- nineteen from `mattpocock/skills` and `vercel-labs/skills`, installed through a skill manager that records them in `~/.agents/.skill-lock.json`
- six Paseo skills that the Paseo app installs
- `impeccable`, installed by `npx impeccable`, which writes a different copy per agent with that agent's paths in it

`reference-skill-lock.json` lists the source repo, path, and hash for each managed skill, so a new machine can reinstall them instead of copying stale files.
