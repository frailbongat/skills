# skills

My agent skills, and the setup that puts every skill I use back on a new machine.

Two things live here:

- the skills I wrote, in `skills/`, symlinked into every coding agent on the machine
- the list of skills other people wrote that I install, in [SKILLS.md](SKILLS.md), which `bootstrap.sh` reinstalls for me

Take the whole thing or copy one skill out of `skills/`. My skills are MIT. Everything in SKILLS.md belongs to whoever wrote it.

## Quick start

```bash
git clone https://github.com/frailbongat/skills.git ~/skills
cd ~/skills && ./bootstrap.sh
```

`bootstrap.sh` does two jobs:

1. installs each skill in [SKILLS.md](SKILLS.md) with `npx skills add`
2. runs `install.sh`, which symlinks the skills in this repo into each agent

Skip step 1 with `./bootstrap.sh --skip-managed` if you only want my skills. It needs `npx`, plus `jq` or `python3` to read the lock file.

## The skills I wrote

- **paseo-delegation** routes a task to the right [Paseo](https://paseo.sh) subagent profile: scout, researcher, worker, reviewer, or oracle.
- **ship-or-refs** decides whether the closing sentence of an agent turn should close a ticket or run `/ship refs`.

Each is a folder with a `SKILL.md` in it, which is all the skill format needs.

I lean on `unslop` for every writing task, but I did not write it. It is [backnotprop's](https://github.com/backnotprop/pstack), so it is listed in SKILLS.md and installed from there.

## Install

`install.sh` creates one symlink per skill in each of these directories, and skips any that does not exist on the machine:

- `~/.agents/skills` (Codex, pi, and anything else reading the shared location)
- `~/.pi/agent/skills`
- `~/.claude/skills`
- `~/.config/crush/skills`
- `~/.config/devin/skills`

Re-running it is safe. It replaces its own symlinks and leaves real folders alone unless you pass `--force`.

Symlinks mean an edit in this repo reaches every agent at once, with no copy step.

## Skills I did not write

Twenty seven skills sit in `~/.agents/skills` that are not mine:

- twenty installed by the [Skills CLI](https://skills.sh), which records them in `~/.agents/.skill-lock.json`. These are the ones in [SKILLS.md](SKILLS.md), and the ones `bootstrap.sh` reinstalls.
- six Paseo skills that the Paseo app installs and updates itself
- `impeccable`, installed by `npx impeccable`, which writes a different copy per agent with that agent's paths in it

No copy of any of them is committed here. Their repos own them, a vendored copy would go stale, and the license is theirs to set.

Run `./sync.sh` after installing or updating a skill. It copies `~/.agents/.skill-lock.json` into the repo and regenerates `SKILLS.md` from it, so the table can never disagree with what `bootstrap.sh` installs.

## Layout

```
skills/<name>/SKILL.md      a skill I wrote
SKILLS.md                   the third-party skills, generated, one install command each
bootstrap.sh                new machine: install those skills, then run install.sh
install.sh                  symlink each skill in this repo into every agent's skills directory
sync.sh                     refresh reference-skill-lock.json and SKILLS.md from this machine
lockfile.sh                 shared lock file reader used by bootstrap.sh and sync.sh
reference-skill-lock.json   copy of this machine's Skills CLI lock file
```
