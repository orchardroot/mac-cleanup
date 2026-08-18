#!/bin/bash
#
# tidy_mac — a feature-rich, dry-runnable, logged tidy-up tool for macOS.
# Version: 3.0.0   Author: orchardroot   Licence: MIT
#
# Single file, no dependencies, runs on the bash 3.2 that ships with macOS.
#   tidy_mac.sh list                # what it can do, with live sizes
#   tidy_mac.sh scan                # what's eating the disk, without touching it
#   tidy_mac.sh caches logs trash   # run named tasks
#   tidy_mac.sh all -n              # everything safe, dry run
# See `tidy_mac.sh help` for the lot.

set -uo pipefail

VERSION="3.0.0"
SCRIPT_PATH="${BASH_SOURCE[0]}"
case "$SCRIPT_PATH" in /*) ;; *) SCRIPT_PATH="$PWD/$SCRIPT_PATH" ;; esac

# ---------------------------------------------------------------------------
# Environment / test seams. Real use never sets these.
# ---------------------------------------------------------------------------
SYS="${TIDY_MAC_SYSTEM_ROOT:-}"                     # prefix for /Library, /var/log, /Volumes
NO_SUDO="${TIDY_MAC_NO_SUDO:-}"                    # 1 = never call sudo
NO_EXTERNAL="${TIDY_MAC_NO_EXTERNAL:-}"            # 1 = record external mutators instead of running
CMD_LOG="${TIDY_MAC_CMD_LOG:-/dev/null}"
FAKE_RUNNING="${TIDY_MAC_FAKE_RUNNING:-}"
LAUNCH_AGENTS_DIR="${TIDY_MAC_LAUNCH_AGENTS_DIR:-$HOME/Library/LaunchAgents}"

# ---------------------------------------------------------------------------
# Paths and defaults (config file may override some)
# ---------------------------------------------------------------------------
CONFIG_FILE="${TIDY_MAC_CONFIG:-${XDG_CONFIG_HOME:-$HOME/.config}/tidy_mac/config}"
LOG_FILE="$HOME/.tidy_mac.log"
STATE_DIR="$HOME/.local/share/tidy_mac"
RUNS_DIR="$STATE_DIR/runs"
LAUNCH_AGENT_LABEL="com.orchardroot.tidy-mac"

DOWNLOADS_DIR="$HOME/Downloads"
DESKTOP_DIR="$HOME/Desktop"
SCREENSHOTS_DIR="$HOME/Desktop/Screenshots"
USER_CACHE_DIR="$HOME/Library/Caches"
SYSTEM_CACHE_DIR="$SYS/Library/Caches"
USER_LOGS_DIR="$HOME/Library/Logs"
SYSTEM_LOG_DIR="$SYS/var/log"
TRASH_DIR="$HOME/.Trash"
VOLUMES_DIR="$SYS/Volumes"
APP_SUPPORT="$HOME/Library/Application Support"

OLDER_DAYS=0            # downloads: 0 = everything; installers use 30 when this is 0
SCREENSHOT_DAYS=1
INSTALLER_DAYS_DEFAULT=30
LARGE_COUNT=20
LARGE_MIN_SIZE="100M"

PROTECTED_CACHES="CloudKit:com.apple.nsurlsessiond:com.apple.Safari:com.apple.containermanagerd:com.apple.bird:com.apple.akd:com.apple.iconservices:com.apple.HomeKit"
EXTRA_CACHE_DIRS=""
EXCLUDES=""
DEFAULT_TASKS=""

# runtime flags
DRY_RUN=false; INTERACTIVE=false; ASSUME_YES=false; VERBOSE=false; QUIET=false
JSON=false; USE_TRASH=false; COLOR=auto; PROFILE=""
COMMAND=""; SELECTED=""; POSITIONALS=""

# accounting
FREE_BEFORE_KB=0; FREE_AFTER_KB=0; TOTAL_BYTES=0
RESULT_IDS=""; RESULT_STATUS=""; RESULT_BYTES=""; RESULT_NOTES=""
CUR_TASK=""; CUR_BYTES=0; CUR_NOTE=""; TRASH_OK=false; MANIFEST=""

# ---------------------------------------------------------------------------
# Output
# ---------------------------------------------------------------------------
C_RESET=""; C_BOLD=""; C_DIM=""; C_RED=""; C_GREEN=""; C_YELLOW=""; C_BLUE=""; C_CYAN=""
setup_colors() {
    local want=false
    case "$COLOR" in
        always) want=true ;;
        never)  want=false ;;
        *)      [ -t 1 ] && [ -z "${NO_COLOR:-}" ] && want=true ;;
    esac
    if [ "$want" = true ]; then
        C_RESET=$'\033[0m'; C_BOLD=$'\033[1m'; C_DIM=$'\033[2m'; C_RED=$'\033[31m'
        C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'; C_BLUE=$'\033[34m'; C_CYAN=$'\033[36m'
    fi
}
say()     { [ "$QUIET" = true ] || [ "$JSON" = true ] || printf '%s\n' "$*"; }
info()    { say "  ${C_DIM}$*${C_RESET}"; }
verbose() { [ "$VERBOSE" = true ] && say "    ${C_DIM}$*${C_RESET}"; return 0; }
warn()    { printf '%s\n' "${C_YELLOW}warning:${C_RESET} $*" >&2; }
die()     { printf '%s\n' "${C_RED}error:${C_RESET} $*" >&2; exit "${2:-1}"; }
heading() { say ""; say "${C_BOLD}$*${C_RESET}"; }

log_line() {   # to log file only
    printf '%s - %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$LOG_FILE" 2>/dev/null
}
log() { log_line "$*"; say "$*"; }
rotate_log() {
    [ -f "$LOG_FILE" ] || return 0
    local sz; sz=$(stat -f '%z' "$LOG_FILE" 2>/dev/null || echo 0)
    [ "$sz" -gt 1048576 ] && mv -f "$LOG_FILE" "$LOG_FILE.1"
    return 0
}

fmt_bytes() {
    local b=${1:-0}
    if   [ "$b" -ge 1073741824 ]; then awk -v b="$b" 'BEGIN{printf "%.1f GB", b/1073741824}'
    elif [ "$b" -ge 1048576 ];    then awk -v b="$b" 'BEGIN{printf "%.1f MB", b/1048576}'
    elif [ "$b" -ge 1024 ];       then awk -v b="$b" 'BEGIN{printf "%.0f KB", b/1024}'
    else printf '%d B' "$b"; fi
}

# ---------------------------------------------------------------------------
# Config file: KEY=VALUE, whitelisted keys only, never sourced.
# ---------------------------------------------------------------------------
load_config() {
    [ -f "$CONFIG_FILE" ] || return 0
    local line key val
    while IFS= read -r line || [ -n "$line" ]; do
        line="${line%%#*}"
        [ -z "${line// /}" ] && continue
        key="${line%%=*}"; val="${line#*=}"
        key="${key// /}"; val="${val#"${val%%[! ]*}"}"; val="${val%"${val##*[! ]}"}"
        val="${val%\"}"; val="${val#\"}"
        case "$key" in
            OLDER_DAYS)        [[ "$val" =~ ^[0-9]+$ ]] && OLDER_DAYS=$val ;;
            SCREENSHOT_DAYS)   [[ "$val" =~ ^[0-9]+$ ]] && SCREENSHOT_DAYS=$val ;;
            SCREENSHOTS_DIR)   SCREENSHOTS_DIR="${val/#\~/$HOME}" ;;
            PROTECTED_CACHES)  PROTECTED_CACHES="$PROTECTED_CACHES:$val" ;;
            EXTRA_CACHE_DIRS)  EXTRA_CACHE_DIRS="$EXTRA_CACHE_DIRS:${val//\~/$HOME}" ;;
            EXCLUDES)          EXCLUDES="$EXCLUDES:$val" ;;
            DEFAULT_TASKS)     DEFAULT_TASKS="$val" ;;
            USE_TRASH)         case "$val" in 1|true|yes) USE_TRASH=true ;; esac ;;
            COLOR)             COLOR="$val" ;;
            LARGE_MIN_SIZE)    LARGE_MIN_SIZE="$val" ;;
            *) warn "config: ignoring unknown key '$key'" ;;
        esac
    done < "$CONFIG_FILE"
}

config_template() {
    cat << 'TPL'
# tidy_mac configuration. KEY=VALUE, one per line. Lines starting with # are ignored.
# Colon-separate lists. ~ is expanded in paths.

# Age threshold in days for `downloads` (0 = everything) — also the default for --older
#OLDER_DAYS=30

# Age threshold for screenshot tasks
#SCREENSHOT_DAYS=1

# Where `screenshots-move` puts things
#SCREENSHOTS_DIR=~/Desktop/Screenshots

# Extra ~/Library/Caches entries to leave alone (prefix match), added to the built-in list
#PROTECTED_CACHES=com.mycorp.agent:com.example.keepme

# Extra directories whose *contents* the `caches` task should clear
#EXTRA_CACHE_DIRS=~/Library/Application Support/SomeApp/Cache

# Glob patterns (matched against file name or full path) that are never touched
#EXCLUDES=*.iso:*important*

# Tasks to run when invoked with no tasks at all (default: show help)
#DEFAULT_TASKS=caches quicklook trash

# Move user files to Trash instead of deleting (same as --trash)
#USE_TRASH=false

# auto | always | never
#COLOR=auto

# Threshold for the `large` command
#LARGE_MIN_SIZE=100M
TPL
}

# ---------------------------------------------------------------------------
# Safety helpers
# ---------------------------------------------------------------------------
have() { command -v "$1" >/dev/null 2>&1; }

is_root_needed() {   # path outside $HOME → needs root (unless test root prefix in play)
    case "$1" in
        "$HOME"/*) return 1 ;;
        *) [ -n "$SYS" ] && case "$1" in "$SYS"/*) return 1 ;; esac; return 0 ;;
    esac
}
as_root() {
    if [ -n "$NO_SUDO" ] || [ "$(id -u)" = 0 ]; then "$@"; else sudo "$@"; fi
}

# External mutating commands go through here so dry-run and tests can intercept.
ext() {
    if [ "$DRY_RUN" = true ]; then info "would run: $*"; return 0; fi
    if [ -n "$NO_EXTERNAL" ]; then printf '%s\n' "$*" >> "$CMD_LOG"; return 0; fi
    verbose "running: $*"
    if [ "$VERBOSE" = true ]; then "$@"; else "$@" >/dev/null 2>&1; fi
}
ext_root() {
    if [ "$DRY_RUN" = true ]; then info "would run (as root): $*"; return 0; fi
    if [ -n "$NO_EXTERNAL" ]; then printf 'sudo %s\n' "$*" >> "$CMD_LOG"; return 0; fi
    verbose "running (as root): $*"
    if [ "$VERBOSE" = true ]; then as_root "$@"; else as_root "$@" >/dev/null 2>&1; fi
}
# Read-only external query; returns nothing in test mode.
ext_query() { [ -n "$NO_EXTERNAL" ] && return 1; "$@" 2>/dev/null; }

is_running() {   # is_running "Google Chrome"
    local app="$1"
    case ",$FAKE_RUNNING," in *",$app,"*) return 0 ;; esac
    [ -n "$NO_EXTERNAL" ] && return 1
    pgrep -x "$app" >/dev/null 2>&1
}

path_is_safe() {   # refuse to ever remove these
    local p="$1"
    case "$p" in
        ""|"/"|"$HOME"|"$HOME/"|"/Users"|"/Library"|"/System"*|"/usr"*|"/bin"*|"/sbin"*|"/etc"*|"/private"|"/var"|"/Applications"*) return 1 ;;
    esac
    case "$p" in
        "$HOME"/*|"$SYS"/Library/*|"$SYS"/var/log/*|"$SYS"/private/var/*|"$SYS"/Volumes/*) return 0 ;;
        /Library/*|/var/log/*|/private/var/*|/Volumes/*) [ -z "$SYS" ] && return 0 ;;
    esac
    return 1
}
is_excluded() {
    local p="$1" base pat rest="$EXCLUDES"
    base=$(basename "$p")
    while [ -n "$rest" ]; do
        pat="${rest%%:*}"
        if [ "$pat" = "$rest" ]; then rest=""; else rest="${rest#*:}"; fi
        [ -z "$pat" ] && continue
        # shellcheck disable=SC2053
        if [[ "$base" == $pat || "$p" == $pat ]]; then return 0; fi
    done
    return 1
}
size_of() {   # bytes of all given paths (that exist)
    local total=0 p k
    for p in "$@"; do
        [ -e "$p" ] || continue
        k=$(du -sk "$p" 2>/dev/null | awk '{print $1}')
        total=$(( total + ${k:-0} * 1024 ))
    done
    printf '%s' "$total"
}
free_kb() { df -k "$HOME" 2>/dev/null | awk 'NR==2 {print $4}'; }

manifest_open() {
    [ "$DRY_RUN" = true ] && return 0
    [ -n "$MANIFEST" ] && return 0
    mkdir -p "$RUNS_DIR" 2>/dev/null || return 0
    MANIFEST="$RUNS_DIR/$(date '+%Y%m%d-%H%M%S').manifest"
    printf '# tidy_mac %s run at %s\n' "$VERSION" "$(date)" > "$MANIFEST"
}
manifest_add() { [ -n "$MANIFEST" ] && printf '%s\t%s\t%s\n' "$1" "$2" "$3" >> "$MANIFEST"; return 0; }

trash_path() {   # move a path into ~/.Trash with a collision-safe name
    local p="$1" base dest n=1
    mkdir -p "$TRASH_DIR" 2>/dev/null
    base=$(basename "$p"); dest="$TRASH_DIR/$base"
    while [ -e "$dest" ]; do dest="$TRASH_DIR/$base ($n)"; n=$((n+1)); done
    mv "$p" "$dest"
}

# remove_paths <label> path...   — the only place anything gets deleted.
remove_paths() {
    local label="$1"; shift
    local p bytes n=0 freed=0
    for p in "$@"; do
        [ -e "$p" ] || [ -L "$p" ] || continue
        if ! path_is_safe "$p"; then warn "refusing to touch unsafe path: $p"; continue; fi
        if is_excluded "$p"; then verbose "excluded: $p"; continue; fi
        bytes=$(size_of "$p")
        if [ "$DRY_RUN" = true ]; then
            info "would remove: $p ($(fmt_bytes "$bytes"))"
        elif [ "$USE_TRASH" = true ] && [ "$TRASH_OK" = true ]; then
            if trash_path "$p"; then verbose "trashed: $p"; manifest_add trashed "$CUR_TASK" "$p"; else warn "could not trash: $p"; continue; fi
        else
            if is_root_needed "$p"; then as_root rm -rf "$p"; else rm -rf "$p"; fi
            if [ -e "$p" ]; then warn "could not remove: $p"; continue; fi
            verbose "removed: $p"; manifest_add removed "$CUR_TASK" "$p"
        fi
        n=$((n+1)); freed=$((freed+bytes))
    done
    CUR_BYTES=$((CUR_BYTES+freed))
    if [ "$n" -gt 0 ]; then
        if [ "$DRY_RUN" = true ]; then info "$label: $n item(s), $(fmt_bytes "$freed") would be freed"
        else log_line "$CUR_TASK: $label — $n item(s), $(fmt_bytes "$freed")"; info "$label: $n item(s), $(fmt_bytes "$freed")"; fi
    else
        verbose "$label: nothing to do"
    fi
    return 0
}
# remove_children <label> <dir> [find-args...]  — remove direct children of dir matching find args
remove_children() {
    local label="$1" dir="$2"; shift 2
    [ -d "$dir" ] || { verbose "$label: $dir not found"; return 0; }
    local -a items; items=()
    while IFS= read -r -d '' p; do items[${#items[@]}]="$p"; done < <(find "$dir" -mindepth 1 -maxdepth 1 "$@" -print0 2>/dev/null)
    [ ${#items[@]} -gt 0 ] && remove_paths "$label" "${items[@]}"
    return 0
}
# scan_children <dir> [find-args]  → bytes
scan_children() {
    local dir="$1"; shift
    [ -d "$dir" ] || { printf 0; return; }
    local -a items; items=()
    while IFS= read -r -d '' p; do is_excluded "$p" || items[${#items[@]}]="$p"; done < <(find "$dir" -mindepth 1 -maxdepth 1 "$@" -print0 2>/dev/null)
    [ ${#items[@]} -gt 0 ] && size_of "${items[@]}" || printf 0
}
mtime_args() {   # emit find -mtime args for "older than N days" (none if N=0)
    [ "${1:-0}" -gt 0 ] && printf -- '-mtime +%s' "$1"
    return 0
}

# ---------------------------------------------------------------------------
# Task registry (parallel arrays: bash 3.2 has no associative arrays)
#   flags: s=needs sudo  o=opt-in (not in `all`)  d=destructive (needs --yes or -i)  t=trashable
# ---------------------------------------------------------------------------
TASK_IDS=(); TASK_GROUPS=(); TASK_FLAGS=(); TASK_DESCS=()
reg() { TASK_IDS[${#TASK_IDS[@]}]="$1"; TASK_GROUPS[${#TASK_GROUPS[@]}]="$2"; TASK_FLAGS[${#TASK_FLAGS[@]}]="$3"; TASK_DESCS[${#TASK_DESCS[@]}]="$4"; }

reg screenshots-move   files    "ot"  "Move old Desktop screenshots into a Screenshots folder"
reg screenshots-delete files    "odt" "Delete old Desktop screenshots"
reg downloads          files    "odt" "Delete files in ~/Downloads (all, or older than --older days)"
reg installers         files    "odt" "Delete old .dmg/.pkg/.iso/.xip installers from Downloads and Desktop"
reg trash              files    "-"   "Empty the Trash (home and every mounted volume)"
reg dsstore            files    "o"   "Sweep .DS_Store files from your home folder"
reg caches             system   "-"   "Clear user application caches (~/Library/Caches, protected list honoured)"
reg system-caches      system   "s"   "Clear system caches (/Library/Caches)"
reg logs               system   "s"   "Delete user logs and rotated system logs"
reg crash-reports      system   "s"   "Delete crash and diagnostic reports"
reg quicklook          system   "-"   "Reset the QuickLook thumbnail cache"
reg font-cache         system   "so"  "Reset font caches (takes effect after restart)"
reg mail-cache         system   "-"   "Clear Mail's downloaded-attachment cache (Mail re-fetches on demand)"
reg tm-snapshots       system   "sod" "Thin Time Machine local snapshots"
reg purge              system   "so"  "Purge inactive memory (sudo purge)"
reg app-caches         apps     "-"   "Clear caches of Slack, Discord, VS Code, Teams, Spotify (skipped while running)"
reg browser-history    browsers "-"   "Clear history for Chrome/Brave/Edge/Arc/Vivaldi/Chromium, Safari and Firefox"
reg browser-cache      browsers "o"   "Clear browser caches"
reg browser-cookies    browsers "od"  "Delete browser cookies (logs you out of everything)"
reg dns                network  "s"   "Flush the DNS resolver cache"
reg xcode              dev      "-"   "Clear Xcode DerivedData, device support and simulator caches"
reg xcode-archives     dev      "od"  "Delete Xcode Archives (your dSYMs live here — be sure)"
reg simulators         dev      "-"   "Delete unavailable iOS simulators"
reg homebrew           dev      "-"   "brew cleanup + autoremove"
reg node               dev      "-"   "Clear npm/yarn/pnpm/bun caches"
reg python             dev      "-"   "Clear pip/uv/poetry caches"
reg go                 dev      "-"   "Clear the Go build cache"
reg rust               dev      "-"   "Clear Cargo registry cache and sources"
reg jvm                dev      "-"   "Clear Gradle caches and daemon logs"
reg cocoapods          dev      "-"   "Clear the CocoaPods cache"
reg docker             dev      "od"  "docker system prune (images, containers, networks; not volumes)"

GROUPS_LIST="files system apps browsers network dev"
PROFILE_quick="caches quicklook logs trash dns"
PROFILE_deep_extra="browser-cache dsstore tm-snapshots"
LEGACY_ALL="downloads caches system-caches logs browser-history dns trash"

task_index() { local i; for i in "${!TASK_IDS[@]}"; do [ "${TASK_IDS[$i]}" = "$1" ] && { printf '%s' "$i"; return 0; }; done; return 1; }
task_has_flag() { local i; i=$(task_index "$1") || return 1; case "${TASK_FLAGS[$i]}" in *"$2"*) return 0 ;; esac; return 1; }
is_group() { case " $GROUPS_LIST " in *" $1 "*) return 0 ;; esac; return 1; }
group_tasks() { local i out=""; for i in "${!TASK_IDS[@]}"; do [ "${TASK_GROUPS[$i]}" = "$1" ] && out="$out ${TASK_IDS[$i]}"; done; printf '%s' "$out"; }
all_tasks() { local i out=""; for i in "${!TASK_IDS[@]}"; do case "${TASK_FLAGS[$i]}" in *o*) ;; *) out="$out ${TASK_IDS[$i]}" ;; esac; done; printf '%s' "$out"; }

# ---------------------------------------------------------------------------
# Task implementations: scan_<id> prints reclaimable bytes; run_<id> does it.
# ---------------------------------------------------------------------------
screenshot_source_dir() {
    local d; d=$(ext_query defaults read com.apple.screencapture location)
    d="${d/#\~/$HOME}"
    [ -n "$d" ] && [ -d "$d" ] && printf '%s' "$d" || printf '%s' "$DESKTOP_DIR"
}
SHOT_NAMES=( -name 'Screen Shot*' -o -name 'Screenshot*' -o -name 'Bildschirmfoto*' -o -name 'Capture d*écran*' -o -name 'Captura de pantalla*' -o -name 'Schermafbeelding*' -o -name 'Schermata*' -o -name 'スクリーンショット*' -o -name 'Снимок экрана*' )
shot_days() { [ "$OLDER_DAYS" -gt 0 ] && printf '%s' "$OLDER_DAYS" || printf '%s' "$SCREENSHOT_DAYS"; }

scan_screenshots-move()   { scan_children "$(screenshot_source_dir)" -type f \( "${SHOT_NAMES[@]}" \) $(mtime_args "$(shot_days)"); }
scan_screenshots-delete() { scan_screenshots-move; }
run_screenshots-move() {
    local src days n=0; src=$(screenshot_source_dir); days=$(shot_days)
    [ "$src" = "$SCREENSHOTS_DIR" ] && { info "screenshots already live in $SCREENSHOTS_DIR"; return 0; }
    while IFS= read -r -d '' p; do
        is_excluded "$p" && continue
        if [ "$DRY_RUN" = true ]; then info "would move: $p"; else
            mkdir -p "$SCREENSHOTS_DIR" && mv "$p" "$SCREENSHOTS_DIR/" && manifest_add moved "$CUR_TASK" "$p" && verbose "moved: $p"; fi
        n=$((n+1))
    done < <(find "$src" -mindepth 1 -maxdepth 1 -type f \( "${SHOT_NAMES[@]}" \) $(mtime_args "$days") -print0 2>/dev/null)
    CUR_NOTE="$n moved"; [ "$DRY_RUN" = true ] || log_line "$CUR_TASK: moved $n screenshot(s) older than $days day(s) to $SCREENSHOTS_DIR"
    info "screenshots older than $days day(s): $n $([ "$DRY_RUN" = true ] && echo 'would be moved' || echo moved) → $SCREENSHOTS_DIR"
}
run_screenshots-delete() { remove_children "screenshots older than $(shot_days) day(s)" "$(screenshot_source_dir)" -type f \( "${SHOT_NAMES[@]}" \) $(mtime_args "$(shot_days)"); }

scan_downloads() { scan_children "$DOWNLOADS_DIR" ! -name .localized $(mtime_args "$OLDER_DAYS"); }
run_downloads()  { remove_children "Downloads$([ "$OLDER_DAYS" -gt 0 ] && echo " older than $OLDER_DAYS day(s)")" "$DOWNLOADS_DIR" ! -name .localized $(mtime_args "$OLDER_DAYS"); }

installer_days() { [ "$OLDER_DAYS" -gt 0 ] && printf '%s' "$OLDER_DAYS" || printf '%s' "$INSTALLER_DAYS_DEFAULT"; }
INSTALLER_NAMES=( -iname '*.dmg' -o -iname '*.pkg' -o -iname '*.mpkg' -o -iname '*.iso' -o -iname '*.xip' )
scan_installers() { local a b; a=$(scan_children "$DOWNLOADS_DIR" -type f \( "${INSTALLER_NAMES[@]}" \) -mtime +"$(installer_days)"); b=$(scan_children "$DESKTOP_DIR" -type f \( "${INSTALLER_NAMES[@]}" \) -mtime +"$(installer_days)"); printf '%s' $((a+b)); }
run_installers() {
    remove_children "installers in Downloads older than $(installer_days) day(s)" "$DOWNLOADS_DIR" -type f \( "${INSTALLER_NAMES[@]}" \) -mtime +"$(installer_days)"
    remove_children "installers on Desktop older than $(installer_days) day(s)" "$DESKTOP_DIR" -type f \( "${INSTALLER_NAMES[@]}" \) -mtime +"$(installer_days)"
}

volume_trashes() { local v; for v in "$VOLUMES_DIR"/*/; do [ -d "$v.Trashes/$(id -u)" ] && printf '%s\n' "$v.Trashes/$(id -u)"; done; return 0; }
scan_trash() { local t=0 v; t=$(scan_children "$TRASH_DIR"); while IFS= read -r v; do [ -n "$v" ] && t=$((t+$(scan_children "$v"))); done < <(volume_trashes); printf '%s' "$t"; }
run_trash() { local v; remove_children "Trash" "$TRASH_DIR"; while IFS= read -r v; do [ -n "$v" ] && remove_children "Trash on $(basename "$(dirname "$(dirname "$v")")")" "$v"; done < <(volume_trashes); }

