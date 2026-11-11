# Boss patterns (2026-11-11)

Goal: the boss is the highlight of each floor (Isaac loop: one boss per floor). Each boss
should have at least three readable patterns with clear tells, a visible phase change, and
attacks that make standing still lose. Every hit must be telegraphed for at least 0.5 s and
must be dodgeable with the dash (0.2 s of invulnerability).

Phases: every boss changes phase at 66% and 33% health (BossBody.PHASES). Each change shows
an "ENRAGED"/"PHASE 3" line, a hitstop, a flash, a shake, a colour shift, a shockwave ring
and cracks on the body (BossShow.phase), and the music changes. The pace guard (no boss dies
before about 28 s), the entrances, the deaths and the quieter own effects (b7a5217) are
unchanged.

## Floors 1 to 3 (a normal run)

| Boss (floor) | Pattern | Tell | Phase 2 (66%) | Phase 3 (33%) |
|---|---|---|---|---|
| **Brute King** (1) | Charge | 0.8 s, he stands still and a red lane shows the path (0.5 s in phase 3) | cooldown 1.8 s | faster, longer reach, 1.2 s cooldown |
| | Barrel throw | 1.0 s, a ring where the barrel lands | 2 barrels; swallows barrels, Gut Blast (1.1 s ring) | as phase 2 |
| | **Leap slam (new)** | 1.0 s, a 110 px ring on the spot he lands; he crouches, then is in the air | slam throws arcs (below) | 0.85 s, then a second slam |
| | **Slam (new)**, when you are within 220 px | 0.9 s, a 150 px ring; he flashes red and rears up | 4 aimed shockwave arcs with gaps, each shown for 0.9 s before it rolls | 0.75 s, double slam, re-aimed |
| | **Roar slam (new)** | phase change: 1.2 s slam before anything else | announces the arcs | announces the double slam |
| **Hive Mother** (2, Rotting Gardens and Rust Ruins) | Swarmer summons | 0.7 s spawn markers | more | more, faster |
| | Poison ring volley | 0.6 s wind-up ring | 10 shots | 12 shots, faster |
| | **Brood spit (new)** | 1.0 to 1.75 s shell rings, on you and round where you are heading | 4 shells | 5 shells, every 3.4 s |
| | Burrow and erupt | 0.8 s dig-in, then the eruption circle is shown for 1.2 s | added, every 6 s | every 8 s |
| **Drowned Choir** (2, Drowned Cistern) | Wet bolt fan | visible bolts at 210 px/s (3, then 5) | 5 bolts | 5 bolts |
| | Pulling song | 1.1 s dashed ring, then 1.8 s of pull | more often | replaced by bell rings |
| | Flood | water stamps round the room (conductive) | phase 2 only | |
| | Bell rings | 0.9 s wind-up, then a full ring (dash through) | | every 3.2 s |
| **Storm Warden** (3, Frostvault) | Bolt burst | **0.55 s wind-up ring (new; it had none)**, then 5 aimed bolts | 3-way bursts | 3 bolts |
| | Strike on you | 1.0 s circle | 3 strikes round you, 1.2 s, plus a recharge strike on himself | a strike every second (0.9 s) |
| | Jump | 0.8 s crackling circle where he lands | every 5 s | replaced by moving storm and charged air |

## Floors 4 and 5 (audit only, not changed)

| Boss | Patterns and tells |
|---|---|
| **Pyre Lord** (4) | Burning trail; bomber summons (0.9 s markers); flame-wave arcs (0.9 s wind-up, never full rings, 3 at once in phase 3); lava pools (1.0 s ring). Phase 2 cracks the armour, phase 3 floods the forge. |
| **Void Herald** (5) | Spiral volleys (visible shots); wisp summons (0.8 s); gravity wells (marked first). Phase 2 steals your most-used element; phase 3 shard volleys with their paths marked. |

## Measured (headless bots, --boss-only, storm build)

| Boss | Bot | Before | After |
|---|---|---|---|
| Brute King (build of floor 2) | kite | 29.4 s, 21 damage taken | 28.0 to 29.9 s over 6 seeds, 0 to 31 damage (mean 14) |
| | idle | died at 7.5 s | died at 7.5 s (2 seeds) |
| Hive Mother (--boss-dps=900) | kite | 52.6 s, 28 damage | 31.6 to 77.2 s, 6 to 27 damage (4 runs) |
| | idle | survived with 128 damage (12% health left) | died at 35 and 41 s |
| Storm Warden (--boss-dps=700) | kite | 42.3 s, 90 damage | 41.9 to 59.6 s, 59 to 90 damage (3 seeds) |
| | idle | died at 17.7 s | died at 20.9 s |
| Drowned Choir (--boss-dps=900) | kite | 171.8 s, 42 damage | 170.9 s, 77 damage |
| | idle | died at 51 s | not rerun |
| Pyre Lord, Void Herald | kite | | 35.7 s, 2 damage; 47.4 s, 79 damage (errors check only) |

- The idle bot now loses to all four bosses on floors 1 to 3. Before, it survived the Hive Mother.
- The kite bot now dashes out of slams, strikes and eruptions, and through shockwave arcs, the
  way a player would. Before, it never dodged Storm Warden strikes. Kite numbers after that
  change measure the patterns, not the bot.
- King fights stay at the pace floor (28 to 30 s). Emil's last three real King fights were
  51, 37 and 28 s, ending at 72, 73 and 56% health. With the slams sharing time with the
  charges, the King should not hit harder overall.
- Choir fights are 171 s for this bot both before and after: the storm build gets no
  Exposed damage there (the Hive Mother fight gets 38k of it). That comes from the boss-only
  sizing (--boss-dps=900 against 228 dps from the bot). Emil's one real Choir fight took 27 s.
- 0 SCRIPT ERRORs in all 35 logs. Headless frame rates match the old code within noise (King
  250 to 265 fps against 264). A windowed fps check is still owed.

## Owed

- Window captures while Emil is away: leap ring and airborne King, slam ring and rear-up,
  shockwave arcs with gaps, Hive brood spit rings, Warden burst wind-up.
- Choir: decide whether its pace needs the Hive Mother's Exposed help (see above).
- Floors 4 and 5: Pyre Lord and Void Herald look complete, but they have not been played since
  the new roster.
