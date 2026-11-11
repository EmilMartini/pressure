"""Emil's marked moments (F8 / hold Back in a run) with their context.

    python tools/moments_report.py [runs.jsonl ...] [--bots] [--tag=unfair] [--last=N] [--json]

With no file it reads the player's own records: %APPDATA%/Godot/app_userdata/Pressure/
telemetry/runs.jsonl plus runs.open.json (the checkpoint of a run that crashed and has not
been merged yet). Read-only: it never writes, moves or deletes anything.

Each moment prints when and where it was (run, build, floor, region, room, seconds into
the room, fighting or not), health, level, guns, items and synergies, the nearest enemies,
what hurt in the 5 s before, the typed note and the screenshot path, then what happened
next in that run (died soon after, cleared the room, how the run ended). A summary counts
tags by region and room type.

Records are de-duplicated by run_id (the finished version wins over partials, then the one
with more events), so checkpoints and floor partials never double count. Human runs only
unless --bots. Standard library only.
"""
import json
import os
import sys
from collections import Counter, defaultdict

TAGS = ['fun', 'boring', 'unfair', 'confusing']


def default_files():
    base = os.path.join(os.environ.get('APPDATA', ''), 'Godot', 'app_userdata', 'Pressure', 'telemetry')
    return [os.path.join(base, 'runs.jsonl'), os.path.join(base, 'runs.open.json')]


def user_dir():
    return os.path.join(os.environ.get('APPDATA', ''), 'Godot', 'app_userdata', 'Pressure')


def ints(v):
    """Godot writes whole numbers back as 1.0 once a record is re-saved: show them as 1."""
    if isinstance(v, float) and v.is_integer():
        return int(v)
    if isinstance(v, list):
        return [ints(x) for x in v]
    if isinstance(v, dict):
        return {k: ints(x) for k, x in v.items()}
    return v


def load(path):
    out = []
    if not os.path.exists(path):
        return out
    with open(path, encoding='utf-8') as f:   # read-only
        text = f.read()
    for line in text.splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            rec = json.loads(line)
        except Exception:
            continue
        if isinstance(rec, dict):
            rec = ints(rec)
            if path.endswith('.open.json'):
                rec['recovered'] = True   # what the game will mark it as when it merges it
            out.append(rec)
    return out


def rank(rec):
    return (0 if rec.get('partial') else 1, len(rec.get('events', [])))


def dedupe(recs):
    best = {}
    for r in recs:
        rid = r.get('run_id')
        if rid is None:
            continue
        if rid not in best or rank(r) > rank(best[rid]):
            best[rid] = r
    return list(best.values())


def shot_path(p):
    if not p:
        return '-'
    if p.startswith('user://'):
        full = os.path.join(user_dir(), *p[len('user://'):].split('/'))
        return full + ('' if os.path.exists(full) else ' (missing)')
    return p


def after(run, ev):
    """What happened next: death within 60 s, the room clearing, the run's end."""
    t = float(ev.get('t', 0))
    evs = run.get('events', [])
    notes = []
    for e in evs:
        te = float(e.get('t', 0))
        if te < t:
            continue
        k = e.get('e')
        if k == 'room_clear' and te - t <= 120:
            notes.append('room cleared %.0f s later (%s hp lost there)' % (te - t, e.get('hp_lost', '?')))
            break
        if k == 'death':
            notes.append('DIED %.0f s later on floor %s to %s' % (te - t, e.get('floor'), e.get('killer')))
            break
        if k == 'room_enter' and te > t:
            break
    end = [e for e in evs if e.get('e') == 'run_end']
    if end:
        e = end[-1]
        notes.append('run %s on floor %s after %s s' % ('WON' if e.get('won') else ('abandoned' if e.get('abandoned') else 'lost'), e.get('floor'), e.get('secs')))
    elif run.get('partial'):
        notes.append('run record is partial%s (saved at %s)' % (', recovered after a crash or kill' if run.get('recovered') else '', run.get('saved_at', 'floor start')))
    return '; '.join(notes) if notes else '-'


def fmt_list(v, n=12):
    v = list(v or [])
    s = ', '.join(str(x) for x in v[:n])
    return s + (' (+%d more)' % (len(v) - n) if len(v) > n else '') if v else '-'


