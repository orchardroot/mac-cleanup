#!/bin/bash

# A script to tidy up unneeded files on a Mac.
# Version: 2.0.0
# Author: orchardroot

set -uo pipefail

# --- Configuration ---
SCREENSHOTS_DIR="$HOME/Desktop/Screenshots"
DOWNLOADS_DIR="$HOME/Downloads"
USER_CACHE_DIR="$HOME/Library/Caches"
SYSTEM_CACHE_DIR="/Library/Caches"
USER_LOGS_DIR="$HOME/Library/Logs"
TRASH_DIR="$HOME/.Trash"
LOG_FILE="$HOME/.tidy_mac.log"

INTERACTIVE=false
DRY_RUN=false
VERBOSE=false

# Actions to perform (set during first pass)
DO_MOVE_SCREENSHOTS=false
DO_DELETE_SCREENSHOTS=false
DO_DELETE_DOWNLOADS=false
DO_CLEAR_CACHES=false
DO_DELETE_LOGS=false
DO_CLEAR_BROWSER_HISTORY=false
DO_FLUSH_DNS=false
DO_EMPTY_TRASH=false

SCREENSHOT_DAYS=1
DELETE_SCREENSHOT_DAYS=1

# Protected caches that shouldn't be cleared (actively used by system)
PROTECTED_CACHES=(
    "CloudKit"
    "com.apple.nsurlsessiond"
    "com.apple.Safari"
    "com.apple.containermanagerd"
)

# --- Logging ---

log() {
    local message="$(date '+%Y-%m-%d %H:%M:%S') - $1"
    echo "$message" | tee -a "$LOG_FILE"
}

log_verbose() {
    if [ "$VERBOSE" = true ]; then
        log "$1"
    fi
}

# --- Utility Functions ---

usage() {
    cat << EOF
Usage: $0 [OPTIONS]

A Mac cleanup utility to tidy up unneeded files.

OPTIONS:
  -s [days]  Move screenshots to $SCREENSHOTS_DIR
             Optional: specify age in days (default: 1)
  -x [days]  Delete screenshots from the Desktop
             Optional: specify age in days (default: 1)
  -d         Delete all files from the Downloads folder
  -c         Clear system and application caches
  -l         Delete old log files
  -b         Clear browser history for Chrome, Safari, and Firefox
  -f         Flush the DNS cache
  -t         Empty the Trash
  -a         Run all cleanup tasks (excluding screenshot actions)
  -i         Interactive mode - asks for confirmation before each action
  -n         Dry run mode - shows what would be done without doing it
  -v         Verbose mode - shows detailed output
  -h         Display this help message

EXAMPLES:
  $0 -a -i          Run all tasks interactively
  $0 -n -d -t       Dry run: see what deleting downloads and emptying trash would do
  $0 -s 30 -c       Move screenshots older than 30 days, then clear caches
  $0 -x 7 -f -i     Interactively delete old screenshots and flush DNS

NOTES:
  - Screenshot actions (-s, -x) are NOT included in -a (run all)
  - Some actions require sudo privileges
  - Use -n (dry run) first to preview changes safely

EOF
}

confirm() {
    if [ "$INTERACTIVE" = true ]; then
        read -p "$1 (y/n)? " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            return 1
        fi
    fi
    return 0
}

get_dir_size() {
    local dir="$1"
    if [ -d "$dir" ]; then
        du -sh "$dir" 2>/dev/null | cut -f1
    else
        echo "0B"
    fi
}

get_available_space() {
    df -h "$HOME" | awk 'NR==2 {print $4}'
}

check_process_running() {
    local process_name="$1"
    pgrep -x "$process_name" > /dev/null 2>&1
}

# --- Cleanup Functions ---

move_screenshots() {
    local days=${1:-1}
    
    confirm "Move screenshots older than $days day(s) to $SCREENSHOTS_DIR?" || return 0
    
    log "Moving screenshots older than $days day(s) to $SCREENSHOTS_DIR..."
    
    if [ "$DRY_RUN" = true ]; then
        echo "DRY RUN: Would move the following files:"
        find "$HOME/Desktop" \( -name "Screen Shot*.png" -o -name "Screenshot*.png" \) -mtime +"$days" -print 2>/dev/null
        return 0
    fi
    
    if [ ! -d "$SCREENSHOTS_DIR" ]; then
        mkdir -p "$SCREENSHOTS_DIR"
        log "Created directory: $SCREENSHOTS_DIR"
    fi
    
    local count=0
    while IFS= read -r -d '' file; do
        mv "$file" "$SCREENSHOTS_DIR/"
        log_verbose "Moved: $file"
        ((count++))
    done < <(find "$HOME/Desktop" \( -name "Screen Shot*.png" -o -name "Screenshot*.png" \) -mtime +"$days" -print0 2>/dev/null)
    
    log "Moved $count screenshot(s) to $SCREENSHOTS_DIR"
}

