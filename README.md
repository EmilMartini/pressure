# Pressure

Co-op elemental-reaction dungeon shooter: Isaac-style rooms, Brotato-style waves,
Magicka-style reactions. See [GDD.md](GDD.md) for the full concept.

## Run it

Godot 4.7 is installed through winget. Either open the folder in the Godot editor
(Project Manager > Import > pick `project.godot`) and press F5, or from a terminal:

```
godot --path .
```

Guns auto-fire at enemies on their own. Hold RT or the left mouse button to fire every gun
where you aim (right stick, mouse cursor, or the way you face): that is also the only way to
hit obstacles, props, secret walls and puzzle pieces, which auto-fire never targets.

| Action | Keyboard / mouse | Controller |
|---|---|---|
| Move | WASD | Left stick |
| Interact (pedestals, stairs, sigil) | E | A |
| Vent pressure | Space | LB |
| Use active item | F | X |
| Fire manually (aim with right stick / mouse, else facing) | Left mouse | RT |
| Character sheet | C | Back / Select |
| Pause | Esc | Start |
| Join (players 2-4) | | Start on a pad that has not joined |
| Give player 1 a gun (debug) | 1 to 0 | |
| Wipe the save file (debug) | F9 | |
| Restart | R | |

The game opens on a main menu (Play, Journal, Wipe save, Quit). The pause menu doubles as
the run-over screen with the run summary and next goals, and also opens the Journal.
Menus take controller input directly: d-pad or left stick to move, A to press, B to go
back, shoulders to switch Journal tabs. Prompts appear on the things themselves: walk up
to a pedestal and a key cap shows A or E depending on whether you last touched the pad
or the keyboard. F1 shows a full control strip if you want one.

## Character sheet

C, the pad's Back button, or the pause menu's Character entry. A paper doll: gear slots
around your figure, your guns below it, a tooltip for whatever you move to, and a readable
stat panel on the right grouped into attributes, offense, elements, pressure, sustain and
set bonuses. Press a gun in the row to drop it on the floor of the current room, where it
sits on a plinth and can be picked up again. Shoulders cycle players in co-op.

## Rooms and loot

Each special room is dressed to be recognised: a counter and keeper in the shop, a chest
on a dais with scattered gold in treasure rooms, weapon racks in challenge rooms, bones in
the boss room, crates in hidden caches. Treasure rooms work like Slay the Spire chests:
one pick from a piece of gear, a gun, or a run-long boon (max health, carry, pressure
limit, or a pile of scrap), with bigger chests on deeper floors. Everything on offer sits
on a stone plinth, and the prompt over it is the pad's coloured face button or a key cap
depending on what you last touched. The minimap reveals rooms only as you reach their
neighbours.

## Post-processing

A screen-space pass (bloom from a thresholded blur, mild contrast and saturation, a
vignette, and a CRT look: slight barrel curve, scanlines, a faint phosphor triad,
chromatic aberration and grain) that runs on the Compatibility renderer so the web build
keeps it. Tweak the uniforms at the top of `scripts/post_fx.gd`; set `crt_curve`,
`scanline`, `aberration` and `grain` to 0 for a clean picture.

## Music

Synthwave by Alex McCulloch (Pro Sensory), CC0 from OpenGameArt, see
`assets/music/CREDITS.txt`: a menu theme, a run theme and a darker boss theme. The
`Music` autoload crossfades and ducks while paused. The licence asks nothing, but the
author asks for a credit, and the main menu shows one.

## Journal

Three tabs, from the main menu or the pause menu:

- **Achievements**: every achievement, its progress, and what it unlocks.
- **Arsenal**: every gun with element, weight and stats. Locked guns show which
  achievement unlocks them.
- **Gear**: every item grouped by rarity with its slot and effect. Locked rarity tiers
  show how to unlock them.
- **Reactions**: all sixty-five element pairs. Each shows as ??? until you fire it once.

Player 1 is keyboard + mouse and the first controller, merged. Every other
controller joins as a new player by pressing Start.

## Levels, the Shrine and reactions that chain

Kills give XP. Each level, once the room is clear, you pick one of three upgrades
(damage, attack speed, crit, bounces, pierce, health, armour, speed, scrap, pressure and
so on; the catalog is `scripts/levelup.gd`).

