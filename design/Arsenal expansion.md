# Arsenal expansion

Emil asked on 2026-11-10 for a much bigger arsenal, after the comparison with Enter the
Gungeon's 270+ weapons. He wants hundreds of items and weapons, weapon families beyond guns
(melee and others), and weapon rarity, so that finding a great weapon is rare and feels good.

This file records his decisions. The full spec (the weapon list per family, numbers, build
batches and tests) is the next step. It should be written in a fresh session that reads this
file, `design/Core loop reset.md` and `GDD.md`.

## Decisions (Emil, 2026-11-10)

| # | Decision |
|---|---|
| A1 | **Melee auto-swings at the nearest enemy**, like Brotato's melee: swords, axes, hammers, spears, whips and fists swing or thrust within a short reach. You play melee by positioning. |
| A2 | **Four new families** beside today's guns: melee; thrown and lobbed (boomerangs, knives, grenades, mortars, chakrams); summons and drones (turrets, familiars, orbiting blades, drones); auras and traps (damage zones, mines, totems, elemental fields you leave behind). |
| A3 | **Five rarity tiers for weapons:** Common, Uncommon, Rare, Epic, Legendary. A legendary shows up about once every few runs and has a unique, run-defining effect. Copies still merge into higher tiers, as today. |
| A4 | **Size:** about 150 weapons and about 300 items, up from 43 weapons and 145 items, built in tested batches. More can follow later. |
| A5 | **Mostly elemental.** Most weapons carry an element, so reactions stay the heart of the game. A few plain or Stone weapons give contrast, and some legendaries carry two elements. |
| A6 | **Mostly unlocked over time.** A fresh save starts with a core set, and the rest unlock through lessons, challenges and milestones, Isaac-style. |
| A7 | **Code-drawn art now, the art pack later.** Each family gets a consistent code-drawn look now. When Emil picks an art pack, its weapon sprites replace them. |

## Rules that still apply

- **The core loop reset holds:**
  - four weapon slots;
  - auto-aim targets the closest enemy (decision 21), and extra projectiles or beams go to different enemies;
  - pick 1 of N rewards;
  - items stack with no slots, on one readable card;
  - almost no text in fights.
- **Readability:** every weapon family must stay readable. Hostile things stay the clearest on screen, and your own effects stay quiet.
- **Balance:** each batch has to pass the stand-still and mover pressure checks, the economy and loot checks, the fusion probe and `tools/exe_smoke.sh`.
- **No windows:** sessions run headless only, and screenshots wait until Emil is away.
- **Art:** no generative AI art.
