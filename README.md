# Pressure

Co-op elemental-reaction dungeon shooter: Isaac-style rooms, Brotato-style waves,
Magicka-style reactions. See [GDD.md](GDD.md) for the full concept.

## Run it

Godot 4.7 is installed through winget. Either open the folder in the Godot editor
(Project Manager > Import > pick `project.godot`) and press F5, or from a terminal:

```
godot --path .
```

Guns aim and fire on their own; you move, vent, and pick things up.

| Action | Keyboard / mouse | Controller |
|---|---|---|
| Move | WASD | Left stick |
| Interact (pedestals, stairs, sigil) | E | A |
| Vent pressure | Space | LB |
| Use active item | F | X |
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

## Levels, mastery and reactions that chain

Kills give XP. Each level, once the room is clear, you pick one of three upgrades
(damage, attack speed, crit, bounces, pierce, health, armour, speed, scrap, pressure and
so on; the catalog is `scripts/levelup.gd`). Runs also earn **mastery points** (one per
floor reached, one per 150 kills, three for a win) spent in the Mastery tree from the main
menu: 212 small permanent nodes across offense, defense, pressure, economy, utility and
every element, drawn as a node graph around a core. Stick or d-pad walks the graph, A
buys, right stick pans, triggers zoom, shoulders switch branch; the mouse drags, wheels
and clicks. Wipe save clears both.

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
unlocked guns. Achievements (50 kills, 20 Chain
Lightnings, a boss kill, a hidden room opened, ...) add guns, obstacle kinds, the
challenge room and a fourth shop slot to the pool future runs draw from. Progress is
saved to `user://save.json`; the run-end screen shows what you unlocked and what is next.
The self-test uses its own save file and never touches yours.

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
  come in twos from 8, threes from 16. The arena feeds 20 + 11 x difficulty enemy hit
  points per second: each spawned group buys a pause of its total hp over that rate.
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

## Names

Main menu > Names: a field per player, saved with the rest of the profile. The name
replaces P1..P4 on the HUD, the character sheet and the level-up screen. Typing needs a
keyboard; the field is still reachable with a pad.

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
that measures the progression loop). The log prints `[FLOOR]` and `[DEATH]` lines. `godot --path . -- --menu-shot`
screenshots the menu and codex. `godot --headless --path . res://scenes/main.tscn -- --obstacle-test`
checks projectiles hit obstacles.
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
- **Effects are generated, not drawn**: every reaction, status and nova is pixel
  particles in the game's own palette (2 to 5 px squares, translucent, additive for hot
  elements) with per-element physics: fire rises and flickers into smoke, water falls and
  splashes, ice shards stop and crumble, sparks jitter with arcs, oil and blood arc and
  stick, void spirals in, gale streaks. Every element has a signature shape (flame
  tongues, splash crown, branching bolts, growing ice spikes, gas blooms, fizzing acid,
  blood spray, void implosion, light pillar, whirl, stone chunks) and a reaction draws
  both of its elements' signatures plus accents for what it does; the ring is only a
  thin outline of a burst radius. Nothing opaque ever covers the fight.
- **Kenney Fonts** (`assets/fonts/`): Kenney Pixel for the HUD and world text.
- **Kenney audio** (`assets/audio/`): a curated set from Sci-fi Sounds, Impact Sounds,
  Interface Sounds and RPG Audio, renamed to what they do in the game. The `Sfx` autoload
  maps names to files, picks variants, wobbles pitch and rate-limits repeats.

To change which sprite something uses, edit the coordinates in `scripts/art.gd`
(column, row on the packed sheet, 16px tiles).

## Layout

```
project.godot        project settings, autoloads, renderer
export_presets.cfg   the Web export preset;  .github/workflows/deploy.yml publishes it
tools/               export_web.sh (export + serve), get_templates.sh
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
  sfx.gd             autoload `Sfx`: one-shot sounds by name
  menu.gd            main menu (scenes/menu.tscn is the start scene), names screen
  pause_menu.gd      pause overlay, also the run-over screen
  journal.gd         achievements / arsenal / gear / reactions journal used by both menus
  levelup.gd         level-up upgrade catalog;  levelup_screen.gd  the pick-one-of-three overlay
  mastery.gd         autoload `Mastery`: the permanent skill tree and its save;  mastery_screen.gd
  cloud.gd           lingering element patches that react with what enters them
  prompts.gd         Xbox-style button and key-cap drawing
  post_fx.gd         bloom, grading and CRT post-process
  character_sheet.gd gear, set bonuses and computed stats for one player
  music.gd           autoload `Music`: looping tracks with crossfades
  menu_pad.gd        direct controller polling for menu navigation
  ui_theme.gd        shared dark theme for menus
```
