# tidy_mac v3 — design

**Goal:** turn `tidy_mac.sh` from an eight-action script into a feature-rich, safe, scriptable Mac tidy-up tool, while staying a single dependency-free Bash 3.2 file (macOS stock bash).

## Interface

```
tidy_mac.sh [COMMAND] [TASK|GROUP|PROFILE ...] [OPTIONS]
```

Commands: `run` (default), `list`, `scan`, `all`, `large [N]`, `schedule install daily|weekly|remove|status`, `config init|show|path`, `completion bash|zsh`, `version`, `help`.

Options: `-n/--dry-run`, `-i/--interactive`, `-y/--yes`, `-v/--verbose`, `-q/--quiet`, `--json`, `--trash` (move user files to Trash instead of `rm`), `--permanent` (explicit rm; the default), `--older N` (days; applies to downloads/installers/screenshots), `--exclude GLOB` (repeatable), `--profile NAME`, `--no-color`, `--version`, `-h`.

Legacy short flags stay: `-s [days]`, `-x [days]`, `-d`, `-c`, `-l`, `-b`, `-f`, `-t`, `-a`.

## Tasks

Each task has an id, a group, a description, `sudo` flag, `opt-in` flag (excluded from `all`), `destructive` flag (prompts unless `--yes`, and is skipped without `--yes` when stdin is not a TTY), a `scan` function (reclaimable bytes) and a `run` function.

| Group | Tasks |
|---|---|
| files | screenshots-move*, screenshots-delete*†, downloads*†, installers*†, trash, dsstore |
| system | caches, system-caches (sudo), logs (sudo), crash-reports (sudo), quicklook, font-cache (sudo), mail-cache, tm-snapshots*† (sudo), purge* (sudo) |
| apps | app-caches (Slack, Discord, VS Code, Teams, Zoom; skipped while running) |
| browsers | browser-history, browser-cache, browser-cookies*† (Chrome/Brave/Edge/Arc/Vivaldi/Chromium, Safari, Firefox; skipped while running) |
| network | dns (sudo) |
| dev | xcode, xcode-archives*†, simulators, homebrew, node, python, go, rust, jvm, cocoapods, docker*† |

`*` opt-in, `†` destructive.

Profiles: `quick` (caches quicklook logs trash dns), `standard` (= `all`), `deep` (all + browser-cache + dsstore + tm-snapshots), `dev` (dev group). Groups are also selectable by name.

## Safety
- Every removal goes through `remove_paths`, which refuses `/`, `$HOME`, and anything outside `$HOME`, `/Library`, `/var/log`, `/private/var`, `/Volumes`.
- Dry-run prints exactly what would go, with sizes; never calls external mutators.
- Protected cache list (configurable) is honoured by `caches`.
- Browser/app tasks skip when the app is running (`pgrep`).
- Trash mode moves into `~/.Trash` with collision-safe names.
- Per-run manifest under `~/.local/share/tidy_mac/runs/`; log at `~/.tidy_mac.log`, rotated at 1 MB.

## Output
- Colour when TTY and not `NO_COLOR`/`--no-color`.
- Summary table: task, status (done/skipped/dry-run/failed), reclaimed; total; disk free before/after.
- `--json`: `{version, dry_run, tasks:[{id,status,bytes}], total_bytes, free_before_kb, free_after_kb}`.

## Config
`~/.config/tidy_mac/config`, `KEY=VALUE`, whitelisted keys only (never sourced): `OLDER_DAYS`, `SCREENSHOT_DAYS`, `SCREENSHOTS_DIR`, `EXCLUDES` (colon-separated globs), `PROTECTED_CACHES`, `EXTRA_CACHE_DIRS`, `DEFAULT_TASKS`, `USE_TRASH`, `COLOR`.

## Scheduling
`schedule install daily|weekly [tasks...]` writes `~/Library/LaunchAgents/com.orchardroot.tidy-mac.plist` running the script with `--yes --quiet` (+ given tasks, default `all`) and loads it; `status`, `remove`.

## Testability
Env overrides used only by tests: `TIDY_MAC_SYSTEM_ROOT` (prefix for `/Library`, `/var/log`, `/Volumes`, `/private/var`), `TIDY_MAC_NO_SUDO=1`, `TIDY_MAC_NO_EXTERNAL=1` (external mutators are appended to `$TIDY_MAC_CMD_LOG` instead of run), `TIDY_MAC_FAKE_RUNNING` (comma list of "running" apps), `TIDY_MAC_LAUNCH_AGENTS_DIR`. Tests set `HOME` to a temp dir. `tests/run_tests.sh` is plain bash.
