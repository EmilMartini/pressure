#!/usr/bin/env bash
# Export the Web preset into export/web and serve it on http://localhost:8060.
# Needs Godot 4.7.2 on PATH (or GODOT set) and the matching export templates installed
# (Editor > Manage Export Templates, or tools/get_templates.sh).
set -e
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
if ! command -v "$GODOT" >/dev/null 2>&1; then
    GODOT="$LOCALAPPDATA/Microsoft/WinGet/Links/godot_console.exe"
fi
mkdir -p export/web
"$GODOT" --headless --path . --import >/dev/null 2>&1 || true
"$GODOT" --headless --path . --export-release Web export/web/index.html
ls -la export/web
if [ "$1" = "--serve" ]; then
    echo "Serving on http://localhost:8060 (Ctrl+C to stop)"
    python -m http.server 8060 -d export/web
fi
