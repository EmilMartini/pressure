# Pressure: world and progression design

Version 2, 2026-11-06. The design is agreed in outline and nothing in it is built yet. The current
game is described in `GDD.md`; this document describes where it goes next. Evidence comes from
`research_notes/World structure references/notes.md` (claims tagged there as verified, single
source or unverified), from `reports/Roguelite meta progression analysis.md`, and from the
designer's own telemetry.

---

## 0. Brief for agents

Read this section before starting any phase.

### How to use this document

- **Locked** means the designer decided it. Build it as written, unless the data says it fails;
  then report the data instead of quietly changing it.
- **Default** means the question is still open. Build the default, keep it easy to change, and
  list it in your report.
- Each phase in section 15 has a goal, a scope, the code to start from, acceptance checks and
  what is out of scope. Do one phase per task unless told otherwise.
- When a phase is done, update section 16 (decisions and open questions) and the relevant
  section of `GDD.md`.
- **Each phase runs in a fresh session**, decided by the designer on 2026-11-06. Start from this
  document, `GDD.md` and `README.md`, not from an old conversation. A long session re-reads its
  whole history on every message, which costs far more of the budget.
- Keep usage low: use a cheaper model for research, line reviews and simple checks; test small;
  don't re-run a measurement unless a result looks wrong.

### Standing rules from the designer

| Rule | What it means in practice |
|---|---|
| Data, not guesses | Measure before and after with bots and telemetry. Report numbers, not impressions. |
| Usage budget | About 20% of the weekly limit per work day. Keep agents few, runs short, edits targeted. Nothing runs overnight. |
| Bot load | At most 4 Godot instances at once per agent. Measure fps only while nothing else runs. |
| Difficulty | Like Hades: early runs are meant to fail, and meta progression carries the player. Fix unfair deaths (sudden bursts, unreadable threats), not overall difficulty. |
| Single player | Design and test for one player. Don't break the existing co-op code, and don't invest in it. |
| Art | No generative AI art. Only existing assets, verified CC0 assets credited with their source, or art drawn in code. |
| Writing | Claude may write player-facing text, but it must feel human (section 9). |
| Controller first | Every new screen and interaction works on a gamepad, with keyboard and mouse as well. |
| Readability | Anything that can hurt the player uses the hostile signature: black outline, red rim, drawn above player effects (`scripts/hostile.gd`, GDD "Friend or foe"). |

### Checks every phase runs

Godot 4.7.2 is installed through winget. `godot_console.exe` is a shim: launch parallel runs with
`&` and `wait`, never kill Godot by image name, and never poll with a tasklist loop.

```bash
G="$LOCALAPPDATA/Microsoft/WinGet/Links/godot_console.exe"
"$G" --headless --path . --editor --quit          # load check: no script errors
git checkout -- default_bus_layout.tres            # the editor sometimes rewrites it
```

```bash
# Bot runs: headless, fast-forwarded, each with its own --instance so the real save is never touched
"$G" --headless --fixed-fps 60 --path . res://scenes/main.tscn -- --autotest --one-floor --secs=420 --idle --loadout=frost_caster,blowtorch,mist_sprayer,gale_blaster,storm_pike,arc_rifle --instance=N
"$G" --headless --fixed-fps 60 --path . res://scenes/main.tscn -- --autotest --one-floor --secs=420 --fusion-probe --instance=N
```

```bash
# Frame rate: a real window, nothing else running; heavy fights should hold about 98-100 fps with vsync
"$G" --path . --audio-driver Dummy res://scenes/main.tscn -- --autotest --secs=75 --short --arsenal --gear --perf --instance=N
```

Every bot log must have 0 `SCRIPT ERROR` lines. `README.md` lists every bot flag, including
`--build=storm`, `--start-floor`, `--old-balance`, `--mastery`, `--veteran`, `--gun-probe` and the
screenshot captures (`--hurt-shot`, `--read-shot`, `--payout-shot`, `--gear-shot`). The idle
six-gun bot must keep dying in the first region.

---

## 1. Vision

Pressure becomes a long game made of short runs: a descent into a dark, connected underworld of
elemental regions, built for a player who wants to break the game with element combinations.
A run takes 30 to 45 minutes. The whole game takes dozens of hours, because the world is wide,
not because a run is long.

Five pillars:

1. **Broken combinations stay the heart.** Every system feeds the reaction, fusion and cataclysm
   chain. Regions and bosses ask "which reaction cracks this?", not "do you have enough damage?".
2. **A world, not a list of floors.** Regions connect into a map you learn by heart. Each run takes
   a route through it, and shortcuts you open by hand change how you move through it.
3. **Death teaches.** Every death leaves something: knowledge, a lesson from an NPC, an unlocked
   tool, a shortcut that stays open. Nobody is expected to win early.
4. **One wanderer, many loadouts.** The player is always the same descender. Classes become
   loadouts chosen in the hub.
5. **Dark, gritty and alive.** A Firelink Shrine style hub full of people who remember you, and a
   world whose state changes as you push deeper.

---

## 2. Where the game is today

### Content

| Part | Today |
|---|---|
| Run | 5 floors, each a grid of rooms: start, arena, shop, treasure, challenge, hidden, boss. A winning run took about 42 minutes. |
| Combat | 12 elements, 65 reactions, 220 fusions, 176 cataclysms; 43 guns in 22 firing types; 172 items in 10 sets |
| Themes | 6 dungeon themes with ambience: crypt, ruins, frozen, forge, void, sanctum. Cosmetic only. |
| Bosses | 5: Brute King, Hive Mother, Storm Warden, Pyre Lord, Void Herald. Two phases split at half health, guard rallies from floor 2. |
| Classes | 13: the Vagrant plus one per element, each a starting gun, item and stat change |
| Hub | One room of stations: Armory, Shrine (talents), Mirror, Ledger (journal), Workshop, Gate |
| Meta | Embers buy Shrine talents; achievements unlock guns, classes and elements |
| Pacing | Elites carry elemental shields broken by one reaction. Embers flow too fast: a winning run paid 427 against 928 for the whole Shrine. Floor 2 is being retuned on 2026-11-06; check the balance section of `GDD.md` for the latest numbers. |

