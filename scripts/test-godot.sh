#!/usr/bin/env bash
set -euo pipefail

project_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
godot_bin=${1:-${GODOT_BIN:-godot}}
shopt -s nullglob

run_godot() {
    local output status=0
    output=$("$godot_bin" --headless --path "$project_root" "$@" 2>&1) || status=$?
    printf '%s\n' "$output"
    if (( status != 0 )); then
        return "$status"
    fi
    # Godot can report a script load error even when the process exits successfully.
    if grep -Eq '(SCRIPT ERROR|ERROR|Parse Error):' <<< "$output"; then
        return 1
    fi
}

if [[ ! -f "$project_root/tests/smoke/foundation.gd" ]]; then
    printf '%s\n' 'The foundation smoke test is missing.' >&2
    exit 1
fi

printf '%s\n' 'Importing the Godot project.'
run_godot --import
printf '%s\n' 'Launching the configured main scene.'
run_godot --quit-after 8

for smoke in "$project_root"/tests/smoke/*.gd; do
    test_path=${smoke#"$project_root"/}
    printf 'Running %s\n' "$test_path"
    run_godot --fixed-fps 60 --script "res://$test_path"
done
