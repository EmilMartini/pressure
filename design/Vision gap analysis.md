# Vision gap analysis

Date: 10 November 2026. Main at `d5a34b8`. Written for Emil, to decide what gets built next.

Emil's bar, in his words (9 November):

- "a game that feels amazing to play, and large enough to be really addictive"
- "a progression path that is unique but also very modern and familiar to players"
- "the art style to be ground breaking and not just 'holes in the ground to the next level'"
- "boss fights to be memorable and almost a 'wow factor'", like the Vanguard Demon in the Demon's Souls remake or Baal in Diablo 2
- "a set of oumph that other games dont"

This document compares every request Emil made against what the game does today, and against
that bar. It tries to be honest rather than encouraging.

**Sources:** Emil's 143 messages since 4 November; `design/World and progression GDD.md` (every
phase handoff, sections 13 and 16); `GDD.md`; `README.md`; the art pack, living world and voice
sheet notes; all 103 commits; the latest screenshots in `autotest/`; and Emil's own runs in the
telemetry file (records with `bot:false`, read only). No new bot runs were needed. Numbers
for other games are approximate, from general knowledge, and were not re-checked for this
document.

---

## 1. Executive summary

**Pressure is a strong systems game wrapped in a weak presentation.** Under the hood it's
deep and well built: 12 elements, 65 reactions, 220 fusions and 176 cataclysms (no other
roguelite chains its elements this far); 43 guns and 238 items; 8 regions on a world graph;
6 bosses with body parts, stagger and three phases; a hub; loadouts; "death teaches" lessons;
Dark Souls style shortcuts; and careful measurement for every change. The engineering is
good. Most systems Emil asked for exist and work.

**The vision, though, is about the moment on screen, and that is where Pressure is weakest.**
The five things Emil named are feel, size, progression, art, bosses and "oomph". Only one of
them (progression) is in decent shape, and even that is untested by a human. Against the
vision, the game scores about **4 out of 10** overall:

| Area | Score | One-line reason |
|---|---|---|
| Feel and juice | 4 | Hits have weight, but there's no dash, characters don't animate, auto-fire makes you passive, and late fights turn into a white-out |
| Size and addictiveness | 5 | Plenty of guns, items and reactions; only 11 enemy kinds, shared by every region, so the regions feel alike |
| Progression | 6 | A modern, familiar mix (Isaac pool, Hades talents, Dead Cells lessons, Halls of Torment wells) with two original hooks; half the NPCs and all the bonds are missing, and Emil has barely played it |
| Art | 3 | Coherent and moody at rest, but small borrowed tiles and code-drawn shapes. Only one region and one hub room have the art pass |
| Bosses | 3 | Good mechanics; but each boss is a code-drawn shape about 2.5 times the player's size, with no entrance or death moment, and fell in 5 to 16 seconds in Emil's runs |
| Oomph | 4 | The reaction chains are unique, but they show up as noise and floating words, not as moments |

Four facts matter most:

1. **Emil has hardly played what was built.** The telemetry holds about 105 minutes of real play:
   roughly 20 runs, one win, all on builds from 5 to 8 November. Four big passes since then
   (art, living world, difficulty and frame rate) were judged by bots only. Bots measure
   contrast, frame rate and health curves. They can't tell whether a boss is impressive.
2. **The art ceiling is the source art, not the code.** The game draws 32-pixel Dungeon Crawl
   tiles and shapes made in code. Engine work (light, grading, living plants, a river) has
   moved the rooms from flat to moody. It can't reach Isaac or Ori, and it can't make a
   Vanguard Demon. That needs bought or commissioned art, which is Emil's decision. There's a
   licence trap too: every paid pack reviewed forbids redistributing the files, and the repo is
   public.
3. **The bosses are the biggest gap against the vision.** The mechanics are in place. The scale,
   entrance, arena, music and death are not.
4. **Breadth has outrun depth.** Each request added a system (gear, sets, mods, tiers, weight,
   vent, Shrine, Marks, Kits, Relics, Vows, Wells, lessons, gates). Emil said on 5 November that
   "the progression loop is unclear to me". The first 30 minutes are now dense with systems but
   short on spectacle.

**Recommendation:** stop widening the game for a while. Make the first 30 minutes, the
Ossuary and one more region, and one boss look and feel finished (a vertical slice). Then get
Emil playing it. Section 6 lists the work. Eight items are slam dunks Claude can build now. The
three highest-impact items all need Emil: an art source, the voice sheets, and a playtest.

---

## 2. Request ledger

Every distinct request from Emil's messages, grouped by theme. Status:
**Delivered**, **Partly**, **Not delivered** or **Superseded**. A ⚠ marks a request that was
delivered on paper but misses what Emil meant.

### 2.1 Controls and aiming

| Request (date) | Status | Evidence |
|---|---|---|
| Controller first, mouse and keyboard usable (11-04) | Delivered | `player_input.gd`; controller menus `3093b3e` |
| Auto aim vs manual aim toggle, with a reward for manual (11-04) | Superseded | Manual removed on request (11-04, `7aa9350`), RT manual fire added back (`fb419e7`), then three aim modes (`7c306c2`). No reward for manual aim exists |
| Remove manual shooting (11-04) | Superseded | Done in `7aa9350`, then reversed by the next two rows |
| Target the nearest enemy, not elites (11-04) | Delivered | `cffba40` |
| Fire with RT as well as auto-fire; puzzles must not trigger auto-fire (11-05) | Delivered | `fb419e7` |
| Bring manual aim back now that the game is more active? (11-06) | Delivered | Assisted twin-stick is the default (section 16, AC and AD) |
| Key prompts only near items, matched to the device; Xbox glyphs (11-04) | Delivered | `0224932`, `94b6172` |
| Main menu takes controller input (11-04) | Delivered | `3093b3e` |
| Rumble that follows the sound (11-05) | Delivered | `c0775d1`; on the web it never worked, which is part of why the web build was dropped |

### 2.2 Run structure and rooms

