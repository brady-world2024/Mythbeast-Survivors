#!/usr/bin/env bash
set -euo pipefail

fail() {
    printf '%s\n' "$1" >&2
    exit 1
}

project_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
if [[ ${1:-} == --help || ${1:-} == -h ]]; then
    printf '%s\n' 'Usage: GODOT_IOS_TEAM_ID=<Apple Team ID> GODOT_BIN=<Godot executable> scripts/export-ios.sh [new output directory]'
    exit 0
fi
[[ $# -le 1 ]] || fail 'Expected at most one argument for the new output directory.'
[[ $(uname -s) == Darwin ]] || fail 'iOS export requires macOS with Xcode installed.'

team_id=${GODOT_IOS_TEAM_ID:-}
[[ $team_id =~ ^[A-Z0-9]{10}$ ]] || fail 'Set GODOT_IOS_TEAM_ID to your Apple Team ID (10 uppercase letters or digits).'
godot_bin=${GODOT_BIN:-godot}
command -v "$godot_bin" >/dev/null || fail 'Set GODOT_BIN to the Godot 4 Standard editor executable.'
xcodebuild -checkFirstLaunchStatus || fail 'Complete Xcode first-launch setup in Xcode before exporting.'
xcrun --sdk iphoneos --show-sdk-path >/dev/null || fail 'Select the full Xcode developer directory and install iOS platform support in Xcode.'

output_dir=${1:-"$project_root/build/ios/MythbeastSurvivors"}
[[ ! -e $output_dir && ! -L $output_dir ]] || fail "Choose a new output directory. This path already exists: $output_dir"
preset_file="$project_root/export_presets.cfg"
[[ -f $preset_file ]] || fail 'The project needs an iOS preset in export_presets.cfg.'
options_header=$(awk '
    /^\[preset\.[0-9]+\]$/ { header = $0; next }
    /^\[/ { header = "" }
    header != "" && /^name="iOS"$/ {
        sub(/\]$/, ".options]", header)
        print header
        exit
    }
' "$preset_file")
[[ -n $options_header ]] || fail 'The project needs an export preset named iOS.'
bundle_id=$(awk -v header="$options_header" '
    $0 == header { in_options = 1; next }
    /^\[/ { in_options = 0 }
    in_options && /^application\/bundle_identifier=/ {
        sub(/^application\/bundle_identifier="/, "")
        sub(/"$/, "")
        print
        exit
    }
' "$preset_file")
[[ $bundle_id =~ ^[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+$ ]] || fail 'Set application/bundle_identifier to the approved reverse-DNS bundle identifier.'

scratch=$(mktemp -d "${TMPDIR:-/tmp}/mythbeast-ios-export.XXXXXX")
trap 'rm -rf -- "$scratch"' EXIT
mkdir -- "$scratch/project" "$scratch/output"
rsync -a --exclude='/.git/' --exclude='/.godot/' --exclude='/build/' \
    --exclude='/export/' --exclude='/export_credentials.cfg' \
    "$project_root/" "$scratch/project/"

# Godot requires the Team ID in the preset, even for project-only exports.
MYTHBEAST_IOS_EXPORT_TEAM="$team_id" awk -v header="$options_header" '
    $0 == header {
        in_options = 1
        print
        print "application/app_store_team_id=\"" ENVIRON["MYTHBEAST_IOS_EXPORT_TEAM"] "\""
        print "application/export_project_only=true"
        next
    }
    /^\[/ { in_options = 0 }
    in_options && /^application\/(app_store_team_id|export_project_only)=/ { next }
    { print }
' "$preset_file" > "$scratch/project/export_presets.cfg"

app_name=MythbeastSurvivors
export_base="$scratch/output/$app_name"
"$godot_bin" --headless --path "$scratch/project" --log-file "$scratch/godot.log" \
    --export-debug iOS "$export_base.xcodeproj" || fail 'Godot iOS export failed. Check the output above and the matching iOS export template.'

project_file="$export_base.xcodeproj/project.pbxproj"
info_plist="$export_base/$app_name-Info.plist"
device_library="$export_base.xcframework/ios-arm64/libgodot.a"
[[ -s $project_file && -s $info_plist && -s $export_base.pck && -s $device_library ]] \
    || fail 'The export did not produce the Xcode project, Info.plist, game pack, and arm64 engine library.'
plutil -lint "$project_file" "$info_plist"
xcrun lipo -verify_arch arm64 "$device_library"

mkdir -p -- "$(dirname -- "$output_dir")"
mkdir -- "$output_dir" || fail "Could not reserve a new output directory: $output_dir"
rsync -a "$scratch/output/" "$output_dir/"
printf 'Exported Xcode project: %s\n' "$output_dir/$app_name.xcodeproj"