Almost all of the combat and content carries over. What changes is the shape around it: the
world, the hub, how a run starts, and how progress is earned.

### Code map

| System | Start here |
|---|---|
| Run flow, floor number, difficulty, bot autotest | `scripts/main.gd` (`FLOORS`, `floor_number`, `difficulty()`) |
| Floor layout generation | `scripts/floor_gen.gd`, `scripts/room_data.gd`, `scripts/room_layouts.gd` |
| Room logic, waves, spawning, boss sizing, floor damage | `scripts/room.gd`, `scripts/spawn_table.gd` |
| Enemies, bosses, phases, crowd control | `scripts/enemy.gd` |
| Themes and ambience | `scripts/themes.gd`, `scripts/ambience.gd`, art in `assets/dungeon` |
| Reactions, compounds, fusions, cataclysms | `scripts/elements.gd`, `scripts/fusions.gd`, `scripts/cloud.gd`, `scripts/fusion_fx.gd` |
| Floor materials (GPU drawn) | `scripts/materials.gd` |
| Hub and its stations | `scripts/hub.gd`, `scripts/mastery_screen.gd`, `scripts/journal.gd` |
| Classes | `scripts/classes.gd`, `scripts/class_select.gd` |
| Meta: Embers and talents | `scripts/mastery.gd` |
| Unlocks, achievements, save | `scripts/progress.gd` |
| Items, gear, drops | `scripts/items.gd`, `scripts/drops.gd`, `scripts/pedestal.gd` |
| Player, aim, input | `scripts/player.gd`, `scripts/player_input.gd` |
| Hostile readability | `scripts/hostile.gd`, `scripts/enemy_projectile.gd` |
| Figures (player and NPC look) | `scripts/figure_gen.gd`, `scripts/worn_gear.gd` |
| Tutorial | `scripts/tutorial.gd` |
| Telemetry | `scripts/telemetry.gd`; the designer's real runs are in `%APPDATA%/Godot/app_userdata/Pressure/telemetry/runs.jsonl` (read only) |

---

## 3. Run structure and length

**Locked: 5 regions per run, about 7 to 9 minutes each, 30 to 45 minutes in total.**

The evidence for this length:

| Game | Run length | What it teaches |
|---|---|---|
| Hades II | about 30 min per successful run | Long game, short runs |
| Halls of Torment | 30 min cap | A cap keeps sessions predictable |
| Brotato | about 25 to 30 min | Same |
| Pressure today | about 42 min for a win | Already in range |
| Returnal | 2 h or more near the end | Players asked for a save system |
| Risk of Rain 2 | Clear at stage 20, then endless loops | The end condition, not the content, makes runs long |

The world grows in breadth instead. Each run visits a route of 5 regions out of 11 or more, and
always ends at a fixed final boss, never in an endless loop.

A region replaces today's floor and keeps the room grid and room types:

| Piece | Count | Time |
|---|---|---|
| Arena waves | 3 to 4 | about 45 to 60 s each |
| Optional rooms | shop, treasure, challenge, secrets | the player's choice |
| Region boss | 1 | 25 to 50 s |
| Total | | about 7 to 9 minutes |

**Default:** no hard run timer; regions stay within budget through their room counts.

---

## 4. The world: the Descent

### Shape

**Locked:** the world is a graph of regions in five depths, two or three regions per depth. A run
goes down one region per depth. Dead Cells works this way, with 24 main and 12 boss biomes, of
which each run reaches one per stage.

The graph has two halves, as Hades II has two routes: a **wet and cold** side and a **hot and
dry** side. A run can cross between them at certain depths. This doubles the content without
lengthening any run.

```
Depth 1                  Ossuary Gate
                     /        |         \
Depth 2   Drowned Cistern  Rotting Gardens  Rust Ruins
              |       \        |        /       |
Depth 3   Frostvault    Pitch Mire     Abattoir
              |        /        \        |
Depth 4   Stormspire      The Forge      Chapel of Ash
                  \           |           /
Depth 5                    The Rift
```

The edges are illustrative and get fixed in phase 0. **Default:** the crossing points between
halves are ordinary edges; repaired lifts (section 8) add more of them.

### Regions

**Locked: this roster and these elements.**

| Depth | Region | Theme today | Resists | Weak to | Hazards | Boss |
|---|---|---|---|---|---|---|
| 1 | Ossuary Gate | crypt | nothing | nothing | bone piles, barrels | The Brute King (exists) |
| 2 | Drowned Cistern | new | Wet | Shock | rising water, conductive puddles everywhere | The Drowned Choir (new) |
| 2 | Rotting Gardens | new | Poison | Fire | spore clouds, gas that ignites | The Hive Mother (exists) |
| 2 | Rust Ruins | ruins | Stone | Acid | collapsing floors, rust dust | The Rusted Colossus (new) |
| 3 | Frostvault | frozen | Ice | Fire | ice sheets, cold that slows | The Frost Matron (new) |
| 3 | Pitch Mire | new | Oil | Fire, spread by Gale | tar that slows, oil that can be lit | The Tar Saint (new) |
| 3 | Abattoir | new | Blood | Holy | blood floors that heal enemies | The Butcher Abbot (new) |
| 4 | Stormspire | new | Shock | Stone (grounding) | lightning strikes on a rhythm | The Storm Warden (exists) |
| 4 | The Forge | forge | Fire | Wet, Ice | lava, steam vents | The Pyre Lord (exists) |
| 4 | Chapel of Ash | sanctum | Holy | Void | light pillars, consecrated ground | The Ashen Bishop (new) |
| 5 | The Rift | void | Void | Holy | gravity wells, collapsing space | The Void Herald (exists), then The Heart Below |