scan_dsstore() { local n; n=$(find "$HOME" -xdev -name .DS_Store -type f 2>/dev/null | wc -l | tr -d ' '); printf '%s' $((n*6148)); }
run_dsstore() {
    local -a items; items=()
    while IFS= read -r -d '' p; do items[${#items[@]}]="$p"; done < <(find "$HOME" -xdev -name .DS_Store -type f -print0 2>/dev/null)
    [ ${#items[@]} -gt 0 ] && remove_paths ".DS_Store files" "${items[@]}"; return 0
}

is_protected_cache() {
    local base="$1" rest="$PROTECTED_CACHES" pat
    while [ -n "$rest" ]; do pat="${rest%%:*}"; [ "$pat" = "$rest" ] && rest="" || rest="${rest#*:}"; [ -n "$pat" ] && case "$base" in "$pat"*) return 0 ;; esac; done
    return 1
}
cache_items() {   # prints NUL-separated removable items in ~/Library/Caches + extras
    local p rest="$EXTRA_CACHE_DIRS" d
    for p in "$USER_CACHE_DIR"/* "$USER_CACHE_DIR"/.[!.]*; do
        [ -e "$p" ] || continue
        is_protected_cache "$(basename "$p")" && { verbose "protected cache: $(basename "$p")"; continue; }
        printf '%s\0' "$p"
    done
    while [ -n "$rest" ]; do
        d="${rest%%:*}"; [ "$d" = "$rest" ] && rest="" || rest="${rest#*:}"
        [ -d "$d" ] || continue
        for p in "$d"/* "$d"/.[!.]*; do [ -e "$p" ] && printf '%s\0' "$p"; done
    done
}
scan_caches() { local -a items; items=(); while IFS= read -r -d '' p; do items[${#items[@]}]="$p"; done < <(cache_items); [ ${#items[@]} -gt 0 ] && size_of "${items[@]}" || printf 0; }
run_caches()  { local -a items; items=(); while IFS= read -r -d '' p; do items[${#items[@]}]="$p"; done < <(cache_items); [ ${#items[@]} -gt 0 ] && remove_paths "user caches" "${items[@]}"; return 0; }

scan_system-caches() { scan_children "$SYSTEM_CACHE_DIR"; }
run_system-caches()  { remove_children "system caches" "$SYSTEM_CACHE_DIR"; }

scan_logs() { local a b; a=$(scan_children "$USER_LOGS_DIR"); b=$(scan_children "$SYSTEM_LOG_DIR" -type f \( -name '*.log' -o -name '*.log.[0-9]*' -o -name '*.gz' -o -name '*.bz2' \)); printf '%s' $((a+b)); }
run_logs() {
    remove_children "user logs" "$USER_LOGS_DIR"
    remove_children "system logs" "$SYSTEM_LOG_DIR" -type f \( -name '*.log' -o -name '*.log.[0-9]*' -o -name '*.gz' -o -name '*.bz2' \)
}

scan_crash-reports() { local a b c; a=$(scan_children "$USER_LOGS_DIR/DiagnosticReports"); b=$(scan_children "$SYS/Library/Logs/DiagnosticReports"); c=$(scan_children "$USER_LOGS_DIR/CrashReporter"); printf '%s' $((a+b+c)); }
run_crash-reports() {
    remove_children "user diagnostic reports" "$USER_LOGS_DIR/DiagnosticReports"
    remove_children "user crash reports" "$USER_LOGS_DIR/CrashReporter"
    remove_children "system diagnostic reports" "$SYS/Library/Logs/DiagnosticReports"
}

scan_quicklook() { printf 0; }
run_quicklook()  { if have qlmanage || [ -n "$NO_EXTERNAL" ]; then ext qlmanage -r cache; CUR_NOTE="cache reset"; else CUR_NOTE="qlmanage not found"; fi; }

scan_font-cache() { printf 0; }
run_font-cache()  { ext_root atsutil databases -remove; CUR_NOTE="restart to rebuild"; }

MAIL_DIRS=( "$HOME/Library/Containers/com.apple.mail/Data/Library/Mail Downloads" "$HOME/Library/Mail Downloads" )
scan_mail-cache() { local t=0 d; for d in "${MAIL_DIRS[@]}"; do t=$((t+$(scan_children "$d"))); done; printf '%s' "$t"; }
run_mail-cache()  { local d; for d in "${MAIL_DIRS[@]}"; do remove_children "Mail downloads" "$d"; done; }

scan_tm-snapshots() { printf 0; }
run_tm-snapshots() {
    local snap n=0
    while IFS= read -r snap; do
        [ -n "$snap" ] || continue
        snap="${snap##*TimeMachine.}"; snap="${snap%%.local*}"
        ext_root tmutil deletelocalsnapshots "$snap"; n=$((n+1))
    done < <(ext_query tmutil listlocalsnapshots / | grep 'com.apple.TimeMachine')
    ext_root tmutil thinlocalsnapshots / 100000000000 4
    CUR_NOTE="$n snapshot(s) removed"
}

scan_purge() { printf 0; }
run_purge()  { ext_root purge; CUR_NOTE="memory purged"; }

# app caches: "Process Name|path|path|..."
APP_CACHE_SPECS=(
    "Slack|$APP_SUPPORT/Slack/Cache|$APP_SUPPORT/Slack/Code Cache|$APP_SUPPORT/Slack/Service Worker/CacheStorage|$APP_SUPPORT/Slack/GPUCache"
    "Discord|$APP_SUPPORT/discord/Cache|$APP_SUPPORT/discord/Code Cache|$APP_SUPPORT/discord/GPUCache"
    "Code|$APP_SUPPORT/Code/Cache|$APP_SUPPORT/Code/CachedData|$APP_SUPPORT/Code/CachedExtensionVSIXs|$APP_SUPPORT/Code/Code Cache|$APP_SUPPORT/Code/GPUCache"
    "Microsoft Teams|$APP_SUPPORT/Microsoft/Teams/Cache|$APP_SUPPORT/Microsoft/Teams/Code Cache|$APP_SUPPORT/Microsoft/Teams/Service Worker/CacheStorage"
    "MSTeams|$HOME/Library/Containers/com.microsoft.teams2/Data/Library/Caches"
    "Spotify|$USER_CACHE_DIR/com.spotify.client/Data"
    "zoom.us|$APP_SUPPORT/zoom.us/AutoUpdater"
)
each_app_cache() {   # callback receives: app dir...
    local spec app rest d cb="$1"; shift
    for spec in "${APP_CACHE_SPECS[@]}"; do
        app="${spec%%|*}"; rest="${spec#*|}"
        local -a dirs; dirs=()
        while [ -n "$rest" ]; do d="${rest%%|*}"; [ "$d" = "$rest" ] && rest="" || rest="${rest#*|}"; dirs[${#dirs[@]}]="$d"; done
        "$cb" "$app" "${dirs[@]}"
    done
}
_scan_app() { shift; local d t=0; for d in "$@"; do t=$((t+$(scan_children "$d"))); done; APP_SCAN_TOTAL=$((APP_SCAN_TOTAL+t)); }
_run_app()  { local app="$1"; shift; local d any=false; for d in "$@"; do [ -d "$d" ] && any=true; done; [ "$any" = true ] || return 0
              if is_running "$app"; then info "$app is running — skipping its caches"; return 0; fi
              for d in "$@"; do remove_children "$app cache" "$d"; done; }
scan_app-caches() { APP_SCAN_TOTAL=0; each_app_cache _scan_app; printf '%s' "$APP_SCAN_TOTAL"; }
run_app-caches()  { each_app_cache _run_app; }

# browsers
CHROMIUM_SPECS=(
    "Google Chrome|$APP_SUPPORT/Google/Chrome|$USER_CACHE_DIR/Google/Chrome"
    "Chromium|$APP_SUPPORT/Chromium|$USER_CACHE_DIR/Chromium"
    "Brave Browser|$APP_SUPPORT/BraveSoftware/Brave-Browser|$USER_CACHE_DIR/BraveSoftware/Brave-Browser"
    "Microsoft Edge|$APP_SUPPORT/Microsoft Edge|$USER_CACHE_DIR/Microsoft Edge"
    "Arc|$APP_SUPPORT/Arc/User Data|$USER_CACHE_DIR/company.thebrowser.Browser"
    "Vivaldi|$APP_SUPPORT/Vivaldi|$USER_CACHE_DIR/Vivaldi"
)
chromium_profiles() { local root="$1" p; for p in "$root"/Default "$root"/Profile\ *; do [ -d "$p" ] && printf '%s\0' "$p"; done; return 0; }
SAFARI_DIRS=( "$HOME/Library/Safari" "$HOME/Library/Containers/com.apple.Safari/Data/Library/Safari" )
FIREFOX_PROFILES="$APP_SUPPORT/Firefox/Profiles"

# kind: history | cache | cookies ; mode: scan | run
browser_walk() {
    local kind="$1" mode="$2" spec app root cache prof total=0
    local -a targets
    for spec in "${CHROMIUM_SPECS[@]}"; do
        app="${spec%%|*}"; root="${spec#*|}"; cache="${root#*|}"; root="${root%%|*}"
        [ -d "$root" ] || continue
        targets=()
        while IFS= read -r -d '' prof; do
            case "$kind" in
                history) for f in "$prof"/History "$prof"/History-journal "$prof"/"Visited Links"; do [ -e "$f" ] && targets[${#targets[@]}]="$f"; done ;;
                cookies) for f in "$prof"/Cookies "$prof"/Cookies-journal; do [ -e "$f" ] && targets[${#targets[@]}]="$f"; done ;;
                cache)   for f in "$prof"/Cache "$prof"/"Code Cache" "$prof"/GPUCache "$prof"/"Service Worker/CacheStorage"; do [ -e "$f" ] && targets[${#targets[@]}]="$f"; done ;;
            esac
        done < <(chromium_profiles "$root")
        [ "$kind" = cache ] && [ -d "$cache" ] && targets[${#targets[@]}]="$cache"
        [ ${#targets[@]} -gt 0 ] || continue
        if [ "$mode" = scan ]; then total=$((total+$(size_of "${targets[@]}")))
        elif is_running "$app"; then info "$app is running — skipping ($kind)"
        else remove_paths "$app $kind" "${targets[@]}"; fi
    done
    # Safari
    targets=()
    for d in "${SAFARI_DIRS[@]}"; do
        case "$kind" in
            history) for f in "$d"/History.db "$d"/History.db-wal "$d"/History.db-shm "$d"/History.db-lock "$d"/History.plist "$d"/HistoryIndex.sk "$d"/RecentlyClosedTabs.plist; do [ -e "$f" ] && targets[${#targets[@]}]="$f"; done ;;
            cookies) : ;;
        esac
    done
    case "$kind" in
        cache)   for d in "$USER_CACHE_DIR/com.apple.Safari" "$HOME/Library/Containers/com.apple.Safari/Data/Library/Caches"; do [ -d "$d" ] && for f in "$d"/*; do [ -e "$f" ] && targets[${#targets[@]}]="$f"; done; done ;;
        cookies) for f in "$HOME/Library/Cookies/Cookies.binarycookies" "$HOME/Library/Containers/com.apple.Safari/Data/Library/Cookies/Cookies.binarycookies"; do [ -e "$f" ] && targets[${#targets[@]}]="$f"; done ;;
    esac
    if [ ${#targets[@]} -gt 0 ]; then
        if [ "$mode" = scan ]; then total=$((total+$(size_of "${targets[@]}")))
        elif is_running "Safari"; then info "Safari is running — skipping ($kind)"
        else remove_paths "Safari $kind" "${targets[@]}"; fi
    fi
    # Firefox
    targets=()
    if [ -d "$FIREFOX_PROFILES" ]; then
        for prof in "$FIREFOX_PROFILES"/*/; do
            [ -d "$prof" ] || continue
            case "$kind" in
                history) for f in "$prof"places.sqlite "$prof"places.sqlite-wal "$prof"places.sqlite-shm "$prof"favicons.sqlite; do [ -e "$f" ] && targets[${#targets[@]}]="$f"; done ;;
                cookies) for f in "$prof"cookies.sqlite "$prof"cookies.sqlite-wal "$prof"cookies.sqlite-shm; do [ -e "$f" ] && targets[${#targets[@]}]="$f"; done ;;
                cache)   [ -d "${prof}cache2" ] && targets[${#targets[@]}]="${prof}cache2" ;;
            esac
        done
        if [ "$kind" = cache ]; then for prof in "$USER_CACHE_DIR"/Firefox/Profiles/*/cache2; do [ -d "$prof" ] && targets[${#targets[@]}]="$prof"; done; fi
    fi
    if [ ${#targets[@]} -gt 0 ]; then
        if [ "$mode" = scan ]; then total=$((total+$(size_of "${targets[@]}")))
        elif is_running "firefox"; then info "Firefox is running — skipping ($kind)"
        else remove_paths "Firefox $kind" "${targets[@]}"; fi
    fi
    [ "$mode" = scan ] && printf '%s' "$total"; return 0
}
scan_browser-history() { browser_walk history scan; }; run_browser-history() { browser_walk history run; }
scan_browser-cache()   { browser_walk cache scan; };   run_browser-cache()   { browser_walk cache run; }
scan_browser-cookies() { browser_walk cookies scan; }; run_browser-cookies() { browser_walk cookies run; }

scan_dns() { printf 0; }
run_dns()  { ext_root dscacheutil -flushcache; ext_root killall -HUP mDNSResponder; CUR_NOTE="flushed"; }

# dev
XCODE="$HOME/Library/Developer/Xcode"
XCODE_DIRS=( "$XCODE/DerivedData" "$XCODE/iOS DeviceSupport" "$XCODE/watchOS DeviceSupport" "$XCODE/tvOS DeviceSupport" "$XCODE/visionOS DeviceSupport" "$HOME/Library/Developer/CoreSimulator/Caches" "$XCODE/iOS Device Logs" )
scan_xcode() { local t=0 d; for d in "${XCODE_DIRS[@]}"; do t=$((t+$(scan_children "$d"))); done; printf '%s' "$t"; }
run_xcode()  { local d; for d in "${XCODE_DIRS[@]}"; do remove_children "Xcode $(basename "$d")" "$d"; done; }
scan_xcode-archives() { scan_children "$XCODE/Archives"; }
run_xcode-archives()  { remove_children "Xcode Archives" "$XCODE/Archives"; }
scan_simulators() { printf 0; }
run_simulators()  { if have xcrun || [ -n "$NO_EXTERNAL" ]; then ext xcrun simctl delete unavailable; CUR_NOTE="unavailable simulators deleted"; else CUR_NOTE="xcrun not found"; fi; }
scan_homebrew() { scan_children "$USER_CACHE_DIR/Homebrew"; }
run_homebrew()  { if have brew || [ -n "$NO_EXTERNAL" ]; then ext brew cleanup -s --prune=all; ext brew autoremove; CUR_NOTE="brew cleanup + autoremove"; else CUR_NOTE="brew not found"; fi; }
NODE_DIRS=( "$HOME/.npm/_cacache" "$HOME/.npm/_logs" "$USER_CACHE_DIR/Yarn" "$HOME/.cache/yarn" "$HOME/.yarn/cache" "$HOME/.bun/install/cache" "$USER_CACHE_DIR/node-gyp" "$HOME/.cache/pnpm" )
scan_node() { local t=0 d; for d in "${NODE_DIRS[@]}"; do t=$((t+$(scan_children "$d"))); done; printf '%s' "$t"; }
run_node()  { local d; for d in "${NODE_DIRS[@]}"; do remove_children "$(basename "$(dirname "$d")")/$(basename "$d")" "$d"; done; have pnpm && ext pnpm store prune; return 0; }
PY_DIRS=( "$USER_CACHE_DIR/pip" "$HOME/.cache/pip" "$HOME/.cache/uv" "$USER_CACHE_DIR/uv" "$USER_CACHE_DIR/pypoetry" "$HOME/.cache/pypoetry" "$USER_CACHE_DIR/pipenv" )
scan_python() { local t=0 d; for d in "${PY_DIRS[@]}"; do t=$((t+$(scan_children "$d"))); done; printf '%s' "$t"; }
run_python()  { local d; for d in "${PY_DIRS[@]}"; do remove_children "$(basename "$d") cache" "$d"; done; }
scan_go() { scan_children "$USER_CACHE_DIR/go-build"; }
run_go()  { remove_children "Go build cache" "$USER_CACHE_DIR/go-build"; }
RUST_DIRS=( "$HOME/.cargo/registry/cache" "$HOME/.cargo/registry/src" "$HOME/.cargo/git/checkouts" )
scan_rust() { local t=0 d; for d in "${RUST_DIRS[@]}"; do t=$((t+$(scan_children "$d"))); done; printf '%s' "$t"; }
run_rust()  { local d; for d in "${RUST_DIRS[@]}"; do remove_children "cargo $(basename "$d")" "$d"; done; }
JVM_DIRS=( "$HOME/.gradle/caches" "$HOME/.gradle/daemon" "$HOME/.gradle/wrapper/dists" )
scan_jvm() { local t=0 d; for d in "${JVM_DIRS[@]}"; do t=$((t+$(scan_children "$d"))); done; printf '%s' "$t"; }
run_jvm()  { local d; for d in "${JVM_DIRS[@]}"; do remove_children "gradle $(basename "$d")" "$d"; done; }
scan_cocoapods() { scan_children "$USER_CACHE_DIR/CocoaPods"; }
run_cocoapods()  { remove_children "CocoaPods cache" "$USER_CACHE_DIR/CocoaPods"; }
scan_docker() { printf 0; }
run_docker()  { if have docker || [ -n "$NO_EXTERNAL" ]; then ext docker system prune -f && CUR_NOTE="pruned" || CUR_NOTE="docker not running"; else CUR_NOTE="docker not found"; fi; }

# ---------------------------------------------------------------------------
# Running tasks
# ---------------------------------------------------------------------------
add_result() { RESULT_IDS="$RESULT_IDS $1"; RESULT_STATUS="$RESULT_STATUS $2"; RESULT_BYTES="$RESULT_BYTES $3"; RESULT_NOTES="$RESULT_NOTES|$4"; }

confirm() {   # confirm "question" → 0 yes
    [ "$ASSUME_YES" = true ] && return 0
    [ -t 0 ] || return 1
    local reply
    printf '%s' "$1 [y/N] " > /dev/tty
    read -r reply < /dev/tty
    case "$reply" in y|Y|yes|YES) return 0 ;; esac
    return 1
}

run_task() {
    local id="$1" idx desc status="done"
    idx=$(task_index "$id") || return 1
    desc="${TASK_DESCS[$idx]}"
    CUR_TASK="$id"; CUR_BYTES=0; CUR_NOTE=""; TRASH_OK=false
    task_has_flag "$id" t && TRASH_OK=true

    heading "▸ $id ${C_DIM}— $desc${C_RESET}"
    if task_has_flag "$id" d && [ "$DRY_RUN" = false ]; then
        if [ "$INTERACTIVE" = false ] && [ "$ASSUME_YES" = false ]; then
            if [ -t 0 ]; then
                confirm "  ${C_YELLOW}This permanently deletes files. Continue?${C_RESET}" || { info "skipped"; add_result "$id" skipped 0 "declined"; return 0; }
            else
                info "skipped: destructive task needs --yes when not interactive"
                add_result "$id" skipped 0 "needs --yes"; return 0
            fi
        fi
    fi
    if [ "$INTERACTIVE" = true ] && [ "$DRY_RUN" = false ]; then
        confirm "  Run '$id'?" || { info "skipped"; add_result "$id" skipped 0 "declined"; return 0; }
    fi
    if task_has_flag "$id" s && [ "$DRY_RUN" = false ] && [ -z "$NO_SUDO" ] && [ "$(id -u)" != 0 ]; then
        info "(needs administrator rights — you may be asked for your password)"
    fi
    if "run_$id"; then :; else status="failed"; fi
    [ "$DRY_RUN" = true ] && status="dry-run"
    TOTAL_BYTES=$((TOTAL_BYTES+CUR_BYTES))
    add_result "$id" "$status" "$CUR_BYTES" "$CUR_NOTE"
    return 0
}

print_summary() {
    local -a ids st by; local notes="$RESULT_NOTES" note i
    ids=($RESULT_IDS); st=($RESULT_STATUS); by=($RESULT_BYTES)
    if [ "$JSON" = true ]; then
        printf '{"version":"%s","dry_run":%s,"tasks":[' "$VERSION" "$DRY_RUN"
        for i in "${!ids[@]}"; do
            notes="${notes#*|}"; note="${notes%%|*}"
            [ "$i" -gt 0 ] && printf ','
            printf '{"id":"%s","status":"%s","bytes":%s,"note":"%s"}' "${ids[$i]}" "${st[$i]}" "${by[$i]}" "${note//\"/\\\"}"
        done
        printf '],"total_bytes":%s,"free_before_kb":%s,"free_after_kb":%s}\n' "$TOTAL_BYTES" "${FREE_BEFORE_KB:-0}" "${FREE_AFTER_KB:-0}"
        return 0
    fi
    [ "$QUIET" = true ] && return 0
    say ""; say "${C_BOLD}Summary${C_RESET}"
    printf '  %-20s %-9s %12s  %s\n' TASK STATUS RECLAIMED NOTE
    for i in "${!ids[@]}"; do
        notes="${notes#*|}"; note="${notes%%|*}"
        local col="$C_GREEN"; case "${st[$i]}" in skipped) col="$C_YELLOW" ;; failed) col="$C_RED" ;; dry-run) col="$C_CYAN" ;; esac
        printf '  %-20s %s%-9s%s %12s  %s\n' "${ids[$i]}" "$col" "${st[$i]}" "$C_RESET" "$(fmt_bytes "${by[$i]}")" "$note"
    done
    say ""
    if [ "$DRY_RUN" = true ]; then
        say "  ${C_CYAN}DRY RUN${C_RESET} — nothing was changed. Estimated reclaimable: ${C_BOLD}$(fmt_bytes "$TOTAL_BYTES")${C_RESET}"
    else
        say "  Reclaimed: ${C_BOLD}$(fmt_bytes "$TOTAL_BYTES")${C_RESET}   Free space: $(fmt_bytes $((FREE_BEFORE_KB*1024))) → $(fmt_bytes $((FREE_AFTER_KB*1024)))"
        [ -n "$MANIFEST" ] && say "  Manifest: $MANIFEST"
    fi
}

cmd_run() {
    local id
    [ -n "$SELECTED" ] || die "nothing to do — name some tasks, a group, a profile, or 'all' (see 'tidy_mac.sh list')" 2
    rotate_log
    FREE_BEFORE_KB=$(free_kb)
    if [ "$DRY_RUN" = true ]; then say "${C_CYAN}DRY RUN${C_RESET} — showing what would happen; nothing will be changed."; fi
    say "Tasks:${C_BOLD}$SELECTED${C_RESET}"
    if [ "$INTERACTIVE" = true ] && [ "$DRY_RUN" = false ]; then
        confirm "Proceed?" || { say "Cancelled."; exit 0; }
    fi
    [ "$DRY_RUN" = true ] || log_line "run started:$SELECTED"
    manifest_open
    for id in $SELECTED; do run_task "$id"; done
    FREE_AFTER_KB=$(free_kb)
    [ "$DRY_RUN" = true ] || log_line "run finished: reclaimed $(fmt_bytes "$TOTAL_BYTES")"
    print_summary
}

cmd_list() {
    local i g flags marks
    say "${C_BOLD}tidy_mac $VERSION${C_RESET} — tasks (${C_DIM}sudo${C_RESET} needs admin, ${C_YELLOW}opt-in${C_RESET} not in 'all', ${C_RED}destructive${C_RESET} needs --yes)"
    for g in $GROUPS_LIST; do
        say ""; say "${C_BOLD}$g${C_RESET}"
        for i in "${!TASK_IDS[@]}"; do
            [ "${TASK_GROUPS[$i]}" = "$g" ] || continue
            flags="${TASK_FLAGS[$i]}"; marks=""
            case "$flags" in *s*) marks="$marks ${C_DIM}sudo${C_RESET}" ;; esac
            case "$flags" in *o*) marks="$marks ${C_YELLOW}opt-in${C_RESET}" ;; esac
            case "$flags" in *d*) marks="$marks ${C_RED}destructive${C_RESET}" ;; esac
            printf '  %-20s %s%s\n' "${TASK_IDS[$i]}" "${TASK_DESCS[$i]}" "$marks"
        done
    done
    say ""; say "${C_BOLD}profiles${C_RESET}: quick ($PROFILE_quick) · standard (= all) · deep (all + $PROFILE_deep_extra) · dev (the dev group)"
    say "${C_BOLD}groups${C_RESET}: $GROUPS_LIST — use a group name to run all of its tasks."
}

cmd_scan() {
    local id b total=0 lines="" note
    [ -n "$SELECTED" ] || SELECTED="${TASK_IDS[*]}"
    say "${C_BOLD}Scanning${C_RESET} — measuring what each task could reclaim (nothing is changed)…"
    for id in $SELECTED; do
        CUR_NOTE=""; b=$("scan_$id" 2>/dev/null); b=${b:-0}; note="$CUR_NOTE"
        total=$((total+b))
        lines="$lines$(printf '%013d\t%s\t%s\t%s' "$b" "$id" "$(fmt_bytes "$b")" "$note")"$'\n'
    done
    if [ "$JSON" = true ]; then
        printf '{"scan":['; local first=true
        printf '%s' "$lines" | sort -r | while IFS=$'\t' read -r raw id human note; do [ -n "$id" ] || continue; printf '%s{"id":"%s","bytes":%d}' "$([ "$first" = true ] || echo ,)" "$id" "$((10#$raw))"; first=false; done
        printf '],"total_bytes":%s}\n' "$total"; return 0
    fi
    say ""; printf '  %-20s %12s  %s\n' TASK RECLAIMABLE NOTE
    printf '%s' "$lines" | sort -r | while IFS=$'\t' read -r raw id human note; do
        [ -n "$id" ] || continue
        local mark=""; task_has_flag "$id" o && mark="${C_YELLOW}*${C_RESET}"
        printf '  %-20s %12s  %s%s\n' "$id" "$human" "$note" "$mark"
    done
    say ""; say "  ${C_BOLD}Total: $(fmt_bytes "$total")${C_RESET} reclaimable  ${C_DIM}(* = opt-in, not part of 'all'; sizes for command-based tasks are unknown until run)${C_RESET}"
    say "  Free space now: $(fmt_bytes $(( $(free_kb) * 1024 )))"
}

cmd_large() {
    local n="${1:-$LARGE_COUNT}"
    say "${C_BOLD}Largest files${C_RESET} under $HOME over $LARGE_MIN_SIZE (top $n):"; say ""
    find "$HOME" -xdev -type f -size +"$LARGE_MIN_SIZE" -print0 2>/dev/null \
      | xargs -0 stat -f '%z%t%N' 2>/dev/null | sort -rn | head -n "$n" \
      | while IFS=$'\t' read -r sz path; do printf '  %10s  %s\n' "$(fmt_bytes "$sz")" "$path"; done
    say ""; say "  ${C_DIM}Change the threshold with --min-size (e.g. --min-size 500M).${C_RESET}"
}

cmd_config() {
    case "${1:-show}" in
        init)
            if [ -e "$CONFIG_FILE" ]; then say "config already exists: $CONFIG_FILE"; else
                mkdir -p "$(dirname "$CONFIG_FILE")" && config_template > "$CONFIG_FILE" && say "wrote $CONFIG_FILE — edit it to taste."; fi ;;
        show)  if [ -f "$CONFIG_FILE" ]; then say "# $CONFIG_FILE"; grep -v '^\s*#' "$CONFIG_FILE" | grep -v '^\s*$'; else say "no config file at $CONFIG_FILE (run 'config init')"; fi ;;
        path)  say "$CONFIG_FILE" ;;
        *) die "config: expected init|show|path" 2 ;;
    esac
}

plist_path() { printf '%s/%s.plist' "$LAUNCH_AGENTS_DIR" "$LAUNCH_AGENT_LABEL"; }
cmd_schedule() {
    local sub="${1:-status}"; shift || true
    local pl; pl=$(plist_path)
    case "$sub" in
        install)
            local when="${1:-weekly}"; shift || true
            local tasks="$*"; [ -n "$tasks" ] || tasks="all"
            local cal="<key>Hour</key><integer>12</integer><key>Minute</key><integer>0</integer>"
            case "$when" in
                daily) ;;
                weekly) cal="<key>Weekday</key><integer>1</integer>$cal" ;;
                *) die "schedule install: expected daily|weekly" 2 ;;
            esac
            mkdir -p "$LAUNCH_AGENTS_DIR" "$HOME/Library/Logs" 2>/dev/null
            {
                printf '<?xml version="1.0" encoding="UTF-8"?>\n<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n<plist version="1.0"><dict>\n'
                printf '  <key>Label</key><string>%s</string>\n' "$LAUNCH_AGENT_LABEL"
                printf '  <key>ProgramArguments</key><array>\n    <string>/bin/bash</string>\n    <string>%s</string>\n' "$SCRIPT_PATH"
                for t in $tasks; do printf '    <string>%s</string>\n' "$t"; done
                printf '    <string>--yes</string>\n    <string>--quiet</string>\n  </array>\n'
                printf '  <key>StartCalendarInterval</key><dict>%s</dict>\n' "$cal"
                printf '  <key>StandardOutPath</key><string>%s/Library/Logs/tidy_mac.launchd.log</string>\n' "$HOME"
                printf '  <key>StandardErrorPath</key><string>%s/Library/Logs/tidy_mac.launchd.log</string>\n' "$HOME"
                printf '  <key>RunAtLoad</key><false/>\n</dict></plist>\n'
            } > "$pl"
            ext launchctl bootout "gui/$(id -u)" "$pl"
            ext launchctl bootstrap "gui/$(id -u)" "$pl" || ext launchctl load "$pl"
            say "installed: $when at 12:00 — tasks: $tasks"; say "plist: $pl"
            say "${C_DIM}Note: tasks needing sudo will not get a password prompt from launchd; schedule non-sudo tasks, or configure sudoers.${C_RESET}" ;;
        remove)
            if [ -f "$pl" ]; then ext launchctl bootout "gui/$(id -u)" "$pl"; rm -f "$pl"; say "removed scheduled run."; else say "nothing scheduled."; fi ;;
        status)
            if [ -f "$pl" ]; then
                local when="daily"; grep -q Weekday "$pl" && when="weekly"
                say "installed ($when): $(grep -o '<string>[^<]*</string>' "$pl" | sed 's/<[^>]*>//g' | grep -v '^/bin/bash$' | grep -v "$SCRIPT_PATH" | tr '\n' ' ')"
                say "plist: $pl"
            else say "not installed. Try: tidy_mac.sh schedule install weekly caches trash"; fi ;;
        *) die "schedule: expected install|remove|status" 2 ;;
    esac
}

cmd_completion() {
    local words="list scan run all large schedule config completion version help ${TASK_IDS[*]} $GROUPS_LIST --dry-run --interactive --yes --verbose --quiet --json --trash --permanent --older --exclude --profile --no-color --min-size"
    case "${1:-}" in
        zsh)  printf '#compdef tidy_mac.sh tidy_mac\n_tidy_mac() { local -a w; w=(%s); _describe "tidy_mac" w; }\ncompdef _tidy_mac tidy_mac.sh tidy_mac\n' "$words" ;;
        bash) printf '_tidy_mac() { COMPREPLY=( $(compgen -W "%s" -- "${COMP_WORDS[COMP_CWORD]}") ); }\ncomplete -F _tidy_mac tidy_mac.sh tidy_mac\n' "$words" ;;
        *) die "completion: expected bash|zsh" 2 ;;
    esac
}

usage() {
    cat << USAGE
${C_BOLD}tidy_mac $VERSION${C_RESET} — tidy up a Mac: caches, logs, downloads, screenshots, browsers, dev tools.

${C_BOLD}Usage:${C_RESET} tidy_mac.sh [COMMAND] [TASK|GROUP|PROFILE ...] [OPTIONS]

${C_BOLD}Commands${C_RESET}
  list                       Show every task with its group and flags
  scan [tasks]               Measure what could be reclaimed — changes nothing
  all                        Run every safe task (everything not marked opt-in)
  <task|group|profile> ...   Run the named tasks (see 'list'), e.g. caches logs trash
  large [N]                  Show the N largest files in your home folder
  schedule install daily|weekly [tasks]   Run automatically via launchd; also 'status', 'remove'
  config init|show|path      Manage ~/.config/tidy_mac/config
  completion bash|zsh        Print a shell-completion script
  version, help

${C_BOLD}Options${C_RESET}
  -n, --dry-run        Show what would happen; change nothing
  -i, --interactive    Confirm before each task
  -y, --yes            Don't ask (required for destructive tasks when not interactive)
  -v, --verbose        List every file touched
  -q, --quiet          Only errors (and the log file)
      --json           Machine-readable summary
      --trash          Move user files (Downloads, screenshots, installers) to the Trash instead of deleting
      --older N        Age threshold in days for downloads/installers/screenshots
      --exclude GLOB   Never touch matching names/paths (repeatable)
      --profile NAME   quick | standard | deep | dev
      --min-size SIZE  Threshold for 'large' (default $LARGE_MIN_SIZE)
      --no-color       Plain output
  -h, --help           This

${C_BOLD}Legacy flags${C_RESET} (still work): -s [days] move screenshots · -x [days] delete screenshots · -d downloads ·
  -c caches · -l logs · -b browser history · -f DNS · -t trash · -a the classic set (-d -c -l -b -f -t)

${C_BOLD}Examples${C_RESET}
  tidy_mac.sh scan                        What's eating my disk?
  tidy_mac.sh all -n                      Preview the safe set
  tidy_mac.sh all                         Do it
  tidy_mac.sh dev                         Just the developer caches
  tidy_mac.sh downloads --older 30 -y     Downloads older than a month, no questions
  tidy_mac.sh caches trash --trash -i     Ask before each, Trash instead of delete
  tidy_mac.sh schedule install weekly caches quicklook trash

Everything is logged to $LOG_FILE; each run writes a manifest under $RUNS_DIR.
USAGE
}

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
add_selected() { local t; for t in "$@"; do case " $SELECTED " in *" $t "*) ;; *) SELECTED="$SELECTED $t" ;; esac; done; }
select_word() {   # task | group | profile | all
    local w="$1"
    if task_index "$w" >/dev/null; then add_selected "$w"
    elif is_group "$w"; then add_selected $(group_tasks "$w")
    elif [ "$w" = all ] || [ "$w" = standard ]; then add_selected $(all_tasks)
    elif [ "$w" = quick ]; then add_selected $PROFILE_quick
    elif [ "$w" = deep ]; then add_selected $(all_tasks) $PROFILE_deep_extra
    else die "Unknown task, group or profile: '$w' (try 'tidy_mac.sh list')" 2; fi
}
is_number() { [[ "${1:-}" =~ ^[0-9]+$ ]]; }

parse_args() {
    local a next
    while [ $# -gt 0 ]; do
        a="$1"; shift
        case "$a" in
            -n|--dry-run) DRY_RUN=true ;;
            -i|--interactive) INTERACTIVE=true ;;
            -y|--yes) ASSUME_YES=true ;;
            -v|--verbose) VERBOSE=true ;;
            -q|--quiet) QUIET=true ;;
            --json) JSON=true ;;
            --trash) USE_TRASH=true ;;
            --permanent) USE_TRASH=false ;;
            --no-color) COLOR=never ;;
            --color) COLOR=always ;;
            --older) is_number "${1:-}" || die "--older needs a number of days" 2; OLDER_DAYS=$1; shift ;;
            --older=*) OLDER_DAYS="${a#*=}"; is_number "$OLDER_DAYS" || die "--older needs a number of days" 2 ;;
            --exclude) [ $# -gt 0 ] || die "--exclude needs a pattern" 2; EXCLUDES="$EXCLUDES:$1"; shift ;;
            --exclude=*) EXCLUDES="$EXCLUDES:${a#*=}" ;;
            --profile) [ $# -gt 0 ] || die "--profile needs a name" 2; PROFILE="$1"; shift ;;
            --profile=*) PROFILE="${a#*=}" ;;
            --min-size) [ $# -gt 0 ] || die "--min-size needs a size" 2; LARGE_MIN_SIZE="$1"; shift ;;
            --min-size=*) LARGE_MIN_SIZE="${a#*=}" ;;
            -h|--help|help) COMMAND=help ;;
            --version|version) COMMAND=version ;;
            # legacy single-letter actions
            -s) add_selected screenshots-move; if is_number "${1:-}"; then SCREENSHOT_DAYS=$1; shift; fi ;;
            -x) add_selected screenshots-delete; if is_number "${1:-}"; then SCREENSHOT_DAYS=$1; shift; fi ;;
            -d) add_selected downloads ;;
            -c) add_selected caches ;;
            -l) add_selected logs ;;
            -b) add_selected browser-history ;;
            -f) add_selected dns ;;
            -t) add_selected trash ;;
            -a) add_selected $LEGACY_ALL ;;
            -[a-zA-Z][a-zA-Z]*)   # combined short flags: -ni, -adt
                local letters="${a#-}" i ch; local -a expanded; expanded=()
                for (( i=0; i<${#letters}; i++ )); do ch="${letters:$i:1}"; expanded[${#expanded[@]}]="-$ch"; done
                set -- "${expanded[@]}" "$@" ;;
            -*) die "Unknown option: $a (see --help)" 2 ;;
            *)
                if [ -z "$COMMAND" ]; then
                    case "$a" in
                        list|scan|run|all|large|schedule|config|completion) COMMAND="$a"; [ "$a" = all ] && select_word all; continue ;;
                    esac
                    COMMAND=run
                fi
                POSITIONALS="$POSITIONALS"$'\n'"$a" ;;
        esac
    done
}

main() {
    load_config
    parse_args "$@"
    setup_colors
    [ -n "$PROFILE" ] && select_word "$PROFILE"

    local -a pos; pos=()
    while IFS= read -r p; do [ -n "$p" ] && pos[${#pos[@]}]="$p"; done <<< "$POSITIONALS"

    case "$COMMAND" in
        help)    usage; exit 0 ;;
        version) printf 'tidy_mac %s\n' "$VERSION"; exit 0 ;;
        list)    cmd_list; exit 0 ;;
        large)   cmd_large "${pos[0]:-$LARGE_COUNT}"; exit 0 ;;
        config)  cmd_config "${pos[@]:-show}"; exit 0 ;;
        schedule) cmd_schedule "${pos[@]:-status}"; exit 0 ;;
        completion) cmd_completion "${pos[0]:-}"; exit 0 ;;
        scan)    for p in "${pos[@]:-}"; do [ -n "$p" ] && select_word "$p"; done; cmd_scan; exit 0 ;;
        run|all) for p in "${pos[@]:-}"; do [ -n "$p" ] && select_word "$p"; done ;;
        "")
            if [ -n "$SELECTED" ]; then :               # legacy flags selected tasks
            elif [ -n "$DEFAULT_TASKS" ]; then for p in $DEFAULT_TASKS; do select_word "$p"; done
            else usage; exit 0; fi ;;
    esac
    cmd_run
}

main "$@"