delete_screenshots() {
    local days=${1:-1}
    
    confirm "Delete screenshots older than $days day(s) from the Desktop?" || return 0
    
    log "Deleting screenshots older than $days day(s) from the Desktop..."
    
    if [ "$DRY_RUN" = true ]; then
        echo "DRY RUN: Would delete the following files:"
        find "$HOME/Desktop" \( -name "Screen Shot*.png" -o -name "Screenshot*.png" \) -mtime +"$days" -print 2>/dev/null
        return 0
    fi
    
    local count=0
    while IFS= read -r -d '' file; do
        rm -f "$file"
        log_verbose "Deleted: $file"
        ((count++))
    done < <(find "$HOME/Desktop" \( -name "Screen Shot*.png" -o -name "Screenshot*.png" \) -mtime +"$days" -print0 2>/dev/null)
    
    log "Deleted $count screenshot(s) from Desktop"
}

delete_downloads() {
    confirm "Delete all files from the Downloads folder?" || return 0
    
    log "Deleting all files from the Downloads folder..."
    
    local size_before
    size_before=$(get_dir_size "$DOWNLOADS_DIR")
    
    if [ "$DRY_RUN" = true ]; then
        echo "DRY RUN: Would delete all files in $DOWNLOADS_DIR/ (currently $size_before)"
        if [ "$VERBOSE" = true ]; then
            echo "Contents:"
            ls -la "$DOWNLOADS_DIR/" 2>/dev/null
        fi
        return 0
    fi
    
    if [ -d "$DOWNLOADS_DIR" ]; then
        rm -rf "${DOWNLOADS_DIR:?}"/*
        log "Downloads folder cleared (was $size_before)"
    else
        log "Downloads folder not found at $DOWNLOADS_DIR"
    fi
}

clear_caches() {
    confirm "Clear system and application caches?" || return 0
    
    log "Clearing system and application caches..."
    
    local user_size_before system_size_before
    user_size_before=$(get_dir_size "$USER_CACHE_DIR")
    system_size_before=$(get_dir_size "$SYSTEM_CACHE_DIR")
    
    if [ "$DRY_RUN" = true ]; then
        echo "DRY RUN: Would clear user cache in $USER_CACHE_DIR/ (currently $user_size_before)"
        echo "DRY RUN: Would clear system cache in $SYSTEM_CACHE_DIR/ (currently $system_size_before)"
        echo "DRY RUN: Protected caches that would be skipped: ${PROTECTED_CACHES[*]}"
        return 0
    fi
    
    # Clear user caches (with protection for critical caches)
    if [ -d "$USER_CACHE_DIR" ]; then
        for item in "$USER_CACHE_DIR"/*; do
            if [ -e "$item" ]; then
                local basename
                basename=$(basename "$item")
                local protected=false
                
                for protected_cache in "${PROTECTED_CACHES[@]}"; do
                    if [[ "$basename" == "$protected_cache"* ]]; then
                        protected=true
                        log_verbose "Skipping protected cache: $basename"
                        break
                    fi
                done
                
                if [ "$protected" = false ]; then
                    rm -rf "$item"
                    log_verbose "Cleared cache: $basename"
                fi
            fi
        done
        log "User cache cleared (was $user_size_before)"
    else
        log "User cache directory not found at $USER_CACHE_DIR"
    fi
    
    # Clear system caches
    if [ -d "$SYSTEM_CACHE_DIR" ]; then
        sudo rm -rf "${SYSTEM_CACHE_DIR:?}"/*
        log "System cache cleared (was $system_size_before)"
    else
        log "System cache directory not found at $SYSTEM_CACHE_DIR"
    fi
}

delete_logs() {
    confirm "Delete old log files?" || return 0
    
    log "Deleting old log files..."
    
    local user_logs_size
    user_logs_size=$(get_dir_size "$USER_LOGS_DIR")
    
    if [ "$DRY_RUN" = true ]; then
        echo "DRY RUN: Would delete system logs matching /var/log/*.log"
        echo "DRY RUN: Would delete user logs in $USER_LOGS_DIR/ (currently $user_logs_size)"
        return 0
    fi
    
    # System logs - only top-level .log files
    if [ -d /var/log ]; then
        sudo rm -f /var/log/*.log 2>/dev/null
        log "System logs cleared"
    else
        log "System logs directory not found"
    fi
    
    # User logs
    if [ -d "$USER_LOGS_DIR" ]; then
        rm -rf "${USER_LOGS_DIR:?}"/*
        log "User logs cleared (was $user_logs_size)"
    else
        log "User logs directory not found at $USER_LOGS_DIR"
    fi
}

clear_browser_history() {
    confirm "Clear browser history?" || return 0
    
    log "Clearing browser history..."
    
    if [ "$DRY_RUN" = true ]; then
        echo "DRY RUN: Would clear browser history for Chrome, Safari, and Firefox"
        
        # Check which browsers would be affected
        [ -d "$HOME/Library/Application Support/Google/Chrome" ] && echo "  - Google Chrome: would be cleared"
        [ -d "$HOME/Library/Safari" ] && echo "  - Safari: would be cleared"
        [ -d "$HOME/Library/Application Support/Firefox/Profiles" ] && echo "  - Firefox: would be cleared"
        
        return 0
    fi
    
    # Chrome
    local chrome_dir="$HOME/Library/Application Support/Google/Chrome"
    if [ -d "$chrome_dir" ]; then
        if check_process_running "Google Chrome"; then
            log "WARNING: Google Chrome is running. Skipping to prevent data corruption."
            log "         Please close Chrome and run again, or clear manually."
        else
            rm -f "$chrome_dir/Default/History"* 2>/dev/null
            rm -f "$chrome_dir/Default/History-journal"* 2>/dev/null
            log "Chrome history cleared"
        fi
    else
        log_verbose "Google Chrome not found"
    fi
    
    # Safari
    local safari_dir="$HOME/Library/Safari"
    if [ -d "$safari_dir" ]; then
        if check_process_running "Safari"; then
            log "WARNING: Safari is running. Skipping to prevent data corruption."
            log "         Please close Safari and run again, or clear manually."
        else
            rm -f "$safari_dir/History.db"* 2>/dev/null
            log "Safari history cleared"
        fi
    else
        log_verbose "Safari not found"
    fi
    
    # Firefox - handle all profile types
    local firefox_profiles="$HOME/Library/Application Support/Firefox/Profiles"
    if [ -d "$firefox_profiles" ]; then
        if check_process_running "firefox"; then
            log "WARNING: Firefox is running. Skipping to prevent data corruption."
            log "         Please close Firefox and run again, or clear manually."
        else
            local cleared=0
            for profile_dir in "$firefox_profiles"/*/; do
                if [ -d "$profile_dir" ]; then
                    rm -f "${profile_dir}places.sqlite"* 2>/dev/null
                    rm -f "${profile_dir}places.sqlite-wal"* 2>/dev/null
                    rm -f "${profile_dir}places.sqlite-shm"* 2>/dev/null
                    ((cleared++))
                fi
            done
            log "Firefox history cleared ($cleared profile(s))"
        fi
    else
        log_verbose "Firefox not found"
    fi
}

