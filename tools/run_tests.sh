#!/usr/bin/env bash
# Runs the whole test suite and prints one line per test.
# Usage: tools/run_tests.sh [sim|ui|all] [name-filter]
# Simulation tests run headless (-s); interface tests open the game window (--ui-NAME).
cd "$(dirname "$0")/.." || exit 1
mode="${1:-all}"
filter="${2:-}"
shots="${TMPDIR:-/tmp}/gm-shots"
mkdir -p "$shots"
fail=0
run() {
	local label="$1"; shift
	local log; log=$(timeout 600 "$@" 2>&1)
	local code=$?
	# Failure markers: an explicit FAIL line, a non-zero summary, a script error, or a bad exit code.
	if [ $code -ne 0 ] || grep -qE "^FAIL|SCRIPT ERROR|Parse Error|RESULT: [1-9]" <<<"$log"; then
		echo "FAIL  $label (exit $code)"; grep -E "^FAIL|SCRIPT ERROR|Parse Error|RESULT: [1-9]" <<<"$log" | head -5
		fail=$((fail + 1))
	else
		echo "ok    $label"
	fi
}
for f in tests/*.gd; do
	name=$(basename "$f" .gd)
	[ -n "$filter" ] && [[ "$name" != *$filter* ]] && continue
	[ "$name" = calibrate ] && continue
	if [[ "$name" == ui_* ]]; then
		[ "$mode" = sim ] && continue
		flag="--ui-${name#ui_}"; flag="${flag//_/-}"
		[ "$name" = ui_drive ] && flag="--ui-test"
		run "$name" godot --path . -- "$flag" --shots="$shots"
	else
		[ "$mode" = ui ] && continue
		run "$name" godot --headless --path . -s "$f"
	fi
done
echo "failed: $fail"
exit $((fail > 0))
