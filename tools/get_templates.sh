#!/usr/bin/env bash
# Install the official Godot 4.7.2 export templates into the user's Godot data folder
# (about 1 GB download; the Web template is the part the export uses).
set -e
VER=4.7.2
if [ -n "$APPDATA" ]; then DEST="$APPDATA/Godot/export_templates"; else DEST="$HOME/.local/share/godot/export_templates"; fi
mkdir -p "$DEST"
cd "$DEST"
curl -L -o templates.tpz "https://github.com/godotengine/godot/releases/download/${VER}-stable/Godot_v${VER}-stable_export_templates.tpz"
unzip -q -o templates.tpz
rm -rf "${VER}.stable"
mv templates "${VER}.stable"
rm -f templates.tpz
echo "Installed to $DEST/${VER}.stable"