| Request | Status | Evidence |
|---|---|---|
| Brotato waves with a shop between (11-04) | Delivered | `564b07e` |
| Isaac rooms with Brotato shops, challenge rooms, synergies (11-04) | Delivered | `fb7f1c8`, `203792c`. Emil's "now it's only a Brotato with no shop" (11-04) was fixed |
| Freeze water to reach hidden areas (11-04) | Partly | Ice glide and frozen floors exist (`8ab67bf`); no puzzle built around crossing water |
| Treasure rooms that look different and offer choices, like Slay the Spire (11-04) | Delivered | Chests and plinths, `94b6172` |
| Shop too cheap; max 4 purchases; heal always present (11-04, twice) | Delivered | `17de392`, `564b07e`, `5b9225f` |
| Items on pedestals; empty altar after buying (11-04) | Delivered | `94b6172`, pedestal code |
| Smaller rooms, closer camera (11-04) | Delivered, then questioned | `203792c`. A further zoom (1.6) was measured on 11-09 and not shipped: it needs Emil's call |
| Rooms not identical; hidden puzzles you stumble on; hidden rooms truly hidden (11-05) | Delivered | `f3c4052` |
| Uneven difficulty, "if you don't find a shop you're toast" (11-04) | Delivered | `203792c` arena rewards |
| Bug: moved two rooms at once; boss on top of you from the top door; post-boss pick freeze; double pickup (11-04, 11-05) | Delivered | `3093b3e`, `79194a7`, `f3c4052`, `ddf0119` |
| Enemies never spawn on you, like Brotato (11-07) | Delivered | `d301b70`, `[SPAWN-CHECK]` on every bot run |

### 2.3 Items, gear and the in-run build

| Request | Status | Evidence |
|---|---|---|
| Weight: light guns vs heavy (11-04) | Delivered | `GDD.md` "Weight" |
| Naked start, Isaac-style unlock pool (11-04) | Delivered | `f51e324` |
| Start with no guns, pick one of two (11-04) | Delivered | `23994a0` |
| Hundreds of items with incredible synergies (11-04, 11-05) | ⚠ Partly | 238 items in 10 sets, rarity tiers (`74f2b54`). The count is there. How many items change how you play, rather than add stats or triggers, has never been counted. Emil called the itemization "quite simple" (11-04) and "difficult to read" (11-05) |
| Itemization like Isaac (11-04) | Partly | Isaac-style pools and transformative items (`17de392`) |
| WoW gear: elite loot tables, scrap and upgrade (11-04) | Partly | In-run gear and salvage exist (`f06c4cb`). Gear does not persist between runs, so it isn't the "addictive meta" Emil described |
| Rarity matters; WoW rarity colours (11-04, 11-05) | Delivered | `GDD.md` "UI colour rule: rarity owns colour" |
| Gun upgrades like Brotato plus stacking mods (11-04) | Delivered | `cffba40` |
| Duplicates of a gun; auto-merge into an upgrade (11-05) | Delivered | `afe66e5` |
| Drops biased towards your build (11-05) | Delivered | `4dc01a3` |
| Discard guns; pick which gun gets a mod (11-04) | Delivered | `ee21fcd` |
| Dropped item takes the picked item's spot; spacing so descriptions don't overlap (11-04) | Delivered | `cffba40` era |
| Choose which jewellery slot to replace (11-05) | Probably delivered | Loot redesign `1a5a80a`; not re-checked |
| Fewer floor drops, less of a chore (11-05) | Delivered | `1a5a80a` |
| Level-ups less inflated, like Brotato; easier to read and more impactful (11-04, 11-05) | Partly | `ee21fcd`, `1a5a80a`. Not re-checked with Emil since |
| Unlocks sparser and more rewarding (11-05) | Partly | Lessons and Shrine retune (Phase 3). Bots unlock as designed; no human data since |

### 2.4 Meta progression and the hub

| Request | Status | Evidence |
|---|---|---|
| Journal of what is unlocked and how (11-04) | Delivered | `3093b3e`; now the Archivist's ledger |
| Character sheet like WoW's (11-04) | Delivered | `94b6172` paper-doll sheet |
| Some meta progression; talents as a node tree, not a list (11-04) | Superseded | Node graph (`ee21fcd`), then reworked like Hades, Dead Cells and RoR2 into the Shrine board (`c0775d1`) |
| Classes that favour an element, Dark Souls style (11-04) | Superseded | Classes became loadouts (Phase 2, `c5c9f85`) |
| Hub instead of a menu, like Enter the Gungeon (11-05) | Delivered | `4dc01a3` |
| Bigger hub like Firelink Shrine with NPCs who have personality (11-06) | ⚠ Partly | The Hollow exists with the Keeper, Gatewarden, Archivist, Cartographer and Wellkeeper. Only the Stair room is dressed (`9db8af9`). All 14 lines are placeholders, and the voice sheets have waited for Emil since 11-07 |
| Find NPCs in the world and give them an item to recruit them; journal unlocks late (11-06) | ⚠ Partly | The Archivist works this way. Four of the ten NPCs exist. The stations without an NPC are shown from the first run (decision AN), against Emil's "a journal is not unlocked until way later" |
| A tutorial on first start (11-06) | Delivered | `4dc01a3`, `tutorial.gd` |
| Death teaches: die to a boss, an NPC hints, a counter unlocks (11-06) | Delivered | Phase 3, `0e14e8b`: 11 lessons |
| Loadouts instead of classes, like Halls of Torment (11-06) | Delivered | Phase 2: Kits, Marks, Relics, Vows, the Well |
| Shortcuts done Dark Souls style, not "cleared 20 times" (11-06) | Partly | Far-side gates in every region, the Cistern sluice (Phases 4 and 5). Lifts and secret edges wait for unbuilt regions |
| Hades-like: nobody wins the first run; meta carries (11-06) | Delivered on paper | Section 13 meta curve. Measured with bots only |
| NPC lines written by Claude, but human, with no AI fluff (11-06) | Not delivered | Rules and voice sheets written; waiting for Emil's approval |
| A save wipe in Options (11-05) | Delivered | `e598994` |
| Options menu for everything (11-05) | Delivered | `4dc01a3` and later |