def main():
    args = [a for a in sys.argv[1:] if not a.startswith('--')]
    flags = [a for a in sys.argv[1:] if a.startswith('--')]
    bots = '--bots' in flags
    tag = next((a.split('=', 1)[1] for a in flags if a.startswith('--tag=')), None)
    last = next((int(a.split('=', 1)[1]) for a in flags if a.startswith('--last=')), None)
    as_json = '--json' in flags
    files = args or default_files()
    recs = dedupe([r for p in files for r in load(p)])
    rows = []
    for r in recs:
        if r.get('kind') != 'run' or bool(r.get('bot')) != bots:
            continue
        for e in r.get('events', []):
            if e.get('e') == 'moment' and (tag is None or e.get('tag') == tag):
                rows.append((r, e))
    rows.sort(key=lambda re: (re[0].get('start_time', ''), float(re[1].get('t', 0))))
    if last:
        rows = rows[-last:]
    if as_json:
        for r, e in rows:
            print(json.dumps(dict(e, run_id=r.get('run_id'), build=r.get('build'), start_time=r.get('start_time'), after=after(r, e))))
        return
    print('Files: %s' % ', '.join(f for f in files if os.path.exists(f)) or '(none found)')
    if not rows:
        print('No moments recorded yet%s. In a run press F8 (or hold Back on a pad) and pick a tag.' % (' with tag ' + tag if tag else ''))
        return
    for r, e in rows:
        print()
        print('== %s  t=%ss  run %s  build %s' % (e.get('tag', '?').upper(), e.get('t'), r.get('run_id'), r.get('build')))
        print('   started %s UTC; floor %s (%s), %s room %s, %s s into the room, %s' % (
            r.get('start_time'), e.get('floor'), e.get('region', '-'), e.get('room'), e.get('room_pos'), e.get('room_secs'),
            'FIGHTING' if e.get('fighting') else 'not fighting'))
        if e.get('note'):
            print('   note: "%s"' % e['note'])
        print('   hp %s/%s (%s%%), level %s, scrap %s' % (e.get('hp'), e.get('max_hp'), round(100 * float(e.get('hp_pct', 0))), e.get('level'), e.get('scrap')))
        print('   guns: %s' % fmt_list(e.get('guns')))
        print('   items: %s' % fmt_list(e.get('items')))
        if e.get('synergies'):
            print('   synergies: %s' % fmt_list(e.get('synergies')))
        near = e.get('nearest') or []
        print('   enemies alive %s; nearest: %s' % (e.get('enemies_alive', 0), ', '.join(
            '%s%s %dpx %d%%hp' % (n.get('kind'), ' (elite %s)' % n['elite'] if n.get('elite') else '', n.get('dist', 0), round(100 * float(n.get('hp_pct', 0)))) for n in near) or '-'))
        hurt = e.get('hurt_recent') or {}
        print('   hurt in the last 5 s: %s; last hurt by %s; hp lost this room %s' % (
            ', '.join('%s %s' % (k, v) for k, v in sorted(hurt.items(), key=lambda kv: -kv[1])) or 'nothing', e.get('last_hurt_by') or '-', e.get('hp_lost_room')))
        print('   kills this room: %s' % (', '.join('%s x%s' % kv for kv in (e.get('room_kills') or {}).items()) or '-'))
        print('   screenshot: %s' % shot_path(e.get('shot')))
        print('   next: %s' % after(r, e))
    print()
    by_tag = Counter(e.get('tag') for _, e in rows)
    print('SUMMARY %d moments: %s' % (len(rows), ', '.join('%s %d' % (t, by_tag.get(t, 0)) for t in TAGS)))
    by_place = defaultdict(Counter)
    for _, e in rows:
        by_place['%s / %s' % (e.get('region', '-'), e.get('room'))][e.get('tag')] += 1
    for place, c in sorted(by_place.items(), key=lambda kv: -sum(kv[1].values())):
        print('  %-36s %s' % (place, ', '.join('%s %d' % (t, c[t]) for t in TAGS if c[t])))


if __name__ == '__main__':
    main()
