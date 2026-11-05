#!/usr/bin/env python3
"""Balance report from Pressure telemetry (standard library only).

Reads one or more JSON-lines files: an in-game export (Options: Export play data), a
Cloudflare Worker /dump, or the Apps Script dump. Each line is one record (a run or a
session); partial uploads are deduplicated by run_id, keeping the finished version.

    python tools/analyze_telemetry.py export.jsonl dump.jsonl
    python tools/analyze_telemetry.py dump.jsonl --build 2026.11.05 --include-bots
"""

import argparse
import json
import statistics
import sys
from collections import Counter, defaultdict


# --- Loading ---------------------------------------------------------------


def load(paths):
    best = {}
    bad = 0
    for path in paths:
        with open(path, encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                try:
                    rec = json.loads(line)
                except json.JSONDecodeError:
                    bad += 1
                    continue
                if not isinstance(rec, dict) or not isinstance(rec.get("events"), list):
                    bad += 1
                    continue
                rid = str(rec.get("run_id", ""))
                if not rid:
                    continue
                old = best.get(rid)
                if old is None or _rank(rec) > _rank(old):
                    best[rid] = rec
    if bad:
        print("(skipped %d unreadable lines)" % bad, file=sys.stderr)
    return list(best.values())


def _rank(rec):
    return (0 if rec.get("partial") else 1, len(rec.get("events", [])))


# --- Small helpers ---------------------------------------------------------


def median(xs):
    xs = [x for x in xs if x is not None]
    return statistics.median(xs) if xs else None


def mean(xs):
    xs = [x for x in xs if x is not None]
    return sum(xs) / len(xs) if xs else None


def pct(xs, q):
    xs = sorted(x for x in xs if x is not None)
    if not xs:
        return None
    k = (len(xs) - 1) * q
    lo, hi = int(k), min(int(k) + 1, len(xs) - 1)
    return xs[lo] + (xs[hi] - xs[lo]) * (k - lo)


def fmt(v, spec="{:.1f}"):
    if v is None:
        return "-"
    if isinstance(v, float):
        return spec.format(v)
    return str(v)


def share(a, b):
    return (a / b) if b else None


def heading(title):
    print()
    print(title)
    print("-" * len(title))


PCT_WORDS = ("share", "rate", "hp%")


def table(rows, headers):
    as_pct = [any(w in h for w in PCT_WORDS) for h in headers]
    rows = [[c if isinstance(c, str) else fmt(c, "{:.0%}" if as_pct[i] and isinstance(c, float) else "{:.1f}") for i, c in enumerate(r)] for r in rows]
    widths = [len(h) for h in headers]
    for r in rows:
        for i, c in enumerate(r):
            widths[i] = max(widths[i], len(c))
    line = "  ".join(h.ljust(widths[i]) if i == 0 else h.rjust(widths[i]) for i, h in enumerate(headers))
    print("  " + line)
    for r in rows:
        print("  " + "  ".join(c.ljust(widths[i]) if i == 0 else c.rjust(widths[i]) for i, c in enumerate(r)))
    if not rows:
        print("  (no data)")


def events(rec, name=None):
    for ev in rec.get("events", []):
        if name is None or ev.get("e") == name:
            yield ev


def run_end(rec):
    for ev in events(rec, "run_end"):
        return ev
    return None


# --- Report ----------------------------------------------------------------


def report(records, args):
    runs = [r for r in records if r.get("kind", "run") == "run"]
    sessions = [r for r in records if r.get("kind") == "session"]
    if not args.include_bots:
        runs = [r for r in runs if not r.get("bot")]
    if args.build:
        runs = [r for r in runs if r.get("build") in args.build]
        sessions = [r for r in sessions if r.get("build") in args.build]

    finished = [r for r in runs if run_end(r) and not run_end(r).get("abandoned")]
    abandoned = [r for r in runs if run_end(r) and run_end(r).get("abandoned")]
    open_runs = [r for r in runs if not run_end(r)]
    wins = [r for r in finished if run_end(r).get("won")]
    look = []   # (text) for the "what to look at" section

    # Overview ------------------------------------------------------------
    heading("Overview")
    print("  runs %d   finished %d   won %d   win rate %s   abandoned %d   unfinished (crash / tab closed) %d" % (
        len(runs), len(finished), len(wins), fmt(share(len(wins), len(finished)), "{:.0%}"), len(abandoned), len(open_runs)))
    print("  devices %d   builds %s" % (len({r.get("device_id") for r in runs}), dict(Counter(r.get("build") for r in runs))))
    print("  platforms %s   party sizes %s" % (dict(Counter(r.get("platform") for r in runs)), dict(Counter(r.get("players") for r in runs))))
    classes = Counter()
    class_wins = Counter()
    for r in finished:
        for c in r.get("classes", []):
            classes[c] += 1
            if run_end(r).get("won"):
                class_wins[c] += 1
    table([[c, n, share(class_wins[c], n)] for c, n in classes.most_common()], ["class", "finished runs", "win rate"])
    ends = [run_end(r) for r in finished]
    print("  median run %s s   median kills %s   median level %s   median scrap earned %s / spent %s" % (
        fmt(median([e.get("secs") for e in ends])), fmt(median([e.get("kills") for e in ends])),
        fmt(median([e.get("level") for e in ends])), fmt(median([e.get("scrap_total_earned") for e in ends])),
        fmt(median([e.get("scrap_spent") for e in ends]))))

    # Deaths --------------------------------------------------------------
    heading("Deaths by floor and room type")
    deaths = [ev for r in runs for ev in events(r, "death")]
    by_floor = Counter(d.get("floor") for d in deaths)
    reached = Counter()
    for r in runs:
        for ev in events(r, "floor_start"):
            reached[ev.get("floor")] += 1
    table([[str(f), reached[f], by_floor[f], share(by_floor[f], reached[f])] for f in sorted(reached)], ["floor", "runs reached", "deaths", "death rate"])
    by_room = Counter((d.get("floor"), d.get("room")) for d in deaths)
    table([["floor %s %s" % k, n] for k, n in sorted(by_room.items(), key=lambda kv: -kv[1])[:15]], ["where", "deaths"])

    heading("Killer sources (top 10)")
    table([[k, n, share(n, len(deaths))] for k, n in Counter(d.get("killer") for d in deaths).most_common(10)], ["source", "deaths", "share"])
    hurt = defaultdict(float)
    for r in runs:
        for ev in events(r, "damage_taken"):
            hurt[ev.get("source")] += float(ev.get("amount") or 0)
    total_hurt = sum(hurt.values())
    print("  damage taken by source (top 10):")
    table([[k, v, share(v, total_hurt)] for k, v in sorted(hurt.items(), key=lambda kv: -kv[1])[:10]], ["source", "damage", "share"])

    # Floors ----------------------------------------------------------------
    heading("Floors: time, level, health at the stairs")
    fe = defaultdict(list)
    for r in runs:
        for ev in events(r, "floor_end"):
            fe[ev.get("floor")].append(ev)
    table([[str(f), len(v), median([e.get("secs") for e in v]), median([e.get("level") for e in v]),
            mean([e.get("hp_pct") for e in v]), median([len(e.get("guns", [])) for e in v]), median([len(e.get("items", [])) for e in v])]
           for f, v in sorted(fe.items())], ["floor", "n", "median secs", "median level", "avg hp% end", "guns", "items"])

    heading("Health over time per floor (average wave_hp, 30 s buckets from floor start)")
    buckets = defaultdict(lambda: defaultdict(list))
    for r in runs:
        start = {}
        for ev in events(r):
            if ev.get("e") == "floor_start":
                start[ev.get("floor")] = ev.get("t", 0)
            elif ev.get("e") == "wave_hp":
                f = ev.get("floor")
                if f in start:
                    buckets[f][int((ev.get("t", 0) - start[f]) // 30)].append(ev.get("hp_pct"))
    drops = []
    for f in sorted(buckets):
        b = buckets[f]
        keys = sorted(k for k in b if len(b[k]) >= 1)[:12]
        cells = ["%d:%s" % (k * 30, fmt(mean(b[k]), "{:.0%}")) for k in keys]
        print("  floor %s  %s" % (f, "  ".join(cells)))
        if len(keys) >= 2:
            first, last = mean(b[keys[0]]), mean(b[keys[-1]])
            span = (keys[-1] - keys[0]) * 30
            if span > 0:
                drops.append((f, (first - last) / span * 60.0))
    if drops:
        f, rate = max(drops, key=lambda x: x[1])
        if rate > 0:
            look.append("Floor %s loses health fastest: about %.0f%% of the party's hp per minute of fighting." % (f, rate * 100))

    # Shops -----------------------------------------------------------------
    heading("Shop offers: buy rate (bought / runs where seen) and skips")
    seen_runs = defaultdict(set)
    price_seen = defaultdict(list)
    bought = Counter()
    bought_price = defaultdict(list)
    skipped = Counter()
    skipped_price = defaultdict(list)
    rerolls = []
    free_picks = Counter()
    for r in runs:
        rid = r.get("run_id")
        for ev in events(r):
            e = ev.get("e")
            if e == "shop_view":
                for o in ev.get("offers", []):
                    key = "%s:%s" % (o.get("kind"), o.get("id"))
                    seen_runs[key].add(rid)
                    price_seen[key].append(o.get("price"))
            elif e == "purchase":
                key = "%s:%s" % (ev.get("kind"), ev.get("id"))
                if (ev.get("price") or 0) > 0:
                    bought[key] += 1
                    bought_price[key].append(ev.get("price"))
                else:
                    free_picks[key] += 1
            elif e == "skipped":
                for o in ev.get("offers", []):
                    key = "%s:%s" % (o.get("kind"), o.get("id"))
                    skipped[key] += 1
                    skipped_price[key].append(o.get("price"))
            elif e == "reroll":
                rerolls.append(ev.get("price"))
    rows = []
    for key in sorted(seen_runs, key=lambda k: -len(seen_runs[k])):
        n = len(seen_runs[key])
        rows.append([key, n, bought[key], share(bought[key], n), median(price_seen[key]), skipped[key], median(skipped_price[key])])
        if n >= args.min_seen and bought[key] == 0:
            look.append("%s was on sale in %d runs and never bought (median price %s)." % (key, n, fmt(median(price_seen[key]))))
    table(rows[: args.top], ["offer", "runs seen", "bought", "buy rate", "median price", "skipped", "skip price"])
    print("  rerolls %d, median price %s" % (len(rerolls), fmt(median(rerolls))))

    heading("Free picks (treasure, challenge, arena rewards, entrance guns)")
    treasure_offered = Counter()
    treasure_picked = Counter()
    for r in runs:
        for ev in events(r, "treasure"):
            for i in ev.get("offered", []):
                treasure_offered[i] += 1
            treasure_picked[ev.get("picked")] += 1
    table([[k, treasure_offered[k], treasure_picked[k], share(treasure_picked[k], treasure_offered[k])]
           for k in sorted(treasure_offered, key=lambda k: -treasure_offered[k])[: args.top]], ["treasure offer", "offered", "picked", "pick rate"])
    table([[k, n] for k, n in free_picks.most_common(args.top)], ["free pickup", "taken"])

    # Level-ups ---------------------------------------------------------------
    heading("Level-ups: pick rate given offered, pick share vs offered share")
    off = Counter()
    pick = Counter()
    rar = defaultdict(Counter)
    for r in runs:
        for ev in events(r, "levelup"):
            for o in ev.get("offered", []):
                off[o.get("id")] += 1
                rar[o.get("id")][o.get("rarity")] += 1
            pick[ev.get("picked")] += 1
    tot_off, tot_pick = sum(off.values()), sum(pick.values())
    rows = []
    for k in sorted(off, key=lambda k: -share(pick[k], off[k])):
        rows.append([k, off[k], pick[k], share(pick[k], off[k]), share(off[k], tot_off), share(pick[k], tot_pick)])
        if off[k] >= args.min_seen and pick[k] == 0:
            look.append("Level-up %s was offered %d times and never picked." % (k, off[k]))
    table(rows, ["option", "offered", "picked", "pick rate", "offered share", "pick share"])

    # Guns and elements -------------------------------------------------------------
    heading("Damage dealt by gun and by element")
    by_gun = defaultdict(float)
    by_el = defaultdict(float)
    by_re = defaultdict(float)
    for r in runs:
        for ev in events(r, "damage_dealt"):
            for k, v in (ev.get("by_gun") or {}).items():
                by_gun[k] += float(v)
            for k, v in (ev.get("by_element") or {}).items():
                by_el[k] += float(v)
            for k, v in (ev.get("by_reaction") or {}).items():
                by_re[k] += float(v)
    tot_dmg = sum(by_gun.values())
    gun_offered = Counter()
    gun_picked = Counter()
    gun_carried = Counter()
    carried_total = 0
    for r in runs:
        for ev in events(r):
            e = ev.get("e")
            if e == "shop_view":
                for o in ev.get("offers", []):
                    if o.get("kind") == "gun":
                        gun_offered[o.get("id")] += 1
            elif e == "purchase" and ev.get("kind") == "gun":
                gun_picked[ev.get("id")] += 1
                if (ev.get("price") or 0) == 0:
                    gun_offered[ev.get("id")] += 1   # free guns count as offered once
            elif e == "gun_pick" and ev.get("source") == "start":
                for g in ev.get("offered", []):
                    if g != ev.get("picked"):
                        gun_offered[g] += 1
            elif e == "floor_end":
                for g in ev.get("guns", []):
                    gun_carried[g.split("@")[0]] += 1
                    carried_total += 1
    rows = []
    for g in sorted(by_gun, key=lambda k: -by_gun[k]):
        ds = share(by_gun[g], tot_dmg)
        cs = share(gun_carried[g], carried_total)
        pr = share(gun_picked[g], gun_offered[g])
        rows.append([g, by_gun[g], ds, cs, gun_picked[g], pr])
        if ds is not None and cs and ds >= 0.05 and ds > 2.0 * cs:
            look.append("Gun %s deals %.0f%% of all damage but is only %.0f%% of carried guns (pick rate %s)." % (g, ds * 100, cs * 100, fmt(pr, "{:.0%}")))
    table(rows, ["gun", "damage", "damage share", "carry share", "picked", "pick rate"])
    tot_el = sum(by_el.values())
    table([[k, v, share(v, tot_el)] for k, v in sorted(by_el.items(), key=lambda kv: -kv[1])], ["element", "damage", "share"])

    heading("Reactions: count and damage")
    rcount = Counter()
    for r in runs:
        for ev in events(r, "room_clear"):
            for k, v in (ev.get("reactions") or {}).items():
                rcount[k] += int(v)
    names = set(rcount) | set(by_re)
    tot_re = sum(by_re.values())
    table([[k, rcount[k], by_re.get(k, 0.0), share(by_re.get(k, 0.0), tot_re), share(by_re.get(k, 0.0), rcount[k])]
           for k in sorted(names, key=lambda k: -rcount[k])], ["reaction", "count", "damage", "damage share", "dmg / reaction"])

    # Fights --------------------------------------------------------------
    heading("Bosses")
    boss = defaultdict(list)
    for r in runs:
        for ev in events(r, "boss"):
            boss[ev.get("kind") or "?"].append(ev)
    table([[k, len(v), share(sum(1 for e in v if e.get("won")), len(v)), median([e.get("secs") for e in v if e.get("won")]),
            median([e.get("phase2_at_secs") for e in v]), mean([e.get("player_hp_pct_at_end") for e in v])]
           for k, v in sorted(boss.items())], ["boss", "fights", "win rate", "median secs (won)", "phase 2 at", "avg hp% end"])

    heading("Elites by affix")
    el = defaultdict(list)
    for r in runs:
        for ev in events(r, "elite"):
            el[ev.get("affix") or "(none)"].append(ev.get("secs_to_kill"))
    table([[k, len(v), median(v)] for k, v in sorted(el.items(), key=lambda kv: -len(kv[1]))], ["affix", "killed", "median secs to kill"])

    heading("Rooms: clear time, kills, health lost")
    rc = defaultdict(list)
    for r in runs:
        for ev in events(r, "room_clear"):
            rc[(ev.get("floor"), ev.get("type"))].append(ev)
    table([["floor %s %s" % k, len(v), median([e.get("secs") for e in v]), median([e.get("kills") for e in v]), mean([e.get("hp_lost") for e in v])]
           for k, v in sorted(rc.items(), key=lambda kv: (kv[0][0] or 0, str(kv[0][1])))], ["room", "cleared", "median secs", "median kills", "avg hp lost"])

    # Props, vents, actives, gear --------------------------------------------------
    heading("Props, vents, actives")
    props = Counter()
    for r in runs:
        for ev in events(r, "prop"):
            props[(ev.get("kind"), ev.get("result"))] += 1
    table([["%s -> %s" % k, n] for k, n in props.most_common(args.top)], ["prop", "times"])
    vents = Counter(ev.get("element") for r in runs for ev in events(r, "vent"))
    actives = Counter(ev.get("id") for r in runs for ev in events(r, "active_use"))
    print("  vents %s" % dict(vents))
    print("  actives used %s" % dict(actives.most_common(args.top)))
    drops = Counter(ev.get("id") for r in runs for ev in events(r, "drop_gun"))
    combines = Counter(ev.get("id") for r in runs for ev in events(r, "combine"))
    print("  guns dropped %s" % dict(drops.most_common(args.top)))
    print("  guns combined %s" % dict(combines.most_common(args.top)))

    # Performance -----------------------------------------------------------
    heading("Frame rate per floor")
    fps = defaultdict(list)
    ens = defaultdict(list)
    pxs = defaultdict(list)
    for r in runs:
        for ev in events(r, "fps"):
            f = ev.get("floor")
            fps[f].append(ev.get("fps"))
            ens[f].append(ev.get("enemies"))
            pxs[f].append(ev.get("pixels"))
    table([[str(f), len(fps[f]), pct(fps[f], 0.05), pct(fps[f], 0.5), pct(fps[f], 0.95), median(ens[f]), median(pxs[f])]
           for f in sorted(fps, key=lambda x: x or 0)], ["floor", "samples", "p5 fps", "p50 fps", "p95 fps", "enemies", "pixels"])
    by_plat = defaultdict(list)
    for r in runs:
        for ev in events(r, "fps"):
            by_plat[r.get("platform")].append(ev.get("fps"))
    table([[str(k), len(v), pct(v, 0.05), pct(v, 0.5)] for k, v in by_plat.items()], ["platform", "samples", "p5 fps", "p50 fps"])

    # Tutorial and settings ------------------------------------------------------
    heading("Tutorial")
    done = [ev for s in sessions for ev in events(s, "tutorial_done")]
    skips = [ev for s in sessions for ev in events(s, "tutorial_skipped")]
    started = sum(1 for s in sessions for ev in events(s, "tutorial") if ev.get("step") == 0)
    print("  started %d   completed %d (median %s s)   skipped %d" % (started, len(done), fmt(median([e.get("secs") for e in done])), len(skips)))
    table([[str(k), n] for k, n in sorted(Counter(e.get("at_step") for e in skips).items())], ["skipped at step", "times"])
    step_t = defaultdict(list)
    for s in sessions:
        prev = None
        for ev in events(s, "tutorial"):
            if prev is not None and ev.get("step") == prev.get("step", -1) + 1:
                step_t[prev.get("id")].append(ev.get("secs", 0) - prev.get("secs", 0))
            prev = ev
    table([[k, len(v), median(v)] for k, v in step_t.items()], ["step", "n", "median secs"])

    heading("Settings changed")
    sc = Counter()
    for rec in sessions + runs:
        for ev in events(rec, "settings_change"):
            sc[ev.get("key")] += 1
    table([[k, n] for k, n in sc.most_common()], ["key", "changes"])

    heading("What to look at")
    if not look:
        print("  nothing stands out yet (thresholds: --min-seen %d)" % args.min_seen)
    for line in look:
        print("  - " + line)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("files", nargs="+", help=".jsonl files (game export, worker dump, sheet dump)")
    ap.add_argument("--build", action="append", help="only this build (repeatable)")
    ap.add_argument("--include-bots", action="store_true", help="include autotest bot runs")
    ap.add_argument("--min-seen", type=int, default=5, help="how often something must show up before it is flagged")
    ap.add_argument("--top", type=int, default=25, help="rows in the long tables")
    args = ap.parse_args()
    records = load(args.files)
    if not records:
        print("no records found")
        return 1
    report(records, args)
    return 0


if __name__ == "__main__":
    sys.exit(main())
