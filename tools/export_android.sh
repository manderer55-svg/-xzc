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
BASELINE_APK="${ASHEN_BASELINE_APK:-}"
BASELINE_CERTIFICATE=""
BASELINE_PACKAGE=""
BASELINE_VERSION_CODE=""
package_from_badging() {
    sed -n "s/^package: name='\([^']*\)'.*/\1/p"
}
version_from_badging() {
    sed -n "s/^package: .*versionCode='\([^']*\)'.*/\1/p"
}
if [[ -n "$BASELINE_APK" ]]; then
    [[ "$BASELINE_APK" == /* ]] || BASELINE_APK="$PROJECT_ROOT/$BASELINE_APK"
    [[ -f "$BASELINE_APK" ]] || { echo "Previous APK does not exist: $BASELINE_APK" >&2; exit 1; }
    BASELINE_CERTIFICATE="$("$SDK_ROOT/build-tools/36.0.0/apksigner" verify --print-certs "$BASELINE_APK" | sed -n 's/^Signer #1 certificate SHA-256 digest: //p')"
    BASELINE_BADGING="$("$SDK_ROOT/build-tools/36.0.0/aapt" dump badging "$BASELINE_APK")"
    BASELINE_PACKAGE="$(printf '%s\n' "$BASELINE_BADGING" | package_from_badging)"
    BASELINE_VERSION_CODE="$(printf '%s\n' "$BASELINE_BADGING" | version_from_badging)"
    [[ -n "$BASELINE_CERTIFICATE" && -n "$BASELINE_PACKAGE" && "$BASELINE_VERSION_CODE" =~ ^[0-9]+$ ]] || {
        echo 'Could not read the previous APK signing certificate/package/version.' >&2
        exit 1
    }
fi
mkdir -p -- "$(dirname -- "$APK_PATH")"
"$GODOT_BIN" --headless --path "$PROJECT_ROOT" --editor --import
"$GODOT_BIN" --headless --path "$PROJECT_ROOT" --export-debug Android "$APK_PATH"
SIGNING_REPORT="$("$SDK_ROOT/build-tools/36.0.0/apksigner" verify --verbose --print-certs "$APK_PATH")"
printf '%s\n' "$SIGNING_REPORT" | sed -n '/^Verifies/p; /^Verified /p; /^Number of signers:/p; /^Signer #1 certificate SHA-256 digest:/p'
FINAL_CERTIFICATE="$(printf '%s\n' "$SIGNING_REPORT" | sed -n 's/^Signer #1 certificate SHA-256 digest: //p')"
"$SDK_ROOT/build-tools/36.0.0/zipalign" -c -P 16 4 "$APK_PATH"
FINAL_BADGING="$("$SDK_ROOT/build-tools/36.0.0/aapt" dump badging "$APK_PATH")"
printf '%s\n' "$FINAL_BADGING" | sed -n '/^package:/p; /^sdkVersion:/p; /^targetSdkVersion:/p; /^application-label:/p; /^native-code:/p; /^uses-permission:/p'
if [[ -n "$BASELINE_APK" ]]; then
    FINAL_PACKAGE="$(printf '%s\n' "$FINAL_BADGING" | package_from_badging)"
    FINAL_VERSION_CODE="$(printf '%s\n' "$FINAL_BADGING" | version_from_badging)"
    [[ "$FINAL_CERTIFICATE" == "$BASELINE_CERTIFICATE" && "$FINAL_PACKAGE" == "$BASELINE_PACKAGE" ]] || {
        echo 'Update verification failed: the new APK must retain the previous package and signing certificate.' >&2
        exit 1
    }
    [[ "$FINAL_VERSION_CODE" =~ ^[0-9]+$ ]] && (( FINAL_VERSION_CODE >= BASELINE_VERSION_CODE )) || {
        echo 'Update verification failed: Android versionCode cannot decrease.' >&2
        exit 1
    }
    echo "Verified update compatibility: same package/signing certificate; versionCode $BASELINE_VERSION_CODE -> $FINAL_VERSION_CODE."
fi
sha256sum "$APK_PATH"
echo "Verified Android debug APK: $APK_PATH"
