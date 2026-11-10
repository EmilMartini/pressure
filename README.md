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
| Swap which ring / trinket a pedestal replaces | Q | Y |
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

**Spoils.** Elites no longer drop pedestals in the middle of a wave: their loot is banked
("SPOILS +1" over the body) and the wave's end lays out one choice, a free gun and a free
item plus a card per banked drop, up to four. Take one; the rest are salvaged for scrap
(30% of their shop price) and the game says so, as it does if you walk out without
choosing. When a wave ends every scrap piece on the floor flies to you, and pieces left
lying during a wave reach further the longer they lie. A gun you already carry reads
"Merge: X tier N" on its plinth. With both rings (or trinkets) worn, a ring pedestal shows
which one it replaces (the weaker by default) and which one stays; Y / Q swaps them.

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
chromatic aberration and grain) that runs on the Compatibility renderer (the project's renderer;
the game ships as the Windows exe only) so the exe
keeps it. Tweak the uniforms at the top of `scripts/post_fx.gd`; set `crt_curve`,
`scanline`, `aberration` and `grain` to 0 for a clean picture.

The same pass also lights the world (`scripts/art_pass.gd`, design doc "Art direction"):
ambient times up to 16 point lights (torches, braziers, doorways, sun pools, one on each
player) plus a region grade. It is on in the Rust Ruins and the Hollow; a fight lifts the
darkness so it reads as before, and the mood returns when the room is clear. Options
"Lighting" (Settings `lighting`) or `--no-art` turns it off with its room dressing (wall
faces, doorway jambs and spill, clutter, roots, the Gatewarden's gatehouse). Bot captures:
`--clarity-rest` (the clarity room already cleared: `_rest.png` and `_rest_wall.png`),
`--clarity-ab` (each clarity frame measured again with the pass off, `[CLARITY-AB-NOART]`),
`--clarity-ab-off-first` (the off capture first), and tuning overrides `--art-amb=v`,
`--art-pl=energy`, `--art-cap=v`, `--art-grade=0`; `--art-time` prints `[ART-DRESS]` (ms to
dress each room). The room's plants are a registry for element reactions (`ArtPass.pieces_near`,
`ArtPass.react`).

**Living world** (`scripts/living_world.gd`, the reactions in `ArtPass.Living`; design doc "Art
direction", living world). Same switch (`lighting`, `--no-art`). Plants read the Materials grid
four times a second and answer shots and bodies: fire spreads plant to plant (show only, no floor
fire), ice freezes them and a hit shatters them, poison and acid wilt them, shock makes them
crackle, gales and blasts lean them, void pulls them, and they grow back out of a fight. Vines,
banners, cobwebs and chains on the top wall are point chains that swing and burn segment by
segment. Deep water draws as a river (a flow map from the layout's river lines, foam, depth,
ripples and wakes; ice stops it, shock crackles over it, fire boils it); the `stream` layout
(Cistern, Gardens and Rust Ruins arenas) winds a river across the room. Critters flee, steam vents
puff, a gust crosses the room now and then, and all of it rests in a fight. Lasting floor marks
(`Materials.MARK_*`: frost rims, acid etching, dried blood, rubble, plus scorch) stay for the
floor (`RoomData` meta `floor_marks`). Route doors and stairs are stairwells with the next
region's light rising up them. Setting `river_carry` (on by default since 2026-11-10, Emil's decision) lets
rivers carry oil, blood, poisoned water and ash downstream.
Captures: `--alive-shot=river|react|route [--alive-layout=name] --tag=x` (real window, see
`scripts/alive_shot.gd`) saves `autotest/alive_<region>_<kind>_<tag>_*.png`.

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

