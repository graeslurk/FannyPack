#!/usr/bin/env bash
# Copies this working copy into the game's AddOns folder as FannyPack, to try
# it in the game before a release. Leaves out what the release package leaves
# out (see .pkgmeta) and the git files. The TOC's version stays
# @project-version@, so the options show "dev".
#
#   tools/install-dev.sh                 # WoW Forever, the default install
#   tools/install-dev.sh "/path/to/Interface/AddOns"
#
# After the first install, or when files are added or removed, restart the
# game; for changes to existing files, /reload is enough.

set -euo pipefail

SOURCE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ADDONS="${1:-/mnt/c/Program Files (x86)/World of Warcraft/_forever_/Interface/AddOns}"

if [ ! -d "$ADDONS" ]; then
    echo "No AddOns folder at: $ADDONS" >&2
    exit 1
fi

rsync -a --delete \
    --exclude '.git' --exclude '.github' --exclude '.gitignore' --exclude '.pkgmeta' \
    --exclude 'tools' --exclude 'Art' --exclude 'README.md' \
    "$SOURCE/" "$ADDONS/FannyPack/"

echo "Installed the dev version into $ADDONS/FannyPack"
