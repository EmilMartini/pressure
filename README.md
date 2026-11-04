# Pressure

Co-op elemental-reaction dungeon shooter: Isaac-style rooms, Brotato-style waves,
Magicka-style reactions. See [GDD.md](GDD.md) for the full concept.

## Run it

Godot 4.7 is installed through winget. Either open the folder in the Godot editor
(Project Manager > Import > pick `project.godot`) and press F5, or from a terminal:

```
godot --path .
```

Controls are shown at the bottom of the screen in game. Press `F1` to hide them.

| Action | Keyboard / mouse | Controller |
|---|---|---|
| Move | WASD | Left stick |
| Aim | Mouse | Right stick |
| Fire primary | Left mouse | Right trigger |
| Interact (pedestals, stairs, sigil) | E | A |
| Toggle auto / manual aim | Tab | Y |
| Vent pressure | Space | LB |
| Swap primary gun | Q | X |
| Character sheet | C | Back / Select |
| Pause | Esc | Start |
| Join (players 2-4) | | Start on a pad that has not joined |
| Give player 1 a gun (debug) | 1 to 0 | |
| Wipe the save file (debug) | F9 | |
| Restart | R | |

The game opens on a main menu (Play, Journal, Wipe save, Quit). The pause menu doubles as
the run-over screen with the run summary and next goals, and also opens the Journal.
Menus take controller input directly: d-pad or left stick to move, A to press, B to go
back, shoulders to switch Journal tabs. The help strip at the bottom hides itself after
20 seconds; F1 brings it back.

## Character sheet

C, the pad's Back button, or the pause menu's Character entry. Shows equipped gear per
slot, each gun with its mod, every set with which bonus thresholds are active, and the
full computed stat list: health, armour, dodge, regen, move speed, damage, attack speed,
crit chance and damage, projectiles, pierce, range, potency per element, state duration,
chain jumps, lifesteal, thorns, pressure, vent, focus and scrap. Shoulders cycle players.

## Music

Four tracks by Kevin MacLeod (incompetech.com) under CC BY 4.0, see
`assets/music/CREDITS.txt`: a menu theme, a run theme, a boss theme and an after-run
ambient. The `Music` autoload crossfades and ducks while paused. The credit line is shown
on the main menu; keep it in any build you distribute.

## Journal

Three tabs, from the main menu or the pause menu:

- **Achievements**: every achievement, its progress, and what it unlocks.
- **Arsenal**: every gun with element, weight and stats. Locked guns show which
  achievement unlocks them.
- **Gear**: every item grouped by rarity with its slot and effect. Locked rarity tiers
  show how to unlock them.

Player 1 is keyboard + mouse and the first controller, merged. Every other
controller joins as a new player by pressing Start.

## Progression

Runs start naked: no guns, no gear. The entrance offers each player a pick of two random
unlocked guns. Achievements (50 kills, 20 Chain
Lightnings, a boss kill, a hidden room opened, ...) add guns, obstacle kinds, the
challenge room and a fourth shop slot to the pool future runs draw from. Progress is
saved to `user://save.json`; the run-end screen shows what you unlocked and what is next.
The self-test uses its own save file and never touches yours.

## Gear

Items drop from elites and bosses and sit in shops, treasure, hidden and challenge rooms.
Eight gear slots plus a mod slot per gun. Every item is a few lines of data in
[items.gd](scripts/items.gd): stat modifiers, conditional modifiers and triggered effects
that all compose. To add an item, add one `_add(...)` line; the drop tables, pedestals,
HUD and effect engine pick it up with no other change.

## Self-test

```
godot --path . res://scenes/main.tscn -- --autotest
```

Add `--short` after `--autotest` for a 70-second run. `godot --path . -- --menu-shot`
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
- **Kenney Fonts** (`assets/fonts/`): Kenney Pixel for the HUD and world text.
- **Kenney audio** (`assets/audio/`): a curated set from Sci-fi Sounds, Impact Sounds,
  Interface Sounds and RPG Audio, renamed to what they do in the game. The `Sfx` autoload
  maps names to files, picks variants, wobbles pitch and rate-limits repeats.

To change which sprite something uses, edit the coordinates in `scripts/art.gd`
(column, row on the packed sheet, 16px tiles).

## Layout

```
project.godot        project settings, autoloads, renderer
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
  enemy.gd           chasing, states, reactions, immunity, elite sequences, boss re-shield
  fx.gd              arcs, rings, floating text, particle puffs
  hud.gd             floor/room status, boss bar, minimap, player panels, help, banners
  art.gd             autoload `Art`: sheet lookups, particle textures, fonts, palette
  sfx.gd             autoload `Sfx`: one-shot sounds by name
  menu.gd            main menu (scenes/menu.tscn is the start scene)
  pause_menu.gd      pause overlay, also the run-over screen
  journal.gd         achievements / arsenal / gear journal used by both menus
  character_sheet.gd gear, set bonuses and computed stats for one player
  music.gd           autoload `Music`: looping tracks with crossfades
  menu_pad.gd        direct controller polling for menu navigation
  ui_theme.gd        shared dark theme for menus
```
