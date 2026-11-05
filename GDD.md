# PRESSURE — Game Design Document (living)

Working title. A controller-first, co-op, wave-based shooter where guns apply elements,
enemies die to *reactions* between elements, and nothing ever gets easy because threat
scales with your power instead of behind it.

Touchstones: Brotato (waves + shop), Vampire Survivors (hordes), Isaac (run map, unlocks,
synergies), Magicka / Genshin (elemental reactions), World of Warcraft (gear, dungeons,
raids, loot tables).

---

## 1. Design pillars

1. **Reactions, not raw damage.** Every gun applies an element. Combining two elements on an
   enemy fires a reaction, and reactions do the real damage. Raw damage is the chip.
2. **Power has a cost you manage every second.** Weight, pressure, and elite sequences mean
   more power always brings more decisions, never fewer.
3. **Difficulty follows you up.** Resistance drift, dungeon tiers keyed to gear score, and
   elite sequences grow with the player. There is no point where you stop paying attention.
4. **Built for the couch, then the internet.** Co-op from the first line of code.
   Browser-playable so friends can join without installing anything.

## 2. Core combat

### Controls
- Controller first, mouse and keyboard fully supported.
- Left stick / WASD moves. Right stick / mouse aims. Right trigger / left mouse fires the primary.
- **Aim mode toggle** (Y / Tab): auto-aim or manual.
- **Vent** (LB / Space) dumps the pressure gauge as a nova.
- **Swap primary** (X / Q) cycles which carried gun is on the trigger.

### Firing model
- Every gun you carry aims and fires on its own at the nearest enemy in range, Brotato
  style. Guns orbit the figure and point where they shoot, so your loadout is visible.
  With nothing to shoot, a gun in range of an obstacle fires its element at that instead,
  which is how hidden rooms open.
- Manual aim, the trigger and focus were cut: play showed they added input without adding
  decisions. The decisions are what you carry, what you wear, where you stand, and when you vent.

### Levels
- Kills give XP. Each level, once the room is clear, pick one of three upgrades from a
  Brotato-like catalog: damage, attack speed, crit chance and damage, bounces, pierce,
  projectiles, health, armour, dodge, regen, speed, range, potency, element duration, chain
  jumps, lifesteal, thorns, scrap, pressure limit and decay, vent size, carry, XP gain.
- Brotato-shaped curve: the cost of a level rises quadratically (20, 35, 56, 83, 116...)
  and each upgrade is small (+4% damage, +8 health, +3% crit), so a floor gives three to
  five levels and no single pick swings a run. Power comes from stacking many of them.
  XP per kill is 2 + 2 x scrap value, which lands around level 14 on floor 4.
