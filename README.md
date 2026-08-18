# mac-cleanup

`tidy_mac.sh` — a small Bash script that tidies the bits of a Mac that quietly fill up: the Desktop screenshots, the Downloads folder, caches, logs, browser history, the DNS cache and the Trash.

I wrote it because my Desktop is where screenshots go to die, and because on a work machine "clear it all out" needs to be a deliberate, logged, dry-runnable action rather than a Finder rampage. Every action is optional, every action can be dry-run, and everything it does is written to `~/.tidy_mac.log` so I can see what I did to myself last Tuesday.

## What it can do

| Action | Flag |
|---|---|
| Move Desktop screenshots older than N days into `~/Desktop/Screenshots` | `-s [days]` (default 1) |
| Delete Desktop screenshots older than N days | `-x [days]` (default 1) |
| Delete everything in `~/Downloads` | `-d` |
| Clear system and application caches | `-c` |
| Delete old system and user logs | `-l` |
| Clear Chrome / Safari / Firefox history | `-b` |
| Flush the DNS resolver cache | `-f` |
| Empty the Trash | `-t` |
| **Run all** of `-d -c -l -b -f -t` (screenshots excluded — those are your call) | `-a` |

And the modifiers:

| Modifier | Flag |
|---|---|
| Interactive — confirm before each action | `-i` |
| Dry run — say what would happen, change nothing | `-n` |
| Verbose — list every file touched | `-v` |
| Help (also what you get with no arguments) | `-h` |

## Usage

```bash
./tidy_mac.sh -a -i          # everything, but ask me first
./tidy_mac.sh -n -d -t       # what *would* clearing Downloads and Trash do?
./tidy_mac.sh -s 30 -c       # archive screenshots older than 30 days, clear caches
./tidy_mac.sh -x 7 -f -i     # delete week-old screenshots and flush DNS, interactively
```

Start with `-n`. Then `-i`. Then, once you trust it, `-a` — but the screenshot options are never part of `-a`, because deleting screenshots is the one thing people regret.

## Good to know

- Some actions (system caches, system logs, DNS flush) need `sudo`; the script asks when it gets there.
- It won't fall over if something isn't installed — no Firefox, no Firefox history to clear, move on.
- Browser history is skipped if that browser is running, so it can't corrupt a live history database.
- Everything is logged to `~/.tidy_mac.log`.

## Licence

MIT — see [LICENSE](LICENSE).

---

*orchardroot — made in Cheshire, under the supervision of two cats, neither of whom tidies up after themselves.*
