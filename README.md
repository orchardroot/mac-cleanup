# mac-cleanup

`tidy_mac.sh` — a single-file, dependency-free tool that tidies the bits of a Mac that quietly fill up: caches, logs, the Trash, Downloads, Desktop screenshots, browser leftovers, and the several gigabytes every developer toolchain hoards behind your back.

Version 3 is a rewrite. It started life as a script that deleted screenshots older than a day, and it kept the same principles while growing up: **every action is optional, every action can be dry-run, everything it does is logged, and nothing is deleted anywhere it hasn't been explicitly told to look.** I run a SOC; I like tools that show their working before they touch anything.

```
$ tidy_mac.sh scan

  TASK                  RECLAIMABLE  NOTE
  caches                     7.2 GB
  homebrew                   2.6 GB
  trash                      2.5 GB
  system-caches              2.2 GB
  node                       2.1 GB
  browser-cache              1.4 GB  *
  python                   272.0 MB
  downloads                187.4 MB  *
  ...
  Total: 18.8 GB reclaimable  (* = opt-in, not part of 'all')
```

## Install

```bash
git clone https://github.com/orchardroot/mac-cleanup
cd mac-cleanup && ./install.sh        # symlinks tidy-mac onto /usr/local/bin
```

Or just run `./tidy_mac.sh` from the clone. It's one file; there's nothing to build. Runs on the bash 3.2 that ships with macOS.

## Usage

```
tidy_mac.sh [COMMAND] [TASK|GROUP|PROFILE ...] [OPTIONS]
```

The commands you'll actually use:

| | |
|---|---|
| `tidy_mac.sh scan` | Measure what every task could reclaim. Changes nothing. Start here. |
| `tidy_mac.sh list` | Every task, its group, and whether it needs sudo / is opt-in / is destructive |
| `tidy_mac.sh all -n` | Preview the safe set (everything not marked opt-in) |
| `tidy_mac.sh all` | Do it |
| `tidy_mac.sh caches logs trash` | Run named tasks |
| `tidy_mac.sh dev` | Run a whole group (`files`, `system`, `apps`, `browsers`, `network`, `dev`) |
| `tidy_mac.sh --profile quick` | `quick` · `standard` (= all) · `deep` (all + browser-cache, dsstore, tm-snapshots) · `dev` |
| `tidy_mac.sh large 20` | The 20 largest files in your home folder (`--min-size 500M` to change the bar) |
| `tidy_mac.sh schedule install weekly caches trash` | Run automatically via launchd (`status`, `remove`) |
| `tidy_mac.sh config init` | Write a commented config file to `~/.config/tidy_mac/config` |
| `tidy_mac.sh completion zsh` | Shell completion |

Options: `-n/--dry-run` · `-i/--interactive` (confirm each task) · `-y/--yes` · `-v/--verbose` (list every file) · `-q/--quiet` · `--json` · `--trash` (send user files to the Trash instead of deleting) · `--older N` (days) · `--exclude GLOB` (repeatable) · `--profile NAME` · `--no-color`.

The old flags still work exactly as before, so existing aliases and cron lines survive: `-s [days]`, `-x [days]`, `-d`, `-c`, `-l`, `-b`, `-f`, `-t`, `-a`, `-i`, `-n`, `-v`.

## Tasks

**files** — `screenshots-move`* · `screenshots-delete`*† · `downloads`*† (all, or `--older N`) · `installers`*† (old .dmg/.pkg/.iso/.xip in Downloads and Desktop, 30 days by default) · `trash` (home *and* every mounted volume) · `dsstore`*

**system** — `caches` (~/Library/Caches, with a protected list you can extend) · `system-caches` (sudo) · `logs` (sudo) · `crash-reports` (sudo) · `quicklook` · `font-cache`* (sudo) · `mail-cache` · `tm-snapshots`*† (sudo) · `purge`* (sudo)

**apps** — `app-caches` (Slack, Discord, VS Code, Teams, Spotify, Zoom — skipped while the app is running)

