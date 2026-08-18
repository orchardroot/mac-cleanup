#!/bin/bash
# Test suite for tidy_mac.sh. Plain bash, no dependencies.
# Every test runs against a throwaway $HOME and a fake system root; nothing
# on the real machine is touched, no sudo is invoked, no external tools run.
set -u
cd "$(dirname "$0")/.." || exit 1
SCRIPT="$PWD/tidy_mac.sh"
PASS=0; FAIL=0; CURRENT=""

# ---------- harness ----------
setup() {
    SANDBOX=$(mktemp -d "${TMPDIR:-/tmp}/tidymac-test.XXXXXX")
    export HOME="$SANDBOX/home"
    export TIDY_MAC_SYSTEM_ROOT="$SANDBOX/sys"
    export TIDY_MAC_NO_SUDO=1
    export TIDY_MAC_NO_EXTERNAL=1
    export TIDY_MAC_CMD_LOG="$SANDBOX/cmds.log"
    export TIDY_MAC_LAUNCH_AGENTS_DIR="$SANDBOX/agents"
    export TIDY_MAC_FAKE_RUNNING=""
    export XDG_CONFIG_HOME="$HOME/.config"
    export NO_COLOR=1
    unset TIDY_MAC_CONFIG
    mkdir -p "$HOME/Desktop" "$HOME/Downloads" "$HOME/Library/Caches" "$HOME/Library/Logs" \
             "$HOME/.Trash" "$TIDY_MAC_SYSTEM_ROOT/Library/Caches" "$TIDY_MAC_SYSTEM_ROOT/var/log" \
             "$TIDY_MAC_SYSTEM_ROOT/Volumes" "$TIDY_MAC_LAUNCH_AGENTS_DIR"
    : > "$TIDY_MAC_CMD_LOG"
}
teardown() { rm -rf "$SANDBOX"; }

run_tm() { OUT=$("$SCRIPT" "$@" 2>&1 < /dev/null); RC=$?; }

t() { CURRENT="$1"; setup; }
ok()   { PASS=$((PASS+1)); }
fail() { FAIL=$((FAIL+1)); echo "FAIL: $CURRENT — $1"; [ -n "${OUT:-}" ] && printf '%s\n' "$OUT" | sed 's/^/    | /' | head -40; }
assert_rc()      { [ "$RC" -eq "$1" ] && ok || fail "expected rc $1, got $RC"; }
assert_out()     { printf '%s' "$OUT" | grep -q -- "$1" && ok || fail "output should contain: $1"; }
assert_not_out() { printf '%s' "$OUT" | grep -q -- "$1" && fail "output should NOT contain: $1" || ok; }
assert_exists()  { [ -e "$1" ] && ok || fail "should exist: $1"; }
assert_missing() { [ -e "$1" ] && fail "should be gone: $1" || ok; }
mkfile() { mkdir -p "$(dirname "$1")"; head -c "${2:-1024}" /dev/zero > "$1"; }
oldfile() { mkfile "$1" "${2:-1024}"; touch -t 202001010000 "$1"; }   # dated 2020

# ---------- tests ----------
t "no args prints usage"; run_tm; assert_rc 0; assert_out "Usage"; teardown
t "--version"; run_tm --version; assert_rc 0; assert_out "tidy_mac 3."; teardown
t "unknown task is an error"; run_tm frobnicate; assert_rc 2; assert_out "Unknown"; teardown
t "list shows tasks and groups"; run_tm list; assert_rc 0; assert_out "caches"; assert_out "xcode"; assert_out "browser-history"; assert_out "dev"; teardown

t "dry-run downloads deletes nothing"
mkfile "$HOME/Downloads/a.txt"; run_tm downloads -n -y; assert_rc 0; assert_out "DRY RUN"; assert_exists "$HOME/Downloads/a.txt"; teardown

t "downloads deletes everything by default with -y"
mkfile "$HOME/Downloads/a.txt"; mkdir -p "$HOME/Downloads/dir"; mkfile "$HOME/Downloads/dir/b.txt"
run_tm downloads -y; assert_rc 0; assert_missing "$HOME/Downloads/a.txt"; assert_missing "$HOME/Downloads/dir"; assert_exists "$HOME/Downloads"; teardown

