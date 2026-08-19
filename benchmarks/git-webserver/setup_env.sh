#!/usr/bin/env bash
# Set up the docker-free git-webserver task environment in $1 (a fresh sandbox).
# Creates an empty bare repo (default branch master) and an empty webroot.
# The AGENT must write the deploy hook and start the HTTP server.
set -euo pipefail
SB="$1"
[ -d "$SB" ] && rm -rf "$SB"
mkdir -p "$SB/webroot"
git init -q -b master --bare "$SB/git/server.git"
# touch a marker so the repo is not empty for some git versions
echo "task env ready: bare repo at $SB/git/server.git (branch master), webroot at $SB/webroot"
