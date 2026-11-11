#!/usr/bin/env bash
# Exported-exe smoke test (README "Exe smoke test", World and progression GDD section 0).
# Required before every push. Exports a release exe to a scratch folder (never
# export/windows/), then runs it HEADLESS through the real Gate path: the Hollow opens the
# loadout screen and presses Descend, the bot plays a few seconds, the run hands back to the
# Hollow, a second Descend, back again, quit. Descend is a real mouse click through the GUI
# (or Enter). Three runs, at most 3 instances at once:
#   on      lighting on (the art pass and living world), mouse click
#   off     lighting off (the Options flag, through a throwaway settings file), Enter
#   player  lighting on, player mode (no bot), mouse click: the path Emil takes
# Each must exit 0, reach "[HUB-DESCEND] back in the Hollow" and print no SCRIPT ERROR.
# A release-only crash (exit 139 / 0xc0000005 at teardown) fails it; the debug editor can
# miss these. Also fails on a Callable kept in a static var or a synchronous scene change
# (the two 2026-11-10 crashes).
#
#   tools/exe_smoke.sh [scratch_dir]     # default: $TMPDIR/pressure_exe_smoke
#
# The exe is never run windowed here: tools/bot_window.sh cannot keep an exported exe from
# taking focus (its override file lives in res://, inside the project).
set -u
cd "$(dirname "$0")/.."
GODOT="${GODOT:-$LOCALAPPDATA/Microsoft/WinGet/Links/godot_console.exe}"
OUT="${1:-${TMPDIR:-/tmp}/pressure_exe_smoke}"
USERDIR="$APPDATA/Godot/app_userdata/Pressure"
mkdir -p "$OUT"
fail=0

# 1. The class of bug: no Callable (lambda or method) in a static var.
if grep -rnE "^\s*static var [A-Za-z_]+\s*:\s*Callable" scripts --include=*.gd; then
    echo "[SMOKE] FAIL: a static var holds a Callable (crashes the release exe at teardown)"
    fail=1
fi

# The Descend crash: a scene change run inside an input callback (a click) tore the scene out
# from under the GUI. Every change_scene_to_file goes through call_deferred.
if grep -rnE "change_scene_to_file\(" scripts --include=*.gd | grep -v "call_deferred"; then
    echo "[SMOKE] FAIL: a synchronous change_scene_to_file (use .call_deferred)"
    fail=1
fi

# 2. Export (about 25 s; the first export after an import can take longer).
timeout 300 "$GODOT" --headless --path . --export-release "Windows" "$OUT/Pressure.exe" 2>&1 | tail -1
git checkout -- default_bus_layout.tres 2>/dev/null
[ -f "$OUT/Pressure.exe" ] || { echo "[SMOKE] FAIL: export produced no exe"; exit 1; }
rm -f "$OUT/override.cfg"

# 3. The runs, headless, each with its own throwaway save files (--instance), a timeout and a
# capped log.
run() {   # name instance args...
    local name=$1 inst=$2; shift 2
    timeout 180 "$OUT/Pressure.exe" --headless --audio-driver Dummy --log-file "$OUT/$name.godot.log" -- "$@" --instance="$inst" 2>&1 | head -c 400000 > "$OUT/$name.log"
    echo "${PIPESTATUS[0]}" > "$OUT/$name.code"
}
printf '{"lighting": false}\n' > "$USERDIR/settings_autotest_9902.json"
run on 9901 --hub-descend --descend-runs=2 --autotest --one-floor --secs=8 &
run off 9902 --hub-descend --descend-key --descend-runs=2 --autotest --one-floor --secs=8 &
run player 9903 --hub-descend --descend-runs=2 --keep-save --secs=4 &
wait

for name in on off player; do
    code=$(cat "$OUT/$name.code")
    back=$(grep -c "\[HUB-DESCEND\] back in the Hollow" "$OUT/$name.log")
    desc=$(grep -c "\[HUB-DESCEND\] pressing Descend" "$OUT/$name.log")
    errs=$(grep -c "SCRIPT ERROR" "$OUT/$name.log")
    if [ "$code" = "0" ] && [ "$back" -ge 1 ] && [ "$desc" -ge 2 ] && [ "$errs" = "0" ]; then
        echo "[SMOKE] PASS $name: exit 0, Descend x$desc, back in the Hollow, 0 SCRIPT ERROR"
    else
        echo "[SMOKE] FAIL $name: exit $code, Descend x$desc, back=$back, SCRIPT ERROR x$errs (log $OUT/$name.log)"
        fail=1
    fi
done

# 4. Throwaway files of these instances.
for n in 9901 9902 9903; do
    rm -f "$USERDIR/save_autotest_$n.json" "$USERDIR/mastery_autotest_$n.json" \
        "$USERDIR/settings_autotest_$n.json" "$USERDIR/telemetry/runs_$n.jsonl"
done

[ $fail = 0 ] && echo "[SMOKE] ALL PASS" || echo "[SMOKE] FAILED"
exit $fail