t "downloads --older keeps recent files"
mkfile "$HOME/Downloads/new.txt"; oldfile "$HOME/Downloads/old.txt"
run_tm downloads --older 30 -y; assert_rc 0; assert_exists "$HOME/Downloads/new.txt"; assert_missing "$HOME/Downloads/old.txt"; teardown

t "destructive task is skipped without --yes when non-interactive"
mkfile "$HOME/Downloads/a.txt"; run_tm downloads; assert_exists "$HOME/Downloads/a.txt"; assert_out "skipped"; teardown

t "--exclude protects matching files"
mkfile "$HOME/Downloads/keep.iso"; mkfile "$HOME/Downloads/bin.txt"
run_tm downloads -y --exclude '*.iso'; assert_exists "$HOME/Downloads/keep.iso"; assert_missing "$HOME/Downloads/bin.txt"; teardown

t "caches honours protected list and config extras"
mkfile "$HOME/Library/Caches/com.example.app/x"; mkfile "$HOME/Library/Caches/CloudKit/x"; mkfile "$HOME/Library/Caches/com.apple.Safari/x"
mkdir -p "$HOME/.config/tidy_mac"; printf 'PROTECTED_CACHES=com.mycorp.keep\nEXTRA_CACHE_DIRS=%s\n' "$HOME/extra" > "$HOME/.config/tidy_mac/config"
mkfile "$HOME/Library/Caches/com.mycorp.keep/x"; mkfile "$HOME/extra/junk"
run_tm caches; assert_rc 0
assert_missing "$HOME/Library/Caches/com.example.app"; assert_exists "$HOME/Library/Caches/CloudKit/x"; assert_exists "$HOME/Library/Caches/com.apple.Safari/x"
assert_exists "$HOME/Library/Caches/com.mycorp.keep/x"; assert_missing "$HOME/extra/junk"; teardown

t "system-caches and logs use the fake system root"
mkfile "$TIDY_MAC_SYSTEM_ROOT/Library/Caches/foo/x"; mkfile "$TIDY_MAC_SYSTEM_ROOT/var/log/system.log"; mkfile "$TIDY_MAC_SYSTEM_ROOT/var/log/keep.txt"; mkfile "$HOME/Library/Logs/app.log"
run_tm system-caches logs; assert_rc 0; assert_missing "$TIDY_MAC_SYSTEM_ROOT/Library/Caches/foo"; assert_missing "$TIDY_MAC_SYSTEM_ROOT/var/log/system.log"
assert_exists "$TIDY_MAC_SYSTEM_ROOT/var/log/keep.txt"; assert_missing "$HOME/Library/Logs/app.log"; teardown

t "screenshots-move moves only old screenshots (legacy -s 30 too)"
oldfile "$HOME/Desktop/Screenshot 2020-01-01 at 10.00.00.png"; mkfile "$HOME/Desktop/Screenshot 2026-08-18 at 10.00.00.png"; oldfile "$HOME/Desktop/holiday.png"
run_tm -s 30 -y; assert_rc 0
assert_exists "$HOME/Desktop/Screenshots/Screenshot 2020-01-01 at 10.00.00.png"; assert_exists "$HOME/Desktop/Screenshot 2026-08-18 at 10.00.00.png"; assert_exists "$HOME/Desktop/holiday.png"; teardown

t "screenshots-delete deletes old ones only"
oldfile "$HOME/Desktop/Screen Shot 2020-01-01 at 1.png"; mkfile "$HOME/Desktop/Screenshot 2026-08-18 at 1.png"
run_tm screenshots-delete --older 7 -y; assert_missing "$HOME/Desktop/Screen Shot 2020-01-01 at 1.png"; assert_exists "$HOME/Desktop/Screenshot 2026-08-18 at 1.png"; teardown

t "--trash moves user files into ~/.Trash instead of deleting"
mkfile "$HOME/Downloads/a.txt"; run_tm downloads -y --trash; assert_missing "$HOME/Downloads/a.txt"; assert_exists "$HOME/.Trash/a.txt"; teardown

