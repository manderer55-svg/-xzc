#!/usr/bin/env bash
# Export is offline once setup_android.sh has installed the official toolchain.
set -euo pipefail
PROJECT_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
WORKSPACE_ROOT="$(dirname -- "$PROJECT_ROOT")"
TOOL_ROOT="${ASHEN_TOOL_ROOT:-$WORKSPACE_ROOT/.tools/ashen-veil}"
CACHE_ROOT="${ASHEN_CACHE_ROOT:-$WORKSPACE_ROOT/.cache/ashen-veil}"
SDK_ROOT="$TOOL_ROOT/android-sdk"
[[ -f "$TOOL_ROOT/godot-binary.txt" && -f "$SDK_ROOT/build-tools/36.0.0/apksigner" ]] || {
    echo 'Run tools/setup_android.sh before exporting.' >&2
    exit 1
}
export XDG_DATA_HOME="$TOOL_ROOT/godot/data"
export XDG_CONFIG_HOME="$TOOL_ROOT/godot/config"
export XDG_CACHE_HOME="$CACHE_ROOT"
export ANDROID_HOME="$SDK_ROOT"
export ANDROID_SDK_ROOT="$SDK_ROOT"
export ANDROID_USER_HOME="$TOOL_ROOT/android-user"
export JAVA_HOME="$(cat "$TOOL_ROOT/java-root.txt")"
GODOT_BIN="${GODOT_BIN:-$(cat "$TOOL_ROOT/godot-binary.txt")}"
APK_PATH="${1:-$PROJECT_ROOT/builds/ashen-veil-debug.apk}"
if [[ "$APK_PATH" != /* ]]; then
    APK_PATH="$PROJECT_ROOT/$APK_PATH"
fi
mkdir -p -- "$(dirname -- "$APK_PATH")"
"$GODOT_BIN" --headless --path "$PROJECT_ROOT" --editor --import
"$GODOT_BIN" --headless --path "$PROJECT_ROOT" --export-debug Android "$APK_PATH"
"$SDK_ROOT/build-tools/36.0.0/apksigner" verify --verbose "$APK_PATH"
"$SDK_ROOT/build-tools/36.0.0/zipalign" -c -P 16 4 "$APK_PATH"
"$SDK_ROOT/build-tools/36.0.0/aapt" dump badging "$APK_PATH" | sed -n '/^package:/p; /^sdkVersion:/p; /^targetSdkVersion:/p; /^application-label:/p; /^native-code:/p; /^uses-permission:/p'
sha256sum "$APK_PATH"
echo "Verified Android debug APK: $APK_PATH"
