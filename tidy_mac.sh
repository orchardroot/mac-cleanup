#!/bin/bash

# A script to tidy up unneeded files on a Mac.

# --- Configuration ---
SCREENSHOTS_DIR=~/Desktop/Screenshots
INTERACTIVE=false
DRY_RUN=false

# --- Functions ---

usage() {
  echo "Usage: $0 [-s [days]] [-x [days]] [-d] [-c] [-l] [-b] [-f] [-t] [-a] [-i] [-n] [-h]"
  echo "  -s [days]: Move screenshots to $SCREENSHOTS_DIR. Optional: specify days to keep (default: 1)."
  echo "  -x [days]: Delete screenshots from the Desktop. Optional: specify days to keep (default: 1)."
  echo "  -d: Delete all files from the Downloads folder."
  echo "  -c: Clear system and application caches."
  echo "  -l: Delete old log files."
  echo "  -b: Clear browser history for Chrome, Safari, and Firefox."
  echo "  -f: Flush the DNS cache."
  echo "  -t: Empty the Trash."
  echo "  -a: Run all cleanup tasks (excluding screenshot actions)."
  echo "  -i: Interactive mode. Asks for confirmation before each action."
  echo "  -n: Dry run mode. Shows what would be done without actually doing it."
  echo "  -h: Display this help message."
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

move_screenshots() {
    local days=${1:-1}
    confirm "Move screenshots older than $days day(s) to $SCREENSHOTS_DIR?" || return
    echo "Moving screenshots older than $days day(s) to $SCREENSHOTS_DIR..."
    if [ "$DRY_RUN" = true ]; then
        echo "DRY RUN: Would move files found by: find ~/Desktop -name \"Screen Shot*.png\" -mtime +$days"
    else
        if [ ! -d "$SCREENSHOTS_DIR" ]; then
            mkdir -p "$SCREENSHOTS_DIR"
        fi
        find ~/Desktop -name "Screen Shot*.png" -mtime +$days -exec mv {} "$SCREENSHOTS_DIR" \;
        echo "Screenshots moved."
    fi
}

delete_screenshots() {
    local days=${1:-1}
    confirm "Delete screenshots older than $days day(s) from the Desktop?" || return
    echo "Searching for and deleting screenshots older than $days day(s) from the Desktop..."
    if [ "$DRY_RUN" = true ]; then
        echo "DRY RUN: Would delete files found by: find ~/Desktop -name \"Screen Shot*.png\" -mtime +$days"
    else
        find ~/Desktop -name "Screen Shot*.png" -mtime +$days -delete -print
    fi
}

delete_downloads() {
    confirm "Delete all files from the Downloads folder?" || return
    echo "Deleting all files from the Downloads folder..."
    if [ "$DRY_RUN" = true ]; then
        echo "DRY RUN: Would delete all files in ~/Downloads/"
    else
        if [ -d ~/Downloads ]; then
            rm -rf ~/Downloads/*
            echo "Downloads folder cleared."
        else
            echo "Downloads folder not found."
        fi
    fi
}

clear_caches() {
    confirm "Clear system and application caches?" || return
    echo "Clearing system and application caches..."
    if [ "$DRY_RUN" = true ]; then
        echo "DRY RUN: Would clear user cache in ~/Library/Caches/"
        echo "DRY RUN: Would clear system cache in /Library/Caches/"
    else
        if [ -d ~/Library/Caches ]; then
            rm -rf ~/Library/Caches/*
            echo "User cache cleared."
        else
            echo "User cache not found."
        fi
        if [ -d /Library/Caches ]; then
            sudo rm -rf /Library/Caches/*
            echo "System cache cleared."
        else
            echo "System cache not found."
        fi
    fi
}

delete_logs() {
    confirm "Delete old log files?" || return
    echo "Deleting old log files..."
    if [ "$DRY_RUN" = true ]; then
        echo "DRY RUN: Would delete system logs in /var/log/"
        echo "DRY RUN: Would delete user logs in ~/Library/Logs/"
    else
        if [ -d /var/log ]; then
            sudo rm -rf /var/log/*.log
            echo "System logs cleared."
        else
            echo "System logs not found."
        fi
        if [ -d ~/Library/Logs ]; then
            rm -rf ~/Library/Logs/*
            echo "User logs cleared."
        else
            echo "User logs not found."
        fi
    fi
}

clear_browser_history() {
    confirm "Clear browser history?" || return
    echo "Clearing browser history..."
    if [ "$DRY_RUN" = true ]; then
        echo "DRY RUN: Would clear browser history for Chrome, Safari, and Firefox."
    else
        # Chrome
        if [ -d ~/Library/Application\ Support/Google/Chrome ]; then
            rm -rf ~/Library/Application\ Support/Google/Chrome/Default/History*
            echo "Chrome history cleared."
        else
            echo "Google Chrome not found."
        fi

        # Safari
        if [ -d ~/Library/Safari ]; then
            rm -rf ~/Library/Safari/History.db*
            echo "Safari history cleared."
        else
            echo "Safari not found."
        fi

        # Firefox
        if [ -d ~/Library/Application\ Support/Firefox/Profiles ]; then
            rm -rf ~/Library/Application\ Support/Firefox/Profiles/*_default/places.sqlite*
            echo "Firefox history cleared."
        else
            echo "Firefox not found."
        fi
    fi
}

flush_dns() {
    confirm "Flush DNS cache?" || return
    echo "Flushing DNS cache..."
    if [ "$DRY_RUN" = true ]; then
        echo "DRY RUN: Would flush DNS cache."
    else
        sudo dscacheutil -flushcache
        sudo killall -HUP mDNSResponder
        echo "DNS cache flushed."
    fi
}

empty_trash() {
    confirm "Empty the Trash?" || return
    echo "Emptying the Trash..."
    if [ "$DRY_RUN" = true ]; then
        echo "DRY RUN: Would empty the Trash."
    else
        rm -rf ~/.Trash/*
        echo "Trash emptied."
    fi
}

# --- Main Script ---

if [[ $# -eq 0 ]] ; then
    usage
    exit 0
fi

while getopts "s:x:dclbfatinh" opt; do
  case $opt in
    s)
      move_screenshots "${OPTARG:-1}"
      ;;
    x)
      delete_screenshots "${OPTARG:-1}"
      ;;
    d)
      delete_downloads
      ;;
    c)
      clear_caches
      ;;
    l)
      delete_logs
      ;;
    b)
      clear_browser_history
      ;;
    f)
      flush_dns
      ;;
    t)
      empty_trash
      ;;
    a)
      delete_downloads
      clear_caches
      delete_logs
      clear_browser_history
      flush_dns
      empty_trash
      ;;
    i)
      INTERACTIVE=true
      ;;
    n)
      DRY_RUN=true
      ;;
    h)
      usage
      ;;
    \?)
      usage
      ;;
  esac
done

echo "Tidy up complete!"