Kills give XP, and a level comes about once per arena wave (the curve is fitted to the XP
a run earns per wave, so the first room no longer gives three levels and floor 5 no
longer waits two minutes for one). Each level, once the room is clear, you pick one of
three **boons** (`scripts/levelup.gd`): fewer, bigger picks than before (+10 to 35%
damage instead of +4 to 16%), and every one feeds what deals the damage. Damage reaches
guns, reactions, fusions and burns (a shot's damage seeds the potency of everything it
causes); Catalyst, Smoulder (burn, poison, bleed), Alchemist (fusions), Apocalypse
(cataclysms), Residue (compounds wait longer) and Standing Fields (fields last longer)
push one tier of the ladder; each element you carry has an Attunement (+damage for its
guns) and an Echo (your reactions with it spread a partner element nearby: Shock spreads
Wet, Fire spreads Oil...); Glass Cannon, Overclock, Heavy Plate and Split Barrel trade one
stat for another. A card shows the effect big ("+16% damage"), your value now and after,
what it changes in plain words, the rarity as frame colour and word, and the element as
a badge. XP gain, luck, scrap, range, projectile speed and element duration are no longer
level-ups (measured: they barely moved damage, and element duration lowered it).

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
unlocked guns. Achievements add guns, Marks and Kits, obstacle kinds, the challenge room and
shop upgrades to the pool future runs draw from. The first ten teach the basics and hand
out one new element per run, Risk of Rain 2 style, so every element is in the pool by
about run 5: discover 3 reactions (ice), vent 10 times (acid), start 2 runs, clear 5
rooms (poison), discover 6 reactions (gale), kill 3 elites (blood), start 3 runs (stone),
fire 250 reactions (void), start 5 runs (holy). Mark unlocks (each with its Kit) ask for 15
to 40 of their signature reaction instead of 60 to 90. Progress is saved to `user://save.json`; the
run-end screen shows what you unlocked, the Embers earned and what is next. The
self-test uses its own save file and never touches yours: any command-line argument after
`--` points the save at `user://save_autotest<_N>.json` before it is first read.

## Loadouts