### 2.5 Elements and effects

| Request | Status | Evidence |
|---|---|---|
| Resistances, elites, an element gauge (11-04) | Delivered | Resistances (Phase 0b), elite shields |
| Many effects, Noita-like (11-04) | Delivered | 12 elements, 65 reactions (`2212370`) |
| Effects that chain beyond one pair; steam carries electricity (11-04) | Delivered | `7aa9350`, fusions `e505904` |
| Every element interacts "as in real life"; contained, not recursive; water a puddle, fire spreads to fuel (11-04) | Delivered | `cffba40`, `8ab67bf` material grid |
| Effects visual, not text (11-04) | ⚠ Partly | `ed21066` cut combat text. But reaction names still float over fights in large letters ("PESTILENT SHALLOWS" in the 11-08 Choir capture, "Wildfire" and "Hailstorm" over the Pyre Lord) |
| Steam + acid, acid rain + fire = chemical firestorm; "literal broken combinations" (11-05) | Delivered | 220 fusions and 176 cataclysms up to tier 4 (`e505904`) |
| Pixel simulation like Noita, "more wild", bloom (11-04, 11-05) | Delivered, then toned down | `5b468ae`; the clarity pass later dimmed own effects |
| Effects "grand", "oumphy" (11-05) | ⚠ Partly | Grand effects (`4dc01a3`) made the screen unreadable; the clarity pass quietened them. Oomph and clarity were traded against each other instead of both being solved |
| Effects less solid; see what is under an explosion (11-04) | Delivered | Generated pixel effects (`17de392`) |
| The pressure gauge feels like a chore (11-04, 11-05) | Superseded | Became "vent charge" (`GDD.md`). The game's name no longer describes a mechanic |

### 2.6 Difficulty

| Request | Status | Evidence |
|---|---|---|
| First level too easy; harder opening (11-04, 11-05) | Delivered | `857cf0f`, `d20a6aa` |
| Bosses that need reactions in order, or are immune, are bad design (11-04) | Delivered | Reaction shields replaced (`cffba40`) |
| Too easy once 3 or 4 guns are online; boss dead in seconds (11-05) | ⚠ Partly | `25de2ae`. Emil's winning run, on 11-05, killed all five bosses in 6 to 10 seconds each at full health |
| Many enemies, not bullet sponges (11-05) | Delivered | `d20a6aa` crowd-target spawning |
| Too easy once you have healing or a few weapons; "you only measure TTK" (11-09) | ⚠ Partly | Difficulty pass `2c1d0c9`: Mending fades, flankers, fans, lobs. It measures health curves now, not time to kill. But it's still measured on bots, and Emil hasn't played it yet |
| Harden floors 3 to 5 (11-04) | Delivered | `74a0e9c` |

### 2.7 Readability

| Request | Status | Evidence |
|---|---|---|
| UI too small and unintuitive; text unreadable; pixel font but bigger (11-04, three times) | Partly | `857cf0f`, `ee21fcd`, `c0775d1`. Screenshots still show small grey labels ("the Gate, past runs", "Cleared") |
| HUD split around the screen; carry capacity wraps (11-04) | Delivered | `cffba40` |
| See what hits you; deaths you don't notice (11-06) | Delivered | `e86ed1a`: low-health warning, hit direction, death recap |
| Your shots vs enemy shots; your hazards vs theirs (11-06) | Delivered | `3f2c0c3`, clarity pass |
| Too messy, "Brotato is super clear" (11-07) | Delivered | Clarity pass, six measured items (`d301b70` to `c0a3d98`), Frostvault fix |
| Enemy projectile sprite doesn't fit the look (11-06) | Not delivered | It still pops, which was the point. The style question was never revisited |
| Flyers too small (11-06) | Delivered | `3f2c0c3` |
| Player and obstacles hard to see (11-05) | Delivered | Outlines, `29701e4` |

### 2.8 Art and look

| Request | Status | Evidence |
|---|---|---|
| No generative-AI art; free packs; dark fantasy, not bright (11-04) | Delivered | Kenney 1-Bit (`3525386`), Dungeon Crawl tiles, ENDESGA 64 palette (`2ade373`) |
| Player isn't a knight; guns visible on the figure (11-04) | Delivered | `7aa9350` |
| The character morphs with items like Isaac and Brotato; blend classes; picked-up hat visible (11-05) | ⚠ Partly | Paper-doll figures (`f2760ba`) and worn gear (`1a5a80a`). On a figure about 26 pixels tall, the changes are hard to see in play |
| Better icons than generated ones (11-05) | Delivered | Dungeon Crawl icons, `da7b411` |
| One pixel grid; nicer dungeon, not N64; themed floors, less blur (11-05) | Delivered | `2ade373` |
| Environmental effects per room type (11-05) | Partly | Ambience per theme. Art-pass weather and extras are only in the Rust Ruins |
| Bloom and post-processing; CRT (11-04) | Delivered | `94b6172`, `7aa9350` |
| "Not interesting enough … holes pointing down … look like Isaac, Ori" (11-09) | ⚠ Partly | Art pass (`9db8af9`): light, grade, dressing. But only the Rust Ruins and the hub's Stair room have a recipe. The route "hole" is now a stairwell with pillars (`12e539d`): nicer, but still a hole in a room |
| Vines and props react to elements; a flowing river; animation in rooms (11-09) | Delivered | `5a4e4a8`, `12e539d` |
| Find a cohesive art pack, paid is fine (11-09) | Partly, parked | `design/Art pack research.md`. Emil chose to store the options for later |

### 2.9 Audio

