#!/bin/bash
# Symlink tidy_mac.sh onto your PATH as `tidy-mac`, so `git pull` updates the live tool.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
target="${1:-/usr/local/bin}"
mkdir -p "$target" 2>/dev/null || sudo mkdir -p "$target"
if [ -w "$target" ]; then ln -sf "$here/tidy_mac.sh" "$target/tidy-mac"; else sudo ln -sf "$here/tidy_mac.sh" "$target/tidy-mac"; fi
chmod +x "$here/tidy_mac.sh"
echo "installed: $target/tidy-mac -> $here/tidy_mac.sh"
echo "shell completion:  tidy-mac completion zsh > ~/.zsh/completions/_tidy-mac   (or eval \"\$(tidy-mac completion bash)\")"
echo "try:               tidy-mac scan"
