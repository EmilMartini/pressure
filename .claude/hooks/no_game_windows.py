"""PreToolUse guard: no Claude session may open a game or Godot window while Emil plays.

Blocks Bash / PowerShell commands that launch Godot or Pressure.exe without --headless,
or run tools/bot_window.sh, unless autotest/WINDOWS_OK exists (created only when Emil says
he is away). Headless runs, exports (tools/export_exe.sh) and the headless exe smoke test
(tools/exe_smoke.sh) are always allowed.
"""
import json
import os
import re
import sys

LAUNCH = re.compile(
    r"""^(?:["']?)(?:
        \$\{?G\}?                                  # "$G" holding the godot path
      | [^\s"';|&]*godot[\w.-]*(?:\.exe)?          # godot, godot_console.exe, Godot_v4...exe
      | [^\s"';|&]*Pressure\.exe
    )(?:["']?)(?:\s|$)""",
    re.IGNORECASE | re.VERBOSE,
)
PREFIX = re.compile(
    r"^(?:timeout\s+\d+\s+|exec\s+|&\s*|start-process\s+(?:-filepath\s+)?|[A-Za-z_]\w*=\S*\s+)+",
    re.IGNORECASE,
)
SAFE_SCRIPTS = ("tools/export_exe.sh", "tools/exe_smoke.sh")


def blocked(cmd: str) -> str:
    if "bot_window.sh" in cmd:
        return "tools/bot_window.sh opens a game window"
    for seg in re.split(r"\n|;|&&|\|\||\||(?<![&>])&(?![>&])", cmd):
        s = PREFIX.sub("", seg.strip())
        if not s or any(x in s for x in SAFE_SCRIPTS):
            continue
        if LAUNCH.match(s) and "--headless" not in s:
            return "a Godot/Pressure launch without --headless: " + s[:120]
    return ""


def main() -> None:
    data = json.load(sys.stdin)
    cmd = str((data.get("tool_input") or {}).get("command", ""))
    root = os.environ.get("CLAUDE_PROJECT_DIR", os.getcwd())
    if os.path.exists(os.path.join(root, "autotest", "WINDOWS_OK")):
        return
    why = blocked(cmd)
    if why:
        print(json.dumps({"hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "deny",
            "permissionDecisionReason": (
                "Blocked: " + why + ". Emil plays on this PC and every game window steals his "
                "focus. Run Godot and Pressure.exe with --headless only (exports and "
                "tools/exe_smoke.sh are fine). Windowed runs and screenshots wait until Emil "
                "says he is away (then autotest/WINDOWS_OK exists)."),
        }}))


if __name__ == "__main__":
    main()