Secret regions are reached only through secret edges or puzzles: **The Hollow Wells** under the
hub, home of the Wellkeeper, and **The Gale Galleries** above the Stormspire, with Gale enemies
and a hidden boss.

Six of the eleven region themes exist as art. The others are built from the free Dungeon Crawl
tiles the game already uses, which include water, swamp, lava, gore and chapel sets.

**Default:** the final region always ends with The Heart Below (section 6), a boss built from the
player's own run.

---

## 5. Elemental resistances and weaknesses

**Locked: start with 60% damage for a resisted element and 140% for a weakness, then tune with
data.**

1. **Soft, never absolute.** A resisted element deals 60% damage, and its states last half as long.
   A weakness deals 140%, and its states last longer. Only boss phases can be immune. No build is
   useless in a region; it is only slower.
2. **Reactions break resistances.** Soaking a Forge enemy with water makes it *Exposed* to fire
   for a few seconds; electrifying a Cistern enemy turns its water resistance into a weakness.
   Noita already makes wetness change how things burn; Pressure makes it the main tool against a
   region.
3. **Regions bend drops, not builds.** A region's shops and spoils lean toward its weakness, so a
   build can adapt during the run without starting over.
4. **Readable at a glance.** Resistant enemies show a dull element badge and weak ones a cracked
   one. The Journal records each region's profile once discovered.
5. **Elite shields stay.** Elites keep "break this shield with reaction X", now matching the
   region.

**Default:** the player's own floor hazards don't change with the region.

---

## 6. Bosses: elemental creatures you can chain on

Today a boss is one sprite with two phases and one compound slot like any enemy: a bigger health
bar, not a creature. The goal is a fight people tell stories about: "I steamed the Pyre Lord's
armour, then lit the steam, and the storm cloud tore it off."

### Rules

**Default for all of these; the designer has not locked the boss design yet (section 16).**

1. **The body is a reaction surface.** A boss has two to four body parts, such as a molten core,
   armour plates, a crown or a spore sac. Each part holds its own element state and compound, so
   one boss can carry several chains at once, all the way to cataclysms.
2. **The boss feeds you its own counter.** Its attacks leave its element in the arena, and the
   fight teaches you to turn that into the next step of a chain against it.
3. **Stagger from reactions, not raw damage.** A stagger bar fills from reactions, more for higher
   tiers: a little for a reaction, more for a fusion, half the bar for a cataclysm. A staggered
   boss drops its guard for a few seconds and takes extra damage. Stagger adds to today's guard
   rallies rather than replacing them.
4. **Three phases, each a new problem.** At roughly two thirds and one third of health, each
   phase changes or adds an element, the arena or the rules, with a roar, an arena change and a
   new music layer.
5. **The arena is a weapon.** Every boss room has elemental tools: water vats to break, braziers
   to topple, pylons to charge, bells to ring.
6. **Readable.** Every attack uses the hostile signature and has a wind-up you can learn. No
   unavoidable damage.
7. **Presence.** A name card when the fight starts, its own music theme, a body three to six times
   a grunt's height, and hub NPCs who talk about it before and after. Bosses stay silent
   creatures.
8. **Death teaches.** Every boss has a lesson (section 10) that names its key chain.

Limits so chains don't trivialise bosses: each body part has its own fusion cooldown; bosses keep
the crowd-control diminishing returns at their resistance of 0.25, with stagger as the reward;
cataclysms keep the room limit of one per 1.5 seconds.

### Art

The free Dungeon Crawl set has only standard-size monster tiles, so bosses are built from several
tiles plus parts drawn in code, the way the figure generator builds the player. Each body part is
visibly separate so the player sees where each chain is building.

### Sketches

