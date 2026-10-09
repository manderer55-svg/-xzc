#!/usr/bin/env bash
set -euo pipefail
PROJECT_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
WORKSPACE_ROOT="$(dirname -- "$PROJECT_ROOT")"
export XDG_DATA_HOME="${XDG_DATA_HOME:-$WORKSPACE_ROOT/.tools/ashen-veil/godot/data}"
export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$WORKSPACE_ROOT/.tools/ashen-veil/godot/config}"
export XDG_CACHE_HOME="${XDG_CACHE_HOME:-$WORKSPACE_ROOT/.cache/ashen-veil}"
mkdir -p "$XDG_DATA_HOME" "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME"
GODOT_BIN="${GODOT_BIN:-$(command -v godot || command -v godot4 || true)}"
if [[ -z "$GODOT_BIN" ]]; then
    selector="$WORKSPACE_ROOT/.tools/ashen-veil/godot-binary.txt"
    [[ -f "$selector" ]] || { echo 'Install Godot 4.6.3 or run tools/setup_android.sh.' >&2; exit 1; }
    GODOT_BIN="$(cat "$selector")"
fi
exec "$GODOT_BIN" --path "$PROJECT_ROOT" "$@"
