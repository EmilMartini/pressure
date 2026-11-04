# Pressure

Co-op elemental-reaction wave shooter. See [GDD.md](GDD.md) for the full concept.

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

Plays by itself for about 110 seconds, kiting and firing, saves screenshots to
`autotest/`, and prints kills and reaction counts per wave. Use it to check a build
still works after a change.

## Layout

```
project.godot        project settings, autoloads, renderer
scenes/main.tscn     the only scene; everything is built in code
scripts/
  main.gd            arena, waves, elites, resistance drift, camera, HUD, joins
  player.gd          movement, aim modes, arsenal, pressure, focus, health
  player_input.gd    one player's controller / keyboard+mouse reading
  gun.gd             a carried gun, fires projectiles
  gun_data.gd        gun stats resource
  gun_library.gd     autoload `Guns`: the gun pool
  projectile.gd      bullets: raw damage, then apply element
  elements.gd        autoload `Elements` / class `Element`: kinds, colours, reaction table
  enemy.gd           chasing, states, reactions, immunity, elite sequences
  fx.gd              arcs, rings, floating text
  hud.gd             wave timer, player panels, help, game over
```