| Request | Status | Evidence |
|---|---|---|
| Sounds from a pack; overlapping loud audio; water loop running on (11-04) | Delivered | `857cf0f`, `f06c4cb` |
| Synthwave music (11-04) | Delivered | OpenGameArt synthwave, `ee21fcd` |
| Music too stale (11-05) | ⚠ Partly | 13 tracks from 7 composers (`4dc01a3`). More variety, but no identity, and synthwave doesn't match the Dark Souls tone Emil later set |
| Sounds lacking for the visuals (11-05) | ⚠ Partly | CC0 overhaul (`c0775d1`). No audio has been added since, apart from per-phase filtering of existing boss tracks |
| No audio in the browser (11-05) | Superseded | Fixed, then the web build was dropped |

### 2.10 Platform, data and process

| Request | Status | Evidence |
|---|---|---|
| Share with friends; browser build; Azeroth Survivors style (11-04) | Superseded | Pages build `dbc344b`, dropped for the exe only (`ca3ab15`) |
| Co-op (11-04) | Superseded | Kept working, not a priority (11-05) |
| Player names (11-04) | Delivered | `dbc344b` |
| Damage numbers (11-04) | Delivered | `dbc344b`. They now fill late fights with clutter (see 2.5) |
| Data collection for balancing (11-05) | Delivered | Telemetry `405e96e`, pressure readout |
| "Don't build just to know, I need actual data" (11-05) | Delivered | Every phase handoff has measurements |
| Optimise; offload to the GPU (11-05) | Delivered | `896f408`, late-build fps; 60 fps cap (`c737029`) |
| Windows exe (11-05) | Delivered | `9bcbab2`; exe crash fixed `d5a34b8` |
| Bot windows never steal focus (11-09) | Delivered | `tools/bot_window.sh`; exe runs headless only |
| Run several muted instances (11-05) | Delivered | `--instance=N` |
| A game design document, large world, not a dungeon crawler (11-06) | ⚠ Partly | The GDD is written and phases 0 to 5 (part) are built. Structurally it's still rooms in a grid, one region after another. Phase 6 (living world: the Rival, weather, NPC camps) hasn't started |

### 2.11 Bosses

| Request | Status | Evidence |
|---|---|---|
| Bosses as cool creatures with phases and elemental chains, such as steaming a fire boss and shocking the steam (11-06) | ⚠ Partly | Phase 0b: body parts, stagger, three phases, quench vats, name card, phase music. The chain example works on the Pyre Lord. But see section 4: none is a "creature" yet |
| "Wow factor" bosses (11-09) | Not delivered | Section 4 |

**Tally:** about 75 distinct requests. About 47 delivered, 17 partly, 3 not delivered and 8
superseded. Eleven of them carry a ⚠. That says a lot: the requests that are about *how
something feels or looks* are the ones that keep landing as "technically done".

---

## 3. Vision scorecard

### 3.1 Feel and juice: 4 / 10

**Today.** Hit-stop and screen flash hooks (`afe66e5`), screen shake with a slider, rumble that
follows the sound, bloom, damage numbers, plant and prop hit reactions, 43 guns with 22
distinct firing types. Frame rate holds 60 with the cap, though the 1% low sits around 33 against
a 55 target, from hitches of 80 to 160 ms.

**What's missing:**

- **No dash or dodge roll.** "Dodge" is only a passive stat. Every reference action
  roguelite gives the player one active defensive verb: Hades' dash, Gungeon's roll, Dead
  Cells' roll. That verb carries most of the feel of moment-to-moment play.
- **Auto-fire as the default.** On 5 November Emil wrote: "I just stand in the middle of the room
  and my guy massacres everything." Assisted aim helps, but with no aim input the game still
  falls back to auto-fire in 1.2 seconds.
- **Characters don't animate.** The handoff says so directly: "Characters have no squash or
  stretch." The player is about 26 screen pixels tall. Enemies don't recoil, stagger or fly
  back.
- **Late fights white out.** The Pyre Lord and Void Herald captures are mostly white bloom,
  floating numbers and reaction names. Those captures came before the clarity pass. But the
  Choir capture from 8 November, after the pass, still shows a giant "PESTILENT SHALLOWS".
- **The 1% low misses the target.** A hitch of 80 to 160 ms in a fight is felt as a stutter.

**The reference games.** Nuclear Throne is the textbook: gun kick, screen shake with direction,
muzzle flash, enemies that fly back and leave corpses, a short freeze on a kill. Hades: a dash
with a trail, hits that flash white, and enemies that slide when hit. Gungeon: a roll with
invulnerability frames, and guns with personality in sound and recoil.

**Gap:** the layer that turns input into pleasure (an active defensive verb, recoil, knockback,
animation) is thin, and the spectacle layer is too loud.

**Why 4:** the hit feedback hooks and rumble exist, and the guns are varied. But there's no
dash, no character animation and no knockback, and big fights are hard to read.

### 3.2 Size, content and addictiveness: 5 / 10

| Content | Pressure | Isaac (Repentance) | Enter the Gungeon | Dead Cells (with DLC) | Hades | Brotato | RoR2 |
|---|---|---|---|---|---|---|---|
| Regions or biomes | 8 built of 11 planned (+2 secret) | about 15 floor variants | 6 chambers plus secret floors | about 20 | 4 plus the surface | 1 arena | about 10 stages |
| Enemy kinds | **11, shared by every region**, plus 5 affixes | 200+ | about 100+ | about 100 | about 40 to 50 | about 20 | about 30 |
| Bosses | 6 (5 reworked + Choir) | 50+ | about 25 | about 12 | 4 plus minibosses | a few elites and bosses | about 10 |
| Guns or weapons | 43 | n/a | about 240 guns | about 150 weapons and skills | 6 weapons × 4 aspects | about 70 | n/a |
| Items | 238 | 700+ | about 270 | many mutations | about 100+ boons | about 170 | about 150 |
| Characters or loadouts | 13 Kits, 13 Marks, Relics, 2 Vows | 34 | 6 to 8 | 1 plus outfits | 1 | 40+ | about 14 |
| Reaction depth | 65 reactions, 220 fusions, 176 cataclysms | none | none | none | duo boons only | none | none |