flush_dns() {
    confirm "Flush DNS cache?" || return 0
    
    log "Flushing DNS cache..."
    
    if [ "$DRY_RUN" = true ]; then
        echo "DRY RUN: Would flush DNS cache (dscacheutil -flushcache && killall -HUP mDNSResponder)"
        return 0
    fi
    
    sudo dscacheutil -flushcache
    sudo killall -HUP mDNSResponder 2>/dev/null
    log "DNS cache flushed"
}

empty_trash() {
    confirm "Empty the Trash?" || return 0
    
    log "Emptying the Trash..."
    
    local trash_size
    trash_size=$(get_dir_size "$TRASH_DIR")
    
    if [ "$DRY_RUN" = true ]; then
        echo "DRY RUN: Would empty the Trash (currently $trash_size)"
        return 0
    fi
    
    if [ -d "$TRASH_DIR" ]; then
        rm -rf "${TRASH_DIR:?}"/*
        log "Trash emptied (was $trash_size)"
    else
        log "Trash directory not found at $TRASH_DIR"
    fi
}

show_summary() {
    echo ""
    echo "======================================"
    echo "        CLEANUP SUMMARY"
    echo "======================================"
    echo ""
    echo "The following actions will be performed:"
    echo ""
    
    [ "$DO_MOVE_SCREENSHOTS" = true ] && echo "  ✓ Move screenshots older than $SCREENSHOT_DAYS day(s)"
    [ "$DO_DELETE_SCREENSHOTS" = true ] && echo "  ✓ Delete screenshots older than $DELETE_SCREENSHOT_DAYS day(s)"
    [ "$DO_DELETE_DOWNLOADS" = true ] && echo "  ✓ Delete all files from Downloads"
    [ "$DO_CLEAR_CACHES" = true ] && echo "  ✓ Clear system and application caches"
    [ "$DO_DELETE_LOGS" = true ] && echo "  ✓ Delete old log files"
    [ "$DO_CLEAR_BROWSER_HISTORY" = true ] && echo "  ✓ Clear browser history"
    [ "$DO_FLUSH_DNS" = true ] && echo "  ✓ Flush DNS cache"
    [ "$DO_EMPTY_TRASH" = true ] && echo "  ✓ Empty the Trash"
    
    echo ""
    echo "Current available space: $(get_available_space)"
    echo ""
    
    if [ "$DRY_RUN" = true ]; then
        echo "[DRY RUN MODE - No changes will be made]"
        echo ""
    fi
}

# --- Main Script ---

# Show help if no arguments
if [[ $# -eq 0 ]]; then
    usage
    exit 0
fi

# First pass: Set flags (interactive, dry-run, verbose) and record actions
while getopts ":s:x:dclbfatinvh" opt; do
    case $opt in
        s)
            DO_MOVE_SCREENSHOTS=true
            # Handle optional argument
            if [[ -n "$OPTARG" && "$OPTARG" =~ ^[0-9]+$ ]]; then
                SCREENSHOT_DAYS="$OPTARG"
            fi
            ;;
        x)
            DO_DELETE_SCREENSHOTS=true
            if [[ -n "$OPTARG" && "$OPTARG" =~ ^[0-9]+$ ]]; then
                DELETE_SCREENSHOT_DAYS="$OPTARG"
            fi
            ;;
        d)
            DO_DELETE_DOWNLOADS=true
            ;;
        c)
            DO_CLEAR_CACHES=true
            ;;
        l)
            DO_DELETE_LOGS=true
            ;;
        b)
            DO_CLEAR_BROWSER_HISTORY=true
            ;;
        f)
            DO_FLUSH_DNS=true
            ;;
        t)
            DO_EMPTY_TRASH=true
            ;;
        a)
            DO_DELETE_DOWNLOADS=true
            DO_CLEAR_CACHES=true
            DO_DELETE_LOGS=true
            DO_CLEAR_BROWSER_HISTORY=true
            DO_FLUSH_DNS=true
            DO_EMPTY_TRASH=true
            ;;
        i)
            INTERACTIVE=true
            ;;
        n)
            DRY_RUN=true
            ;;
        v)
            VERBOSE=true
            ;;
        h)
            usage
            exit 0
            ;;
        \?)
            echo "Invalid option: -$OPTARG" >&2
            usage
            exit 1
            ;;
        :)
            # Handle missing argument for -s or -x (use default)
            case $OPTARG in
                s)
                    DO_MOVE_SCREENSHOTS=true
                    ;;
                x)
                    DO_DELETE_SCREENSHOTS=true
                    ;;
            esac
            ;;
    esac
done

# Record space before cleanup
SPACE_BEFORE=$(get_available_space)

# Show summary of planned actions
show_summary

# If interactive and not dry-run, ask for overall confirmation
if [ "$INTERACTIVE" = true ] && [ "$DRY_RUN" = false ]; then
    read -p "Proceed with cleanup? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Cleanup cancelled."
        exit 0
    fi
    echo ""
fi

# Second pass: Execute actions in logical order
log "Starting cleanup..."

[ "$DO_MOVE_SCREENSHOTS" = true ] && move_screenshots "$SCREENSHOT_DAYS"
[ "$DO_DELETE_SCREENSHOTS" = true ] && delete_screenshots "$DELETE_SCREENSHOT_DAYS"
[ "$DO_DELETE_DOWNLOADS" = true ] && delete_downloads
[ "$DO_CLEAR_CACHES" = true ] && clear_caches
[ "$DO_DELETE_LOGS" = true ] && delete_logs
[ "$DO_CLEAR_BROWSER_HISTORY" = true ] && clear_browser_history
[ "$DO_FLUSH_DNS" = true ] && flush_dns
[ "$DO_EMPTY_TRASH" = true ] && empty_trash

# Final report
SPACE_AFTER=$(get_available_space)

echo ""
echo "======================================"
echo "        CLEANUP COMPLETE"
echo "======================================"
echo ""
echo "Space before: $SPACE_BEFORE"
echo "Space after:  $SPACE_AFTER"
echo ""
log "Cleanup complete. Space: $SPACE_BEFORE -> $SPACE_AFTER"
