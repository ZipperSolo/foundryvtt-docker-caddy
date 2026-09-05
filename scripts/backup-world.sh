#!/usr/bin/env bash
#
# Back up a FoundryVTT world from the rootless-Podman deployment on this host.
#
# Usage:
#   backup-world.sh <world-id> [--full]
#
#   --full   Also archive the complete Data tree (systems, modules, all worlds).
#
# Worlds use LevelDB, so the server is stopped for the copy and started again
# afterwards, also when the copy fails.
#
# Environment overrides:
#   FOUNDRY_ROOT   default: $HOME/services/foundryvtt
#   BACKUP_DIR     default: $HOME/backups/foundryvtt
#   SERVICE        default: foundryvtt.service

set -euo pipefail

FOUNDRY_ROOT="${FOUNDRY_ROOT:-$HOME/services/foundryvtt}"
BACKUP_DIR="${BACKUP_DIR:-$HOME/backups/foundryvtt}"
SERVICE="${SERVICE:-foundryvtt.service}"

DATA_DIR="$FOUNDRY_ROOT/data"
WORLDS_DIR="$DATA_DIR/Data/worlds"

WORLD="${1:-}"
FULL=0
[ "${2:-}" = "--full" ] && FULL=1

if [ -z "$WORLD" ]; then
    echo "usage: $(basename "$0") <world-id> [--full]" >&2
    echo "available worlds:" >&2
    ls -1 "$WORLDS_DIR" 2>/dev/null | sed 's/^/  /' >&2
    exit 2
fi

if [ ! -d "$WORLDS_DIR/$WORLD" ]; then
    echo "error: no world '$WORLD' in $WORLDS_DIR" >&2
    exit 1
fi

STAMP="$(date +%Y%m%d-%H%M%S)"
DEST="$BACKUP_DIR/$STAMP-$WORLD"
mkdir -p "$DEST"

# Record what the world was running on, so a restore knows what it needs.
manifest() {
    echo "backup_date: $(date -Is)"
    echo "host: $(hostname)"
    echo "world: $WORLD"
    echo "image: $(grep -oE 'docker\.io/felddy/foundryvtt:[^ ]*' \
        "$HOME/.config/systemd/user/$SERVICE" 2>/dev/null || echo unknown)"
    echo "--- world.json ---"
    cat "$WORLDS_DIR/$WORLD/world.json"
    echo "--- systems ---"
    for f in "$DATA_DIR"/Data/systems/*/system.json; do
        [ -e "$f" ] || continue
        python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(d["id"], d["version"])' "$f"
    done
    echo "--- modules ---"
    for f in "$DATA_DIR"/Data/modules/*/module.json; do
        [ -e "$f" ] || continue
        python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(d["id"], d.get("version","?"))' "$f"
    done
}
manifest > "$DEST/MANIFEST.txt"

WAS_ACTIVE=0
if systemctl --user is-active --quiet "$SERVICE"; then
    WAS_ACTIVE=1
    echo "==> stopping $SERVICE"
    systemctl --user stop "$SERVICE"
fi

restart_service() {
    if [ "$WAS_ACTIVE" = 1 ]; then
        echo "==> starting $SERVICE"
        systemctl --user start "$SERVICE"
    fi
}
trap restart_service EXIT

echo "==> archiving world '$WORLD'"
tar -czf "$DEST/$WORLD.tar.gz" -C "$WORLDS_DIR" "$WORLD"

echo "==> archiving Config"
tar -czf "$DEST/Config.tar.gz" -C "$DATA_DIR" Config

if [ "$FULL" = 1 ]; then
    echo "==> archiving full Data tree (this takes a while)"
    tar -czf "$DEST/Data-full.tar.gz" -C "$DATA_DIR" Data
fi

echo "==> verifying archives"
for a in "$DEST"/*.tar.gz; do
    tar -tzf "$a" > /dev/null
    sha256sum "$a" >> "$DEST/SHA256SUMS"
done

echo
echo "backup complete: $DEST"
ls -lh "$DEST"
