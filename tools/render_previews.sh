#!/usr/bin/env bash
# Render the real game with software OpenGL on a local display, never a web preview.
set -euo pipefail
PROJECT_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
WORKSPACE_ROOT="$(dirname -- "$PROJECT_ROOT")"
export DISPLAY="${DISPLAY:-:98}"
DISPLAY_PID=""
cleanup() { if [[ -n "$DISPLAY_PID" ]]; then kill "$DISPLAY_PID" 2>/dev/null || true; fi; }
trap cleanup EXIT
if ! xdpyinfo -display "$DISPLAY" >/dev/null 2>&1; then
    [[ -x /usr/lib/xorg/Xorg && -f /usr/lib/xorg/modules/drivers/dummy_drv.so ]] || {
        echo 'A working X display, or Xorg with the dummy driver, is needed to render screenshots.' >&2
        exit 1
    }
    mkdir -p "$WORKSPACE_ROOT/.cache/ashen-veil"
    /usr/lib/xorg/Xorg "$DISPLAY" -noreset -nolisten tcp \
        -config "$PROJECT_ROOT/tools/virtual-display.conf" \
        -logfile "$WORKSPACE_ROOT/.cache/ashen-veil/xorg-preview.log" \
        >"$WORKSPACE_ROOT/.cache/ashen-veil/xorg-preview.stdout.log" 2>&1 &
    DISPLAY_PID="$!"
    for attempt in {1..30}; do
        xdpyinfo -display "$DISPLAY" >/dev/null 2>&1 && break
        kill -0 "$DISPLAY_PID" 2>/dev/null || { echo 'Virtual display failed; inspect xorg-preview.log.' >&2; exit 1; }
        sleep 0.1
    done
    xdpyinfo -display "$DISPLAY" >/dev/null 2>&1 || { echo 'Virtual display was not ready.' >&2; exit 1; }
fi
bash "$PROJECT_ROOT/tools/run_game.sh" --headless --editor --import
bash "$PROJECT_ROOT/tools/run_game.sh" --audio-driver Dummy --resolution 720x1280 -- --smoke
