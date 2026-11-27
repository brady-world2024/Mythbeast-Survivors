#!/usr/bin/env bash
set -euo pipefail

project_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
gate_only=0
if [[ ${1:-} == --gate ]]; then
    gate_only=1
    shift
fi
godot_bin=${1:-${GODOT_BIN:-godot}}
shopt -s nullglob

test_save_dir=$(mktemp -d "${TMPDIR:-/tmp}/mythbeast-smoke.XXXXXX")
export MYTHBEAST_TEST_SAVE_DIR="$test_save_dir"
trap 'rm -rf -- "$test_save_dir"' EXIT

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
run_godot --script res://tests/support/boot.gd

if (( gate_only )); then
    # Keep the required gate on an explicit list of critical suites.
    smoke_tests=(
        "$project_root/tests/smoke/foundation.gd"
        "$project_root/tests/smoke/movement.gd"
        "$project_root/tests/smoke/combat.gd"
        "$project_root/tests/smoke/progression.gd"
        "$project_root/tests/smoke/survival.gd"
        "$project_root/tests/smoke/persistent_progression.gd"
        "$project_root/tests/smoke/presentation.gd"
    )
else
    smoke_tests=("$project_root"/tests/smoke/*.gd)
fi

for smoke in "${smoke_tests[@]}"; do
    test_path=${smoke#"$project_root"/}
    if [[ ! -f "$smoke" ]]; then
        printf 'Required smoke test missing: %s\n' "$test_path" >&2
        exit 1
    fi
    if (( gate_only )); then
        printf 'Running %s (gate profile)\n' "$test_path"
        run_godot --fixed-fps 60 --script "res://$test_path" -- --gate
    else
        printf 'Running %s\n' "$test_path"
        run_godot --fixed-fps 60 --script "res://$test_path"
    fi
done