**Where Pressure is big:** guns, items and the reaction system. On elemental depth, Pressure
has more than any of these games.

**Where it is small:** enemies. Eleven kinds is a tenth of what Gungeon or Dead Cells has. All
11 appear in every region, so the Cistern, the Forge and the Rift differ in tiles,
resistances and hazards, but not in what you fight. Bosses: 6 against the 11 planned, plus the final
boss.

**Addictiveness.** The hooks exist: unlock pool, Shrine, lessons, gates, Relics. Emil's play
pattern (about 20 runs over four days, runs of 2 to 12 minutes, one 42-minute win) doesn't yet
show the "one more run" pull, though that's too little data to judge. The real test is how the
next 10 human runs feel.

**Why 5:** the item and gun breadth is fine, and the reaction space is unusually rich. But
enemy variety and region identity are thin, and one in three planned bosses is missing.

### 3.3 Progression: 6 / 10

**Today.** Four layers:

1. An Isaac-style unlock pool: 58 achievements and 76 rewards.
2. The Keeper's Shrine: 11 slots and 22 talents, Hades-mirror style, with Embers retuned so it
   fills in about 22 to 36 human runs.
3. Death-teaches lessons: 11, each unlocking a counter gun.
4. Loadouts: Kit, Mark, Relic and Vow.

On top of that: the Well, which saves an item and sells it back as a Relic; far-side gates and
the sluice; and the Archivist recruit.

**Familiar:** Hades (talents bought with a run currency, a hub of characters), Dead Cells
(blueprint-like lessons, biome graph), Isaac (unlock pool), Halls of Torment (wells, loadouts),
Risk of Rain 2 (challenge unlocks per Mark).

**Unique:** "death teaches" (a death to a boss unlocks the tool that counters it) and shortcuts
opened from the far side, which change the world. The research found no game doing the first
exactly. Both are good hooks.

**Gaps:**

- Only 4 of the 10 NPCs exist. Bonds (Phase 1b), which were to be the main sink for unwanted
  loot, aren't built.
- No endgame layer: Hades' Heat or Dead Cells' Boss Cells. Vows are the start of it.
- The Heart Below (the final boss built from your own run) isn't built, so there's no ending
  to aim for.
- The number of currencies and systems is high. Emil's 5 November "the progression loop is
  unclear to me" was answered with more structure, not with fewer things.
- Every target in section 13 was hit by bots, which the doc itself says "can't place the meta
  curve on their own".

**Why 6:** the design is the most complete part of the game and the most in line with
"unique but modern and familiar". It loses points because it hasn't been played, and because
the people and the ending that would make it compelling are missing.

### 3.4 Art: 3 / 10

**Today.** Dungeon Crawl Stone Soup 32-pixel tiles, Kenney 1-Bit, code-drawn figures, effects,
bosses and props; the ENDESGA 64 palette; one pixel grid; bloom and a light CRT. The art pass
adds lighting in post-processing, dressing, foreground roots and pillars, sun shafts, plants that
sway and react, Verlet vines and chains, a flowing river and lasting floor marks.

**What the screenshots show:**

- **At rest, the Rust Ruins look moody and coherent.** Torches, moss, a landmark ring of
  candles: a big step from the flat grey grid of 7 November.
- The hub's Stair room reads as a place: hearth, ledger table, weapon rack, the Gate.
- **But the floors are still a grid of dark grey bricks.** The player is a tiny white figure in
  a green outline. And the river, while it flows, is a stepped band across the room.
- **Only `ruins` and `hollow` have an art recipe** (`ArtPass.RECIPES`). The Ossuary, where
  every run starts, the Frostvault, the Forge, the Chapel, the Rift, the Gardens and the Cistern
  get the living layer but no light or grade recipe.
- **In a fight, the art pass fades itself out on purpose**, to keep the clarity numbers. So in
  the moments that matter most, the look goes back to the clarity-pass look.

**The reference games.** Isaac: hand-drawn sprites with heavy outlines and squash, rooms
with a strong silhouette, gore that stays. Ori: painted layers, parallax, light as the main
material. Dead Cells: 3D models rendered to pixels, with rich animation. Noita: every pixel
simulated. Pressure has some of Noita's idea (the material grid) but shows it at small scale and
dims it in fights.

**"Ground breaking" is honestly out of reach with this source art.** The one visual idea no
other game has, a living chemistry layer where every reaction leaves marks, is the closest
thing to it. Right now it's tuned down for clarity, not tuned up into a look.

**Why 3:** coherent, dark and moody at rest, which is a real improvement, but borrowed, small
and generic, and mostly limited to one region.

### 3.5 Bosses: 3 / 10

See section 4. **Why 3:** the mechanics (parts, stagger, three phases, chains, arena tools for
two of the six) are well thought out and work. But none of the presence, scale or spectacle
that a Vanguard Demon or Baal moment depends on exists yet.

### 3.6 Oomph: 4 / 10

**The unique thing is real.** No shipped roguelite lets a player soak a fire boss's armour,
light the steam and tear the plates off with a storm cloud, across 400 compound reactions.
That is the "set of oumph that other games don't" have, in principle.

**But it doesn't land as a moment.** A cataclysm currently looks like more particles, a
number and a word. Nothing tells the player "you just did something rare": no freeze, no
camera punch, no unique sound, no title, no lasting mark that's clearly yours. The clarity
pass rightly made routine effects quieter, but it never made the rare ones louder.

Compare Balatro's chips × mult crescendo, Vampire Survivors' evolutions, Hades' Duo boons
with their own voice line, or Noita's chain explosions you can read and laugh at.

**Why 4:** the raw material is world-class. The delivery is noise.

---

## 4. Bosses deep dive

### 4.1 What makes a Vanguard Demon or Baal moment

