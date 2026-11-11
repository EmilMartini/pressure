#!/usr/bin/env python3
"""Unlock pacing check (Arsenal expansion 6.3, batch 5).

Replays a player's stat gains run after run against every goal in progress.gd ACHIEVEMENTS
and prints how many unlocks (rewards) land per run, by the bands of section 6.3:

    runs 1-10 about 4 a run, 10-40 about 2, 40-120 about 1, 120-240 about 0.5,
    and something still unlocking past run 200.

    python tools/unlock_sim.py                     # the default 30-minute run below
    python tools/unlock_sim.py --run-stats=FILE    # gains from a bot's [RUN-STATS] line, scaled
                                                   # to a 30-minute run (the bot plays faster)
    python tools/unlock_sim.py --runs=300 --verbose

Not modelled: Shrine mastery, lessons, Trials (each Trial is one won run; assumed won one
every 10 runs from run 10) and the Kit rewards of marks. Counts only ACHIEVEMENTS rewards.
"""
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

# A 30-minute run of a middling player (floor 2 to 3): kills, reactions and the rest.
# Family kills split the kills by what a typical mixed build deals.
DEFAULT_RUN = {
    "kills": 450, "reactions": 350, "reactions_fire": 120, "vents": 12, "rooms": 12, "elites": 3,
    "bosses": 1.5, "floors": 2.5, "items_picked": 10, "secrets_found": 0.6, "hidden_rooms": 0.3,
    "shots_cut": 4,
}
FAMILY_SHARE = {"kills_melee": 0.20, "kills_thrown": 0.15, "kills_summon": 0.15, "kills_ground": 0.10}
NAMED_REACTION = 14          # each named reaction a run ("reaction:Steam" and the rest)
# Discoveries: a share of what is left each run, up to a cap.
DISCOVER = {"reactions_discovered": (28, 0.25), "fusions_discovered": (40, 0.10),
            "cataclysms_discovered": (12, 0.08), "secret_kinds": (8, 0.15)}
BANDS = [(1, 10, 4.0), (11, 40, 2.0), (41, 120, 1.0), (121, 240, 0.5)]


def achievements():
    src = (ROOT / "scripts" / "progress.gd").read_text(encoding="utf-8")
    body = src[src.index("const ACHIEVEMENTS := ["):]
    body = body[:body.index("\n]\n")]
    out = []
    for m in re.finditer(r'"id": "([^"]+)".*?"stat": "([^"]+)", "goal": (\d+), "rewards": \[([^\]]*)\]', body, re.S):
        rewards = re.findall(r'"([^"]+)"', m.group(4))
        out.append({"id": m.group(1), "stat": m.group(2), "goal": int(m.group(3)), "rewards": rewards})
    return out


def win_chance(run):
    if run < 15:
        return 0.0
    return min(0.35, 0.10 + 0.0025 * (run - 15))


def main():
    runs = 260
    run_stats = dict(DEFAULT_RUN)
    verbose = "--verbose" in sys.argv
    for a in sys.argv[1:]:
        if a.startswith("--runs="):
            runs = int(a[7:])
        if a.startswith("--run-stats="):
            line = Path(a[12:]).read_text(encoding="utf-8")
            m = re.search(r"\[RUN-STATS\] secs=(\d+) (\{.*\})", line)
            secs, data = float(m.group(1)), json.loads(m.group(2))
            scale = 1800.0 / max(60.0, secs)
            run_stats = {k: float(v) * scale for k, v in data.items() if not k.startswith("boss:")}
    goals = achievements()
    have = {}
    done = set()
    per_run = []
    first = {}
    wins = 0.0
    for run in range(1, runs + 1):
        have["runs_started"] = have.get("runs_started", 0) + 1
        for k, v in run_stats.items():
            if k in DISCOVER or k == "runs_won" or k == "runs_started":
                continue
            have[k] = have.get(k, 0) + v
        if "kills_melee" not in run_stats:
            for k, s in FAMILY_SHARE.items():
                have[k] = have.get(k, 0) + run_stats.get("kills", 0) * s
        for st in {g["stat"] for g in goals}:
            if st.startswith("reaction:") and st not in run_stats:
                have[st] = have.get(st, 0) + NAMED_REACTION
        for k, (cap, share) in DISCOVER.items():
            have[k] = have.get(k, 0) + (cap - have.get(k, 0)) * share
        wins += win_chance(run)
        have["runs_won"] = int(wins)
        n = 0
        for g in goals:
            if g["id"] in done:
                continue
            if have.get(g["stat"], 0) >= g["goal"]:
                done.add(g["id"])
                n += len(g["rewards"])
                first[g["id"]] = run
                if verbose and g["rewards"]:
                    print("run %3d  %-22s %s" % (run, g["id"], ", ".join(g["rewards"])))
        per_run.append(n)
    total = sum(len(g["rewards"]) for g in goals)
    print("[UNLOCK-SIM] goals=%d rewards=%d unlocked=%d by run %d" % (len(goals), total, sum(per_run), runs))
    ok = True
    for lo, hi, want in BANDS:
        seg = per_run[lo - 1:min(hi, runs)]
        if not seg:
            continue
        avg = sum(seg) / len(seg)
        good = want * 0.5 <= avg <= want * 1.6
        ok = ok and good
        print("[UNLOCK-SIM] runs %3d-%3d: %.2f a run (spec about %.1f) %s" % (lo, hi, avg, want, "ok" if good else "OFF"))
    last = max((r for r in range(1, runs + 1) if per_run[r - 1] > 0), default=0)
    past = last > 200
    ok = ok and past
    print("[UNLOCK-SIM] last unlock at run %d (%s)" % (last, "past 200: ok" if past else "before 200: OFF"))
    never = [g["id"] for g in goals if g["id"] not in done and g["rewards"]]
    if never:
        print("[UNLOCK-SIM] not reached by run %d: %s" % (runs, ", ".join(never)))
    print("[UNLOCK-SIM] %s" % ("PASS" if ok else "FAIL"))


if __name__ == "__main__":
    main()