t "trash task empties home trash and volume trashes"
mkfile "$HOME/.Trash/x"; mkdir -p "$TIDY_MAC_SYSTEM_ROOT/Volumes/USB/.Trashes/$(id -u)"; mkfile "$TIDY_MAC_SYSTEM_ROOT/Volumes/USB/.Trashes/$(id -u)/y"
run_tm trash; assert_rc 0; assert_missing "$HOME/.Trash/x"; assert_missing "$TIDY_MAC_SYSTEM_ROOT/Volumes/USB/.Trashes/$(id -u)/y"; assert_exists "$HOME/.Trash"; teardown

t "browser-history skips a running browser and clears a closed one"
mkfile "$HOME/Library/Application Support/Google/Chrome/Default/History"; mkfile "$HOME/Library/Safari/History.db"; mkfile "$HOME/Library/Application Support/Firefox/Profiles/abc.default/places.sqlite"
TIDY_MAC_FAKE_RUNNING="Google Chrome" run_tm browser-history; assert_rc 0
assert_exists "$HOME/Library/Application Support/Google/Chrome/Default/History"; assert_out "running"
assert_missing "$HOME/Library/Safari/History.db"; assert_missing "$HOME/Library/Application Support/Firefox/Profiles/abc.default/places.sqlite"; teardown

t "browser-history also covers Brave/Edge/Arc"
mkfile "$HOME/Library/Application Support/BraveSoftware/Brave-Browser/Default/History"; mkfile "$HOME/Library/Application Support/Microsoft Edge/Default/History"; mkfile "$HOME/Library/Application Support/Arc/User Data/Default/History"
run_tm browser-history; assert_missing "$HOME/Library/Application Support/BraveSoftware/Brave-Browser/Default/History"; assert_missing "$HOME/Library/Application Support/Microsoft Edge/Default/History"; assert_missing "$HOME/Library/Application Support/Arc/User Data/Default/History"; teardown

t "scan reports sizes and deletes nothing"
mkfile "$HOME/Library/Caches/com.example/x" 200000; mkfile "$HOME/Downloads/a" 300000
run_tm scan; assert_rc 0; assert_out "caches"; assert_out "downloads"; assert_out "Total"; assert_exists "$HOME/Library/Caches/com.example/x"; assert_exists "$HOME/Downloads/a"; teardown

t "--json emits valid JSON with tasks and totals"
mkfile "$HOME/Library/Caches/com.example/x" 4096
run_tm caches --json; assert_rc 0
printf '%s' "$OUT" | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d["tasks"][0]["id"]=="caches"; assert d["tasks"][0]["status"]=="done"; assert d["total_bytes"]>0; print("json-ok")' >/dev/null 2>&1 && ok || fail "invalid json"; teardown

t "legacy -a -n selects the classic set"
run_tm -a -n; assert_rc 0; assert_out "downloads"; assert_out "caches"; assert_out "logs"; assert_out "browser-history"; assert_out "dns"; assert_out "trash"; assert_not_out "xcode"; teardown

t "all excludes opt-in tasks; deep adds some"
run_tm all -n; assert_rc 0; assert_out "caches"; assert_out "homebrew"; assert_not_out "downloads"; assert_not_out "docker"; assert_not_out "screenshots"
run_tm --profile deep -n; assert_out "browser-cache"; assert_out "dsstore"; teardown

t "group name selects its tasks"
run_tm dev -n; assert_rc 0; assert_out "▸ xcode"; assert_out "▸ homebrew"; assert_not_out "▸ caches"; teardown

t "external commands are recorded, not run, and dry-run only prints"
run_tm dns -n; assert_out "dscacheutil"; [ -s "$TIDY_MAC_CMD_LOG" ] && fail "dry-run must not invoke externals" || ok
run_tm dns; grep -q dscacheutil "$TIDY_MAC_CMD_LOG" && ok || fail "dns should invoke dscacheutil via wrapper"; teardown

t "dsstore sweeps .DS_Store files"
mkfile "$HOME/Documents/.DS_Store"; mkfile "$HOME/Documents/real.txt"; run_tm dsstore; assert_missing "$HOME/Documents/.DS_Store"; assert_exists "$HOME/Documents/real.txt"; teardown