| Ingredient | What it means | Vanguard Demon (Demon's Souls) | Baal (Diablo 2) |
|---|---|---|---|
| **Scale** | The boss dwarfs you; the screen can barely hold it | Fills the screen; you reach its knee | Throne-room scale; the minion waves set it up |
| **Reveal and entrance** | You see it before you fight it; the camera tells you this is different | Fog gate, then it lands from above in a cutscene | Seen sitting on the throne through five waves of minions before you reach him |
| **Arena** | The room is built for this fight and looks like nowhere else | A huge open courtyard after the tight tutorial corridors | The Throne of Destruction, then the Worldstone Chamber |
| **Music and sound** | A theme that belongs to this boss; a voice, a roar | Orchestral sting; footsteps that shake the screen | Baal's laugh and voice lines; the Worldstone hum |
| **Phase change** | The boss becomes something else, not just faster | (In the tutorial you are *meant* to die, which is a twist) | The minion waves end, Baal flees into the Worldstone Chamber, a new fight with clones |
| **Foreshadowing** | You hear of it, or see its work, before you meet it | You die to it, which teaches you the world | Act 5's story, his name all through the act |
| **Signature mechanic** | One thing only this boss does | Sheer size and a ground slam | The clone, a tentacle field, the mana drain |
| **Aftermath** | The world changes; you get a moment to breathe | Death and the Nexus, a whole new place | The Worldstone is destroyed; Tyrael's words; the credits |

Pressure's own section 6 already lists most of these (a name card, a body three to six times a
grunt, its own music, NPCs who talk about it, a phase that "changes the arena or the rules").
The mechanics were built. The presentation half wasn't.

### 4.2 Each boss against those ingredients

Boss radius is 30 to 34 pixels against the player's 14 and a grunt's 12, so a boss is about
**2.3 to 2.8 times a grunt** (section 6 asked for three to six). At the run camera's zoom, a boss
is about 12% of the screen's height. The Vanguard Demon fills more than half.

| Boss | Scale | Entrance | Arena | Sound | Phases | Foreshadowing | Signature | Aftermath | Human fight length |
|---|---|---|---|---|---|---|---|---|---|
| **Brute King** (Ossuary) | 2.5× grunt, code-drawn body with plates and crown | Name card | Plain boss room | Shared roar; a pool track with a filter per phase | 3: smash, swallows barrels, enrage | A lesson after you die to it | Barrels as fuel; plates crack | Spoils, gate | 4.6 to 16 s (8 fights) |
| **Hive Mother** (Gardens) | Green blob of circles (capture) | Name card | Plain; spore pods are a region hazard | As above | 3: swarms, burrows, splits | Lesson | Firedamp tears the sacs | Spoils | 10 to 36 s (3 fights) |
| **Drowned Choir** (Cistern) | Singers around a bell, code-drawn | Name card | **Best of the six:** the arena floods, there are dry ledges, the sluice afterwards | As above | 3: pull, flood, bell shockwaves | Lesson | Galvanic Sea on the floodwater; you stand in it too | **The sluice drains the Cistern for later runs** | no human data |
| **Storm Warden** | Rods around a core | Name card | Plain | As above | 3 | Lesson | Ground the rods; Storm Cloud overload | Spoils | 6.4 s (1 fight, old code) |
| **Pyre Lord** (Forge, "the showcase") | Orange disc with a crown icon (capture) | Name card | **Quench vats** | As above | 3: flame waves, armour cracks, lava flood | Lesson | The full steam, storm, obsidian chain | Spoils | 6.0 s (1 fight, old code) |
| **Void Herald** (Rift) | Shards around a hollow centre | Name card | Gravity wells | As above | 3: wells, steals your element, shards close | Lesson | Element theft | Spoils (final win) | 8.9 s (1 fight, old code) |
| **The Heart Below** | Not built | | | | | | | | |

**What the table says:**

- **The mechanics column is strong.** Element theft, a flooding arena you have to climb out of,
  armour you have to steam before you can shock it: these are genuinely good boss ideas.
- **Every presentation column is weak or missing.** There's no entrance beyond a name card,
  scale is a third of the planned size, none of the bosses has its own music or its own
  sound, there's no death sequence, and only the Choir changes the world afterwards.
- **The bosses are code-drawn shapes.** In the captures, the Pyre Lord is an orange disc with a
  crown symbol, and the Hive Mother is a cluster of green circles. At this size, no amount of
  code drawing will make them read as "creatures". That needs art.
- **The fights end too soon to have phases a person notices.** Emil's real fights lasted 4.6 to
  36 seconds, most under 10. Five of them were on code from before the boss rework. The bot fights
  on current code last 20 to 44 seconds. Even so, at that length the three phases go by in the
  middle of a lot of noise.

**What could land the wow without new art**, since much of it is camera, timing and sound:

- an entrance: the camera pans to the boss, the lights in the room go out and come back on it,
  a roar with a big shake and rumble, the name card in large type;
- a scale bump to the planned three to six times;
- a phase change the arena shows: the lights change colour, the floor cracks, the music changes
  track, not just filter;
- a death: slow motion, a white flash, the body breaking into its element over the arena floor,
  a music sting, and silence before the spoils;
- an NPC line about the boss, before and after (that needs the voice sheets).

The rest (a body that reads as a monster, animation, a theme per boss) needs an artist and a
composer.

---

## 5. What's holding it back

1. **The art source sets a ceiling.** The game's look comes from free 32-pixel tiles and
   shapes drawn in code. A week of engine work moved it from flat to moody, but Emil's bar
   (Isaac, Ori, "ground breaking") and the boss bar need art made for this game. The art pack
   research found no single pack that covers everything. The best fit for tone (ELV Games' Rogue
   Adventure) still leaves bosses and effects to an artist. And every paid licence forbids
   committing the files to a public repo. **This is the single biggest blocker, and only Emil can
   unblock it.**

