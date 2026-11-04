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
| Join (players 2-4) | | Start |
| Give player 1 a gun (debug) | 1 to 5 | |
| Restart | R | Start (after game over) |

Player 1 is keyboard + mouse and the first controller, merged. Every other
controller joins as a new player by pressing Start.

## Self-test

```
godot --path . -- --autotest
```

A bot plays by itself for up to five minutes: explores rooms, buys from pedestals,
clears obstacles, fights elites and the boss, takes the stairs. It saves screenshots to
`autotest/` and prints progress and reaction counts. Use it to check a build still
works after a change.

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
  gun_library.gd     autoload `Guns`: the gun pool
  projectile.gd      bullets: raw damage, then apply element; also hit obstacles
  elements.gd        autoload `Elements` / class `Element`: kinds, colours, reaction table
  enemy.gd           chasing, states, reactions, immunity, elite sequences, boss re-shield
  fx.gd              arcs, rings, floating text
  hud.gd             floor/room status, boss bar, minimap, player panels, help, banners
```
