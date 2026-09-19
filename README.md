# skills

My agent skills, and the setup that puts every skill I use back on a new machine.

Two things live here:

- three skills I wrote, in `skills/`, symlinked into every coding agent on the machine
- `reference-skill-lock.json`, a record of the third-party skills I install, so `bootstrap.sh` can fetch them again

Take the whole thing or copy one skill out of `skills/`. Everything is MIT.

## Quick start

```bash
git clone https://github.com/frailbongat/skills.git ~/skills
cd ~/skills && ./bootstrap.sh
```

`bootstrap.sh` does two jobs:

1. reinstalls the third-party skills listed in `reference-skill-lock.json` with `npx skills add <owner/repo@skill> -g -y`
2. runs `install.sh`, which symlinks the skills in this repo into each agent

Skip step 1 with `./bootstrap.sh --skip-managed` if you only want my three skills. It needs `npx`, plus `jq` or `python3` to read the lock file.

## The skills I wrote

- **unslop** cuts AI tells from any writing. A numbered rule list, from em dashes and "delve" to passive voice and mannered prose. Other skills cite the rule numbers, so they are stable.
- **paseo-delegation** routes a task to the right [Paseo](https://paseo.sh) subagent profile: scout, researcher, worker, reviewer, or oracle.
- **ship-or-refs** decides whether the closing sentence of an agent turn should close a ticket or run `/ship refs`.

Each is a folder with a `SKILL.md` in it, which is all the skill format needs.

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

Twenty six other skills sit in `~/.agents/skills` and are not in this repo, because their upstream repos own them:

- nineteen from `mattpocock/skills` and `vercel-labs/skills`, installed with the [Skills CLI](https://skills.sh), which records them in `~/.agents/.skill-lock.json`
- six Paseo skills that the Paseo app installs
- `impeccable`, installed by `npx impeccable`, which writes a different copy per agent with that agent's paths in it

`reference-skill-lock.json` is a copy of `~/.agents/.skill-lock.json`. It lists the source repo, path, and hash of every skill the Skills CLI manages, which is what lets `bootstrap.sh` reinstall them instead of vendoring stale copies.

Run `./sync.sh` after installing or updating a skill. It copies the live lock file over the one in the repo and prints the diff, so the next commit records the change.

The Paseo skills and `impeccable` are not in the lock file. `bootstrap.sh` prints a reminder about both when it finishes.

## Layout

```
skills/<name>/SKILL.md      a skill I wrote
bootstrap.sh                new machine: reinstall third-party skills, then run install.sh
install.sh                  symlink each skill in this repo into every agent's skills directory
sync.sh                     refresh reference-skill-lock.json from this machine
reference-skill-lock.json   the third-party skills, and where to get them
```