2. **The feedback loop with the person who matters has gone quiet.** About 105 minutes of
   Emil's play is recorded, all before 8 November 20:01. Since then, four passes were judged by
   bots measuring contrast, fps and health curves. Those metrics stop mistakes (they caught real
   ones, such as dark fights cutting enemy contrast by 9%), but none of them can measure "wow",
   "feels amazing" or "boring". The clarity metric can't see a 40-pixel reaction name. Some
   recent human runs may also have been lost: the exe crashed at quit after a run until this
   morning's fix.

3. **Systems first, presentation later, and later never came.** Nearly every request got a
   system: 103 commits in six days. Almost none got a polish pass to "finished" quality. The
   result is a game that does a great many things at prototype quality. The vision words
   ("amazing", "ground breaking", "wow", "oomph") are all about finish.

4. **The core-feel layer is missing.** There's no active defensive move, characters don't
   animate, enemies don't react to hits, and auto-fire is the fallback. These are the
   cheapest and highest-leverage parts of "feels amazing to play", and nobody has asked for them
   by name, because players feel them rather than notice them.

5. **Oomph and clarity were set against each other.** Grand effects made a mess, so the effects
   were dimmed. Neither pass made the rare, big moments louder while keeping the routine ones
   quiet. Good games do both: Hades' basic hits are subtle, and a Duo boon is a fanfare.

6. **No audio direction.** The music is 13 synthwave tracks from 7 OpenGameArt composers.
   Emil asked for synthwave on 4 November, then for a Dark Souls tone on 6 November. The two
   were never reconciled. No boss has its own theme. No audio has been added since 5 November,
   while the visuals have moved a long way.

7. **The regions are reskins in combat terms.** With 11 shared enemy kinds, a new region is
   tiles, resistances and hazards. "A large dynamic world" needs regions that are different
   places to *fight* in.

---

## 6. Ranked plan

Ordered by impact on the vision against effort. **SLAM DUNK:** no decision needed; Claude can
build it now with what exists; clearly in line with what Emil asked for; low risk. **NEEDS
EMIL:** a decision, a purchase, a playtest or an approval. **NEEDS ARTIST:** beyond code-drawn
art.

| Rank | Item | Tag | Impact | Effort |
|---|---|---|---|---|
| 1 | Choose an art source and solve the licence (private repo or assets kept out of git) | NEEDS EMIL | Very high | Decision, money |
| 2 | Playtest the current exe: three runs, notes on feel, bosses and look | NEEDS EMIL | Very high | 2 hours |
| 3 | Boss entrances and deaths | SLAM DUNK | High | 1 session |
| 4 | Cataclysm moments: the rare chain becomes an event | SLAM DUNK | High | 1 session |
| 5 | Combat text diet | SLAM DUNK | High (clarity and oomph) | Small |
| 6 | Hit feel: knockback, squash and stretch, recoil, enemy hit reactions | SLAM DUNK | High | 1 session |
| 7 | Add a dash or roll | NEEDS EMIL | High | 1 session after the decision |
| 8 | Art-pass recipes for every region, starting with the Ossuary | SLAM DUNK | Medium-high | 1 to 2 sessions |
| 9 | Boss sprites with animation, a player sprite | NEEDS ARTIST | Very high | Weeks, money |
| 10 | Regional enemy rosters from Dungeon Crawl monster tiles | SLAM DUNK | Medium-high | 1 to 2 sessions |
| 11 | Approve the voice sheets, then the first line batch | NEEDS EMIL | Medium-high | 30 minutes for Emil |
| 12 | Arena tools for the remaining bosses | SLAM DUNK | Medium | 1 session |
| 13 | Music direction: a composer or a bought pack, a theme per boss | NEEDS EMIL | High | Money, time |
| 14 | A "this moment" button in telemetry | SLAM DUNK | Medium (process) | Small |
| 15 | Vertical slice before breadth: pause new regions until 1 to 8 are at "finished" quality | NEEDS EMIL | High | A choice |
| 16 | Camera zoom 1.6 (measured on 11-09, changes the game) | NEEDS EMIL | Medium | Small after the decision |
| 17 | Hitches: 1% low from about 33 to 55 | SLAM DUNK | Medium | 1 session |
| 18 | Phase 1b bonds, the remaining NPCs, the Heart Below | NEEDS EMIL (writing) | Medium | Several sessions |

### 6.1 Slam dunk briefs

**3. Boss entrances and deaths.**
Files: `scripts/boss_body.gd`, `scripts/main.gd` (camera, `shake`), `scripts/art_pass.gd` (room
lights), `scripts/hud.gd` (name card), `scripts/music.gd`.
Entrance: the player stops for about 1.5 s (invulnerable); the camera pans to the boss; room
lights dim and a light comes up on the boss; roar, heavy shake and rumble; a big name card;
then the camera returns. Skippable after the first sight of that boss (save flag).
Phase change: a short freeze, a light colour shift, a full track change rather than a filter.
Death: about 0.6 s of slow motion, a flash, the body bursts into its element on the floor grid,
a sting, two seconds of quiet, then the spoils.
Done: all six bosses use it; the boss checks and fusion probe still pass; fight lengths
unchanged within noise; a capture of each entrance in `autotest/`.

**4. Cataclysm moments.**
Files: `scripts/elements.gd`, `scripts/fusion_fx.gd`, `scripts/fx.gd`, `scripts/main.gd`.
A tier 3 or 4 cataclysm gets 60 to 90 ms of hit-stop, a short camera zoom punch, a layered
sound (two existing sounds pitched down together), a strong rumble, and a one-colour shockwave
ring. The first time a player finds each cataclysm, its name shows once, large, at the screen
edge, never over the fight. Keep the existing limit of one per 1.5 s.
Done: the paired clarity test (`--clarity-ab`) shows enemy and shot contrast unchanged outside
the 0.3 s of the moment; a before and after capture.

**5. Combat text diet.**
Files: `scripts/fx.gd` (damage numbers), `scripts/elements.gd` (`reaction_fired` labels),
`scripts/settings.gd`, `scripts/options_menu.gd`.
Reaction and fusion names no longer float over the fight. They show only on first discovery,
small, at the edge. Damage numbers merge per target every 0.25 s; small own hits are hidden;
crits and boss hits stay. Options: "Damage numbers: all / big hits / off", defaulting to big hits.
Done: the Pyre Lord and Choir captures with no word bigger than the HUD text; clarity numbers
equal or better.