t "xcode clears DerivedData but keeps Archives; xcode-archives is separate"
mkfile "$HOME/Library/Developer/Xcode/DerivedData/Proj-abc/x"; mkfile "$HOME/Library/Developer/Xcode/Archives/2026/a.xcarchive/x"; mkfile "$HOME/Library/Developer/Xcode/iOS DeviceSupport/17.0/x"
run_tm xcode; assert_missing "$HOME/Library/Developer/Xcode/DerivedData/Proj-abc"; assert_exists "$HOME/Library/Developer/Xcode/Archives/2026/a.xcarchive/x"; assert_missing "$HOME/Library/Developer/Xcode/iOS DeviceSupport/17.0"
run_tm xcode-archives -y; assert_missing "$HOME/Library/Developer/Xcode/Archives/2026"; teardown

t "installers removes only old installer files"
oldfile "$HOME/Downloads/old.dmg"; mkfile "$HOME/Downloads/new.dmg"; oldfile "$HOME/Downloads/old.pkg"; oldfile "$HOME/Downloads/report.pdf"
run_tm installers -y; assert_missing "$HOME/Downloads/old.dmg"; assert_exists "$HOME/Downloads/new.dmg"; assert_missing "$HOME/Downloads/old.pkg"; assert_exists "$HOME/Downloads/report.pdf"; teardown

t "large lists biggest files"
mkfile "$HOME/Movies/big.mov" 3000000; mkfile "$HOME/small.txt" 10
run_tm large 5 --min-size 1M; assert_rc 0; assert_out "big.mov"; assert_not_out "small.txt"; teardown

t "config init/show and OLDER_DAYS default"
run_tm config init; assert_rc 0; assert_exists "$HOME/.config/tidy_mac/config"
printf 'OLDER_DAYS=30\n' >> "$HOME/.config/tidy_mac/config"; run_tm config show; assert_out "OLDER_DAYS=30"
mkfile "$HOME/Downloads/new.txt"; oldfile "$HOME/Downloads/old.txt"; run_tm downloads -y; assert_exists "$HOME/Downloads/new.txt"; assert_missing "$HOME/Downloads/old.txt"; teardown

t "schedule install/status/remove"
run_tm schedule install weekly caches trash; assert_rc 0; PL="$TIDY_MAC_LAUNCH_AGENTS_DIR/com.orchardroot.tidy-mac.plist"; assert_exists "$PL"
grep -q "<string>caches</string>" "$PL" && ok || fail "plist should carry task args"; grep -q "<string>--yes</string>" "$PL" && ok || fail "plist should pass --yes"; grep -q Weekday "$PL" && ok || fail "weekly should set Weekday"
run_tm schedule status; assert_out "installed"; run_tm schedule remove; assert_missing "$PL"; teardown

t "app-caches clears closed apps only"
mkfile "$HOME/Library/Application Support/Slack/Cache/x"; mkfile "$HOME/Library/Application Support/Code/Cache/x"
TIDY_MAC_FAKE_RUNNING="Slack" run_tm app-caches; assert_exists "$HOME/Library/Application Support/Slack/Cache/x"; assert_missing "$HOME/Library/Application Support/Code/Cache/x"; teardown

t "log file is written and manifest recorded"
mkfile "$HOME/Downloads/a.txt"; run_tm downloads -y; assert_exists "$HOME/.tidy_mac.log"; grep -q "downloads" "$HOME/.tidy_mac.log" && ok || fail "log should mention task"
ls "$HOME/.local/share/tidy_mac/runs/"*.manifest >/dev/null 2>&1 && ok || fail "manifest should exist"; teardown

t "completion prints a script"; run_tm completion zsh; assert_rc 0; assert_out "compdef"; run_tm completion bash; assert_out "complete -F"; teardown

t "refuses to run task needing sudo when NO_SUDO... still runs against fake root without sudo"
mkfile "$TIDY_MAC_SYSTEM_ROOT/Library/Logs/DiagnosticReports/crash.ips"; mkfile "$HOME/Library/Logs/DiagnosticReports/mine.ips"
run_tm crash-reports; assert_missing "$TIDY_MAC_SYSTEM_ROOT/Library/Logs/DiagnosticReports/crash.ips"; assert_missing "$HOME/Library/Logs/DiagnosticReports/mine.ips"; teardown

echo; echo "Passed: $PASS  Failed: $FAIL"; [ "$FAIL" -eq 0 ]