Runs also pay **Embers**, for how well you played rather than only how deep you got:
1 per room cleared, 2 per elite, 3 per reaction you fire for the first time ever, 3 per
boss kill, a 12 Ember bounty the first time a boss kind dies to a class, 2 per floor
reached beyond the first, 10 for clearing the dungeon. A floor-1 death that cleared one
room pays 1; one that cleared five rooms, killed two elites and found two new reactions
pays 15 (the old mastery formula paid both 1 point).

Embers are spent at the hub's **Shrine** (`scripts/mastery.gd`, Hades' Mirror of Night
in shape). Eleven slots, each an exclusive pair: side A or side B is active, switching is
free, each side has 2 or 3 ranks, and **Refund all** gives every Ember back:

| Slot | Side A | Side B |
|---|---|---|
| Sights | Long Barrel: +4% range per rank (3) | Hot Load: +5% shot speed per rank (3) |
| Catalyst | Catalyst: +1.5% potency per rank (3) | Lingering Touch: +4% element duration per rank (3) |
| Nerve | Thick Skin: +4 max HP per rank (3) | High Confidence: +1.5% damage at 80%+ HP per rank (3) |
| Vent | Reinforced Tank: +4 vent capacity per rank (3) | Hard Vent: +4% vent power per rank (3) |
| Footwork | Light Feet: +2% move speed per rank (3) | Sidestep: +1% dodge per rank (2) |
| Salvage | Salvager: +4% scrap per rank (3) | Second Thoughts: 1 level-up reroll per run per rank (3) |
| Fortune | Lucky Coin: +4% luck per rank (3) | Wider Choice: a 4th level-up card, every other level-up, then every one (2) |
| Pack | Deep Pockets: +1 carry per rank (2) | Heirloom: the gunsmith is free on floor 1, then floors 1-2 (2) |
| Scout | Cartographer: shop, then treasure, then boss on the map (3) | Dowser: hidden rooms, then puzzle rooms on the map (2) |
| Bite | Rime (needs an ice gun): +3% ice fire rate, +2% ice potency (2) | Etch (needs an acid gun): +3% acid damage, +2% acid potency (2) |
| Twilight | Halo (needs a holy gun): +3% holy damage, +2% holy potency (2) | Hollow (needs a void gun): +3% void fire rate, +2% void potency (2) |

Below the slots, **Last Breath** is the survival track: each of its 3 ranks is one revive
per run at 25% max HP with 2 s of invulnerability, costing 3, 50 and 100 Embers (Hades'
Death Defiance at 30 / 500 / 1,000 Darkness, scaled by a room = 1 Ember). Everything
together costs 928 Embers. At most the board adds about +10% damage-equivalent and +15
HP-equivalent (the old 212-node tree gave +21% damage, +12% fire rate, +32 max HP and 6
armour); see GDD.md section 4 and `reports/Roguelite meta progression analysis.md` for
the numbers behind every value. Pad: d-pad moves, A buys, X switches side; keyboard:
arrows, Enter / E, Tab / Q; mouse: click the lit row to buy, the other row to switch.
Old saves convert every mastery point ever earned into 8 Embers. Wipe save clears both.

Levels follow Brotato's shape: a quadratic XP curve and small upgrades (+4% damage, +8
health) so a floor gives a few levels and power comes from stacking many picks.

Reactions chain through clouds. Steam, Toxic Mist, Firestorm, Magma, Blizzard, Tar Pit
and others leave a cloud; any element that enters a cloud of a different element reacts
with the whole cloud and the cloud takes on that element. Shock through steam is a
lightning field that keeps shocking; fire into a poison cloud is a Noxious Flame over
everyone in it; two clouds meeting react with each other. A vent sweeping through a cloud
does the same.

## Progression

Runs start naked: no guns, no gear. The entrance offers each player a pick of two random
unlocked guns. Achievements add guns, classes, obstacle kinds, the challenge room and
shop upgrades to the pool future runs draw from. The first ten teach the basics and hand
out one new element per run, Risk of Rain 2 style, so every element is in the pool by
about run 5: discover 3 reactions (ice), vent 10 times (acid), start 2 runs, clear 5
rooms (poison), discover 6 reactions (gale), kill 3 elites (blood), start 3 runs (stone),
fire 250 reactions (void), start 5 runs (holy). Class unlocks ask for 15 to 40 of their
signature reaction instead of 60 to 90. Progress is saved to `user://save.json`; the
run-end screen shows what you unlocked, the Embers earned and what is next. The
self-test uses its own save file and never touches yours.

## HUD

