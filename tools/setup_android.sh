#!/usr/bin/env bash
# Official prebuilt Godot templates: no Gradle, NDK, or C++ compilation required.
set -euo pipefail

PROJECT_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
WORKSPACE_ROOT="$(dirname -- "$PROJECT_ROOT")"
TOOL_ROOT="${ASHEN_TOOL_ROOT:-$WORKSPACE_ROOT/.tools/ashen-veil}"
DOWNLOAD_ROOT="${ASHEN_DOWNLOAD_ROOT:-$WORKSPACE_ROOT/.cache/ashen-veil-downloads}"
CACHE_ROOT="${ASHEN_CACHE_ROOT:-$WORKSPACE_ROOT/.cache/ashen-veil}"
SDK_ROOT="$TOOL_ROOT/android-sdk"
GODOT_VERSION="4.6.3"
GODOT_RELEASE="${GODOT_VERSION}-stable"
GODOT_TEMPLATE_SHA512="da606b61c10157844f8300172df374472665f95015495cb1a7cd132c40ede404faa96cc1016a4b9662db9909ddea69632c4948b2cd11163438dad4808881fb68"
GODOT_BINARY_SHA512="a035258da32b77f966a5376f9fa29c30a6adde826a85ba918e1605bd1fc9823eba7d85f1dd5e748956bd2ba72827c0025ffa11bb82aec91128c407a2e723c99c"

for required in curl unzip python3 sha1sum sha512sum java keytool; do
    command -v "$required" >/dev/null || { echo "Required command is missing: $required" >&2; exit 1; }
done
mkdir -p "$TOOL_ROOT" "$DOWNLOAD_ROOT" "$CACHE_ROOT" "$SDK_ROOT"
export XDG_DATA_HOME="$TOOL_ROOT/godot/data"
export XDG_CONFIG_HOME="$TOOL_ROOT/godot/config"
export XDG_CACHE_HOME="$CACHE_ROOT"
export ANDROID_USER_HOME="$TOOL_ROOT/android-user"
mkdir -p "$XDG_DATA_HOME" "$XDG_CONFIG_HOME/godot" "$XDG_CACHE_HOME" "$ANDROID_USER_HOME"

verified_download() {
    local url="$1" name="$2" algorithm="$3" expected="$4"
    local target="$DOWNLOAD_ROOT/$name"
    if [[ ! -f "$target" ]]; then
        echo "Downloading $name from the official publisher…"
        curl --fail --location --show-error --silent --retry 3 "$url" --output "$target.part"
        printf '%s  %s\n' "$expected" "$target.part" | "${algorithm}sum" --check --status
        mv -- "$target.part" "$target"
    fi
    printf '%s  %s\n' "$expected" "$target" | "${algorithm}sum" --check --status || {
        echo "Publisher checksum failed: $name. Remove the corrupt cached file and rerun." >&2
        exit 1
    }
}

GODOT_BIN="${GODOT_BIN:-$(command -v godot || true)}"
if [[ -z "$GODOT_BIN" ]] || [[ "$("$GODOT_BIN" --version 2>/dev/null)" != "$GODOT_VERSION.stable."* ]]; then
    [[ "$(uname -m)" == "x86_64" ]] || { echo "Install Godot $GODOT_VERSION for this host architecture first." >&2; exit 1; }
    binary_archive="Godot_v${GODOT_RELEASE}_linux.x86_64.zip"
    verified_download "https://github.com/godotengine/godot-builds/releases/download/$GODOT_RELEASE/$binary_archive" "$binary_archive" sha512 "$GODOT_BINARY_SHA512"
    mkdir -p "$TOOL_ROOT/bin"
    unzip -q -o "$DOWNLOAD_ROOT/$binary_archive" -d "$TOOL_ROOT/bin"
    GODOT_BIN="$TOOL_ROOT/bin/Godot_v${GODOT_RELEASE}_linux.x86_64"
    chmod +x "$GODOT_BIN"
fi

template_archive="Godot_v${GODOT_RELEASE}_export_templates.tpz"
verified_download "https://github.com/godotengine/godot-builds/releases/download/$GODOT_RELEASE/$template_archive" "$template_archive" sha512 "$GODOT_TEMPLATE_SHA512"
TEMPLATE_ROOT="$XDG_DATA_HOME/godot/export_templates/$GODOT_VERSION.stable"
mkdir -p "$TEMPLATE_ROOT"
if [[ ! -f "$TEMPLATE_ROOT/android_debug.apk" || ! -f "$TEMPLATE_ROOT/android_release.apk" ]]; then
    unzip -q -j -o "$DOWNLOAD_ROOT/$template_archive" templates/android_debug.apk templates/android_release.apk templates/android_source.zip templates/version.txt -d "$TEMPLATE_ROOT"
fi

