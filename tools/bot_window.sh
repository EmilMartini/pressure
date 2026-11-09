#!/bin/bash
# Real-window bot run that never takes focus: the Godot window opens behind whatever the
# user is working in (WS_EX_NOACTIVATE) and is not throttled (it still renders with vsync).
#
#   tools/bot_window.sh <timeout_s> <log_file> <log_cap_bytes> <godot args...>
#   tools/bot_window.sh 240 autotest/choir.log 400000 --path . --audio-driver Dummy \
#       res://scenes/main.tscn -- --autotest --boss-only ... --perf --instance=7
#
# How: project.godot points `application/config/project_settings_override` at
# res://autotest/window_override.cfg (git-ignored, never exported). This script writes that
# file (display/window/size/no_focus=true), starts Godot, and deletes the file again once
# Godot has read its settings (3 s), so the editor and Emil's own runs never see it. Several
# launches inside 3 s share the file; the last one out removes it. Runs in the foreground
# (returns when Godot exits); the log is capped at <log_cap_bytes>.
set -u
cd "$(dirname "$0")/.."
secs=$1; log=$2; cap=$3; shift 3
G="${GODOT:-$LOCALAPPDATA/Microsoft/WinGet/Links/godot_console.exe}"
ov=autotest/window_override.cfg
mkdir -p autotest
printf '[display]\n\nwindow/size/no_focus=true\n' > "$ov"
timeout "$secs" "$G" "$@" 2>&1 | head -c "$cap" > "$log" &
run=$!
sleep 3
# Only the newest launcher deletes it (the file is rewritten by each launch).
if [ -f "$ov" ] && [ $(( $(date +%s) - $(date -r "$ov" +%s) )) -ge 3 ]; then
    rm -f "$ov"
fi
wait $run