Vitals top-left (portrait, level, health, XP), room and timer top-centre, minimap with
scrap and kills top-right, the gun hotbar bottom-centre (tier pips and mod dots on each
gun, weight beside it), gear slots bottom-left, the vent gauge bottom-right with its
prompt. Everything is set in the Kenney Pixel font at 20 px or more.

## Balance model

Borrowed from Brotato and tuned by the bot:

- **Difficulty** is one number: 2 + 4 per floor past the first + half the rooms cleared.
  Five floors, so it runs from 2 to about 22.
- **Enemies** scale linearly per kind (hp = base + slope x difficulty, contact damage
  +0.35 per step); speed never scales. Thirteen kinds plus elite affixes and five bosses
  with two phases each; `scripts/spawn_table.gd` gates kinds by floor.
- **Rarity odds** have gates and caps: uncommon from difficulty 1 (+7% per step, cap
  55%), rare from 3 (+3%, cap 25%), epic from 6 (+1.2%, cap 10%), legendary from 9
  (+0.5%, cap 4%), all multiplied by 1 + luck. Treasure and boss rooms raise the floor.
- **Prices**: base by rarity (22 / 38 / 62 / 98 / 150) + 2 x difficulty + 10% of base
  per step; guns the same shape from 16 + 9 x weight. Services: repair 24 + 10 per
  floor, carry 50 + 18, gunsmith 45 + 20, reroll 10 + 6 per floor and climbing.
- **Rarity gates power**: common items are one modest stat, uncommon two, rare is where
  bounce, pierce and chain live, epic adds projectiles or big conditionals with a cost,
  legendary is run-defining. Level-ups use the same tiers keyed on level and luck.
- **Waves** last 18 s to 60 s with difficulty; elites get affixes from difficulty 6 and
  come in twos from 8, threes from 16, and a second elite lands late in every wave from
  floor 3. The arena feeds 20 + 11 x difficulty enemy hit points per second, bending
  upward past difficulty 6, with a bodies-per-second budget beside it; each spawned group
  buys a pause of the larger of the two. Floors 3 to 5 multiply enemy contact and shot
  damage by 1.15, 1.3 and 1.5, bosses grow 12% a floor past the second, and the stairs
  heal to 40% instead of 60% from floor 3.
- **Shops** are Brotato shops: four wares (guns or gear from the shop pool), a Reroll
  plinth whose price climbs with every use, and carry, repair and gunsmith once each.
  Arena rewards pay a gun until the party carries three, so a naked start ramps up.

## Isaac layer: pools, no repeats, active items

- **Pools by room**: every item belongs to pools (shop = economy, utility, defence, gun
  mods; treasure = build-defining triggers and mechanics; boss = plain stat-ups; hidden =
  weird and strong, legendaries and drawbacks; challenge = offence; arena = the free
  post-fight commons and uncommons). Rooms roll from their pool, treasure and hidden
  never below uncommon, and very strong items carry a lower pick weight.
- **No repeats in a run**: an item that has been on show leaves the pool until the run
  ends, like Isaac removing an item from its pool.