| Region | Boss | Body parts | Element and what it leaves | The chain it invites | Phases |
|---|---|---|---|---|---|
| Ossuary Gate | The Brute King (rework) | Bone armour plates, a crown | None; throws barrels | Teaches stagger: any reaction cracks a plate, and its barrels are your fuel | 1: smash. 2: plates fall; it swallows barrels and turns volatile. 3: enraged, crown exposed |
| Drowned Cistern | The Drowned Choir | A great bell with drowned singers fused to it | Wet; slowly floods the arena | Shock on the floodwater makes a Galvanic Sea against the singers, but you stand in it too: climb onto the platforms first | 1: songs that pull. 2: the arena floods. 3: the bell cracks and rings in shockwaves |
| Rotting Gardens | The Hive Mother (rework) | Spore sacs, a hive body | Poison; spore clouds | Fire on spores makes Smog, then shock on the Smog makes Firedamp: blow the sacs off her | 1: swarms. 2: she burrows; the sacs stay above ground. 3: the hive splits open |
| Rust Ruins | The Rusted Colossus | Iron plates, a magnetic core | Stone; collapsing floor | Acid dissolves the plates; shock on the bare core magnetises it so it pulls its own debris into itself | 1: stomps. 2: plates rust off; the core turns magnetic. 3: it rebuilds from the arena's scrap |
| Frostvault | The Frost Matron | Ice armour, a frozen heart, an icicle crown | Ice; ice floors, freezing breath | Fire melts the armour into water, shock on the water gives Cryoshock, and refreezing shatters the plates | 1: blizzard. 2: armour shatters into orbiting shards. 3: the heart is exposed and the room freezes over |
| Pitch Mire | The Tar Saint | A tar body, a burning halo | Oil; tar everywhere | Lit oil burns you both, so gale pushes the fire onto her. Firewhirls and conflagrations reward risky play | 1: tar rain. 2: the halo ignites and the arena becomes a fire trap. 3: she sinks and erupts from pools |
| Abattoir | The Butcher Abbot | Cleaver arms, a blood font | Blood; floors that heal him | Holy consecrates the blood floors and stops his healing; bleed on his arms turns his attacks on himself | 1: cleaves. 2: the font fills and he heals on blood. 3: he drinks the font and frenzies |
| Stormspire | The Storm Warden (rework) | Lightning rods, a storm core | Shock; strikes on a rhythm | Stone grounds the rods; his lightning on your steam makes Storm Clouds that hit him; water floors carry his strikes back | 1: pylons charge. 2: the arena rains lightning. 3: he becomes a moving storm you fuse against |
| The Forge | The Pyre Lord (rework, the showcase) | Molten core, slag armour, a fire crown | Fire; lava pools, flame waves | Water on the armour makes Steam on his body, shock on the Steam gives a Storm Cloud that tears the armour, and ice on the bare core gives an Obsidian shatter. Quench vats in the arena supply the water | 1: flame waves. 2: the armour cracks and the core is weak to ice. 3: the forge floods with lava; only quenched paths are safe |
| Chapel of Ash | The Ashen Bishop | Censer, light pillars, a mask | Holy; consecrated ground, blinding light | Void on the pillars makes an Eclipse that dims his light; breaking the mask reveals a void-weak face | 1: sermons, slow beams. 2: the pillars blind you and heal him. 3: the mask breaks; ash and void |
| The Rift | The Void Herald (rework) | Orbiting shards, a hollow centre | Void; gravity wells that bend your shots | Holy collapses the wells; a Rift compound on the shards pulls them into a cataclysm | 1: wells bend your shots. 2: it steals your most-used element. 3: the shards close in |
| The Rift, final | The Heart Below (new) | Built from your run | Resists your most-used element and uses it | Every win needs a second plan | Three phases built from your top three elements |

**Default:** no harder "awakened" boss versions until the endgame (section 12).

---

## 7. Aiming

Today guns auto-fire at the nearest enemy, and holding RT fires where the right stick or mouse
points. Multi-part bosses and mixed resistances make *where* you shoot matter: the chain you want
builds on one body part, resistant and weak enemies stand side by side, and beams, charge guns,
mines and sprays already depend on aim.

**Default: three aim modes in the options, with assisted twin-stick as the default.**

| Mode | How it plays |
|---|---|
| Assisted twin-stick (default) | Fires where the right stick or mouse points, with a soft lock that snaps to the nearest enemy or boss part inside a narrow cone. With no aim input for a moment, it falls back to auto-fire. |
| Manual | Fires only where you aim, with no assist. Hold to fire, or toggle constant fire. As in Enter the Gungeon. |
| Auto | Today's behaviour: nearest enemy, with RT to override. For accessibility and relaxed play, as in Brotato. |

In every mode, auto-fire never targets puzzles, props or obstacles, and boss parts are valid
soft-lock targets. The bot uses assisted mode with its own aim. Before fixing the default, compare
clear and boss times per mode with bots, and add telemetry for how often players aim manually.

---

## 8. Shortcuts, Dark Souls style

"You don't find shortcuts in Dark Souls, you find how one area is connected to the other." A
shortcut is a place in the world you open by hand, usually from the far side, and it stays open.
Nothing unlocks by counting clears.

**Locked:**

- **No waystones.** Every run starts at the top. Shortcuts work inside regions and between them.
- **Shortcuts open routes; they never skip bosses.** Dead Cells' runes open edges of the biome
  graph and never shorten the finale.
- **No free warping.** Dark Souls 2 critics say shortcuts lost their meaning once warping was free.

| Kind | Example | Effect in later runs |
|---|---|---|
| Gate opened from the far side | A chain-gate in the Ossuary, opened from inside its boss antechamber | You can walk from the region's entrance straight to the boss door. You skip the arenas, and their loot and XP with them. |
| Repaired lift | A broken lift in the Rust Ruins, fixed with a part from the Frostvault | A new edge in the graph: the Rust Ruins can lead down to the Frostvault |
| Bridge or sluice | Opening the Drowned Cistern's sluice | World state change: the Cistern is drained in later runs, with new rooms and fewer hazards but tougher enemies in the open |
| Secret edge | A breakable wall in the Chapel of Ash | A path to a secret region |

Each region has one or two shortcuts, found in play. The hub's world map shows every one you have
opened. **Default:** opened shortcuts never close again.

---

## 9. The hub: the Hollow

### Place

A ruined bell tower and crypt above the Descent, lit by a single fire. It starts nearly empty and
fills as you bring people home, like Firelink Shrine. It is a few connected rooms you walk
through: the fire, a forge, a library, a well, a chapel, and the stair down.

### The cast

Every station becomes a person with one job, one personality and lines that react to your runs.

