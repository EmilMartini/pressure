"""Per-floor pressure from telemetry (difficulty pass, 2026-11-09).

    python tools/pressure_report.py runs.jsonl [more.jsonl] [--bots]

Human runs by default (`--bots` for bot runs). Uses the per-floor "pressure" event
(scripts/pressure_meter.gd) when the build records it; older runs are rebuilt roughly from
damage_taken, wave_hp and room_clear: max health is estimated from the hits, time under
50% / 25% from the 5 s wave_hp samples, healing from rises between samples. Standard
library only. Reads the files; never writes them."""
import json, sys

def load(path):
    out = []
    for l in open(path, encoding='utf-8'):
        try:
            out.append(json.loads(l))
        except Exception:
            pass
    return out

def burst(hits, w):
    best = s = 0.0
    i = 0
    for j in range(len(hits)):
        s += hits[j][1]
        while hits[j][0] - hits[i][0] > w:
            s -= hits[i][1]
            i += 1
        best = max(best, s)
    return best

def floors(run):
    ev = run.get('events', [])
    cur = None
    out = []
    for e in ev:
        k = e.get('e')
        if k == 'floor_start':
            cur = {'floor': int(e['floor']), 'region': e.get('region'), 'ev': []}
            out.append(cur)
        elif cur is not None:
            cur['ev'].append(e)
    return out

def rebuild(f):
    ev = f['ev']
    pe = [e for e in ev if e.get('e') == 'pressure']
    if pe:
        return dict(pe[-1], src='meter')
    maxhp = 100.0
    hits = []
    samples = []  # (t, frac)
    for e in ev:
        if e.get('e') == 'damage_taken':
            a = float(e['amount']); ha = float(e['hp_after'])
            maxhp = max(maxhp, ha + a)
    for e in ev:
        if e.get('e') == 'damage_taken':
            hits.append((float(e['t']), float(e['amount']) / maxhp))
            samples.append((float(e['t']), float(e['hp_after']) / maxhp))
        elif e.get('e') == 'wave_hp':
            samples.append((float(e['t']), float(e['hp_pct'])))
    samples.sort()
    fights = [e for e in ev if e.get('e') == 'room_clear']
    fight = sum(float(e.get('secs', 0)) for e in fights)
    death = [e for e in ev if e.get('e') == 'death']
    end = [e for e in ev if e.get('e') == 'floor_end']
    if death and ev:
        # the fatal room never clears: count its time since the last room_enter
        enters = [e for e in ev if e.get('e') == 'room_enter']
        if enters:
            fight += float(death[0].get('secs', ev[-1]['t'])) - float(enters[-1]['t'])
    mins = max(fight, 1.0) / 60.0
    # time below thresholds: wave_hp samples are every 5 s of fight time
    wave = [e for e in ev if e.get('e') == 'wave_hp']
    n = max(len(wave), 1)
    lt50 = sum(1 for e in wave if float(e['hp_pct']) < 0.5) / n
    lt25 = sum(1 for e in wave if float(e['hp_pct']) < 0.25) / n
    # heal: rises between consecutive samples
    heal = 0.0
    for (t0, a), (t1, b) in zip(samples, samples[1:]):
        if b > a:
            heal += b - a
    close = 0
    armed = True
    for t, fr in samples:
        if fr >= 0.35:
            armed = True
        elif armed and fr < 0.2:
            armed = False
            close += 1
    if death and close:
        close -= 1 if samples and samples[-1][1] < 0.2 else 0
    rooms = len(fights)
    clean = sum(1 for e in fights if float(e.get('hp_lost', 0)) <= 0.01)
    return {'floor': f['floor'], 'region': f['region'], 'fight': round(fight), 'lt50': round(lt50, 2), 'lt25': round(lt25, 2),
            'dmg_pm': round(sum(h[1] for h in hits) / mins, 2), 'heal_pm': round(heal / mins, 2), 'hits': len(hits),
            'max_hit': round(max([h[1] for h in hits] or [0]), 2), 'close': close, 'rooms': rooms, 'clean': clean,
            'burst1': round(burst(hits, 1.0), 2), 'burst3': round(burst(hits, 3.0), 2), 'died': bool(death),
            'end_hp': end[0].get('hp_pct') if end else None, 'src': 'rebuilt', 'maxhp': maxhp}

def main():
    bots = '--bots' in sys.argv
    for path in [a for a in sys.argv[1:] if not a.startswith('--')]:
        for r in load(path):
            if bool(r.get('bot')) != bots:
                continue
            fl = floors(r)
            if not fl or sum(len(f['ev']) for f in fl) < 30:
                continue
            rs = [e for e in r.get('events', []) if e.get('e') == 'run_start']
            print('RUN', r.get('build'), r.get('start_time'), rs[0].get('class') if rs else '-', 'talents=%d' % len(rs[0].get('talents', [])) if rs else '')
            for f in fl:
                d = rebuild(f)
                keys = ['floor', 'region', 'fight', 'lt50', 'lt25', 'dmg_pm', 'heal_pm', 'hits', 'max_hit', 'close', 'clean', 'rooms', 'burst1', 'burst3', 'died', 'end_hp', 'src']
                print('  ' + ' '.join('%s=%s' % (k, d.get(k)) for k in keys))

main()