**browsers** — `browser-history` · `browser-cache`* · `browser-cookies`*† — Chrome, Chromium, Brave, Edge, Arc, Vivaldi (all profiles), Safari, Firefox (all profiles); a running browser is always skipped so its databases can't be corrupted

**network** — `dns` (sudo)

**dev** — `xcode` (DerivedData, device support, simulator caches) · `xcode-archives`*† · `simulators` · `homebrew` (`cleanup` + `autoremove`) · `node` (npm, yarn, pnpm, bun) · `python` (pip, uv, poetry) · `go` · `rust` (cargo registry) · `jvm` (gradle) · `cocoapods` · `docker`*† (`system prune`, never volumes)

`*` **opt-in** — not included in `all`; name it explicitly. `†` **destructive** — permanently deletes user data, so it prompts unless you pass `--yes` (and is skipped outright without `--yes` when there's no terminal, e.g. under cron/launchd).

## The safety story

- **Dry run is real.** `-n` prints every path that would go, with its size, and never invokes an external command (`brew`, `qlmanage`, `tmutil`…) — it prints what it *would* run instead.
- **One choke point.** Every deletion goes through a single function that refuses `/`, your home folder itself, `/System`, `/Applications`, and anything outside the handful of places it's allowed to work in.
- **Protected caches.** `caches` never touches CloudKit, Safari, `nsurlsessiond`, iCloud (`bird`), HomeKit and friends. Add your own to the list in the config.
- **Running apps are left alone.** Browser and Electron-app tasks check `pgrep` first.
- **`--exclude`** globs win over everything.
- **`--trash`** moves Downloads/screenshots/installers into `~/.Trash` (collision-safe names) instead of `rm`, if you'd like a safety net. Caches and logs are always deleted outright because trashing them is pointless.
- **Receipts.** Every run appends to `~/.tidy_mac.log` (rotated at 1 MB) and writes a manifest of exactly what was removed to `~/.local/share/tidy_mac/runs/`.
- **Nothing runs by default.** `tidy_mac.sh` with no arguments prints help; set `DEFAULT_TASKS` in the config if you want otherwise.

## Config

`tidy_mac.sh config init` writes a commented `~/.config/tidy_mac/config`. It's `KEY=VALUE`, parsed against a whitelist (never sourced), and lets you set: `OLDER_DAYS`, `SCREENSHOT_DAYS`, `SCREENSHOTS_DIR`, `PROTECTED_CACHES`, `EXTRA_CACHE_DIRS`, `EXCLUDES`, `DEFAULT_TASKS`, `USE_TRASH`, `COLOR`, `LARGE_MIN_SIZE`.

## Scheduling

```bash
tidy_mac.sh schedule install weekly caches quicklook trash    # Mondays at noon
tidy_mac.sh schedule install daily node python homebrew
tidy_mac.sh schedule status
tidy_mac.sh schedule remove
```

Installs a launchd agent (`~/Library/LaunchAgents/com.orchardroot.tidy-mac.plist`) that runs the given tasks with `--yes --quiet`, logging to `~/Library/Logs/tidy_mac.launchd.log`. Schedule tasks that don't need sudo — launchd can't type your password.

## JSON

`--json` on a run or a scan gives you something a dashboard or a fleet script can eat:

```json
{"version":"3.0.0","dry_run":false,"tasks":[{"id":"caches","status":"done","bytes":7730941132,"note":""}],"total_bytes":7730941132,"free_before_kb":834007152,"free_after_kb":841556340}
```

## Development

```bash
/bin/bash tests/run_tests.sh
```

The test suite is plain bash and runs every task against a throwaway `$HOME` and a fake system root — no sudo, no external tools, nothing on your real Mac is touched. Design notes live in [`docs/superpowers/specs/`](docs/superpowers/specs/).

## Licence

MIT — see [LICENSE](LICENSE).

---

*orchardroot — made in Cheshire, under the supervision of two cats, neither of whom tidies up after themselves.*