| NPC | Job (replaces) | Personality | Where you meet them | What they ask for | What moves in with them |
|---|---|---|---|---|---|
| The Keeper | Shrine: Embers buy talents | Old, patient, tends the fire; speaks rarely and kindly | In the Hollow from the start | Nothing | The Shrine |
| The Gatewarden | Gate: start a run, Vows, the run history until the Archivist arrives | Grim veteran who lost a squad below; counts your deaths | In the Hollow from the start | Nothing | The Gate |
| The Archivist | Ledger and Journal; gives death lessons | Obsessive scholar of monsters, delighted by gruesome deaths | Chained in a side room of the Ossuary | A Torn Bestiary Page from your first elite kill | The Journal: reactions, fusions, enemies, region profiles, lessons |
| The Collector | Collection log | Haggles with corpses | The Rotting Gardens | Any Rare item | Every gun and item you've ever found, with completion rewards |
| The Smith | Armory: gun unlocks and Kits | Gruff, burned, proud of every gun | Trapped under rubble in the Forge | A Forge Hammer from the Rust Ruins | The Armory |
| The Tinker | Workshop: gun mods | Nervous, talks to their tools | Hiding in a lift shaft in the Rust Ruins | A gun at tier 3 or higher | The Workshop |
| The Cartographer | World map and shortcut hints | Restless, half-mad from the Rift | Lost at the top of the Stormspire | Map Fragments from three different regions | The world map |
| The Alchemist | Reaction lore, fusion and cataclysm hints | Cheerful heretic, scarred by her experiments | Experimenting on herself in the Abattoir | A cataclysm discovered in that same run | Fusion and cataclysm hints |
| The Wellkeeper | The Well and Relics | Silent, trades in favours | The Hollow Wells, a secret region | Nothing: she follows whoever reaches her | The Well |
| The Rival | A fellow descender | Arrogant, competes for kills; can die or be saved | In regions from depth 2 | Story-driven (section 12) | Lines and a personal story |

Art: the free Dungeon Crawl tiles include many humanoid figures, and the figure generator can
dress them in worn gear like the player.

### Recruiting

**Locked: the Keeper and the Gatewarden are there from the start, and the Archivist is the first
NPC to recruit.** The rest follow in later phases.

- **Features arrive with their NPC.** A fresh save has the Shrine, the Gate and a bare run history.
  The Journal, the collection log, the Armory and the rest open when their NPC moves in, so each
  appears when there's something in it.
- **Giving costs something.** The item leaves your run, so recruiting means choosing between a
  stronger run now and a richer hub later, as in Elden Ring and Dark Souls quests.
- **Some asks are specific, some open.** A specific item makes a small quest; an open ask teaches
  the system early.
- **They remember.** First meetings have their own lines, and a second meeting on a later run
  remembers the first.
- **Missed, never lost.** If you skip someone or die, they're still there next run.
- **Default:** NPCs don't die permanently, except the Rival as part of their story.

### Bonds

Once an NPC lives in the Hollow, you can keep giving them items. Each has tastes: the Smith likes
heavy guns and the Alchemist anything Acid. Gifts raise a bond level, and each level unlocks new
lines that tell their story in pieces, a Keepsake for the Relic slot (as Hades' keepsakes come
from nectar), or a better service such as an extra mod slot from the Tinker. Gifts become the
main sink for unwanted loot, replacing plain salvage to scrap. **Default:** five bond levels per
NPC, one gift per NPC per visit to the hub.

### Dialogue volume

Hades shipped over 300,000 words and 22,000 voiced lines so its cast would not repeat across many
runs. Pressure uses fewer NPCs with lines keyed to state: what killed you, where, how deep, how
many deaths, which boss is new, which shortcut you just opened, which loadout you wear. The first
target is **1,500 to 3,000 lines** across the cast, written in batches per phase. **Default:**
text only, with no voice.

### Writing rules: human, not generated

The designer's rule: Claude may write the lines, but they must never read like generated text.

**Before any lines, each NPC gets a voice sheet:**

- What they want, what they fear and what they hide.
- How they talk: sentence length, vocabulary, and one or two verbal habits. The Gatewarden counts
  things; the Smith names guns like animals.
- What they never say.
- Ten sample lines the designer approves. Every later batch is checked against them.

**Rules for every line:**

1. **Specific beats general.** Name the thing: "the Frost Matron", "your third death on the
   bridge", "that oil slinger". Never "the darkness", "the challenges ahead" or "your journey".
2. **Short.** Most lines are one or two sentences. Dark Souls NPCs say little and imply more.
3. **Subtext, not exposition.** Characters talk around the world and their feelings rather than
   explaining them.
4. **No generated-text tells.** Banned words: delve, tapestry, testament, journey, embark, realm,
   beacon, unwavering, profound, intricate, vibrant, whisper of. Banned constructions: "it's not
   just X, it's Y"; "in the depths of"; three adjectives in a row; rhetorical questions to the
   player; motivational endings such as "you've got this"; lines that end on a moral.
5. **People are uneven.** They interrupt themselves, repeat a word, get something wrong, lose their
   train of thought, joke badly, and don't always answer what was asked.
6. **Grit without melodrama.** Dark and dry, not epic. Humour comes from character, not jokes.
7. **No praising the player.** NPCs have their own concerns. Respect is shown, rarely said.
8. **React to the actual run.** Prefer lines that could only exist after this death, region or item.

Example: the Gatewarden after your third death to the Frost Matron.

| Generated-sounding | Human |
|---|---|
| "Do not despair, brave wanderer. The icy depths have tested you, but your journey is far from over. Rise again!" | "Third time. She's patient, that one. So was I, once." |
| "The Frost Matron's power is immense, yet even the coldest heart can be melted by fire." | "You know what melts? Everything. Eventually. Bring something warmer." |

**Review for every batch:**