- Measured loop (bot, naked start, explores every room, spends in shops): floor 2 at
  5 min, floor 3 at 10, floor 4 at 18 with level 19, ten guns and 141 max health, never
  in danger past floor 1; a human who skips rooms is faster and leaner. The arena feeds
  20 + 11 x difficulty enemy hp per second; every spawned group buys itself a pause of
  its hp over that rate. Floors 2 to 5 were retuned from a won human run (see "Late-floor
  balance" below).

### Gun tiers and mods
- Guns have tiers I to IV, Brotato style. Picking up a duplicate merges it into the one
  you carry one tier higher (no extra weight); the shop's Gunsmith raises your lowest-tier
  gun for scrap. Each tier adds 35% damage, 12% fire rate, a bigger projectile, and from
  tier III a point of pierce.
- A gun holds as many mods as its tier, and mod effects stack: four Coatings on one gun
  mean every hit applies five elements. That is meant to get absurd late in a run.
- Picking up a mod with more than one gun that has a free slot opens a small picker:
  one card per gun with its tier and the mods it already carries. With one candidate the
  mod goes straight on; with none, the pedestal says so and the mod stays.

### Weight
- No gun slots. A **carry budget** (starts at 10, bought up in the shop).
- Pistol 1, SMG 2, shotgun 3, flamethrower 5, lightning cannon 6, and so on.
- Total weight slows you (about 2.5% move speed per point). Many light guns = many small
  reactions everywhere. Few heavy guns = rare huge reactions. Both viable, both feel different.

### Elements and reactions
Twelve elements: **Wet, Shock, Fire, Ice, Oil, Poison, Acid, Blood, Void, Holy, Gale, Stone**.
Sixty-six pairs, sixty-five reactions (water and oil do not mix), all defined as
data in `scripts/elements.gd` using a small action vocabulary: damage, burst, apply an
element in a radius, burn, poison, bleed, corrode, freeze, stun, slow, pull, push, chain,
chain along a state, lingering cloud, purge, spread, decay, heal the source. Adding a
reaction is one line; adding an element is a colour, a pressure weight and its lines.

Status effects on enemies: burn, stacking poison (a poisoned corpse passes it on),
bleed (hurts while moving), corrosion (+50% damage taken), freeze (x3 damage, shatters),
stun, slow, shoves from pulls and pushes, and lingering clouds that keep applying an element.

**Patches, contained.** A few reactions leave something on the floor or in the air: Steam
leaves a puddle, Toxic Mist and Noxious Flame a poison cloud, Magma a lava pool, Blizzard an
ice cloud, Consecrate hallowed ground. A patch keeps applying its element to whoever is in
it, and anything of another element that enters it (a projectile, a vent, another patch)
plays that pair's reaction once over everyone inside, then the patch is used up. Lightning
through a steam puddle shocks everyone standing in it, fire into a poison cloud burns the
crowd, and then it is gone. A patch never spawns another patch, so there is no recursion.
Water is a puddle that drenches, not weather. Fire spreads only where there is fuel: a
burning enemy ignites oiled neighbours. An earlier version let clouds transform and chain
into each other; it produced spectacular nonsense, so it was pulled back to one step.

A few of the sixty-five: Wet + Void is a Whirlpool that drags everything in. Shock + Holy is
Smite, one enormous strike. Fire + Stone leaves a pool of Magma. Poison + Gale is a Plague
Wind. Void + Holy is Annihilation. Wet + Holy is Baptism: strips every state and punishes
each one. Fire the pair once and the journal's Reactions tab reveals what it does.

Rules: an enemy carries states for a few seconds. When a new element lands on an enemy that
already has a different state, the pair reacts, consumes the existing state, and the new one
is not applied. Same element refreshes the timer.

**Physical rules on top of the pairs** (what an element does to a body's condition):
- Water conducts: shock does +50% raw damage to a wet enemy. Water puts fire out: wet
  bodies take half fire damage, burn for half as long, and a wet hit extinguishes a burn.
- Oil feeds fire: +25% fire damage and burns last half again as long on an oiled body;
  a burning body ignites oiled neighbours; shock sparks oil (Ignition).
- Fire thaws: a fire hit ends a freeze. Cold cracks: stone and shock hit frozen bodies
  harder (Cryoshock stuns and cracks). Stone grounds shock, so that pair barely reacts.
- Wind fans: a gale hit on a burning body spreads the burn to neighbours; a gale carries
  poison, acid, blood and oil onto everyone nearby (Plague Wind, Acid Rain, Spray, Oil
  Spray) and pushes.
- Holy scours: +25% against poisoned or void-marked bodies; purges states (Baptism,
  Cleanse, Neutralize). Poison dissolves in water and spreads (Contamination).
- Stone weighs: a stone-marked body moves at three quarters speed. Acid corrodes: +50%
  damage taken while corroded. Void pulls, gale pushes, blood bleeds while they move.

#### Compounds and fusions — BUILT (data `scripts/fusions.gd`, live in `elements.gd`, `enemy.gd`, `cloud.gd`)
A reaction used to be a dead end. The gimmick is broken combinations, so reactions now climb a
**tier ladder** with a hard ceiling, and each rung is worth more than the last:

| Tier | What | Made by | Leaves | Potency x |
|---|---|---|---|---|
| 1 | element state | a hit | the state (Element.DURATION) | 1.0 |
| 2 | **reaction** (65) | state + element | a **compound** on the target and/or as a patch | 1.0 |
| 3 | **fusion** (220) | compound + an element that is not one of its ingredients | nothing, or (19 signatures) a **fusion field** | 1.8 to 2.5 |
| 4 | **cataclysm** (176) | fusion field + a fourth element | nothing, ever | 3.0 to 4.0 |

`MAX_TIER = 4`. Anything can only make something one tier higher, and everything that
happens inside a tier N effect (reactions set off by its applies and spreads, the payload a
field keeps applying) runs at **context tier N** and may only create products above N. A
fusion's apply that sets off Inferno on a neighbour still burns, but leaves no compound.
Nothing exists above 4, so every chain stops by construction. That replaces the old
"patches react once" rule as the guarantee; patches still react once.

**Compounds.** Each of the 65 reactions leaves one of 22 compounds. The canonical pair is the
compound's ingredients; the other reactions that make it are its members, and their extra
ingredients are its **kin** (Petrichor and Erosion make Mud, so poison and acid are Mud's kin).
A compound on an enemy lasts 1.5 to 3 s, a compound patch (cloud or floor) 3 to 5 s. One
compound slot per enemy; a newer compound replaces the older. Compounds never react with
each other. Colours are 30% the mix of the two element colours, 70% a hand-picked look.

| Compound | From (canonical first) | Lives | Life (enemy / patch) | Flavour |
|---|---|---|---|---|
| **Steam** | Wet + Fire: Steam, Thermal Shock | cloud | - / 4s | A scalding fog that hangs where the water boiled. |
| **Mud** | Wet + Stone: Mud, Petrichor, Erosion | floor | - / 5s | Churned earth that sucks at every step. |
| **Plasma** | Shock + Fire: Plasma, Ignition, Electrolysis | enemy | 1.5s / - | A body crackling white-hot, one spark from going off. |
| **Stormfront** | Shock + Gale: Thunderstorm, Chain Lightning, Monsoon | enemy + cloud | 2s / 3.5s | Charged air that hums before it strikes. |
| **Brine** | Wet + Acid: Caustic Splash, Contamination, Dissolve, Acid Rain | floor | - / 4.5s | A hissing, corrosive slurry. |
| **Magma** | Fire + Stone: Magma | floor | - / 5s | Molten rock, crusting at the edges. |
| **Glass** | Shock + Stone: Grounded, Brittle, Cryoshock | enemy | 2.5s / - | Sand fused by lightning into a brittle shell. |
| **Tar** | Oil + Stone: Asphalt, Tar Pit, Slick, Black Ice | floor | - / 5s | Black, sticky, and very flammable. |
| **Napalm** | Fire + Oil: Inferno, Chemical Fire, Anointing, Oil Spray | enemy + floor | 2.5s / 4s | Fuel that clings and keeps burning. |
| **Cinder** | Fire + Gale: Firestorm, Sandstorm | cloud | - / 3.5s | Glowing grit carried on a hot wind. |
| **Smog** | Fire + Poison: Noxious Flame, Virulence | cloud | - / 4.5s | Acrid, choking smoke that pools low. |
| **Miasma** | Poison + Gale: Plague Wind, Sepsis, Galvanic Rot | cloud | - / 4.5s | A sick green air that clings to the living. |
| **Rime** | Wet + Ice: Deep Freeze, Glacier, Frostbite, Hemostasis | enemy | 3s / - | A hard glaze of ice over everything. |
| **Blizzard** | Ice + Gale: Blizzard, Absolute Zero | cloud | - / 4s | Whirling snow that bites and blinds. |
| **Nova** | Fire + Holy: Holy Fire, Smite, Neutralize | enemy | 2s / - | Radiance gathering under the skin. |
| **Hallow** | Holy + Stone: Consecrate, Sanctuary, Divine Wind | floor | - / 5s | Sanctified ground that remembers. |
| **Chrism** | Wet + Holy: Baptism, Cleanse | floor | - / 4s | Holy water, still glowing. |
| **Hemo** | Wet + Blood: Thin Blood, Spray, Martyrdom | enemy + floor | 2.5s / 4s | Thin, spreading blood that will not clot. |
| **Clot** | Acid + Blood: Coagulant, Cauterize, Bludgeon, Defibrillate | enemy | 2s / - | Seared, hardened blood clotting in the wound. |
| **Rift** | Shock + Void: Singularity, Whirlpool, Black Hole, Gravity Well, Vacuum | cloud | - / 3s | A pinhole in space that will not stay shut. |
| **Voidstuff** | Poison + Void: Decay, Null Acid, Exsanguinate | enemy | 2s / - | Matter that has started to forget itself. |
| **Eclipse** | Void + Holy: Annihilation, Dark Flame | enemy + cloud | 1.5s / 3s | Light and its absence, held in a shaking balance. |

**Fusions.** A compound meets a third element: the compound is consumed and the fusion
plays, on the target, or once over everyone inside a patch (area actions once, at 0.7
potency, like a cloud reaction today). An element that was an ingredient of the reaction that
made this particular compound does not fuse (it refreshes), so the third element is always new.
Forty fusions are hand-designed signatures; the other 180 come from four rules:

- **Compose** (109): the compound's `core` plus the third element's `ROLE` (wet soaks and
  slows, shock chains and stuns, fire burns and bursts, ice freezes, oil slicks, poison
  spreads, acid corrodes, blood bleeds and feeds you, void pulls and decays, holy purges and
  heals, gale throws, stone stuns). Same actions merge (bursts take the larger radius and sum
  their damage). x2.2 for enemy-only compounds (same target inside 1.5 to 3 s), x1.9 for patch
  compounds. Named "<element adjective> <compound noun>": Venomous Mire, Howling Pall.
- **Amplify** (26): the element is kin to the compound, so it is the compose result with damage
  over time, slows and corrosion lasting x1.5 and freeze/stun x1.25 (capped).
- **Neutralize** (45): the element cancels one of the ingredients (wet cancels fire, fire
  cancels ice and wet, oil and stone cancel wet, stone and oil ground shock, holy and void
  cancel each other, holy cancels poison, acid and blood, stone cancels gale and acid, acid
  cancels stone). The compound collapses into one hard burst (110 radius, 2.0) at x1.8.
  Named "<cancel word> <noun>": Quenched Slag, Grounded Squall.
- **Signature** (40): hand-designed, x1.9 to x2.5 by how hard the setup is; they override the
  rules above (Obsidian is fire cancelled by ice, but it is a signature, not a fizzle).

**Fusion fields.** Nineteen signature fusions linger (rain, storms, floods, fields): they
leave a field (3 to 5 s, radius 160 to 220) that keeps applying a payload element every
0.5 s (at context tier 3, so the reactions it sets off leave nothing) and can react **once**
more, with a fourth element, into a cataclysm. Instant fusions (bursts, shatters, implosions)
leave nothing. Fusions never spawn clouds; fields are the only thing that lingers.

**Cataclysms.** A field meets a fourth element: the field is consumed and the cataclysm
plays once over everything inside, then nothing is left. Twenty-five are signatures; the
rest follow two rules, and only a genuinely new element (not one of the field's three)
triggers a generated one, so each field answers to 9 or 10 elements:
- **Surge** (128): an echo burst of the field (field radius x1.25, x2.0) plus the element's
  cataclysm role (`CATA_ROLE`: a tidal wave, a chain storm, a firestorm, a flash freeze...),
  x3.2. Named "<cataclysm adjective> <field noun>": Thundering Deluge, Abyssal Shallows.
- **Fizzle** (23): the element cancels the field's payload: one small burst (120, 1.5) at
  x3.0, so it still pays out a little but wastes the field.
The element that made the fusion and the field's payload do not react with their own field.

**Balance and anti-recursion rules** (constants in `fusions.gd`):
- Tier multipliers: reactions x1.0, fusions x1.8 to x2.5, cataclysms x3.0 to x4.0, on
  potency. Freeze, stun and the decay share are never multiplied.
- `FUSION_COOLDOWN` 0.8 s per enemy after a fusion: no new fusion and no new compound on it.
- Freeze and stun from any tier go through the existing diminishing returns in enemy.gd
  (7 s window, half, quarter, immune; elites and bosses resist) and are capped at 3 s before it.
- Radius caps: 260 for fusions, 320 for cataclysms; decay at most 20% of max health.
- A fusion or cataclysm applies **at most one element kind**, and at most 10 (fusion) or 16
  (cataclysm) element applications in all, so it can never put two reacting elements on the
  same body. Reactions those applications cause leave nothing (context tier).
- Room budgets: 4 compound patches, 3 fusion fields (a new one replaces the oldest), 6
  fusions a second (past that the element lands as a plain element and the compound stays),
  one cataclysm per 1.5 s, and a field cataclysms once and only after it has existed 0.4 s.
- Repetition: the same fusion or cataclysm fired again inside 8 s in a room is worth x0.8 per
  repeat, never under x0.3, and the same fusion cannot fire twice within 1 s in a room
  (`REPEAT_GAP`: the element lands as itself and the compound stays, so a different element
  can still fuse it). Spamming one combination decays; rotating them does not. (Designed as
  x0.85 / x0.55 with no gap; the bots showed Wildfire firing 1.3 times a second in a
  wet + shock build and taking 19 to 32% of its fusion damage, so it was tightened.)
- Shields: a reaction cracks 1 pip (attuned pair 2, as now), a fusion 2, a cataclysm 3.

Why this stays rewarding and finite: fusions are the fastest way to clear a floor (twice the
potency of a reaction, usually over an area, and they crack shields twice), and a cataclysm
is a room-clearer, but each rung asks for a new element at the right place within a few
seconds, so a build has to carry and aim four elements to reach the top. The ceiling,
the context tier, the one-kind apply rule and the per-enemy cooldown make loops impossible
rather than merely unlikely; the repeat decay and the room budgets keep one combination from
carrying a run, and the crowd target (more enemies for more guns and elements) means the
extra clear speed is spent on a bigger horde, not on standing still.

Signature fusions (tier 3). "Field" is life, radius and the payload the field keeps applying.
Firedamp uses Shock, not Fire: fire is an ingredient of Smog, and a spark is what sets off
firedamp. Steam + Acid is named **Acid Deluge** because Acid + Gale is already the reaction Acid Rain;
renaming that reaction would free the name.

| Fusion | Compound + element | x | Field | What it does |
|---|---|---|---|---|
| **Acid Deluge** | Steam + Acid | 2.0 | 4.5s, r220, Acid | The steam condenses into a corroding rain over a wide area |
| **Storm Cloud** | Steam + Shock | 2.2 | 5s, r180, Shock | The steam takes a charge and hangs there, arcing into everything inside |
| **Hailstorm** | Steam + Ice | 2.0 | 4s, r180, Ice | The steam freezes in the air and comes down as hail |
| **Kiln** | Mud + Fire | 2.0 | - | The mud bakes hard around everyone standing in it |
| **Permafrost** | Mud + Ice | 1.9 | 5s, r170, Ice | The mire freezes solid underfoot |
| **Quicksand** | Mud + Void | 2.0 | 4s, r200, Void | The mud opens and swallows: everything is dragged to the middle |
| **Collapse** | Plasma + Void | 2.5 | - | The plasma folds in on itself: everything is pulled in, then it implodes |
| **Ball Lightning** | Plasma + Gale | 2.2 | 4s, r160, Shock | A drifting ball of plasma that arcs to everything it shocks |
| **Starfall** | Plasma + Holy | 2.3 | - | The plasma ignites into a falling star |
| **Hurricane** | Stormfront + Wet | 2.2 | 4.5s, r220, Wet | Rain drives into the storm: everything is soaked, shocked and thrown |
| **Wildfire** | Stormfront + Fire | 2.0 | 4s, r200, Fire | Lightning on a dry wind: fire runs across the whole crowd |
| **Galvanic Sea** | Brine + Shock | 2.3 | 4s, r180, Shock | The whole slurry conducts: lightning through every body in it, eating them as it goes |
| **Brinicle** | Brine + Ice | 2.0 | - | A spear of salt ice forms through the target |
| **Obsidian** | Magma + Ice | 2.4 | - | The lava glasses over and shatters into stone shards |
| **Pyroclast** | Magma + Gale | 2.3 | - | Wind lifts the lava into a scorching blast |
| **Eruption** | Magma + Oil | 2.3 | 4s, r180, Fire | Fuel in the lava: it erupts, and keeps erupting |
| **Glass Storm** | Glass + Gale | 2.4 | 4s, r200, Gale | The shell shatters into a whirl of shards that cut everyone nearby |
| **Burning Lens** | Glass + Fire | 2.3 | - | The glass focuses the fire into one searing beam |
| **Pitch Fire** | Tar + Fire | 2.2 | 5s, r180, Fire | The tar goes up in a black, clinging blaze |
| **Firewhirl** | Napalm + Gale | 2.2 | 4s, r180, Fire | The burning fuel spins up into a tornado of fire |
| **Flashover** | Napalm + Wet | 2.4 | - | Water on burning fuel: it explodes outward |
| **Firefall** | Cinder + Oil | 2.1 | - | Oil caught in the cinders comes down as burning rain |
| **Firedamp** | Smog + Shock | 2.4 | - | A spark in the smog: the whole cloud detonates, and a bigger cloud is a bigger blast |
| **Censer** | Smog + Holy | 2.0 | 4s, r160, Holy | The smoke turns to incense: it scours states and mends you |
| **Black Death** | Miasma + Blood | 2.1 | 5s, r200, Poison | The sickness takes to the blood and leaps body to body |
| **Plague Pyre** | Miasma + Fire | 2.0 | - | The tainted air catches: a burning, poisoned flash |
| **Shatter Arc** | Rime + Shock | 2.4 | - | Lightning cracks the glaze and jumps to every frozen body |
| **Ice Shrapnel** | Rime + Gale | 2.3 | - | The glaze is blown apart into freezing shrapnel |
| **Thaw Flood** | Blizzard + Fire | 2.0 | 4s, r220, Wet | The blizzard melts at once: a wave of water that soaks and shoves |
| **Avalanche** | Blizzard + Stone | 2.2 | - | Snow and rock come down together |
| **Black Sun** | Nova + Void | 2.4 | 4s, r180, Void | The radiance inverts into a dark star that devours what it lights |
| **Judgement** | Nova + Shock | 2.2 | - | A bolt from above, then every holy-marked body nearby is struck too |
| **Blood Altar** | Hallow + Blood | 1.9 | 5s, r160, Holy | Blood on hallowed ground: an altar that wounds them and feeds you |
| **Communion** | Chrism + Blood | 1.9 | - | Holy water and blood: every state is scoured and you are mended |
| **Haemolysis** | Hemo + Acid | 2.1 | - | The blood boils away from the inside |
| **Heartstop** | Clot + Void | 2.4 | - | The clot is pulled into the heart: the target stops dead |
| **Accretion** | Rift + Fire | 2.2 | 4s, r200, Fire | Fire falls into the rift and spins into a burning disk |
| **Unmaking** | Voidstuff + Holy | 2.2 | - | Light meets matter that has forgotten itself: it is erased |
| **Fossilize** | Voidstuff + Stone | 2.2 | - | The fading body sets into stone |
| **Corona** | Eclipse + Fire | 2.2 | - | A ring of fire flares around the eclipse |

Signature cataclysms (tier 4):

| Cataclysm | Field + element | x | What it does |
|---|---|---|---|
| **Chemical Firestorm** | Acid Deluge + Fire | 3.6 | The acid rain catches: a corroding firestorm over the whole field |
| **Supercell** | Storm Cloud + Wet | 3.5 | The cloud drinks the water and becomes a supercell: everything soaked, everything struck |
| **Eye of the Storm** | Storm Cloud + Void | 3.6 | The storm folds around a hole: dragged into the eye and struck there |
| **Meteor Hail** | Hailstorm + Stone | 3.4 | The hail turns to stone and falls like meteors |
| **Polar Vortex** | Hailstorm + Gale | 3.2 | The hail spins into a freezing vortex that drags everything in |
| **Methane Bloom** | Permafrost + Fire | 3.5 | Thawed ground releases its gas, and the fire finds it |
| **Sinkhole** | Quicksand + Stone | 3.4 | The ground gives way: everything falls in and is buried |
| **Pulsar** | Ball Lightning + Void | 3.6 | The ball collapses into a spinning star that whips lightning around the room |
| **Hypercane** | Hurricane + Fire | 3.5 | Heat feeds the hurricane until it tears itself apart |
| **Perfect Storm** | Hurricane + Shock | 3.8 | Every soaked body in the storm is struck at once |
| **Conflagration** | Wildfire + Oil | 3.6 | Fuel on a running fire: the whole field goes up |
| **Maelstrom** | Galvanic Sea + Void | 3.8 | The charged sea drains into a hole, dragging and dissolving everything |
| **Phreatic Blast** | Eruption + Wet | 3.6 | Water meets the eruption: a steam explosion that levels the field |
| **Obsidian Rain** | Eruption + Ice | 3.4 | The eruption glasses in the air and rains black blades |
| **Molten Glass** | Glass Storm + Fire | 3.4 | The shards melt mid-flight and stick, burning |
| **Black Tornado** | Pitch Fire + Gale | 3.5 | The burning tar is torn up into a black tornado |
| **Hellmouth** | Firewhirl + Void | 3.8 | The fire tornado bores down into the void, and the void opens |
| **Sacrament** | Censer + Blood | 3.0 | Blood in the incense: a rite that scours them and restores you |
| **Great Fire** | Black Death + Fire | 3.4 | The plague is burned out, and the city with it |
| **Extinction** | Black Death + Void | 3.4 | The plague forgets its hosts, and they forget themselves |
| **Live Water** | Thaw Flood + Shock | 3.6 | The flood is electrified: every body standing in it is struck |
| **Flash Freeze** | Thaw Flood + Ice | 3.2 | The flood freezes in an instant, with everything in it |
| **Syzygy** | Black Sun + Holy | 4.0 | Light and dark sun align: one blinding, room-wide detonation |
| **Blood Moon** | Blood Altar + Void | 3.4 | The altar darkens: it drinks from everyone in reach and gives it to you |
| **Quasar** | Accretion + Holy | 4.0 | The disk ignites into a quasar: everything is pulled into the beam |

**How it plays.** A reaction leaves its compound where the table says: on the enemy it hit
(a thin rim and three motes orbiting it in the compound's colour, faster as it is about to
fade) and/or as a patch on the floor or in the air (a dashed ring in the compound's colour).
The next element that lands on that enemy, or flies or vents into that patch, is checked
against the compound **before** any pair reaction: if it fuses, the compound is consumed and
the fusion plays instead (on the enemy at potency x mult, or once over everyone in the patch
at x0.7), cracks shields 2 pips, and puts the enemy on its 0.8 s cooldown. An element that
made the compound refreshes it instead. Signature fusions leave a field: a breathing double
ring in the payload's colour with its remaining life on the rim, ticking the payload every
0.5 s. Once it is 0.4 s old, a fourth element entering it sets off the cataclysm (3 pips)
and the field is gone. A reaction played over an ordinary cloud leaves its compound patch
there and primes the enemies inside. Clouds spawned by reactions never fuse with compound
patches or fields by themselves (only projectiles, vents and landing shells do), so nothing
climbs without the player.

The show scales by tier (`scripts/fusion_fx.gd`, built only from existing Fx emitters,
PostFx pulses and Sfx keys): the entry's element signatures (the arriving element leads,
the others echo smaller; a cataclysm rings them round the field), its outline, glow and
thrown droplets, its layered sounds (rumble follows the Sfx bus), the name floating over it
on the reaction-label path (28 px for a fusion, 44 px capitals for a cataclysm, "NEW" the
first time ever), a shake, and for cataclysms always, for fusions at most once per 0.45 s:
a ripple, an aberration pulse, a hit-stop (0.07 s / 0.16 s) and a flash (0.2 / 0.42), all
through the existing hit-stop and screen-shake settings. Discoveries show in the Journal's
Fusions (by compound) and Cataclysms (by field) tabs, ??? until fired, recipe after.

**Measured** (bots, `--fusion-probe` vs the same four w1 guns with `--no-fusions`, four
copies of one w1 gun, and idle six-gun, 300 s headless each; runs where the bot got stuck
on a pedestal excluded):

| Build | Runs | Floor 1 cleared | Died on floor 1 | Boss kill | Kills/s (floor 1) | Damage tier 2 / 3 / 4 |
|---|---|---|---|---|---|---|
| 4 elements, fusions | 17 | 16 (212 s) | 1 | 26.8 s | 2.83 | 37% / 29% / 11% |
| same guns, no fusions (the old game) | 10 | 5 (222 s) | 5 | 34.0 s | 2.56 | 63% / 0 / 0 |
| 1 element x4, fusions | 7 | 1 | 6 | 34.9 s | 1.75 | 25% / 5% / 0% |
| idle six-gun, fusions | 6 | 0 | 6 (67 to 125 s) | - | 3.77 | 23% / 40% / 11% |
| idle six-gun, no fusions | 3 | 0 | 3 (38 to 40 s) | - | 2.68 | 52% / 0 / 0 |

Arena time is mostly the wave timer, so clear times barely move; what fusions buy is
survival, boss speed and kill rate. About 785 fusions and cataclysms fire per four-element
run (3 a second at peak, the 6-a-second budget is hit), 149 different names across the
probe runs. Share of fusion damage: Wildfire 11.5%, Conflagration 8.2%, Supercell 6.5%,
Flashover 3.6%, Firefall 3.3%, the rest under 3.1%. Within one loadout the top name is 13
to 21% (Wildfire in wet/fire/shock/gale, where Chain Lightning makes Stormfront all the
time). The termination check held in every run: context never above 4, at most 3 fusions
in one frame, nesting at most 7 deep, no product made at or below its own tier. Frame rate
with vsync in heavy fights is unchanged (99 fps mean, 93 to 98 minimum per run with
fusions, 95 to 97 without; about 70 more draw calls).

Integration notes: `Fusions.compound_for(reaction)`, `fusion(compound, element, origin)`,
`cataclysm(field, element)`, `prepared_actions(entry, patch_radius)` (resolves the "-1 =
this patch's radius x1.25" convention used by Firedamp, Censer, Plague Pyre and Haemolysis,
and applies the caps), `can_produce(tier, context)`, `repeat_mult(n)`, `shield_cracks(tier)`,
`all_fusion_names()` and `all_cataclysm_names()` for the Journal, `validate()` for a test.
Fields reuse Cloud (element = payload) tagged with the fusion name; in patch and field
contexts `heal_source` runs once, like other area actions.

### Pressure gauge (now: vent charge)
- One gauge per player, from **cold (-100)** through **neutral (0)** to **hot (+100)**.
  Fire and Shock guns push hot, Wet and Ice push cold, it drifts back toward neutral.
- **Vent** turns the gauge into a weapon: a fire nova when hot, a frost nova when cold,
  scaled by how far from neutral you are, and a vent sweeping through a cloud or puddle
  reacts with it.
- The overheat and freeze-up stalls were cut. Watching the bot play showed the gauge was
  being managed rather than used: a penalty you avoid is a chore, a charge you spend is a
  decision. Pressure is now purely the fuel for the one active ability.

### What keeps it hard
- **Resistance drift.** From wave 3, a growing share of enemies spawn immune to raw damage
  from one element you carry (shown as a ring in that colour). Reactions still work on them.
  Your mono-fire god build meets a wave that only shatters.
- **Reaction shields.** Elites and bosses carry a shield with crack pips. Any reaction cracks
  it; the one it is attuned to (shown as the element pair above its head) cracks it twice;
  raw damage leaks through at a fifth. Bosses re-attune at half health. Two earlier designs
  died here: "reactions in order" could not survive auto-fire, and "only the attuned
  reaction" turned bosses into lotteries once a run carried many elements. The shield is now
  a test of whether you are reacting at all, with a bonus for the right one.
- **Dungeon tiers** (see section 4). Difficulty keys to your gear score, like Mythic+ keystones.

### Late-floor balance (measured, 2026-11-05)
The ground truth is a human Stormcaller run (telemetry `4487a37a46b6c384`): six guns of six
elements, coatings, Leech Mail, Vampiric Loop, a Leech pick; won all five floors, never
downed, every floor ended at 100% health, every boss died in 6 to 10 s at full health.
Analysis scripts: per-floor table from telemetry, and a replay that re-runs the run's own
hits under another sustain and damage model.
- **Cause 1, Leech had no ceiling.** Lifesteal healed its amount on every reaction, and a
  six-element build causes thousands: 1,100 reactions on floor 1, 8,600 on floor 2, 10,100,
  15,100 and 34,800 on floors 3 to 5. At 2 to 3 per reaction that is 17,000 to 70,000 HP of
  healing a floor against 760 to 3,670 damage taken; inferred healing matched damage taken
  on every floor, so any hit was undone within a second. Damage taken per arena grew from 23
  (floor 1) to 524 (floor 5) and the player never noticed. Now only `Player.LEECH_PER_SEC`
  (3) reactions a second heal: Leech is 3 HP/s per point, strong but outpaceable. Regen
  (2 to 2.6 HP/s in that run) and the heal reactions (60 to 190 HP a floor) were never the
  problem and are unchanged.
- **Cause 2, bosses did not scale with the build.** Boss health was 1,800 + 420 x
  difficulty (x1.25 at most), about 7k to 13k, while the party's measured arena output
  rose from 200/s on floor 1 to 800, 1,500, 2,400 and 3,800/s (bots, same build), and the
  boss as a single target takes several times the arena rate (fusions, DoTs, shatter and
  corrode all land on one body). From floor 2 a boss has at least `Room.BOSS_DPS_SECS`
  (30) seconds of the floor's measured arena output (the mean of the last three arenas,
  every tier and DoT included; `Enemy.dealt_total`), never under the old formula and at most
  9 times it. The time goes to the horde, not only to health: at two thirds and one third
  the boss **rallies**, a gold guard (5% of damage gets through) for up to 8 s that breaks
  early once the three spawn groups it calls are dead, and the boss room keeps 40% of the
  arena crowd alive. Floor 1 bosses are unchanged.
- **Cause 3, late damage was flat where it mattered.** Bomber and volatile blasts were a
  flat 18 on every floor and the top damage source of floors 2 to 4; boss and splitter
  summons always hit at x1.0. Blasts and summons now take the floor multiplier, which is
  x1.3 on floor 2 and x1.55 on floors 3 to 5 (was 1.0, 1.15, 1.3, 1.5; floor 1 stays x1.0).
  The multipliers come from the replay: with Leech capped, the run's own hits put its low
  point near 51% (floor 2), 62% (3), 42% (4) and 28% (5).
- Measured with bots replaying that build (`--build=storm --start-floor=N`, gear kept,
  `--old-balance` for before; low point from 5 s health samples). Before (3 runs a floor):
  low point 93 to 97% (floor 2), 92 to 100% (3), 89 to 96% (4), 88 to 91% (5); bosses 1 to
  9 s, always at full health. After (5 to 8 runs a floor): 85 to 92%, 70 to 83%, 45 to 86%,
  73 to 84% with one death in eight on floor 5's last arena; bosses 18 to 41 s (floor 2),
  25 to 74 s (3), 17 to 66 s (4), 15 to 32 s (5 at the 9x cap), phase two every time. Arena
  length is the wave timer and kills per arena moved under 5%. The bot kites more carefully
  than the human (it loses a third to half of the human's health per arena on floors 2 and
  3), so its dips are shallower; the replay above is the estimate for a human. A mediocre
  build (`--build=mid`: tier-one guns, random picks, no healing gear) died on floor 3 in one
  run of three after (it survived its one run before) and early on floors 4 and 5 in every
  run, before and after. Floor 1 is unchanged
  (its code paths are untouched): idle six guns die there, four-element fusion bots clear it
  with a median low point of 76% (67% before, 9 runs each, same spread).
- Telemetry's clock overcounted around hit-stops (delta divided by a time_scale that changed
  mid-frame): room, boss and elite seconds read about 1.4x long for bots and up to
  2x on the human's late floors (127 s "arenas" on floor 5 were 60 s waves). It now counts
  wall-clock time.

## 3. Run structure: Brotato waves inside an Isaac map

The run is a **dungeon**: a node map of rooms, Isaac style. Most rooms are **arenas** that play
as a Brotato wave (timed, enemies pour in, survive). Clear it and the doors open. Between rooms
you pick the next node. Room types:

- **Arena** (wave room, the bread and butter)
- **Shop** (guns by weight, carry budget, upgrades; scrap is the currency)
- **Challenge room** (opt-in: a sequence elite gauntlet, a mono-element room, no-vent room, for a
  guaranteed gear drop)
- **Hidden room** (reached only by an environmental reaction: freeze a pool to cross it, burn a
  thicket, shock a door's water-logged lock. Reactions are a traversal tool, not just damage.)
- **Boss room** (end of each floor)

A dungeon is 5 floors. Floors get larger and add more room types and enemy kinds. A
distinct two-phase boss ends each floor (brute king, hive mother, storm warden, pyre
lord, void herald).

**Raids** are the endgame: a longer co-op dungeon with multiple bosses that have WoW-style
mechanics (split the party, soak zones, interrupt casts with a specific reaction, adds that
must die in element order). Designed for 2-4 players. Only reachable at a gear score threshold.

## 4. Meta progression — BUILT (Shrine rework R4 to R8 done, R9 to R12 pending)

Principle: **every run starts naked, and nothing you own makes a run easier.** Meta
progression widens what can happen in a run and what you are allowed to attempt, never
your starting power. That keeps the "overpowered and bored" failure out by construction.

**Status (2026-11-05; see `reports/Roguelite meta progression analysis.md`).** The audit
found the meta layer generous where the reference games are stingy and stingy where they
are generous: a 212-node, 326-point Mastery tree sold +21% damage, +12% fire rate, +32
max HP and 6 armour (a bot probe with it bought reached floor 2 in all three runs at
120-147 HP, while two of three naked runs died on floor 1; 6 armour alone cut the
measured ~6.5 HP average hit to ~1.5-2.7), while 39 of 43 guns started locked and holy
arrived at a median run of about 45. Hades keeps its combat talents to a cheap core of
swappable A/B pairs, Dead Cells caps permanent power at four flask charges, Risk of Rain 2
sells no stats and teaches with challenges. The defects (R1, R2, R3, R10) were fixed
first; the structural rework R4 to R8 is now built: the Shrine below replaces the tree
(R4 slots, R5 survival, R6 element sidegrades, R7 Embers for play quality) and the first
achievements hand out a new element per run (R8). R9 (opt-in difficulty ladder), R11
(pool curation) and R12 (co-op meta rules) are next. Every number is provisional until
real-player telemetry exists.

**Target pacing to tune against** (provisional until real-player telemetry exists): one
visible unlock per run for the first five runs, then one every one to two runs to run 20;
every element available by run 5; first win around runs 8 to 15; meta stat power at most
+10% damage and +20 max HP at completion, the rest of progression being options. The
Shrine at completion: at most +9.7% damage-equivalent and +15 HP-equivalent per floor from
talents, plus up to three revives per run (25 HP each) from the survival track; one side
of every slot plus the survival track is about 470 Embers (around run 20 at 20-25 Embers a
run), everything 928.

**Current counts:** 58 achievements with 64 unlock rewards (39 guns, 12 classes, 5
obstacle kinds, 2 rarity tiers, 2 shop upgrades, 1 room type, 3 secret upgrades); 43 guns;
238 items (55 common, 65 uncommon, 63 rare, 39 epic, 16 legendary); 13 classes; 65
reactions; 11 Shrine slots (22 talents, 57 ranks) and a 3-rank survival track.

### Itemization model (Brotato tiers, Isaac pools) — BUILT
- Rarity is the quality axis and gates power: commons are one small stat, uncommons two,
  rares introduce mechanics (bounce, pierce, chain), epics add projectiles or big
  conditionals with a cost, legendaries are run-defining. Rarity odds use gates and caps
  by difficulty and scale with luck; prices are base + difficulty + 8% of base per step.
- Pools by room type, Isaac style, with per-item pick weights and no repeats within a
  run. Treasure rooms are the build-defining source, shops are utility, boss drops are
  stat-ups, hidden rooms are weird and strong.
- An active item slot with room-clear charges, Isaac's spacebar item.
- Level-ups use the same tiers keyed on level and luck; mechanical level-ups are rare.

### In-run gear (the WoW loot loop, inside one run) — BUILT, first batch
- Gear drops during the run and is lost at the end, like Isaac items. Elites drop an item
  55% of the time, bosses always drop rare or better, shops sell two, treasure rooms offer
  two guns and two items (take one), hidden rooms hold a rare, challenge rooms pay three
  to choose from. Replacing an equipped item puts the old one back on the floor.
- Slots: head, chest, hands, feet, two rings, two trinkets, and one mod per gun.
  Rarities common to legendary with WoW colours; epic and legendary are unlocked.
- **Items are data.** `scripts/items.gd` has a small vocabulary: flat stat mods, conditional
  mods (while hot, while cold, below 40% HP, in manual aim), and triggers (on hit, kill,
  reaction, a specific reaction, vent, room clear, hurt, overheat, freeze-up) that do things
  (apply an element, nova, heal, scrap, shoot, chain, slow, shield). Seventy items exist today:
  forty-five hand-written plus five families of five across the elements. Hundreds is an
  authoring job in that one file, and every new item automatically composes with every other.
- Synergy examples that already work: a Shock Coating on the Water Pistol makes every shot
  Chain Lightning on its own. Conductor's Mail plus Hands of the Storm turns hits into
  arcing chains. Heart of the Forge plus any fire gun makes kills explode in chains.
  Signet of Overload turns overheating into a weapon, so Overclock stops being a downside.
- **Sets.** Eight sets (five elemental families, Scavenger, Overloader, Warden) grant
  bonuses at 2, 3 and 4 pieces; gun mods count as pieces. The character sheet shows every
  set you have a piece of and which thresholds are active.
- Scrap in the run buys, repairs and rerolls. Nothing carries out except unlocks.

### Layer 1: the unlock pool (Isaac) — BUILT
- Every run starts with no guns and no gear. The entrance offers each player two random
  unlocked guns on pedestals; take one. The pool of guns a run can offer
  (shops, treasure, challenge rewards), the obstacle kinds in front of hidden rooms, the
  challenge room itself and a fourth shop slot are all unlocked by achievements.
- 58 achievements tracked across runs in the save file: kills, reactions discovered,
  specific reaction counts, rooms cleared, elites and bosses killed, floors cleared, hidden
  rooms opened, secrets, vents fired, gear equipped, runs started and won.
- **Teach the basics, one element per run (R8, Risk of Rain 2's early challenges).** The
  first ten achievements are cumulative goals any run moves, each giving a gun of a new
  element: Chemistry (discover 3 reactions, ice, run 1), Blow-off (vent 10 times, acid,
  run 1-2), Regular (start 2 runs), Housekeeper (clear 5 rooms, poison, run 2), Field
  Notes (discover 6 reactions, gale, run 2-3), Headhunter (kill 3 elites, blood, run 2-4),
  Persistent (start 3 runs, stone, run 3), Catalyst (fire 250 reactions, void, run 3),
  Pilgrim (start 5 runs, holy, run 5). Expected runs come from the bot's floor-1 rates
  (6 distinct reactions, 7 vents, 3 rooms, 0-3 elites, ~100 reactions a run); three of
  them count runs started, so ice, stone and holy are guaranteed by runs 1, 3 and 5 for
  anyone. They reuse the ids whose rewards they took (conductor, bloodied, chemist,
  stormcaller, butcher, veteran, catalyst, zealot), so saves keep their progress; no
  reward moved, all 64 stay assigned.
- **Reaction goals were 50 to 90 and swung 5-10x between runs** (142 Infernos in one run,
  a median of 4). They are now about one to three median runs of their pairing: class
  unlocks 15 to 40 (Pyromancer 15 Infernos, Stormcaller 40 Chain Lightnings, the
  off-element classes 20-25), gun goals 10 to 25, the long tail 50 to 90 instead of 120 to
  240. On load, an achievement whose goal the save already meets is granted quietly and a
  done achievement always has all its rewards. Descriptions always state the real goal; only real reactions count (popups like
  "Shield cracked" do not). The "next goals" shown in the hub and the run-over screen are
  the closest to done that the current gun pool can actually progress.
- Unlocks pop as a toast when earned. The run-end screen lists what this run unlocked and
  the next three achievements with progress, so a lost run still shows a path.
- 43 guns exist; 4 start unlocked. The pool is the lever: adding a gun, obstacle or room
  type to the game should always come with the achievement that unlocks it.
- Epic and legendary gear unlock after 8 and 25 pieces equipped, and from then on can roll
  from floor 1 at low odds (epic 1.2% per difficulty step from difficulty 2, cap 10%;
  legendary 0.4%, cap 4%) instead of only from floor 2 and 3.
- Save file: `user://save.json` (on Windows: `%APPDATA%/Godot/app_userdata/Pressure/`).
  F9 wipes it for testing a first-ever run.

### Layer 1b: the Shrine (Embers, talents, Last Breath) — BUILT
The one deliberate exception to "nothing makes a run easier", kept small, swappable and
capped (report R4 to R7). Code: `scripts/mastery.gd` (autoload `Mastery`, save
`user://mastery.json`), UI `scripts/mastery_screen.gd`.

**Embers (R7): pay for play quality, not only depth.** Paid once at run end:

    Embers = 1 x rooms cleared + 2 x elites + 3 x reactions fired for the first time ever
           + min(12, 4 x new fusions + 6 x new cataclysms)
           + 3 x boss kills + 12 x bounties (first kill of a boss kind with a class)
           + 2 x (floor reached - 1) + 10 if cleared

Fusion and cataclysm discoveries pay like reactions, but there are 396 of them (1,936
Embers uncapped, twice the whole Shrine's 928), so together they pay at most 12 a run
(`Mastery.FUSION_PAY_CAP`): about one more good floor. Measured on fresh bot saves, every
four-element fusion run hit the cap (15 to 63 new fusions in a run); a long-lived save
discovers a few a run and pays 4 to 12.

Scale: a cleared room is 1 Ember the way a Hades chamber is 10 Darkness, so Hades prices
divide by 10. Elites pay like Hades' harder (skull) chambers, double. Discoveries are what
the early game should teach and front-load income (65 reactions, 195 Embers). Bounties are
Hades' first-kill-per-weapon rewards: 5 boss kinds x 13 classes, so rotating classes pays.
Depth is the small part: a floor of rooms and an elite is worth more than its stairs. Two
floor-1 deaths on a save that knows the base reactions: one room and nothing else pays 1;
five rooms, two elites and two new reactions pay 5 + 4 + 6 = 15 (the old formula paid both
1 point). Kills no longer pay: they track time spent (about 60 a minute in every sample),
not play.

**Talents (R4).** Eleven slots, each an exclusive A/B pair like Hades' Mirror: one side is
active, switching is free and unlimited between runs, each side has its own 2 or 3 ranks,
and Refund all returns every Ember at no cost. Values are budgeted with factors measured
from the mastery-free bot telemetry: reactions dealt 49% of damage (so +x potency is about
+0.49x damage), vents 12.6%, the median share of wave samples at 80%+ HP was 0.44, and a
floor-1 death took 100-222 damage (about 150 per floor, ~6.5 a hit). Duration converts at
an assumed 0.15. Economy and agency count as zero stat power.

| Slot | Side A (ranks, costs) | Side B (ranks, costs) | Max power of the slot |
|---|---|---|---|
| Sights | Long Barrel +4% range (3: 3/8/16) | Hot Load +5% shot speed (3: 3/8/16) | 0 |
| Catalyst | Catalyst +1.5% potency (3: 4/10/20) | Lingering Touch +4% duration (3: 4/10/20) | 2.2% dmg (4.5 x 0.49) |
| Nerve | Thick Skin +4 max HP (3: 4/10/20) | High Confidence +1.5% dmg at 80%+ HP (3: 4/10/20) | 12 HP or 2.0% dmg (4.5 x 0.44) |
| Vent | Reinforced Tank +4 capacity (3: 4/10/20) | Hard Vent +4% vent power (3: 4/10/20) | 1.5% dmg (12% x 0.126) |
| Footwork | Light Feet +2% speed (3: 3/8/16) | Sidestep +1% dodge (2: 6/16) | 3 HP (2% x 150) |
| Salvage | Salvager +4% scrap (3: 3/8/16) | Second Thoughts +1 level-up reroll per run (3: 10/25/45) | 0 |
| Fortune | Lucky Coin +4% luck (3: 4/10/20) | Wider Choice 4th level-up card, every other then every level-up (2: 35/75) | 0 |
| Pack | Deep Pockets +1 carry (2: 8/20) | Heirloom free gunsmith on floor 1, then floors 1-2 (2: 10/25) | 0 |
| Scout | Cartographer: shop, + treasure, + boss on the map (3: 3/6/12) | Dowser: hidden rooms, + puzzle rooms on the map (2: 6/15) | 0 |
| Bite (R6) | Rime, needs an ice gun: +3% ice fire rate, +2% ice potency (2: 8/20) | Etch, needs an acid gun: +3% acid damage, +2% acid potency (2: 8/20) | 4% of that element |
| Twilight (R6) | Halo, needs a holy gun: +3% holy damage, +2% holy potency (2: 8/20) | Hollow, needs a void gun: +3% void fire rate, +2% void potency (2: 8/20) | 4% of that element |

The twelve element-damage branches (120 of the tree's 326 points, inert until the element
was in the pool) are gone (R6); two slots keep element sidegrades for the first and last
elements the challenges hand out, buyable only once a gun of the element is unlocked.
Element shares of an arsenal sum to 1, so both element slots together add at most 4%.
Upper bound at completion, the larger side of every slot summed: **+9.7%
damage-equivalent and +15 HP-equivalent** (GDD target: 10% and 20). The old tree by the
same factors: +21% damage, +12% fire rate, +7 pp crit, +1 projectile, +2 pierce, +2
bounce, +2 chains, +11% damage and +12% potency per element, +32 max HP and 6 armour.
Costs follow Hades' shape: cheap first ranks, power sides 34 Embers each, agency (rerolls
and the 4th card) the expensive tail at 190 of 775, about a quarter (Hades' Fated rerolls
are 59% of its Mirror, but a 59% tail would push completion past a hundred runs).

**Survival (R5): Last Breath.** Three ranks, each one revive per run at 25% max HP with 2 s
of invulnerability, costing 3, 50 and 100 Embers: Hades' Death Defiance (30 / 500 / 1,000
Darkness) at the room scale above, the same shape as Dead Cells' flasks (5 / 50 / 150 /
300 cells). The first is bought after a first run; the others are long-term goals. 25%
rather than Death Defiance's 50% because the stairs already heal to 60% / 40% each floor
and 25 HP is about four of the measured hits. In co-op each player gets the charges.

**UI.** The hub's Shrine opens a board: eleven slot cards in a 4-column grid (both sides,
the active one lit, rank pips, the next rank's cost in Embers), the survival row under it,
Embers in the header, three detail lines for the focused card (active side now and next,
the other side, what to press) and Refund all with a press-again confirmation. Pad: d-pad
moves, A buys the lit side, X switches; keyboard: arrows, Enter / E, Tab / Q; mouse: hover,
click the lit row to buy and the dark row (or right-click) to switch. The run-over screen
shows the Embers earned with their breakdown and any bounties; the Ledger shows Embers per
run and the lifetime total by source.

**Save migration.** Version-1 mastery files (points, purchased nodes) convert every point
ever earned into 8 Embers and refund the whole tree, as Hades' Patch 040 refunded
over-investment when it moved to A/B pairs; one old point was about a floor of play, and a
floor now pays about 8 (five rooms, an elite, the floor bonus). Version 2 stores Embers,
ranks per side, active sides, survival ranks, bounties paid and lifetime Embers by source.

### Layer 2: starting classes (Dark Souls, Isaac) — BUILT
- A class is only the first room. Each is a starting gun of its element, one themed
  starting item, a small permanent affinity (that element's reactions +20% potency, its
  guns +10% damage) and a quirk (the Pyromancer is frailer, the Frostbinder slower, the
  Templar regenerates, the Voidwalker is lucky). From there the run goes wherever the
  loot takes it, Dark Souls style: a Pyromancer who finds a hydro cannon becomes a
  steam build.
- The Vagrant is the naked start (pick of two guns, a little more carry and scrap) and
  is always unlocked; the twelve elemental classes unlock through achievements on their
  element's signature reaction, Isaac style. Later joiners in co-op get a random unlocked
  class. Picked on a card screen between Play and the first room.
- Items are visible on the figure (Isaac costumes, Brotato weapons): hats, plate, gloves,
  boots, charms, an aura for rings and legendaries, the active item on the back, and a
  completed set tints the whole figure (Guppy-style transformation). Twenty
  shot-modifier items (homing, shards, splash, boomerang, spectral, orbitals, shot size)
  are the tear-modifier layer.

### Layer 3: keystone tiers (WoW Mythic+)
- Clearing a dungeon earns a **keystone** one tier higher. Tiers add affixes: more
  resistances, longer elite sequences, a bleed on contact, rooms that lock elements out.
- Higher tiers drop from richer loot tables and unlock faster. This is the "gear score
  gates content" hook with the power creep removed: the number that grows is the difficulty
  you are allowed to attempt, and the reward for growing it is more chaos, not an easier game.

### Layer 4: the hall (small, cosmetic, satisfying)
- A hub room between runs that fills up: trophies from bosses on the wall, a bestiary with
  what you have learned about elites (their sequences shown once discovered), a reaction
  compendium, run history. Nothing in it changes gameplay.

### Save file
- Unlocks, characters, highest keystone per character, bestiary, stats and run history.

## 5. Co-op
- 2 to 4 players. **Couch co-op first** (one keyboard + mouse player, any number of pads;
  press Start on a pad to join). Works in the browser build too.
- **Online later**: host-authoritative with Godot's built-in multiplayer. One friend hosts the
  desktop build. Browser-to-browser needs a relay server and comes last.
- Architecture rule from day one: the host owns all enemies, waves, drops and reactions.
  Clients send input; everything else is replicated.

## 6. Tech
- **Godot 4.7, GDScript.** Web export is GDScript only, and Azeroth Survivors proves a
  no-install browser game is the right way to share.
- Compatibility renderer (WebGL 2) so the web build runs everywhere. The Web preset is
  single-threaded on purpose: that build needs no cross-origin isolation headers, so
  GitHub Pages (or any static host) can serve it. A push to main deploys it.
- Damage numbers on every hit, batched for damage over time; player names from the
  menu replace P1..P4.
- Art: Kenney CC0 packs, tinted dark. The 1-Bit Pack gives a single white-on-transparent
  sheet, so the whole look is a palette in `art.gd`: bone, blood, rust and stone, with a
  vignette over everything. No generative art.
- Effects: generated pixel particles (Noita-inspired, no sheets): a 700-slot ring
  buffer of 2 to 5 px squares in three-step element palettes, translucent so the fight
  stays readable, with a behaviour per element (fire rises and flickers, water falls and
  splashes, ice crumbles, sparks arc, oil sticks, void spirals in). Reactions map by
  what they do: a burst is a hollow pixel ring, a cloud lingers, a freeze is a shard
  star, pulls spiral in. Burning enemies shed embers, poisoned ones motes.
- Music: three CC0 synthwave tracks by Alex McCulloch (menu, run, boss).
- Text: the Kenney Pixel font everywhere, never under 20 px, and as few words as the
  screen can get away with.
- Code-driven scenes for now (everything is built in `_ready`), so the project is easy to
  read as plain scripts. Scenes get moved into the editor when they stabilise.

## 7. Milestones

| # | Milestone | Status |
|---|---|---|
| 0 | **Combat core** | Done. Guns, five reactions, pressure, vent, focus, resistance drift, sequence elites, couch co-op. |
| 1 | **Dungeon run** | Done (first pass). Generated floor of rooms, doors, arena waves, shop with scrap, treasure, challenge, hidden room behind an elemental obstacle, five bosses with phases, five floors, minimap. |
| 2 | Tuning & content | Human playtesting, 10+ guns, more enemy types, more obstacles and reactions, room layouts with cover |
| 3 | Meta progression | Unlock pool done (achievements, save file, gated guns/obstacles/rooms). Next: in-run gear with loot tables, characters, keystone tiers, the hall |
| 4 | Online co-op | Host-authoritative netcode for the desktop build |
| 5 | Raids | Multi-boss co-op dungeons with mechanics |
| 6 | Art, sound & juice | Done (first pass): Kenney 1-Bit sprites, particle reactions on an additive layer, scorches, corpses and bone bits, procedural animation (hop, spawn pop, hit squash, recoil, muzzle flash), camera shake, 46 Kenney sounds, main menu, codex, pause menu, Brotato-style HUD. Music still to do. |

### What the dungeon run does today
- A floor is a tree of 9 to 13 rooms on a grid. Dead ends become the boss, treasure, shop
  and challenge rooms. One hidden room hangs off an ordinary room behind an obstacle:
  a pool (freeze it), a thicket (burn it) or a rusted valve (Steam it: Wet, then Fire).
- Arena rooms lock their doors and run a timed wave; the timer grows with difficulty.
  Difficulty starts at 2, adds 4 per floor, and creeps up one step every second room
  cleared, so a floor is one difficulty band and the stairs are the jump.
- Every arena clear pays out a free gun or item on a pedestal, so power grows with the
  rooms whether or not the shop turns up. The minimap reveals rooms Isaac-style, as you
  reach their neighbours; special rooms are dressed so you know them on sight.
- Treasure rooms are chests: one pick from gear, a gun, or a run boon (Vitality, Pack
  Mule, Boiler, Hoard). Chest tier rises with the floor and a little luck, raising the
  gear rarity and the boon size. Shop prices are high enough that a floor's scrap buys one
  or two things, not the whole counter.
- Rooms are 1120 by 720 with the camera zoomed to 1.3x, so a room is about a screen and
  a half, close to Isaac's one-screen rooms with a little scroll.
- Enemies drop scrap. The shop sells three guns, a carry upgrade and a repair.
  Treasure rooms give a free pick of one gun from three. Challenge rooms start from a sigil,
  spawn two sequence elites plus adds, and pay out scrap and a free gun pick.
- The boss has a reaction sequence shield, re-shields with a new sequence at half health,
  and summons adds. From floor 2 its health is sized to the party's measured output and it
  rallies twice (a guard held by a wave of adds). Killing it spawns the stairs. Five
  floors, then the run is won.
- The trigger always fires along your aim even with no enemy in range, so obstacles can
  be shot deliberately. Interact with pedestals using E or the A button.

## 8. Balance probes (bot flags)

`godot --path . res://scenes/main.tscn -- --autotest` plus: `--secs=N` run length,
`--short` 70 s, `--class=<id>`, `--idle` (stand still in fights), `--loadout=a,b,c`
(start with these guns), `--veteran` (everything unlocked), `--mastery=full` (every Shrine
rank of both sides and the whole survival track, side A active; `--mastery-side=b` for B)
or `--mastery=N` (spend N Embers cheapest-first on the survival track and active sides),
both on a throwaway Shrine file that prints a `[MASTERY]` line with the loadout and its
power estimate; every run prints `[EMBERS]` with what it paid (or would have paid when
the time cap ended it),
`--arsenal` (every gun), `--gear` (equip shock gear at 45 s for the sheet screenshot),
`--fusion-probe[=K]` (four w1 guns of four elements, rotating with `--instance`),
`--build=storm|mid --start-floor=N` (start on floor N with the human run's build at that
floor, or a mediocre one; profile gear is kept), `--one-floor` (quit at the next floor),
`--old-balance` (the late-floor tuning off, for before/after),
`--no-fusions` (the tier ladder off: the pre-fusion game, for baselines), `--perf` (fps and
frame-time lines every 2 s), `--instance=N` (own save, Shrine and telemetry per parallel
run). Every run ends with `[FUSION]` (counts, damage by tier, top names) and
`[FUSION-CHECK]` (termination proof) lines.
Telemetry from bot runs is stored locally with `bot: true` and never uploaded.

## 9. Debug controls in this build
- `1`..`0` give player 1 any gun, unlocked or not
- `R` restarts the run
- `F1` toggles the help overlay
- `F9` wipes the save file
- `godot --path . -- --autotest` runs the self-test bot through the dungeon
