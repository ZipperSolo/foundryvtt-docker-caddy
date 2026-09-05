#!/usr/bin/env bash
#
# Roll the FoundryVTT deployment back from v14 to a pinned v13 core.
#
# The rollback has three parts, because a core downgrade alone leaves an
# unopenable world:
#   1. restore the world from its last v13 snapshot (Foundry .bak = a ZIP)
#   2. replace the world's game system with a v13-compatible release
#   3. pin the container image to the target core version
#
# Anything replaced is moved aside under $ASIDE_DIR, never deleted.
#
# Usage: rollback-to-v13.sh [--dry-run]

set -euo pipefail

CORE_TAG="${CORE_TAG:-13.351}"
WORLD="${WORLD:-abomination-vaults}"
SNAPSHOT="${SNAPSHOT:-world.abomination-vaults.2026-07-11.1783789865277.bak}"
SYSTEM_ID="${SYSTEM_ID:-pf2e}"
SYSTEM_VER="${SYSTEM_VER:-7.12.2}"
SYSTEM_URL="${SYSTEM_URL:-https://github.com/foundryvtt/pf2e/releases/download/pf2e-$SYSTEM_VER/system.zip}"

FOUNDRY_ROOT="${FOUNDRY_ROOT:-$HOME/services/foundryvtt}"
SERVICE="${SERVICE:-foundryvtt.service}"
UNIT="$HOME/.config/systemd/user/$SERVICE"

DATA="$FOUNDRY_ROOT/data"
WORLDS="$DATA/Data/worlds"
SYSTEMS="$DATA/Data/systems"
SNAP_PATH="$DATA/Backups/worlds/$WORLD/$SNAPSHOT"
ASIDE_DIR="$HOME/backups/foundryvtt/pre-v13-rollback-$(date +%Y%m%d-%H%M%S)"

DRY=0
[ "${1:-}" = "--dry-run" ] && DRY=1
run() { echo "  + $*"; [ "$DRY" = 1 ] || "$@"; }

echo "==> preflight"
for p in "$SNAP_PATH" "$UNIT" "$WORLDS/$WORLD" "$SYSTEMS/$SYSTEM_ID"; do
    [ -e "$p" ] || { echo "error: missing $p" >&2; exit 1; }
    echo "  ok $p"
done
python3 -c "import zipfile,sys; zipfile.ZipFile(sys.argv[1]).testzip()" "$SNAP_PATH"
echo "  ok snapshot ZIP integrity"

echo "==> downloading $SYSTEM_ID $SYSTEM_VER"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
curl -sSL --fail -o "$TMP/system.zip" "$SYSTEM_URL"
python3 -c "import zipfile,sys; zipfile.ZipFile(sys.argv[1]).testzip()" "$TMP/system.zip"
echo "  ok $(du -h "$TMP/system.zip" | cut -f1) downloaded and valid"

echo "==> stopping $SERVICE"
run systemctl --user stop "$SERVICE"

echo "==> moving current state aside -> $ASIDE_DIR"
run mkdir -p "$ASIDE_DIR"
run cp -a "$UNIT" "$ASIDE_DIR/$SERVICE"
run mv "$WORLDS/$WORLD" "$ASIDE_DIR/world-$WORLD-v14"
run mv "$SYSTEMS/$SYSTEM_ID" "$ASIDE_DIR/system-$SYSTEM_ID-v14"

echo "==> restoring world '$WORLD' from $SNAPSHOT"
if [ "$DRY" = 0 ]; then
    mkdir -p "$WORLDS/$WORLD"
    python3 -c "import zipfile,sys; zipfile.ZipFile(sys.argv[1]).extractall(sys.argv[2])" \
        "$SNAP_PATH" "$WORLDS/$WORLD"
fi
echo "  + extracted to $WORLDS/$WORLD"

echo "==> installing $SYSTEM_ID $SYSTEM_VER"
if [ "$DRY" = 0 ]; then
    python3 -c "import zipfile,sys; zipfile.ZipFile(sys.argv[1]).extractall(sys.argv[2])" \
        "$TMP/system.zip" "$TMP/sys"
    # Some system archives nest everything under a single top-level directory.
    src="$TMP/sys"
    if [ ! -f "$src/system.json" ]; then
        inner="$(find "$src" -maxdepth 2 -name system.json -print -quit)"
        [ -n "$inner" ] || { echo "error: no system.json in archive" >&2; exit 1; }
        src="$(dirname "$inner")"
    fi
    mv "$src" "$SYSTEMS/$SYSTEM_ID"
fi
echo "  + installed to $SYSTEMS/$SYSTEM_ID"

echo "==> pinning core image to $CORE_TAG"
run sed -i -E "s#(docker\.io/felddy/foundryvtt):[A-Za-z0-9._-]+#\1:$CORE_TAG#" "$UNIT"
grep -n 'felddy/foundryvtt' "$UNIT" | sed 's/^/  /'

echo "==> starting $SERVICE"
run systemctl --user daemon-reload
run systemctl --user start "$SERVICE"

echo
echo "rollback complete. previous state kept at:"
echo "  $ASIDE_DIR"