1. One agent writes against the voice sheets and the approved samples.
2. A second agent, given only these rules and the voice sheets, flags every line that breaks a
   rule or could be moved to another NPC without anyone noticing. Flagged lines are rewritten or
   cut.
3. The designer reads at least 20 lines of each batch before it ships. Rejected lines go into the
   voice sheet as examples of what not to write.

The same rules cover all player-facing prose: item flavour, lore, region descriptions.

---

## 10. Death teaches: lessons and unlocks

### The loop

1. A boss or region kills you.
2. Back in the Hollow, the Archivist, or the NPC tied to that region, talks about it in character.
   They name the killer and hint at its weakness: "The Frost Matron? Ice bends to fire, child, but
   oil makes fire stay."
3. The first death to each boss unlocks a **lesson**: a counter tool joins the drop pool, such as
   the Oil Slinger after dying to the Frost Matron.
4. The Journal records the lesson, the boss's resistances and your best attempt.

The research found no game that does exactly this. The nearest are Halls of Torment's conditional
unlocks ("as the Archer, stand still for 3 minutes"), Dead Cells' blueprints, and Outer Wilds,
where knowledge itself is the progression. That makes it a strong hook.

### Rules

- One lesson per boss and per region hazard: about 20 to 30 in the first world.
- Lessons only unlock counters to what killed you: a gun, an item, a mod, a Mark or a shortcut
  hint. Never raw power.
- Today's achievement unlocks move to lessons or to loadout challenges (section 11), so every
  unlock has a story.
- **Default:** lessons trigger on bosses and region hazards, not on ordinary elites. The hint is
  vague after the first death and plain after the third.

---

## 11. Loadouts instead of classes

**Locked: one descender, starting as the Vagrant, with four loadout slots chosen at the Gate.**

| Slot | What it is | Comes from today's | Example |
|---|---|---|---|
| Kit | Your starting gun | Class starting gun | Flare Pistol |
| Mark | A rule-changing passive with its own trait pool | Class element and stat changes | Mark of the Pyre: burns spread when a burning enemy dies, and fire reactions grow faster; −10 max health |
| Relic | One item carried into the run | New, through the Well and Keepsakes | A ring saved from an earlier run |
| Vow | Optional difficulty modifiers for better rewards | New (meta report recommendation R9) | "Bosses enrage at half health" for +25% Embers |

The 12 elemental classes become 12 Marks. New Marks can change how a run plays, as Halls of
Torment's characters do, rather than only adding stats:

- **Mark of the Tide:** you can't fire while moving, but each volley doubles.
- **Mark of the Hollow:** no gun slots past three, but every reaction counts as one tier higher.

**The Well**, adapted from Halls of Torment: once per region you can drop one item into a well. If
you then die, the item is saved, and the Wellkeeper sells it back as a Relic.

**Unlocks:** each Mark and Kit unlocks through a challenge or a lesson tied to it, as Risk of
Rain 2 ties a challenge to each skill. For example, "kill the Frost Matron using only fire
reactions" unlocks the Mark of the Pyre.

**Defaults:** your appearance comes from gear, and the Mark adds a small accent such as a glow or
a cloak colour. One Relic slot, growing with the Wellkeeper's bond. Vows replace a classic
difficulty setting.

---

## 12. A living world

**Locked: these four ideas come first.**

1. **World state that changes.** Draining the Cistern, breaking the Forge's dam, putting out the
   Chapel's fire. Each change alters that region in later runs and can open or close routes. The
   hub's world map shows the current state.
2. **People who move.** Recruited NPCs also set up camps inside the Descent: a merchant at depth 3,
   the Tinker's workbench in the Rust Ruins. The world fills with your own history.
3. **The Rival.** A fellow descender who turns up in regions, competes for kills and loot, and
   remembers. Sometimes you save them, sometimes they die, sometimes they turn on you. A story
   told across many runs, as Thanatos's is in Hades.
4. **Elemental weather.** Fronts that sweep a region for a whole run: a blizzard through the
   Frostvault, a thunderstorm in the Stormspire, ash fall in the Chapel. They shift resistances and
   hazards using systems that already exist.

Parked for later:

5. **Border fights.** Where two regions meet, their enemies fight each other, and a wet enemy hitting
   a fire enemy makes steam.
6. **World-scale puzzles.** Today's hidden walls grow into elemental locks that need a specific
   fusion to open a secret region.
7. **Lore in the world.** Murals, corpses with notes and item flavour that piece together why the
   Descent exists, read through the Archivist.