There is one descender, the Vagrant (`scripts/loadout.gd`). At the Gate (the arch or the
Gatewarden's Descend) you pick four slots on one screen (`scripts/loadout_screen.gd`):
up / down picks a slot, left / right or LB / RB changes it, A / Enter descends; the mouse
clicks a slot's arrows and Descend.

- **Kit**: the starting gun. Bare hands means the entrance offers a pick of two guns.
- **Mark**: an element affinity (+20% potency, +10% damage), a quirk and a starting item,
  shown on the figure as a glowing brand on the chest. The 13 old classes are the 13 Kits
  and Marks: the Pyromancer is the Flare Pistol Kit with the Mark of the Pyre, with the
  same numbers. Old saves turn each unlocked class into its Mark and its Kit (save
  version 3), and each Mark achievement grants both.
- **Relic**: one item carried into the run. Each region's start room has a Well: drop one
  worn item down it and, however the run ends, it waits for the Wellkeeper. She moves into
  the Fire room the first time something waits, and sells it back as a Relic for Embers
  (15 to 75 by rarity). A Relic is yours for every run.
- **Vow**: harder runs for more Embers. Vow of Iron: enemies have 25% more health. Vow of
  Glass: -30 max HP. Each pays +20% Embers on the whole run.

Mark and Vow names and texts are placeholders until the writing review (World and
progression GDD, section 9).

## HUD

Vitals top-left (portrait, level, health, XP), room and timer top-centre, minimap with
scrap and kills top-right, the gun hotbar bottom-centre (tier pips and mod dots on each
gun, weight beside it), gear slots bottom-left, the vent gauge bottom-right with its
prompt. Everything is set in the Kenney Pixel font at 20 px or more.

**Rarity owns colour.** In menus, cards and the HUD, colour means rarity, in the World of
Warcraft palette: Common white, Uncommon green, Rare blue, Epic purple, Legendary orange
(gun tiers I to IV use the first four), always with the rarity word or pips beside it.
Elements never colour a frame or a name; they show as a small grey chip with a swatch
and the element's name. In the world, elements keep their colours. See GDD 6, "UI colour
rule". `-- --ui-shot --instance=N` (with `res://scenes/main.tscn`) saves review captures
of every rarity and element to `autotest/ui_*.png`.

## Danger: never die without knowing

- **Every hit**: the screen edge flashes red, strongest on the side the hit came from
  (all round for the floor), your figure flashes red-white, a red "-N" rises, the health
  bar flashes and leaves a pale ghost of what you lost, and a deep "you were hit" thud plays.
- **Low health** (under 35%): the screen edge glows red and pulses with a heartbeat, the
  pad rumbles on each beat, the health bar and card pulse and say LOW HEALTH; under 15%
  it is deeper and wider and says CRITICAL. The "Screen flashes" option softens the hit
  flash and holds the low-health edge steady instead of pulsing.
- **Hurting floors** (burning floor, charged water): your rim and a ring at your feet take
  the floor's colour while you stand in it, each tick hisses, and the first time each kind
  bites in a run it names itself ("Charged floor: 3/s"). A floor made by an element you
  carry hurts you half (charged water is only ever made by shock).
- **Exploding barrels** burn a 0.6 s fuse: they blink faster and faster while a ring grows
  to the blast radius over the danger zone. **Bombers** show their blast radius once you
  are close enough to be caught.
- **Enemy shots** are drawn above all of your own effects: a near-black outline, the
  element colour, a white-hot core.
- **Death recap** on the run-over screen: what killed you, the last 10 s of damage by
  source and a health line over the last 30 s with each hit marked.

`-- --autotest --hurt-shot --instance=N` (real window) saves `autotest/hurt_*.png`: a hit
from the left, low and critical health in a six-gun fight, charged water underfoot, a lit
barrel and the death recap.

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

Forty-three guns in 22 archetypes, and each archetype fires its own way, so two guns of
different archetypes never play the same (at most three guns share one, and no element has
two of one): pistols (plain aimed shots), bursts, repeaters (spin up from 40% to full rate
while firing), a shotgun (pellets, knockback), a sling (caroms off walls and enemies), a
helix (an ice and a fire bolt twisted together, every hit melts), wands (split into bolts
on the first hit), cannons (a huge slow ball through everything, shoving it), flak
(proximity burst into shards), homing (seekers that spread over different enemies),
boomerangs, orbs (slow, pulse damage around them; the void one pulls), mortars, throwers
(a flask that leaves a pool), beams (a continuous ray that ticks and sweeps toward the
aim), sprayers (a short cone that hits everything in it and paints its floor: fire, water,
wind), chains (an arc that jumps between enemies), a nova (a ring around you), a melee
sweep, charge guns (wind up, then a rail through the whole line), mines (burst when an
enemy steps near) and a turret (sets down a kettle that fires steam on its own). The gun
card and the Journal say how each one fires in one line; icons come in one family per
archetype. Balance is measured, not budgeted: `--gun-probe` fires every gun alone at
dummies and the numbers sit in `scripts/gun_library.gd` and GDD.md ("Gun archetypes").
Gun ids never changed; Prayer Burst is now called Prayer Chain and Duality Burst Duality
Helix.
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

The game starts in the Hollow, a hub of five connected rooms (`scripts/hub.gd`): walk up
to a person or a station and press A or E. People talk first (a line keyed to your save,
`scripts/dialogue.gd`), then offer their services as buttons. In the Fire, the Keeper
opens the talent board (the Shrine). In the Stair, the Gatewarden starts a run (pick a
loadout first, see Loadouts) and shows your past runs; the Gate arch beside them opens the
same loadout screen.
The Archivist, once freed (see below), lives in the Library and opens the Journal
(Reactions, Fusions, Cataclysms, Secrets) and the full Ledger with totals. In the Forge,
the Armory opens the Journal's Arsenal and Gear tabs and the Workshop opens Options. In
the Chapel, the Mirror sets names and the Trophy Wall lights one tile per achievement with
the next three goals under it. A fresh save shows only the Keeper, the Gatewarden and the
Gate; the Forge and Chapel stations appear after the first run.

The Archivist sits chained in the treasure room of the Ossuary Gate (the first region)
every run until freed. The first elite you kill in a run drops a Torn Bestiary Page;
carry it to the Archivist and give it (A / E) to free them. People are drawn in code
(`scripts/npc.gd`, FigureGen blends). Every line in the game is a placeholder until the
voice sheets in `design/Voice sheets, phase 1.md` are approved. The first time you play, a short tutorial room runs before the
hub (replayable from the hub's Esc menu). A one-time explainer card states the loop:
runs are five floors ending in bosses; dying keeps achievements, unlocks and Embers;
runs pay Embers for rooms, elites and new reactions, and the Shrine trades them for
swappable talents; the loadout changes the start only. The run-over screen reports this run,
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
for the DualSense). Local build: `tools/export_exe.sh` (stamps the build label), or the "Windows" export preset,
or `godot --headless --path . --export-release Windows export/windows/Pressure.exe`.

### Exe smoke test (required before every push)

`tools/exe_smoke.sh [scratch_dir]` exports a release exe to a scratch folder and runs it
**headless** three ways, each through the real Gate path: the Hollow opens the loadout screen
and presses Descend, a short run, back to the Hollow, a second Descend, back, quit. The runs
are lighting on, lighting off (the Options flag through a throwaway settings file), and player
mode (no bot). Each must exit 0 with no crash, reach the Hollow again and print 0
`SCRIPT ERROR`. It ends in `[SMOKE] ALL PASS` (about 2 minutes) and cleans up its throwaway
files (instances 9901 to 9903). Run it before every push. The debug editor does not catch
release-only crashes. On 2026-11-10 a lambda kept in a static var (`Materials.on_force`)
crashed the exported exe at every teardown after a run (exit 139, 0xc0000005) while every
editor check passed. The same day a mouse click on Descend crashed the exe outright:
`change_scene_to_file` ran inside the click's own GUI dispatch and pulled the Hollow out from
under it (Enter only printed a SCRIPT ERROR, and the debug editor never crashed). The script
also fails on any `static var ...: Callable` and on any `change_scene_to_file(` without
`.call_deferred`. Keep Callables out of static vars, and never change scene synchronously.

The probe flags: `-- --hub-descend` (the Hollow opens the Gate and clicks Descend with the
mouse, through the GUI; `--descend-key` presses Enter instead; the run
hands back to the Hollow after `--secs=N`, and the Hollow quits after `--descend-runs=K` runs,
default 1). Add `--autotest --one-floor` for the bot, or leave it out for player mode.

Exported-exe runs are headless only. `tools/bot_window.sh` cannot keep an exported exe from
taking focus, because its override file lives in res://, inside the project. If a windowed
exe run is really needed, put an `override.cfg` with `[display]` /
`window/size/no_focus=true` next to the scratch exe only, never in `export/windows/`, and
check with GetForegroundWindow that focus does not change before relying on it. On 2026-11-10 such a
file did not stop the exe taking focus, probably because project.godot sets its own
`project_settings_override`, so treat windowed exe runs as off-limits.

## Frame rate

The game caps at 60 fps by default (Options "Frame cap": 60 FPS or UNCAPPED, Settings
`fps_cap`, applied through `Engine.max_fps`); vsync is its own option. The target is that
heavy fights hold 60 fps with a 1% low at or above about 55. On a 100 Hz monitor with vsync a
60 cap can pace frames slightly unevenly; UNCAPPED avoids that. Runs started with command-line
arguments (bots, captures, `--perf`) stay uncapped to show headroom; `--fps-cap` caps them.
The Web build and the GitHub Pages deploy were dropped on 2026-11-09: the game ships as the
Windows exe only.

## Telemetry

Anonymous, opt-in play data for balancing (`scripts/telemetry.gd`, autoload `Telemetry`).

- **What.** One record per run: a random run id, a random device id (saved in settings,
  never a name), the build label (`Telemetry.BUILD`, see "Build label" below),
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
- **Build label.** Every record carries `Telemetry.BUILD` = `VERSION+COMMIT`, for example
  `2026.11.08-p4+1a2b3c4`. Each phase (or any build you share) bumps `VERSION` in
  `scripts/telemetry.gd` by hand to the date plus a phase tag. `COMMIT` stays `"dev"` in the
  repository: the Windows release workflow stamps the short commit hash into it before
  exporting, and `tools/export_exe.sh` does the same for the local exe (commit first; it
  restores `"dev"` afterwards). A run from the editor or a bot says `+dev`.
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

Late floors (retuned from a won human run, details in GDD.md "Late-floor balance"):
- **Leech is capped**: lifesteal heals per reaction, but only three reactions a second
  count. A six-element build causes 40 to 80 reactions a second late in a run, so uncapped
  Leech healed 20 times the damage the floor dealt and nothing could threaten it.
- **Bosses scale with the build** from floor 2: at least 30 s of the party's measured arena
  output (capped at 9x the old health), and two **rallies** at two thirds and one third: a
  guard that holds up to 8 s while a wave of adds lives, with 40% of the arena crowd kept
  alive in the boss room.
- **Late damage**: x1.3 on floor 2 and x1.55 on floors 3 to 5, now also on bomber blasts
  and on summons (both used to be flat). Floor 1 is unchanged.

The vent gauge is the vent's charge, so "pressure decay" upgrades were a trap: they are
now vent charge speed (the vent fills faster), and pressure limit reads as vent capacity.

## Figures are generated from your build

The character is a paper doll drawn pixel by pixel (`scripts/figure_gen.gd`), not a
fixed sprite. The Vagrant's own theme and every item, gun and completed set add weight to themes
(the twelve elements plus plate, scout, arcane, gunslinger and merchant). The strongest
theme picks the head and torso, the second the cape, arms and an accent, up to three
accents come from the top three, and the palette blends all of them with a touch of your
player colour. Close runners-up overlay a detail, so a Vagrant in fire gear with an
alchemist piece keeps the flame hood and gains goggles and a flask belt. The Mark adds only
its brand on the chest (`Player._draw_mark`).
Each pickup nudges a part or the colour instead of swapping the figure.
`FigureGen.debug_sheet(path)` renders every Mark's element theme and eight blends to one PNG.

What you wear is drawn on it (`scripts/worn_gear.gd`): every head, chest, hands and feet
item is its own hand-authored pixel piece of its kind, layered on the blended body. Hats:
pointed wizard hat (tall or bent), wide-brim hat, hood, open helm, visored helm, flat-top
great helm, horned helm, winged helm, crown, circlet, cap, skullcap, feathered cap, miner's
lamp, gas mask, goggles, monocle. Chest: vest, quilted jerkin, hide, apron, coat, robe,
shroud, plate (with pauldrons), spiked plate, thorned leather, mail, cloak (a cape in the
item's colours), bandolier, harness. Hands: gloves, gauntlets, spiked gauntlets, mitts,
wraps, fingerless gloves, bracers, a held sword. Feet: boots, tall boots, greaves,
sandals, wraps, shoes, winged boots. Each item maps to a kind by an explicit table
(`KIND_OVERRIDES`) with keyword rules on its name and icon as the fallback, and is
coloured from its own Dungeon Crawl icon (dominant hue with its shading, plus the most
common other hue as the trim or gem colour), so the hat on your head matches the hat you
saw on the pedestal; spell-icon items use their look tint, element or material. A worn
head replaces the theme head, a chest piece goes over the theme torso (open vests and
straps let the body show), so the class and gear themes still blend underneath. Rings and
trinkets stay small accents (sparkles, auras). Pieces are kept under the bloom threshold
so the glow does not wash them out. Figures are built once per gear change (about 1.5 ms)
and cached. `FigureGen.gear_sheet(path, slot)` renders every item of a slot on three
bodies next to its icon.

## Guns: six slots, duplicates, combining

Brotato's shape: six gun slots (a few items add one). Picking up a copy of a gun you
already carry merges it automatically: your lowest-tier copy rises one tier, with no slot
or extra weight needed, so a duplicate can always be taken even with six guns. Only when
every copy is at max tier does it take a new slot. Two carried copies at the same tier can
still be combined from the character sheet (Combine prompt). Drops are
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
- **Player**: hurt (a punch with a deep thud under it, unlike any enemy hit), a hiss per
  hurting floor tick, down, Last Breath revive, level-up, gun pickup, item pickup by rarity
  (richer as it gets rarer), active item, a low-health heartbeat under 35% HP (faster and
  louder toward 15%).
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

Big hits print their damage over the target: crits always (big yellow with a bang),
any other hit at 2.5x the running average of your hits (at least 25), element-coloured. Damage you take is a big "-N" in hot red
with a black outline over your figure, never crowded out by your own numbers.
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
(what the run paid, or would have paid when the time cap ended it), and on a death
`[LESSON] killer=<boss:kind|region:id> deaths=N new=<first death> unlocks=...`.
Every run with arguments after `--` uses throwaway `settings_`, `save_` and
`mastery_autotest<_N>.json` files and `telemetry/runs<_N>.jsonl` from the first frame
(`Main.bot_run()`), never the player's own.
`--fusion-probe` starts with four w1 guns of four elements so compounds, fusions and
cataclysms actually happen; the loadout rotates with `--instance` (wet/fire/shock/gale,
oil/fire/shock/gale, wet/fire/shock/blood, oil/fire/blood/gale), or pick one with
`--fusion-probe=K`. `--no-fusions` turns the tier ladder off (reactions leave no compounds),
which is the game before fusions for a like-for-like baseline. Late floors:
`--build=storm --start-floor=N` starts on floor N (2 to 5) with the build a human Stormcaller
carried there in a won run (guns and tiers, gear, gun mods, every level-up pick; the bot then
only fills free slots), `--build=mid` is a mediocre build at the same levels (tier-one guns,
random picks, no healing gear), `--route=ossuary_gate,rust_ruins,frostvault,the_forge,the_rift`
fixes the regions taken (checked against the graph; otherwise the bot takes a random route
door out of each boss room and prints `[ROUTE-DOOR]`, and every bot run prints a `[ROUTE]`
line with the graph check), `--no-exposed` turns the Exposed state off (soft resistances
stay; for A/B runs), `--loadout=id@tier,...` with a `--build` replaces the build's guns
(gear and levels stay), so element builds compare on one footing, `--one-floor`
quits when the next floor starts, and
`--old-balance` turns the late-floor tuning off (uncapped Leech, formula bosses without the
rally, the old floor damage) for before/after comparisons. Each boss kill prints a `[BOSS]`
line (game seconds, phase two, max health, the arena output it was sized from) and a
`[BOSS-BODY]` line (max health, phases reached and when, staggers, every reaction and fusion
per body part). During the fight `[BOSS-PHASE]`, `[STAGGER]` and `[BOSS-CHAIN]` lines log
phases, staggers, and each product on a part, plus torn and re-formed armour; `[BOSS-MOVE]`
logs the Hive Mother's eruptions, the Storm Warden's recharge strikes and the Void Herald's
theft and shard volleys; `[CHOIR-LEDGES]` and `[CHOIR-FLOOD]` log the Drowned Choir's dry
ledges and the player's phase 2 seconds on a ledge and on charged water; `[ARENA]` logs arena tool bursts (quench vats, war braziers, grounding pylons, holy lamps);
`[BOSS-SHOW]` logs the entrance (start, reveal, control back), each phase change and the death; `[MUSIC]` logs the boss music
per phase. Real-floor boss probes (the storm build at each boss's depth):
`--build=storm --start-floor=2 --route=ossuary_gate,rust_ruins --one-floor` (Hive Mother),
`--start-floor=3 --route=ossuary_gate,rust_ruins,frostvault --one-floor --secs=900` (Storm
Warden), `--start-floor=5 --route=ossuary_gate,rust_ruins,frostvault,the_forge,the_rift
--secs=1000` (Void Herald).
`--aim=assisted|manual|auto` sets the aim mode for the run (never saved); `--bot-aim` makes
the bot hold fire at its own pick in fights (on a parted boss, intact armour first, then
the part that takes most), and `--aim=manual` implies it.
`--boss-only` sends the bot straight to the floor's boss room and quits when the boss dies.
`--boss-dps=N` stands in for the arena output a real floor would have measured, which
sizes bosses from depth 2. `--boss-shot` (real window) saves `autotest/boss_<kind>_<s>.png`
at 1.5, 6, 12, 18, 24, 30 and 38 s into the fight, plus `boss_<kind>_entrance.png` (the name
card), `boss_<kind>_phase2.png` / `phase3.png` and `boss_<kind>_death.png` from the boss show
(`scripts/boss_show.gd`); with `--boss-only` the run then waits 1.4 s after the kill for the
death capture. `--fusion-probe=4` is the Pyre Lord's
chain loadout (water, shock, ice, fire). Example:
`--build=storm --start-floor=4 --route=ossuary_gate,rust_ruins,frostvault,the_forge,the_rift
--loadout=water_pistol@2,spark_needler@2,rime_chakram@2,flare_pistol@2 --boss-only --boss-dps=2200`. Every run ends with a
`[FUSION]` line (fusions and cataclysms fired, compounds and fields made, damage share by
tier 0 to 4, the top names by count and by share of fusion damage, a `[FUSION-JSON]` dump
for scripts) and a `[FUSION-CHECK] PASS/FAIL` line: the termination proof (no context
above tier 4, no product made at or below its own tier, at most the room budget of fusions
in one frame). For parallel silent runs add `--audio-driver Dummy` before the scene and
`--instance=N` after `--`; each instance gets its own save, Shrine and telemetry file.
`--dps-probe` (with `--build=storm --start-floor=N`) stands the player among eight harmless
dummies that never die and prints `[DPS]`: damage per second over `--probe-secs=N` (default
40) and its share by tier; `--probe-picks=id,id` adds level-up options, `--no-picks` drops
the profile's own. Add `--fixed-fps 60` before the scene to run it faster than real time.

**Pressure readout** (`scripts/pressure_meter.gd`, difficulty pass 2026-11-09). Every floor
ends with one `[PRESSURE]` line in bot logs and a `pressure` telemetry event in every run,
human or bot (player 1): `fight` seconds a room was active; `lt50` / `lt25` share of that
time under 50% / 25% health; `dmg_pm` and `heal_pm` damage taken and health healed per
fight minute as shares of max health, with healing by source (leech, regen, item, active,
fusion, pickup, altar, shrine, stairs, repair, revive); `hits` and `max_hit`; `close` drops
under 20% that were survived (re-armed above 35%); `threat` share of fight time with an
enemy shot within 150 px or an enemy within 70 px, and `moving` the share of that time
spent moving; `near_miss_pm` enemy shots per fight minute that passed within 24 px of a
hit; `clean` fights cleared without losing health, of all fights; `burst1` / `burst3` the
most damage taken inside any 1 s / 3 s, as shares of max health. Older telemetry has no
`pressure` event; its numbers can be rebuilt roughly from `damage_taken`, `wave_hp` and
`room_clear` (design doc, "Difficulty pass").

**Real-window bot runs** (fps, screenshots) go through `tools/bot_window.sh <timeout_s>
<log_file> <log_cap_bytes> <godot args...>`, so the window opens behind whatever Emil is
working in and never takes focus. It writes `autotest/window_override.cfg`
(`display/window/size/no_focus=true`), which project.godot names as
`application/config/project_settings_override`, starts Godot and deletes the file 3 s later,
once Godot has read its settings; the editor, exports and Emil's own runs never see it.
The window is not throttled: it still renders at 100 fps with vsync. Don't launch a
windowed Godot any other way, and don't add an `override.cfg`.
`--perf` measures frame times there: it stores every frame's wall time and prints once, at
the end, `[PERF-SUMMARY]` (mean fps, 1% low = mean of the slowest 1% of frames, median and
p99 frame time, frames over 12.5/16/25/50 ms, wall time lost past 10 ms), `[PERF-HIST]`
(frames per whole millisecond) and `[PERF-LABELS]` (per-frame cost of the frame phases and
any `Perf.add` labels, `[SPIKE]` lines for the first 200 frames of 16 ms or more). A
`--perf` run also keeps the fight's chatty logs quiet (`[TICK]`, `[BOSS-CHAIN]`,
`[BOSS-MOVE]`, `[STAGGER]`): every print through the bot's log pipe costs a 15 ms hitch on
Windows. `--perf-lines` brings them back plus a `[PERF]` sample line every 2 s.
`--grid-hash` prints `[GRID-HASH]` once a second: one hash of the whole materials grid
state. Same-seed headless runs still drift apart within a second (the game reads wall time
in places), so the identity proof for a grid change is the replay: `git show
<rev>:scripts/materials.gd | sed -e '/^class_name Materials/d' -e 's/var mats: Materials/var
mats/' > autotest/materials_old.gd`, then `godot --headless --path .
res://tools/grid_replay.tscn -- --old=res://autotest/materials_old.gd`. It drives both
versions through the same seeded workload (every element, gales, fills, still pools, wipes,
raised ground, shocked floods past STEP_CAP, a real Fx), compares the state hash after every
step and the global RNG position at the end, times steps, sweeps and stamps, and prints
`[REPLAY-CHECK] PASS/FAIL` (`--perf` adds any `Perf` labels).
`--payout-shot` saves the level-up cards, the wave-end spoils, the ring swap card and a
merge pedestal to `autotest/` (real window); `--hurt-shot` the danger cues (see Danger). Bots print `[LEVEL]` (level, floor, rooms,
XP so far), `[WAVE]` (what lay on the floor when a wave ended, lowest health),
`[DWELL]` (seconds spent in a cleared arena) and `[SALVAGE]` lines. `godot --path . -- --menu-shot`
screenshots the menu and codex. `--recruit-probe` (with `--autotest`, e.g. with
`--fusion-probe --one-floor`) walks to the Torn Bestiary Page after the first elite dies,
carries it to the chained Archivist, frees them and quits; it prints `[RECRUIT]` lines. The
bot's loadout: `--class=<old class>` is that class's Kit and Mark (`--class=pyromancer`),
and `--kit=<gun>`, `--mark=<id>`, `--relic=<item>` and `--vow=iron|glass` set one slot
each (the throwaway save opens what is asked for); every run prints `[GATE-LOADOUT]` and a
`[LOADOUT-STATS]` line per player (max HP, carry, guns, items and every non-zero stat) for
before/after checks. `--well-probe` drops the first worn item down the first Well and
prints `[WELL]` lines; a `--hub-walk --keep-save` on the same instance then buys it back
from the Wellkeeper (`[HUB-RELIC]`) and checks the Gate's slots (`[HUB-LOADOUT]`). A save
older than the current version (4) prints `[MIGRATE]` when it loads.
Shortcuts (`scripts/shortcuts.gd`, design doc "Phase 4"): every run prints `[SHORTCUT]` (the
floor's gate laid, skipped, opened or walked through), `[TRAVEL]` (seconds from floor start to
the boss room, and whether the gate was open) and `[BOSS-CHECK] PASS/FAIL` at every way down.
`[HAZARD] region=... gas_lit=N` (each new floor and at the end) counts gas cells set alight
in the Rotting Gardens (phase 5). Gardens probe: `--build=storm --start-floor=2
--route=ossuary_gate,rotting_gardens --one-floor --secs=700`.
`--rush` walks straight for the boss room, `--open-gates` walks through a gate from the
antechamber side to open it (and turns the Cistern's sluice wheel after the Choir dies:
`[SLUICE] opened`; every Cistern floor prints `[SLUICE] ... drained=true/false`),
`--shortcuts=all` opens every gate and the sluice in the throwaway save first,
and `--keep-save` keeps the instance's save from its last run (open a gate in one run, then
`--keep-save` the next to see it persist). A hub walk with the Cartographer home opens the
world map (`[HUB-MAP]`); `--hub-shot` also saves `autotest/hub_<station>_open.png`.
`godot --headless --fixed-fps 60 --path . res://scenes/hub.tscn -- --hub-walk --instance=N`
walks the Hollow on a fresh save and uses every station on show (`[HUB]`, `[HUB-FRESH]`,
`[HUB-TALK]`, `[HUB-STEP]`, `[HUB-WALK] PASS/FAIL`); `--keep-save` keeps the instance's
save instead (run it after a `--recruit-probe` on the same instance to check the Archivist,
the Journal and every old station), and `--hub-shot` (real window) saves
`autotest/hub_<station>.png` and `_talk` captures. `godot --headless --path . res://scenes/main.tscn -- --obstacle-test`
checks projectiles hit obstacles. `godot --headless --fixed-fps 60 --path . res://scenes/main.tscn -- --autotest
--gun-probe[=a,b,...]` fires each gun (or the ones named) alone at tier I against pinned
dummies and prints `[GUN-PROBE] id archetype mechanic element weight single=.. pack=..
budget=..` (damage per second on one dummy 75 px away and on a pack of eight 95 px away;
`--probe-secs=N`, default 6); with `--gun-shots` in a real window it instead saves
`autotest/gun_<id>.png`, each gun's mechanic mid-volley. `godot --path . --audio-driver Dummy res://scenes/main.tscn -- --autotest
--secs=30 --gear-shot[=id,id,...]` dresses the bot (a wizard by default), saves the worn-gear
sheets `autotest/gear_<slot>.png` and, at pixel size 3 (`--pixel-size=N`, `--set=bloom:0`
and the like for other options, nothing saved), a calm shot and fight shots with 4x
close-ups of the player (`gear_fight_<n>.png`, `gear_zoom_<n>.png`). `godot --path . res://scenes/main.tscn -- --themes-shot` saves
one arena per floor theme (crypt, ruins, frozen, forge, void, ambience running 2 s) and the
hub's sanctum as `autotest/theme_<name>.png`.
`--seed=N` fixes the run's random seed. `--clarity-shot[=boss] --tag=name` (real window, with
`--build=storm --start-floor=N --route=...`) stands the player in the floor's first arena (or boss
room) from a fixed seed and saves `autotest/clarity_<region>_<tag>_<n>.png` at three moments, each
with a `[CLARITY]` line: the share of screen pixels the player's own effects change, enemy-to-floor
luminance contrast, and on-screen text items (design doc "Clarity pass"). `--clarity-spitters=N` adds N spitters and
`[CLARITY-SHOTS]` lines (enemy shot contrast against the floor and against own effects). `--clarity-parts` adds a
`[CLARITY-PARTS]` line (each kind of own effect hidden alone, plus `noise=`: what moves with nothing
hidden), a `[CLARITY-CELLS]` line (cells per floor material) and `<shot>_mask.png` (red: own effects, blue: noise); `--floor-flat=sat,contrast,mid`
tries other floor flattening values. Every bot run prints
`[SPAWN-MOVED]` when a player walks onto a spawn marker and it moves, and `[SPAWN-CHECK] PASS/FAIL`
at the end (no body finished emerging within 60 px of a player).
A bot plays by itself for up to five minutes: explores rooms, buys from pedestals,
clears obstacles, fights elites and the boss, takes the stairs. It saves screenshots to
`autotest/` and prints progress and reaction counts. Use it to check a build still
works after a change.

