#!/usr/bin/env bash
# Export the Windows exe to export/windows/Pressure.exe with the build label stamped:
# Telemetry.COMMIT becomes the short hash of HEAD for the export, then goes back to "dev".
# Commit first, so the hash names the code that is in the exe.
set -e
cd "$(dirname "$0")/.."
GODOT="${GODOT:-$LOCALAPPDATA/Microsoft/WinGet/Links/godot_console.exe}"
SHORT="$(git rev-parse --short=7 HEAD)"
sed -i "s/^const COMMIT := \"dev\"/const COMMIT := \"${SHORT}\"/" scripts/telemetry.gd
trap 'sed -i "s/^const COMMIT := \"${SHORT}\"/const COMMIT := \"dev\"/" scripts/telemetry.gd' EXIT
grep -n '^const COMMIT' scripts/telemetry.gd
mkdir -p export/windows
"$GODOT" --headless --path . --export-release "Windows" export/windows/Pressure.exe 2>&1 | tail -3