8. **Endgame.** Vows as heat; after a first win the Rift opens deeper ("Pressure levels", like Dead
   Cells' boss cells); a daily descent with a fixed seed.

**Default:** the story is one question the whole game answers: what lies at the bottom of the
Descent, and why do people keep going down?

---

## 13. Meta progression and pacing

**Target: a first win after roughly 15 to 25 hours.** Hades' main story takes about 15 to 22
hours, typically after 20 to 30 runs. At 30 to 45 minutes per run, that is about 25 to 40 runs.

**Measured today:** one winning run paid 427 Embers against 928 for the whole Shrine, so the meta
would be finished in 2 or 3 runs. Most came from elites (94 at 2 each) and first discoveries
(34 at 3 each).

| Currency | Earned by | Spent on |
|---|---|---|
| Embers | Every run, scaled by depth reached | Shrine talents, from the Keeper |
| Lessons | Dying to new things (section 10) | Unlock counters automatically |
| Keys and parts | Found in regions | Shortcuts and lifts (section 8) |
| Favours | Recruiting and gifting NPCs | The Well, Relics and NPC services |

Four currencies is the upper limit. **Default:** Embers are kept on death, never dropped.

**Locked: difficulty by meta stage.**

| Meta stage | Expected result |
|---|---|
| Fresh save | Usually dies at depth 2 |
| About half the Shrine | Usually reaches depths 3 to 4 |
| Full Shrine plus a strong build | Can win, but not reliably |

Tune Embers per run so the Shrine fills in about 25 to 40 runs, measured with bots at each stage
(`--mastery=N` and `--mastery=full`).

**Measured proposal from 2026-11-06, not built yet.** In a bot win, elites paid 336 to 362 of the
Embers (2 each for 168 to 181 elites), so two wins bought the whole 928-Ember Shrine. Proposed
income per run:

| Source | Embers |
|---|---|
| Each room | 1 |
| Each elite, at most 10 per run | 1 |
| Each first discovery | 2 |
| Fusions and cataclysms | at most 6 per run |
| Each boss | 3 |
| Each bounty | 5 |
| Each floor past the first | 3 |
| A win | 20 |

Once first discoveries run out, this pays about 2 to 7 for a death on the first floor, 17 to 27
for a death on the second, about 56 for reaching the fourth, and about 107 for a win. The Shrine
then fills in about 35 to 45 runs. Reaching a first win after 20 to 40 hours would also need
Shrine costs roughly doubled. Phase 3 builds and measures this.

Caveat: bots play far better than humans past the second floor, so they can't place the meta
curve on their own. Human runs are the reference for the fresh-save target.

---

## 14. Scale

A first full version, roughly:

| Content | Exists | New |
|---|---|---|
| Regions | 6 themes, as art | 5 to 6 themes; 11 regions plus 2 secret regions |
| Bosses | 5 | 7 new, 5 reworked |
| Enemy kinds | 11 | 2 or 3 per new region, plus elemental variants of existing ones |
| NPCs | 0 | 10 |
| Dialogue lines | 0 | 1,500 to 3,000 |
| Marks | 13 classes to convert | 4 to 6 new rule-changing Marks |
| Shortcuts | 0 | 1 or 2 per region, about 15 to 20 |

At the designer's budget of about 20% of the weekly limit per day, one phase takes one to three
days of agent work.

---

## 15. Build phases

Each phase ships a playable game, passes the checks in section 0, and updates `GDD.md`.
**Default order:** 0, 0b, 1, 1b, 2, 3, 4, then 5 and 6 in batches. The designer can move 0b after
1 (section 16).

### Phase 0: Groundwork

- **Goal:** runs become routes through a region graph, and regions have elemental profiles.
- **Scope:**
  - A region data model: id, depth, theme, resists, weak to, hazards, boss, edges.
  - A run picks one region per depth along the graph's edges, replacing `floor_number` as the
    driver of layout and theme.
  - Difficulty follows depth.
  - The 6 existing themes become 6 regions: Ossuary Gate, Rust Ruins, Frostvault, The Forge,
    Chapel of Ash and The Rift, with their profiles from section 4.
  - Soft resistances (60% and 140%) on enemy damage and state duration, the Exposed state from
    reactions, and resistance badges on enemies.
  - A route choice at each region exit, shown as two or three doors.
- **Start from:** `main.gd`, `floor_gen.gd`, `room.gd`, `room_data.gd`, `themes.gd`, `enemy.gd`,
  `elements.gd`.
- **Acceptance:**
  - Bots complete a 5-region route.
  - A build with a region's weakness clears it measurably faster than one with its resistance.
  - The Exposed state measurably helps the resisted build.
  - The idle six-gun bot still dies in the first region.
  - The fusion-probe bot still clears the first region.
  - Heavy fights hold about 98 to 100 fps.
- **Out of scope:** new themes, new bosses, NPCs.

### Phase 0b: Boss framework

- **Goal:** bosses become multi-part elemental creatures, with aim that can target their parts.
- **Scope:**
  - Body parts, each holding its own element state and compound, with their own fusion
    cooldowns.
  - A stagger bar filled by reactions by tier.
  - Three phases.
  - Arena tools.
  - Name cards and a music layer per phase.
  - The three aim modes (section 7), with soft lock on boss parts.
  - Rework all 5 existing bosses, the Pyre Lord first.
- **Start from:** `enemy.gd` (boss code, `_phase`, rallies), `room.gd` (boss sizing and rallies),
  `elements.gd` and `fusions.gd` (compound slots), `player.gd` and `player_input.gd` (aim),
  `music.gd`.
- **Acceptance:**
  - A fusion bot staggers and kills each reworked boss in 25 to 50 seconds.
  - The Pyre Lord's chain works on his body: steam, then a storm cloud, then an obsidian shatter.
  - Each boss reaches all three phases.
  - No fps loss in boss fights.
  - Screenshots show readable body parts and the hostile signature on every attack.

### Phase 1: The Hollow, part 1

- **Goal:** a walkable hub with people in it, and features that arrive with them.
- **Scope:**
  - A larger hub of several connected rooms.
  - A dialogue system with lines keyed to state.
  - The Keeper and the Gatewarden replace the Shrine and the Gate.
  - The Archivist is met in the Ossuary, recruited with a Torn Bestiary Page, and brings the
    Journal.
  - Voice sheets for these three, with designer-approved samples, before any lines are written.
  - A fresh save starts with only the Shrine, the Gate and a bare run history. Stations without an
    NPC yet keep working as they do today.
- **Start from:** `hub.gd`, `mastery_screen.gd`, `journal.gd`, `progress.gd`, `room.gd`
  (encounters), `figure_gen.gd` (NPC looks).
- **Acceptance:**
  - Every old station's function still works.
  - A fresh save starts with only the Shrine and the Gate.
  - Recruiting the Archivist opens the Journal.
  - The line batch passes the writing review (section 9).
  - Hub screenshots read well on a TV.

### Phase 1b: Bonds

- **Goal:** gifts deepen relationships and give unwanted loot a purpose.
- **Scope:**
  - Gifting from the hub.
  - NPC tastes.
  - Five bond levels per NPC.
  - Story lines in pieces.
  - Keepsakes for the Relic slot.
- **Acceptance:** every bond level is reachable; gift tastes are readable in the UI; the writing
  review passes.

### Phase 2: Loadouts

- **Goal:** classes become loadouts on one descender.
- **Scope:**
  - The 13 classes become Kits and Marks.
  - The Gate offers the Kit, Mark, Relic and Vow slots.
  - The Well and the Wellkeeper.
  - The Vagrant as the only body, with a Mark accent.
  - Save migration: a player's unlocked classes become unlocked Marks.
- **Start from:** `classes.gd`, `class_select.gd`, `player.gd`, `items.gd`, `progress.gd`.
- **Acceptance:**
  - All 13 old classes play as Marks with the same numbers.
  - Old saves migrate.
  - Bot loadout probes pass.

### Phase 3: Death teaches

- **Goal:** unlocks come from dying and from challenges, and the meta curve hits its targets.
- **Scope:**
  - Lessons, hints and counter unlocks.
  - Today's achievement unlocks move to lessons or loadout challenges.
  - Embers income retuned.
- **Start from:** `progress.gd`, `mastery.gd`, `telemetry.gd`.
- **Acceptance:** a bot meta-curve check at fresh, half and full Shrine hits the targets in
  section 13, and the Shrine fills in 25 to 40 runs.

### Phase 4: Shortcuts and world state

- **Goal:** the world remembers what you opened.
- **Scope:**
  - Far-side gates, repaired lifts, bridges and sluices, and secret edges.
  - Persistent world state.
  - The Cartographer and the world map.
- **Acceptance:**
  - A shortcut opened in one run persists.
  - Travel time in a known region drops measurably.
  - No shortcut skips a boss.

### Phase 5: New regions

- **Goal:** fill the Descent.
- **Scope:** two regions with their themes, enemies, hazards and bosses per batch. **Default
  order:** Drowned Cistern and Rotting Gardens first, completing depth 2; then Pitch Mire,
  Abattoir and Stormspire; then the secret regions.
- **Acceptance:** each region has its profile, hazards and boss, and bots clear it inside its
  time budget.

### Phase 6: Living world

- **Goal:** the four locked ideas from section 12.
- **Scope:** world state changes beyond shortcuts, NPC camps in the Descent, the Rival, and
  elemental weather. Then the parked ideas, as the designer chooses.

---

## 16. Decisions and open questions

### Locked by the designer on 2026-11-06

| # | Decision |
|---|---|
| 1 | 5 regions per run at about 7 to 9 minutes each |
| 2 | Keep the region roster and elements in section 4 |
| 3 | Resistances start at 60% resisted and 140% weak, tuned with data |
| 4 | No waystones: every run starts at the top |
| 5 | The Keeper and the Gatewarden from the start; the Archivist is the first NPC recruited with an item |
| 6 | Loadout slots: Kit, Mark, Relic and Vow |
| 7 | The living world starts with world state, people who move, the Rival and elemental weather |
| 8 | Early runs are meant to fail; the meta curve in section 13 |
| 9 | NPC writing must feel human and pass the review in section 9 |

### Still open, with the default an agent should build

| # | Question | Default |
|---|---|---|
| A | Bosses: multi-part bodies with stagger? | Yes, as in section 6 |
| B | Boss rework before or after the hub? | Before: phase 0b comes before phase 1 |
| C | Which aim mode is the default? | Assisted twin-stick, confirmed with bot data |
| D | Stagger replaces guard rallies, or adds to them? | Adds |
| E | Hard run timer? | No |
| F | NPCs can die permanently? | No, except the Rival |
| G | Voice? | Text only |
| H | Fixed item asks or category asks? | A mix: specific for quests, category for the first NPCs |
| I | Bond levels and gift limits | Five levels, one gift per NPC per hub visit |
| J | Lessons on elites too? | Bosses and region hazards only |
| K | Marks change your look? | A small accent only |
| L | Relic slots | One, growing with the Wellkeeper's bond |
| M | Vows replace difficulty settings? | Yes |
| N | Opened shortcuts can close? | Never |
| O | Embers dropped on death? | No |
| P | The story's central question | What lies at the bottom of the Descent, and why do people keep going down? |

---

## Sources

From `research_notes/World structure references/notes.md`, which has the tags and links:

- Dead Cells biome graph, rune gates and blueprints (Dead Cells wiki).
- Run lengths for Hades II (Kotaku), Halls of Torment (Godot showcase), Brotato (Brotato wiki),
  Returnal (Inverse) and Risk of Rain 2.
- Dark Souls interconnection analysis (TheGamer) and the Dark Souls 2 warping critique (community
  sources).
- Hades dialogue volume (Cultured Vultures, GDC 2021 talk) and Hades II volume (GamesRadar).
- Halls of Torment marks, the well and conditional unlocks (Godot showcase and guides).
- Risk of Rain 2 skill loadouts and challenges (Risk of Rain 2 wiki).
- Noita wetness and immunities (Noita wiki) and Outer Wilds' knowledge progression (essay and
  review).

Gaps the research could not fill, to verify before relying on them: Elden Ring legacy dungeon
commentary, Enter the Gungeon loadouts, the number of Hades' death-reactive lines, Divinity:
Original Sin 2 and Monster Hunter resistance design, and Inscryption's structure.