## Art and fonts

All art is from Kenney (kenney.nl), CC0, no generative art:

- **Worn gear on the figure** (`scripts/worn_gear.gd`): hand-authored pixel grids, coloured
  at run time from the Dungeon Crawl Stone Soup item icons already in `assets/icons` (CC0,
  see its CREDITS.txt). No new image files.

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
export_presets.cfg   the Windows (and old Web) export presets;  .github/workflows/deploy.yml builds the release
tools/               export_exe.sh, export_web.sh (old Web export), get_templates.sh, analyze_telemetry.py,
                     telemetry_worker.js (Cloudflare), telemetry_sheet.gs (Google Sheets)
scenes/main.tscn     the only scene; everything is built in code
scripts/
  main.gd            run orchestrator: floors, current room, scrap, camera, HUD, joins, bot
  boss_body.gd       the boss framework: stagger, phases, name card, body parts (Pyre Lord)
  boss_show.gd       boss presentation: entrance, phase change, death, the antechamber cue
  regions.gd         the Descent: region graph (depth, theme, resists, weak to, hazards, boss,
                     signature layouts, edges); a run walks one region per depth; the
                     active region's soft resistances (60% / 140%) and Exposed
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
  loadout.gd         Kits, Marks, Relics, Vows;  loadout_screen.gd  the Gate's loadout screen
  well_screen.gd     the Well's pick of a worn item
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
  danger_fx.gd       red screen edge: hit flashes toward the hit, low-health pulse
  hurt_shot.gd       --hurt-shot capture of the danger cues
  character_sheet.gd gear, set bonuses and computed stats for one player
  music.gd           autoload `Music`: looping tracks with crossfades
  menu_pad.gd        direct controller polling for menu navigation
  ui_theme.gd        shared dark theme for menus
  telemetry.gd       autoload `Telemetry`: opt-in anonymous play data, local log, upload, export
```
