#!/usr/bin/env bash
set -euo pipefail

project_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
godot_bin=${GODOT_BIN:-godot}
output_path=${1:-"$project_root/build/android/MythbeastSurvivors-debug.apk"}

if [[ ${1:-} == --help || ${1:-} == -h ]]; then
    printf '%s\n' 'Usage: bash scripts/build-android-debug.sh [output.apk]'
    exit 0
fi
if (( $# > 1 )) || [[ $output_path != *.apk || -d $output_path ]]; then
    printf '%s\n' 'Usage: bash scripts/build-android-debug.sh [output.apk]' >&2
    exit 2
fi
if ! command -v -- "$godot_bin" >/dev/null 2>&1; then
    printf '%s\n' 'Set GODOT_BIN to the Godot 4 Standard executable.' >&2
    exit 1
fi

if [[ -z ${JAVA_HOME:-} && -x /usr/libexec/java_home ]]; then
    JAVA_HOME=$(/usr/libexec/java_home -v 17 2>/dev/null) || true
    export JAVA_HOME
fi

if [[ $(uname -s) == Darwin ]]; then
    default_sdk_dir="$HOME/Library/Android/sdk"
else
    default_sdk_dir="$HOME/Android/Sdk"
fi
export ANDROID_HOME=${ANDROID_HOME:-${ANDROID_SDK_ROOT:-"$default_sdk_dir"}}
build_tools=${ANDROID_BUILD_TOOLS_DIR:-"$ANDROID_HOME/build-tools/36.1.0"}

for tool in aapt2 apksigner zipalign; do
    if [[ ! -x $build_tools/$tool ]]; then
        printf 'Missing %s in %s. Set ANDROID_BUILD_TOOLS_DIR to an installed Android SDK Build Tools directory.\n' "$tool" "$build_tools" >&2
        exit 1
    fi
done

preset_file="$project_root/export_presets.cfg"
package_id=$(awk -F '"' '/^package\/unique_name="/ { print $2; exit }' "$preset_file")
if [[ ! $package_id =~ ^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)+$ ]]; then
    printf '%s\n' 'Set the approved Android package ID in export_presets.cfg.' >&2
    exit 1
fi

mkdir -p -- "$(dirname -- "$output_path")"
output_dir=$(cd -- "$(dirname -- "$output_path")" && pwd)
output_name=$(basename -- "$output_path")
build_dir=$(mktemp -d "$output_dir/.android-debug.XXXXXX")
trap 'rm -rf -- "$build_dir"' EXIT
staged_apk="$build_dir/$output_name"

"$godot_bin" --headless --path "$project_root" --import
"$godot_bin" --headless --path "$project_root" --export-debug Android "$staged_apk"
test -s "$staged_apk"
"$build_tools/apksigner" verify --verbose "$staged_apk"
"$build_tools/zipalign" -c -P 16 4 "$staged_apk"
badging=$("$build_tools/aapt2" dump badging "$staged_apk")
if [[ $badging != *"package: name='$package_id'"* || $badging != *"application-debuggable"* ]]; then
    printf '%s\n' 'The APK does not have the expected package ID or debug manifest.' >&2
    exit 1
fi
awk '/^(package:|minSdkVersion:|targetSdkVersion:|application-label:|native-code:)/' <<< "$badging"
permissions=$("$build_tools/aapt2" dump permissions "$staged_apk")
printf '%s\n' "$permissions"
if [[ $permissions == *"uses-permission"* ]]; then
    printf '%s\n' 'Inspect unexpected Android manifest permissions before installing.' >&2
    exit 1
fi

mv -- "$staged_apk" "$output_dir/$output_name"
printf 'Android debug APK written to %s\n' "$output_dir/$output_name"