**6. Hit feel.**
Files: `scripts/enemy.gd`, `scripts/player.gd`, `scripts/figure_gen.gd`, `scripts/gun.gd`.
Enemies get a short white flash and a small knockback scaled by weight (bosses and brutes
barely move), plus a squash on hit and a stretch on death. The player gets squash and stretch
on start, stop and hurt, a texel of gun recoil on the figure, a muzzle flash, and footstep dust.
Every effect sits on the existing shake and flash settings.
Done: bots' clear times and deaths match the old code within noise (knockback changes
spacing, so measure that); one short capture strip.

**8. Art-pass recipes for every region.**
Files: `scripts/art_pass.gd` (`RECIPES`, `light_room`), `scripts/room.gd`, `scripts/hub.gd`.
Follow "Rolling it out to every region" in the design doc: a recipe per theme (crypt first,
because every run starts there; then frozen, forge, void, garden, cistern, sanctum); light nodes
for lava, rifts and drains; one extra per region (cold glints, ember cracks, rift pools, spore
glows, drain spill); dress the remaining hub rooms the way the Stair was dressed.
Done: each region passes the paired clarity test in both orders and the capped fps check; one
rest capture per region.

**10. Regional enemy rosters.**
Files: `scripts/spawn_table.gd`, `scripts/enemy.gd`, `scripts/regions.gd`, art in
`assets/dungeon` (the Dungeon Crawl set already holds hundreds of monster tiles).
Each region gets its own look for the 11 behaviours: drowned dead in the Cistern, ash-faced
monks in the Chapel, and so on. Each also gets one innate element that matches the region
(Cistern grunts are wet; Forge runners leave embers). Behaviours and numbers stay the same, so
balance stays the same. Section 14 already plans "elemental variants of existing ones".
Done: every built region has its own sprite set; bot clears within noise; a gallery capture.

**12. Arena tools for the remaining bosses.**
Files: `scripts/boss_body.gd`, `scripts/room.gd`, `scripts/pedestal.gd`.
Phase 0b left these: braziers to topple for the Brute King and the Hive Mother (fire on spores),
pylons for the Storm Warden, bells or holy lamps for the Void Herald. Each tool feeds the boss's
own chain, as the quench vats do for the Pyre Lord.
Done: each tool used by a bot recipe at least once (`[BOSS-CHECK]` lines); fights stay in 25 to
50 s.

**14. A "this moment" button.**
Files: `scripts/telemetry.gd`, `scripts/player_input.gd`, `scripts/main.gd`.
The View or Back button (F9 on keyboard) writes a `moment` event with the room, the build, what
is on screen, and a screenshot to `user://moments/`. It's for Emil to mark "this felt great" or
"this was mush" with one press. Also make sure telemetry is flushed at the end of each room,
not only at the end of the run, so a crash can't eat a run.
Done: a moment event appears in a test run's jsonl; `tools/pressure_report.py` lists the moments.

**17. Hitches.**
Files: per "Late-build fps" in the design doc (the materials grid step, enemy spawn and summon,
projectile bursts).
Find and spread the 80 to 160 ms hitches that keep the 1% low near 33.
Done: 1% low of at least 55 in the section 0 perf command, gameplay identical by the grid hash.

### 6.2 What Emil needs to decide

1. **Art source** (rank 1). One of three paths: buy ELV Games' Rogue Adventure as the base
   (closest tone, bigger bosses) and commission the rest; commission a single artist for the
   player, the six bosses and the effects; or stay on free art and accept a ceiling around 5
   out of 10 for art. Any paid art also needs either a private repository or the art kept out of
   git and pulled in by the build.
2. **Play the current exe** (rank 2). Three runs. Press the moment button (rank 14) when
   something feels great or bad. This one step tests four passes nobody has seen yet.
3. **A dash or roll** (rank 7). It makes the game more skilful and modern, and changes the
   balance. My recommendation is yes, with short invulnerability, as Hades does.
4. **The voice sheets** (rank 11). They have waited since 7 November. Every NPC, lesson and
   boss build-up line waits on them.
5. **Music** (rank 13). Pick a direction (dark synth, dark ambient, or orchestral-gothic) and a
   source (a composer, or a bought non-AI pack). One theme per boss is the target.
6. **Depth before breadth** (rank 15). My recommendation: no new regions until the eight that
   exist, and their six bosses, look and feel finished.

---

## Appendix: how the numbers were found

- **Emil's runs:** `runs.jsonl`, 40 records with `bot:false` (about 20 real runs; the rest are
  menu starts). Last record: 8 November 20:01, build `2026.11.08-p5c`. One win (11-05, 42
  minutes). Deaths: 5 to grunts in arenas, 1 to a barrel, 1 to a charged floor, 1 to a spitter.
  Boss fights: 4.6 to 36.2 seconds, most under 10, usually ending at full health.
- **Content counts:** `GDD.md` "Current counts"; `scripts/spawn_table.gd` (`KINDS`, `BOSSES`);
  `scripts/art_pass.gd` (`RECIPES`); `assets/music/CREDITS.txt`.
- **Sizes:** `scripts/enemy.gd` (boss radius 30 to 34, grunt 12) and `scripts/player.gd`
  (radius 14).
- **Captures looked at:** `alive_rust_ruins_react_after_rest`, `alive_rust_ruins_route_after`,
  `alive_drowned_cistern_river_afterstream_rest`, `hub_gatewarden_aliveafter`,
  `boss_pyre_lord_18` and `boss_void_herald_18` (both 7 November, before the clarity pass),
  `boss_drowned_choir_06` (8 November), and `clarity_rust_ruins_boss_after_2` (Hive Mother).
- **Other games:** approximate, from general knowledge, not re-checked here.
