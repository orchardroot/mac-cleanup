#!/bin/bash

# A script to tidy up unneeded files on a Mac.

# --- Configuration ---
SCREENSHOTS_DIR=~/Desktop/Screenshots

# --- Functions ---

usage() {
  echo "Usage: $0 [-s] [-d] [-c] [-l] [-b] [-f] [-h]"
  echo "  -s: Move screenshots to $SCREENSHOTS_DIR instead of deleting."
  echo "  -d: Delete all files from the Downloads folder."
  echo "  -c: Clear system and application caches."
  echo "  -l: Delete old log files."
  echo "  -b: Clear browser history for Chrome, Safari, and Firefox."
  echo "  -f: Flush the DNS cache."
  echo "  -h: Display this help message."
}

move_screenshots() {
  echo "Moving screenshots to $SCREENSHOTS_DIR..."
  if [ ! -d "$SCREENSHOTS_DIR" ]; then
    mkdir -p "$SCREENSHOTS_DIR"
  fi
  find ~/Desktop -name "Screen Shot*.png" -mtime +1 -exec mv {} "$SCREENSHOTS_DIR" \;
  echo "Screenshots moved."
}

delete_screenshots() {
    echo "Searching for and deleting screenshots from the Desktop..."
    find ~/Desktop -name "Screen Shot*.png" -mtime +1 -delete -print
}

delete_downloads() {
  echo "Deleting all files from the Downloads folder..."
  if [ -d ~/Downloads ]; then
    rm -rf ~/Downloads/*
    echo "Downloads folder cleared."
  else
    echo "Downloads folder not found."
  fi
}

clear_caches() {
  echo "Clearing system and application caches..."
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
}

delete_logs() {
  echo "Deleting old log files..."
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
}

clear_browser_history() {
  echo "Clearing browser history..."

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
}

flush_dns() {
  echo "Flushing DNS cache..."
  sudo dscacheutil -flushcache
  sudo killall -HUP mDNSResponder
  echo "DNS cache flushed."
}

# --- Main Script ---

if [[ $# -eq 0 ]] ; then
    usage
    exit 0
fi

while getopts "sdclbfh" opt; do
  case $opt in
    s)
      move_screenshots
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
    h)
      usage
      ;;
    \?)
      usage
      ;;
  esac
done

# Default action for screenshots if -s is not provided
if ! [[ "$@" =~ "-s" ]]; then
    delete_screenshots
fi


echo "Tidy up complete!"