# SHA-1 hashes are the publisher's checksums in Google's repository2-3.xml.
# Exact archive URLs are pinned; HTTPS certificate verification is always enabled.
verified_download "https://dl.google.com/android/repository/build-tools_r36_linux.zip" build-tools_r36_linux.zip sha1 b0b6376977657e8ad9b969bacf4093601da2c6fb
verified_download "https://dl.google.com/android/repository/platform-36_r02.zip" platform-36_r02.zip sha1 2c1a80dd4d9f7d0e6dd336ec603d9b5c55a6f576
verified_download "https://dl.google.com/android/repository/platform-tools_r37.0.1-linux.zip" platform-tools_r37.0.1-linux.zip sha1 477254aa5f903c15cf51001717bdf347fb6b53e0
verified_download "https://dl.google.com/android/repository/commandlinetools-linux-16111833_latest.zip" commandlinetools-linux-16111833_latest.zip sha1 e025545c62a8e64c7559119566a569fb1dec5f60

# Each archive contains Google's complete package; keep the supported SDK layout.
extract_root="$(mktemp -d "$CACHE_ROOT/sdk-unpack.XXXXXX")"
trap 'rm -rf -- "$extract_root"' EXIT
if [[ ! -x "$SDK_ROOT/build-tools/36.0.0/apksigner" ]]; then
    unzip -q -o "$DOWNLOAD_ROOT/build-tools_r36_linux.zip" -d "$extract_root/build-tools"
    mkdir -p "$SDK_ROOT/build-tools"
    mv -- "$extract_root/build-tools/android-16" "$SDK_ROOT/build-tools/36.0.0"
fi
if [[ ! -f "$SDK_ROOT/platforms/android-36/android.jar" ]]; then
    unzip -q -o "$DOWNLOAD_ROOT/platform-36_r02.zip" -d "$extract_root/platforms"
    mkdir -p "$SDK_ROOT/platforms"
    mv -- "$extract_root/platforms/android-36" "$SDK_ROOT/platforms/android-36"
fi
if [[ ! -x "$SDK_ROOT/platform-tools/adb" ]]; then
    unzip -q -o "$DOWNLOAD_ROOT/platform-tools_r37.0.1-linux.zip" -d "$SDK_ROOT"
fi
if [[ ! -x "$SDK_ROOT/cmdline-tools/latest/bin/sdkmanager" ]]; then
    unzip -q -o "$DOWNLOAD_ROOT/commandlinetools-linux-16111833_latest.zip" -d "$extract_root/cmdline"
    mkdir -p "$SDK_ROOT/cmdline-tools"
    mv -- "$extract_root/cmdline/cmdline-tools" "$SDK_ROOT/cmdline-tools/latest"
fi

JAVA_ROOT="${JAVA_HOME:-$(dirname -- "$(dirname -- "$(readlink -f -- "$(command -v java)")")")}"
[[ -x "$JAVA_ROOT/bin/java" && -x "$JAVA_ROOT/bin/keytool" ]] || { echo "A complete JDK 17+ is required." >&2; exit 1; }
DEBUG_KEYSTORE="$TOOL_ROOT/debug.keystore"
if [[ ! -f "$DEBUG_KEYSTORE" ]]; then
    "$JAVA_ROOT/bin/keytool" -genkeypair -noprompt -keystore "$DEBUG_KEYSTORE" -storepass android -alias androiddebugkey -keypass android -dname 'CN=Android Debug,O=Android,C=US' -keyalg RSA -keysize 2048 -validity 10000
    chmod 600 "$DEBUG_KEYSTORE"
fi

# This is a project-scoped editor configuration, outside the Git checkout.
# The Android default debug password is public; no release credentials are saved.
python3 - "$XDG_CONFIG_HOME/godot/editor_settings-4.6.tres" "$JAVA_ROOT" "$SDK_ROOT" "$DEBUG_KEYSTORE" <<'PY'
import json, pathlib, re, sys
settings_file = pathlib.Path(sys.argv[1])
text = settings_file.read_text() if settings_file.exists() else '[gd_resource type="EditorSettings" format=3]\n\n[resource]\n'
values = {
    'export/android/java_sdk_path': sys.argv[2],
    'export/android/android_sdk_path': sys.argv[3],
    'export/android/debug_keystore': sys.argv[4],
    'export/android/debug_keystore_user': 'androiddebugkey',
    'export/android/debug_keystore_pass': 'android',
}
for key, value in values.items():
    line = key + ' = ' + json.dumps(value)
    pattern = r'^' + re.escape(key) + r' = .*?$'
    if re.search(pattern, text, re.MULTILINE):
        text = re.sub(pattern, lambda _: line, text, flags=re.MULTILINE)
    else:
        text = text.rstrip() + '\n' + line + '\n'
settings_file.write_text(text)
PY

# Shell-safe selectors only, without environment dumps or private credentials.
printf '%s\n' "$GODOT_BIN" > "$TOOL_ROOT/godot-binary.txt"
printf '%s\n' "$JAVA_ROOT" > "$TOOL_ROOT/java-root.txt"
"$SDK_ROOT/build-tools/36.0.0/apksigner" version
sed -n '/^Pkg.Revision=/p' "$SDK_ROOT/platform-tools/source.properties"
echo "Android tooling ready. Run tools/export_android.sh to create the signed debug APK."