- **Active item** (Isaac's spacebar item): one slot, used with F or X, charges that refill
  one per cleared room. Fourteen of them from a 15-point heal to the Pressure Bomb, a huge
  nova of whatever you last vented.

## Guns

Forty-three guns, at least three per element plus six exotics, across archetypes (pistol,
rifle, shotgun, SMG, sniper, mortar, beam, orb, boomerang, homing, burst, flak, wand,
cannon) with a DPS budget per weight written next to each in `scripts/gun_library.gd`.
Tiers I to IV: a duplicate merges into the gun you carry one tier up, and the shop's
Gunsmith raises your lowest-tier gun. A gun holds one mod per tier and mod effects stack.
When more than one gun has a free slot, picking up a mod opens a picker (one card per
gun, stick or d-pad to choose, A or E to confirm, B or Esc to leave the mod).
Reactions crack elite and boss shields; the attuned reaction cracks twice.

## Gear

About 240 items (166 hand-made across five rarities plus six per element), including
twenty shot modifiers (homing, shards, splash, boomerang, spectral, orbitals, shot size)
that change how every gun fires, Isaac style, and all of it drawn on the figure,
ten hand-made sets and one per element. Items drop from elites and bosses and sit in
shops, treasure, hidden and challenge rooms.
Eight gear slots plus a mod slot per gun. Every item is a few lines of data in
[items.gd](scripts/items.gd): stat modifiers, conditional modifiers and triggered effects
that all compose. To add an item, add one `_add(...)` line; the drop tables, pedestals,
HUD and effect engine pick it up with no other change.

## The hub, the tutorial and the loop

The game starts in a hub room (Enter the Gungeon's Breach): walk to a station and press
A or E. The Gate starts a run (pick a class first), the Armory is the Journal, the Shrine
the talent board, the Mirror sets names, the Workshop opens Options, the Ledger shows
your last runs and totals, and the Trophy Wall lights one tile per achievement with the
next three goals under it. The first time you play, a short tutorial room runs before the
hub (replayable from the hub's Esc menu). A one-time explainer card states the loop:
runs are five floors ending in bosses; dying keeps achievements, unlocks and Embers;
runs pay Embers for rooms, elites and new reactions, and the Shrine trades them for
swappable talents; classes change the start only. The run-over screen reports this run,
what you unlocked, the Embers earned with their breakdown and the next goals; the Ledger
keeps the Embers per run and the lifetime total by source.

Options (saved to `user://settings.json`): master, music and sound volume, fullscreen,
vsync, screen shake, hit-stop, damage numbers, post-processing, CRT and its intensity,
bloom, the controls strip, pause when a pad drops, Share play data (on / off) and Export
play data (see Telemetry). The Ledger's totals end with a line on play data: how many
runs are kept on this device and whether sharing is on.

## Props that react

Arenas, shops and treasure rooms carry props that react to every element: crates burn
and break, oil barrels leak and explode, fountains boil into steam, freeze over, conduct
a shock, spray in a gale, bless when holy; braziers set walkers alight and spill fire
when tipped; ice crystals shatter into shards on a shock; poison pots and acid vats
break into clouds and puddles; lightning rods arc to every enemy nearby; wind chimes
push; blood altars heal, purge or summon; stone pillars block shots until void or acid
takes them. Broken props stay broken. See `scripts/prop.gd` for the full table.

## Windows build

Every push to main also builds `Pressure.exe` (the game embedded in one file) and attaches
it, zipped, to the **latest** release:
https://github.com/EmilMartini/pressure/releases/latest/download/Pressure-windows.zip
Unzip and run `Pressure.exe`. The exe is not code-signed, so Windows SmartScreen warns on
the first launch: "More info", then "Run anyway". The desktop build has full controller
rumble for every pad; the browser cannot rumble some controllers (Chrome exposes no rumble
for the DualSense). Local build: the "Windows" export preset, or
`godot --headless --path . --export-release Windows export/windows/Pressure.exe`.

## Play in the browser

The game exports to a single-page web build (GL Compatibility, single-threaded, so it
runs on any static host without special headers). Two ways to get it:

- **GitHub Pages, automatic.** Push the repository to GitHub, open Settings > Pages and
  set Source to "GitHub Actions". `.github/workflows/deploy.yml` then exports the Web
  preset on every push to `main` and publishes it at
  `https://<user>.github.io/<repo>/`. Share that link; nothing to install, saves live
  in the browser.
- **Locally.** Install the 4.7.2 export templates once (`tools/get_templates.sh`, or
  Editor > Manage Export Templates), then `tools/export_web.sh --serve` exports to
  `export/web` and serves it on http://localhost:8060.

The web build keeps controllers (browser Gamepad API: press a button once so the page
sees the pad), keyboard and mouse. Co-op is local, so friends on their own machines each
play their own run.

## Telemetry

Anonymous, opt-in play data for balancing (`scripts/telemetry.gd`, autoload `Telemetry`).

- **What.** One record per run: a random run id, a random device id (saved in settings,
  never a name), the build (`Telemetry.VERSION`, bump it with each shared build),
  platform, party size and classes, then small events: run and floor start / end, room
  enter / clear (time, kills by kind, health lost, elites, reactions), health every 5 s
  in fights, damage taken by source (enemy kind, `projectile:<kind>`, `material:<mat>`,
  `prop:<kind>`), damage dealt per room by gun, element and reaction, elites and bosses,
  shop views, purchases, rerolls and skipped offers, level-up / gun / treasure picks,
  equips, drops, combines, vents, actives, prop reactions, death (killer, last 10 health
  samples), run end, frame rate every 10 s (with enemy and particle counts). `run_start`
  carries the Shrine loadout (`talents`: slot, side, talent id and rank of every active
  side with a rank; `survival`: Last Breath ranks; `embers_spent`, `embers_bank`);
  `run_end` carries the payout (`embers`, `embers_parts` and `embers_counts` per source,
  `bounties`, `discoveries`); `revive` and `levelup_reroll` mark Shrine effects in a run.
  Outside runs: tutorial steps, completion or skip step, settings changes and Shrine
  purchases, side switches and refunds. No names, addresses or
  typed text. Bot runs (`--autotest`) are stored with `bot: true` and never uploaded.
- **Where.** `user://telemetry/runs.jsonl`, one JSON line per run (a partial is written at
  every floor so a crash keeps data; the file stays under 5 MB by dropping the oldest
  lines). In the browser `user://` is IndexedDB, so use Options > Export play data: the
  web build downloads a `.jsonl`, desktop writes it to your Downloads folder and shows the
  path.
- **Consent.** Settings key `telemetry`: `ask` (default), `on`, `off`. After the explainer
  card the hub asks once (Allow / No thanks); Options > Share play data flips it later.
  Data is kept locally either way; it only leaves the device when sharing is on and an
  endpoint is set.
- **Endpoint.** Set `ENDPOINT` in `scripts/telemetry.gd`. Each stored record is POSTed as
  JSON (`Content-Type: application/json`, `X-Build: <VERSION>`); the partial goes up at
  every floor and the finished run replaces it. Lines keep an `uploaded` flag; anything
  that failed is retried on the next launch. Two ready endpoints, with setup steps at the
  top of each file: `tools/telemetry_worker.js` (Cloudflare Worker + KV, free tier;
  `GET /dump` with the `X-Dump-Key` header returns everything) and
  `tools/telemetry_sheet.gs` (Google Apps Script appending to a Sheet; set
  `ENDPOINT_SIMPLE = true` for it, since Apps Script cannot answer the browser's CORS
  preflight).
- **Analysis.** `python tools/analyze_telemetry.py export.jsonl dump.jsonl` (standard
  library only; `--build X` to filter, `--include-bots`, `--min-seen N`). It prints runs
  and win rate, deaths by floor and room, top killers, time / level / health per floor,
  health over time, shop buy and skip rates with prices, level-up pick rates against how
  often each was offered, damage share by gun and element, reactions by count and damage,
  bosses, elites, rooms, props, frame-rate percentiles per floor, the tutorial funnel,
  and a "What to look at" list (never-bought items, never-picked level-ups, the floor
  where health drops fastest, guns whose damage share far exceeds how often they are
  carried).

## Fusions and cataclysms: reactions climb

Every reaction leaves one of 22 compounds on its target and/or as a patch (motes orbiting
the enemy, a dashed ring on the floor). A third element on it is a **fusion** (220, x1.8 to
x2.5 potency); nineteen leave a **field** that a fourth element turns into a **cataclysm**
(176, x3 to x4), after which nothing is left. A hard tier ceiling (4) and a context tier
on everything a fusion causes make loops impossible; room budgets, a per-enemy cooldown and
a repetition decay keep one combination from carrying a run. The Journal has a page for
each, and first discoveries pay Embers (capped at 12 a run). Bots: four-element builds
clear floor 1 in 16 of 17 runs against 5 of 10 for the same guns without fusions and 1 of 7
for one element; idle six-gun bots still die on floor 1. Details and numbers: GDD.md,
"Compounds and fusions".

## Threat: crowds, not sponges

Measured with a stand-still bot (`--idle`) and a fixed loadout (`--loadout=a,b,c`):
six light guns of five elements used to clear floor 1 standing still without losing
health, because reactions locked every group down and six guns out-killed any spawn rate.
Now:
- **Crowd target**: an arena keeps a number of enemies alive (6 + 1.1 x difficulty, x1.22
  per extra gun and x1.12 per extra element) and refills as fast as you clear them, so a
  full build meets a horde rather than tankier enemies (health grows at most 25%).
- **Spawns close in**: half of every group appears in a ring around a player, behind a
  0.75 s telegraph during which it cannot be hit; spitters from floor 1; grunts, swarmers
  and splitters lunge the last stretch.
- **Control has diminishing returns**: a second freeze or stun within 7 s lasts half, a
  third a quarter, then the enemy is immune; elites resist half, bosses three quarters;
  slows cap at 50%; frozen enemies take x1.6, not x3.
- Result: six guns standing still die in the first arena; six guns moving clear floor 1
  through about 600 kills of a 20-strong horde, dipping to three quarters health.

The vent gauge is the vent's charge, so "pressure decay" upgrades were a trap: they are
now vent charge speed (the vent fills faster), and pressure limit reads as vent capacity.

## Figures are generated from your build

The character is a paper doll drawn pixel by pixel (`scripts/figure_gen.gd`), not a
fixed sprite. Your class and every item, gun and completed set add weight to themes
(the twelve elements plus plate, scout, arcane, gunslinger and merchant). The strongest
theme picks the head and torso, the second the cape, arms and an accent, up to three
accents come from the top three, and the palette blends all of them with a touch of your
player colour. Close runners-up overlay a detail, so a Pyromancer in alchemist gear keeps
the flame hood and gains goggles and a flask belt, and is named "Pyromancer-Alchemist".
Each pickup nudges a part or the colour instead of swapping the figure.
`FigureGen.debug_sheet(path)` renders every class and eight blends to one PNG.

## Guns: six slots, duplicates, combining

Brotato's shape: six gun slots (a few items add one), duplicates allowed so three oil
slingers and a fire gun is a build, and two copies of the same gun at the same tier
combine into one a tier higher from the character sheet (Combine prompt). Drops are
weighted toward your build: the element you carry most, its best reaction partners, and
items that feed it are two to three times as likely; a quarter of every roll stays
off-build so you can pivot.

## Names

Main menu > Names: a field per player, saved with the rest of the profile. The name
replaces P1..P4 on the HUD, the character sheet and the level-up screen. Typing needs a
keyboard; the field is still reachable with a pad.

## Music

Thirteen CC0 synthwave tracks (Alex McCulloch, Holizna, iamoneabe, MintoDog,
congusbongus, ansimuz; see `assets/music/CREDITS.txt`) in shuffle bags per mood (hub,
menu, run, boss, ambient) that never repeat the last track, crossfade before a track ends,
lean toward later tracks on deeper floors, and open a low-pass as a fight heats up.

## Audio

About 200 sound files (3.3 MB of Ogg Vorbis in `assets/audio/`), all CC0, layered and
levelled from Kenney's audio packs (Impact, Sci-fi, RPG Audio, Digital Audio, Interface)
and OpenGameArt packs by rubberduck, jaggedstone, bart, artisticdude, ogrebane, qubodup and
others; every source with its URL is in `assets/audio/CREDITS.txt`. The `Sfx` autoload
(`scripts/sfx.gd`) owns it all:

- **Shots**: a voice per element (fire whoosh, wet splash, shock zap, ice crystal, oil
  glug, poison bubble, acid sizzle, blood slap, void reversed whoomp, holy chime, gale
  swish, stone knock), four variants each with pitch and volume wobble.
- **Reactions**: composed from the two elements' layers plus a burst weighted by the
  reaction's size (small, medium, large from its damage and area); Steam, Chain
  Lightning, Deep Freeze, Inferno, Ignition, both vents (Fire / Frost Nova), shield
  crack / break / restore, Path opened and the elite sting have dedicated sounds.
- **Impacts and deaths**: flesh, armour (wardens, elites) and attuned shields; props by
  material (wood, barrel, stone, crystal, metal, water) and walls; enemy deaths by size
  class, elite deaths, boss roar, phase change (re-shield) and death.
- **Player**: hurt, down, Last Breath revive, level-up, gun pickup, item pickup by rarity
  (richer as it gets rarer), active item, a low-health heartbeat under 30% HP.
- **World**: footsteps per floor theme (stone, moss and wet, snow, ash, glassy void),
  ceiling drips, and a looping ambient bed per theme (crypt wind and drips, ruins swamp,
  insects and water, frozen howling wind, forge rumble and fire, void drone, sanctum hum
  and torches) that crossfades on a new floor and sits lower while enemies are up.
- **Mix**: world sounds play on positional players (pan with the camera, fade over about
  a screen) on a `World` bus with a light per-theme reverb; the beds on `Ambience`; both
  send into `Sfx`, so the sound slider covers them. Per-name rate limits, voice caps per
  name and per family, and a small dip for rapid repeats keep stacking under control,
  with the compressor and limiter on Master as the backstop. Boss deaths, roars, unlock
  fanfares, secret chimes and other big moments briefly duck the music and the bed.

## Damage numbers

Every hit prints its damage over the target: element-coloured for bullets and
reactions, big yellow with a bang for crits, red on your own figure when you are hit.
Burn, poison and bleed ticks are batched into one dim number every half second so a
burning crowd stays readable.

## Self-test

```
godot --path . res://scenes/main.tscn -- --autotest
```

Add `--short` after `--autotest` for a 70-second run, `--secs=N` for any length, and
`--arsenal` to start with every gun (a stress test; the default is a real naked start
that measures the progression loop). `--mastery=full` buys every Shrine rank and the whole
survival track (side A active, `--mastery-side=b` for B); `--mastery=N` spends N Embers
cheapest-first. Both use a throwaway Shrine file and print a `[MASTERY]` line with the
loadout and its power estimate. The log prints `[FLOOR]`, `[DEATH]` and `[EMBERS]` lines
(what the run paid, or would have paid when the time cap ended it).
`--fusion-probe` starts with four w1 guns of four elements so compounds, fusions and
cataclysms actually happen; the loadout rotates with `--instance` (wet/fire/shock/gale,
oil/fire/shock/gale, wet/fire/shock/blood, oil/fire/blood/gale), or pick one with
`--fusion-probe=K`. `--no-fusions` turns the tier ladder off (reactions leave no compounds),
which is the game before fusions for a like-for-like baseline. Every run ends with a
`[FUSION]` line (fusions and cataclysms fired, compounds and fields made, damage share by
tier 0 to 4, the top names by count and by share of fusion damage, a `[FUSION-JSON]` dump
for scripts) and a `[FUSION-CHECK] PASS/FAIL` line: the termination proof (no context
above tier 4, no product made at or below its own tier, at most the room budget of fusions
in one frame). For parallel silent runs add `--audio-driver Dummy` before the scene and
`--instance=N` after `--`; each instance gets its own save, Shrine and telemetry file. `godot --path . -- --menu-shot`
screenshots the menu and codex. `godot --headless --path . res://scenes/main.tscn -- --obstacle-test`
checks projectiles hit obstacles. `godot --path . res://scenes/main.tscn -- --themes-shot` saves
one arena per floor theme (crypt, ruins, frozen, forge, void, ambience running 2 s) and the
hub's sanctum as `autotest/theme_<name>.png`.
A bot plays by itself for up to five minutes: explores rooms, buys from pedestals,
clears obstacles, fights elites and the boss, takes the stairs. It saves screenshots to
`autotest/` and prints progress and reaction counts. Use it to check a build still
works after a change.

## Art and fonts

All art is from Kenney (kenney.nl), CC0, no generative art:

- **1-Bit Pack** (`assets/kenney/1bit_mono.png`): every sprite in the game, tinted per
  thing through the `Art` autoload. Characters, monsters, items, bricks, floor, decals.
- **Particle Pack** (`assets/kenney/particles/`): reaction puffs (smoke, flame, spark, magic).
- **Materials on the floor** (`scripts/materials.gd`, Noita-inspired): every room has
  an 8 px material grid. Bullets, vents, puddles and deaths lay oil, water, ice, poison
  gas, acid and blood on it; oil pools burn and spread fire, water puts fire out, boils
  to steam and conducts a shock across the whole pool, ice freezes water and you slide
  on it, gas drifts, acid eats oil and ice, door obstacles react to what touches them.
  Enemies and players standing in it take the effect. Only active cells are stepped
  (12 steps a second, 2,500 cells a step), drawn as translucent pixel squares.
- **Materials and particles are one world** (Noita-inspired, 6 px cells): droplets that
  land become floor material, bursts throw droplets of both elements, burning cells shed
  embers, boiling water puffs steam, charged pools spark, oil creeps thin and far, fire
  runs along oil as a bright front and leaves char that never fades, water and poison gas
  make contaminated water, acid thins in water, fire dries blood, shocks pass through
  ice. Hot cells draw on an additive layer that the bloom picks up; fire moments add
  heat shimmer.
- **The show grows over a run**: a spectacle value from 0.35 on the first floor to 1.3
  on the last (floor, rooms cleared, difficulty and guns carried) scales particle counts,
  signature sizes, flashes, hit-stop, ripples and bloom gain. Below 0.55 big moments
  only shake; above 1.1 they get a second ripple. Boss and elite deaths are always full.
  Gameplay never reads it. The tutorial is pinned at 0.6.
- **Effects are generated, not drawn**: every reaction, status and nova is pixel
  particles in the game's own palette (2 to 5 px squares, translucent, additive for hot
  elements) with per-element physics: fire rises and flickers into smoke, water falls and
  splashes, ice shards stop and crumble, sparks jitter with arcs, oil and blood arc and
  stick, void spirals in, gale streaks. Every element has a signature shape (flame
  tongues, splash crown, branching bolts, growing ice spikes, gas blooms, fizzing acid,
  blood spray, void implosion, light pillar, whirl, stone chunks) and a reaction draws
  both of its elements' signatures plus accents for what it does; the ring is only a
  thin outline of a burst radius. Nothing opaque ever covers the fight.
- **Dungeon Crawl Stone Soup tiles** (`assets/icons/`, CC0, see its CREDITS.txt): the
  32 px icons for every item, gun, level-up, class, Shrine talent and trophy, chosen by
  hand per item (`Art.icon`, `Items.icon`, `Art.gun_icon`, `LevelUps.icon`). The world
  stays in Kenney's one-bit style; `Art.debug_icon_sheet(path)` renders every mapping.
- **Kenney Fonts** (`assets/fonts/`): Kenney Pixel for the HUD and world text.
- **Sound** (`assets/audio/`, CC0): Kenney audio packs and OpenGameArt CC0 packs, see
  the Audio section above and `assets/audio/CREDITS.txt`.

To change which sprite something uses, edit the coordinates in `scripts/art.gd`
(column, row on the packed sheet, 16px tiles).

## Layout

```
project.godot        project settings, autoloads, renderer
export_presets.cfg   the Web export preset;  .github/workflows/deploy.yml publishes it
tools/               export_web.sh (export + serve), get_templates.sh, analyze_telemetry.py,
                     telemetry_worker.js (Cloudflare), telemetry_sheet.gs (Google Sheets)
scenes/main.tscn     the only scene; everything is built in code
scripts/
  main.gd            run orchestrator: floors, current room, scrap, camera, HUD, joins, bot
  floor_gen.gd       generates a floor: tree of rooms, specials on dead ends, hidden room
  room_data.gd       persistent state of one room (type, cleared, doors, shop stock)
  room.gd            a room in play: walls, doors, pedestals, waves, challenge, boss
  door.gd            doorway: locked / open / blocked by an obstacle
  obstacle.gd        pool, thicket, valve: cleared by an element or a reaction
  pedestal.gd        interactable offer: gun, carry, repair, stairs, sigil
  scrap.gd           currency pickup
  player.gd          movement, aim modes, arsenal, pressure, focus, health
  player_input.gd    one player's controller / keyboard+mouse reading
  gun.gd             a carried gun, fires projectiles
  gun_data.gd        gun stats resource
  gun_library.gd     autoload `Guns`: the gun pool, gated by unlocks
  progress.gd        autoload `Progress`: save file, stats, achievements, unlocks
  items.gd           autoload `Items`: gear catalog and the trigger/stat effect engine
  projectile.gd      bullets: raw damage, then apply element; also hit obstacles
  elements.gd        autoload `Elements` / class `Element`: kinds, colours, reaction table
  enemy.gd           thirteen kinds, states, reactions, elite affixes, five bosses
  enemy_projectile.gd enemy shots;  spawn_table.gd  floor-gated spawn groups, affixes, bosses
  fx.gd              pixel particles, element signatures, bolts and spikes, numbers, corpses
  materials.gd       the floor material grid: oil, water, fire, ice, gas, acid, blood
  classes.gd         starting classes;  class_select.gd  the class card screen
  gun_pick_screen.gd pick which gun a mod goes on
  hud.gd             floor/room status, boss bar, minimap, player panels, help, banners
  art.gd             autoload `Art`: sheet lookups, particle textures, fonts, palette
  sfx.gd             autoload `Sfx`: sounds by name, positional voices, reactions,
                     footsteps, heartbeat, ambient beds, ducking
  menu.gd            main menu (scenes/menu.tscn is the start scene), names screen
  pause_menu.gd      pause overlay, also the run-over screen
  journal.gd         achievements / arsenal / gear / reactions journal used by both menus
  levelup.gd         level-up upgrade catalog;  levelup_screen.gd  the pick-one-of-three overlay
  mastery.gd         autoload `Mastery`: the Shrine's talents, Last Breath, Embers and their save;  mastery_screen.gd
  cloud.gd           lingering element patches that react with what enters them
  prompts.gd         Xbox-style button and key-cap drawing
  post_fx.gd         bloom, grading and CRT post-process
  character_sheet.gd gear, set bonuses and computed stats for one player
  music.gd           autoload `Music`: looping tracks with crossfades
  menu_pad.gd        direct controller polling for menu navigation
  ui_theme.gd        shared dark theme for menus
  telemetry.gd       autoload `Telemetry`: opt-in anonymous play data, local log, upload, export
```
