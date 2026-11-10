# Core loop reset

Written 2026-11-10 after Emil quit run `6980a749e57a5a83` on floor 3 ("it's not fun"). This is
a spec only: no code changed with it. It sets the numbers, the files and the order for three
or four build sessions.

**Emil's decisions (2026-11-10), locked:**
1. Items stack with no gear slots, Isaac and Brotato style. Guns keep a fixed number of slots.
2. Hybrid loot: a few free items that each matter (treasure room, boss), plus a shop every
   floor where money is tight and spending is a real choice.
3. A dash with a short invulnerable window and a cooldown.
4. The core loop comes first, before more content or polish.

Everything else here is a **default**: build it as written, keep it easy to change, and report
the numbers. Section 15 lists the defaults Emil may want to overrule.

---

## 0. The spec on one page

| Problem in run 6980a749 | Cause in the code | Fix |
|---|---|---|
| Stood still on floor 3, 0% moving, never in danger | Melee walks down the gun line and dies. Only spitters hurt (64 of 65 hits, about 5% each), and regen healed most of it | New threats that punish standing still (lobbers, chargers, ring swarms, ground swell, zoning elites, room hazards), a dash, and fewer but harder hits |
| Melted everything: the Brute King in 5.7 s | Enemy health follows depth and an estimate of gun dps capped at x1.87, while his damage grew x6.7 from floor 1 to 3. The floor-1 boss isn't sized to the build | Health follows measured damage (square root, so a broken build still feels broken), elites and bosses sized to it on every floor, diminishing returns on stacked reaction power |
| Money almost infinite | Scrap comes per kill, and the crowd grows with the build (x1.22 per extra gun), so a strong build earns more. 2,508 scrap at the floor-2 shop against a top price of 286 | Scrap is a fixed budget per room and per floor, not per kill. Prices scale with depth. Target: spend down at most shops |
| The shop is "reroll until epic or legendary" | Rerolls were cheap next to his scrap (11 rerolls in one visit) | Rerolls escalate fast inside a visit, money is tight, explicit rarity odds per floor, a lock button |
| Loot flood, items feel meaningless | Every arena pays a pick of 2 to 4 cards, elites bank more, plus treasure, challenge, boss, shop and a level-up about every wave: about 35 cards to read on floor 1 and 50 on floor 2 | No items from arenas or elites. Free items come from the treasure room, the boss and optional rooms (2 to 4 a floor); 1 to 3 are bought. At most 15 cards to read a floor |
| Items are hard to read | 9 gear slots: every card must say what it replaces, and which ring or trinket. 238 items, 44 of them one small stat (six are "+10 to 15 max HP") | Items stack, no slots. About 140 items after merging. A Brotato-style card: big icon, one line, green and red deltas. A build page on pause |
| No reason to keep going; quitting paid 0 Embers | "Return to hub" never calls `Main._end_run`. Few choices with stakes | Quitting pays like a death. Pact rooms, cursed pedestals, optional elite rooms, resonances at 3 and 5 items, a floor-end summary |
| A broken run gives no spike | Power grows in small invisible numbers | Named synergies with a banner and a visible change to your shots, resonances that change your look |

Build order (section 14): **1. Fight** (dash, threats, healing reserve, power curve), **2. Loot
and economy**, **3. Items without slots and readability**, **4. Broken runs and risk rooms**.
Each session stands alone, has its own tests, and passes `tools/exe_smoke.sh`.

---

## 1. What happened in run 6980a749

Alchemist, Etcher Beam, relic Ricochet Gloves, 2 Shrine talents, build
`2026.11.10-exefix2+fe8877a`, aim mode assisted. Quit in the Frostvault after 3 rooms.

| | Floor 1 | Floor 2 | Floor 3 (quit) |
|---|---|---|---|
| Damage dealt (all sources) | 17k | 69k | 131k |
| Fight time | 107 s | 166 s | 122 s |
| Damage per fight second | about 160 | about 415 | about 1,070 |
| Health at the end | 56% | 100% | 100% (quit) |
| Time under 50% health | 0.44 | 0.03 | 0.04 |
| Damage taken per minute (share of max health) | 0.49 | 0.47 | 1.06 |
| Healing per minute | 0.19 | 0.63 (Leech 0.39) | 0.81 (regen 0.61) |
| Moving while under threat | 98% | 91% | **0%** |
| Hits taken, and from what | 14, melee | 26, mixed | 65, **64 from spitter shots** |
| Scrap when entering the shop | 609 | 2,508 | 2,181 |
| Top price in the shop | 145 | 286 | 160 |
| Rerolls | 2 | 11 | 7 |
| Boss | Brute King, 5.7 s | Hive Mother, 30.7 s | |
| Elite kill time | 3.7 to 7.3 s | 2.5 to 12.4 s | 3.0 to 8.0 s |

Earned 7,614 scrap, spent 3,941. Gear in 10 minutes: 4 guns and 6 items on floor 1, 6 more
items on floor 2. Reactions, fusions and damage over time made about three quarters of his
damage.

**A probe for this spec** (main at `fe8877a` plus the boss session's uncommitted edits;
`--idle --build=storm --start-floor=3 --mastery=full`, two runs): the bot's storm build parked
in the middle of the Frostvault died in both runs, in the 3rd and 5th arena. It took 2.0 to 2.1
health bars a minute and healed 1.6 (Leech 0.9). Emil's build took 1.06 a minute in the same
region and never dropped under half. **The bots' builds are much weaker than a human's real
build**, which is why the difficulty pass, tuned with bots, missed him. Tests in section 13
replay his build.

### Causes in the code

- **Income per kill, crowd per build.** Each kill drops `Enemy.STATS[kind][5]` scrap
  (`Room._drop_scrap`), and `Room.crowd_target` keeps `6 + 1.1 x difficulty` enemies alive,
  x1.22 per extra gun and x1.12 per extra element. Six guns and four elements mean about 2.5
  times the enemies, so 2.5 times the scrap. Spoils that aren't picked are salvaged for 30% of
  their price on top.
- **Flat prices.** `Items.price` is the rarity base (22 to 150) plus a few percent per floor.
  `FloorGen.reroll_price` escalates (10 + 6 x floor, + (6 + 3 x floor) per use), but against
  2,500 scrap that's nothing.
- **Loot everywhere.** `Room._arena_reward` gives a free pick of 2 to 4 cards at the end of
  every arena; elites bank more cards; the treasure room offers 1 of 3, the challenge room 1
  of 5, the boss 1 item, and `LevelUps` gives 1 of 3 about every wave.
- **Slots.** `Player.EQUIP_KEYS` has 9 slots. The card has to show "Replaces X", which ring
  stays and a swap button. Most items are a small stat replacing another small stat.
- **Healing per fight.** Mending (`Player.MEND_SOFT` 0.2) refills at every fight. Regen ticks in
  and out of fights.
- **Health behind damage.** `Room.party_power` estimates power from carried gun dps, clamps it
  to 0.8 to 3.5 and takes the square root (at most x1.87). Enemy health per difficulty point
  grows about x3.4 from floor 1 to floor 5, while a human's damage grows far faster. The
  floor-1 boss keeps its formula (`BOSS_DPS_SECS` applies from floor 2), elites hold at least
  2 s of arena damage.
- **Nothing punishes standing still** except the spitter. Melee spawns in a ring (0.75 s
  telegraph) but walks into a wall of reactions.
- **Quit pays nothing.** The pause menu's "Return to hub" changes scene without `_end_run`;
  `Telemetry` records the run as abandoned with 0 Embers.

---

## 2. How Isaac and Brotato hold attention

Principles only, no content.

1. **Scarcity makes an item an event.** Isaac gives about two free items a floor (treasure,
   boss) and a handful of coins; one item is a moment you remember. Brotato gives many items,
   but each costs money you have just fought for. Pressure gave both kinds of plenty at once.
2. **Items stack and are never replaced.** There's no "what does this replace" question. The
   only question is "do I want this?" The card shows how your build changes, in green and red.
3. **Income is fixed by the level, not by how well you kill.** In Brotato the wave decides how
   many enemies and materials there are; investing in income is a separate, risky choice.
   That keeps every shop tight at any power level.
4. **Rerolls get expensive inside one visit, and you can lock what you want.** Rerolling once
   or twice for a need is smart; rerolling for a jackpot is a losing bet.
5. **Items change how you play, visibly.** In Isaac the item that makes shots home, split or
   come back changes every room after it, and you can see it in the shots. Numbers alone don't
   make a run memorable.
6. **The enemies make you move.** Isaac's rooms are built from projectile patterns and chasers
   that cut off the middle; Brotato's crowds come from every side so standing still is death by
   the middle waves. Pressure comes from positions, not from bigger numbers.
7. **The broken run is a threshold crossed and acknowledged.** A third item of a theme changes
   your look and adds a power; two items that combine produce something neither does alone.
   The game makes it visible, and the player feels clever.
8. **Risk you choose.** Pay health for power, take a curse for a better item, enter an optional
   fight. The run has decisions with stakes, not only pickups.
9. **Even a failed run pays.** Leaving early still moves the meta forward, so the next run
   starts sooner.

---

## 3. Items without slots

### 3.1 The model

- An item is a **passive** (stacks, no slot), a **gun mod** (sits in a gun's mod slots, which
  stay: a gun holds as many mods as its tier) or an **active** (one held at a time, the button
  item; a new one swaps the old onto the floor). Guns keep `Player.MAX_GUNS` 6.
- `slot` stops being a gate. It becomes `look`: which body part the item dresses in
  `worn_gear.gd`, cosmetic only. The figure shows the highest-rarity item per body part.
- Each passive has a `stack` rule:

| Rule | Meaning | Used by |
|---|---|---|
| `add` | Each copy adds the full effect | Plain stats, chances, counts (bounce +1, orbitals +1) |
| `dim` | Each copy adds 60% of the one before | Strong multipliers (Godhead, Twin Triggers) |
| `once` | Only the first copy counts; it's never offered again once owned | Rule changers (boomerang, spectral) |

- **Caps** so stacking can't break the game: dodge 40%, crit chance 100%, move speed +60%,
  scrap gain +50%, luck +60%, dash charges 3, vial chance per element 60%.
- **Armour becomes a percentage.** Today damage is `amount - armor` (minimum 1), which with
  stacking would make 6-damage shots harmless. New: `taken = amount x 15 / (15 + armor)`.
  3 armour takes 17% off, 10 takes 40%, 30 takes 67%. Armour items move from +1 to +3 each.
- **Sets become tags.** Every item carries 1 or 2 tags (an element, or Vent, Guard,
  Gunslinger, Seeker, Alchemy, Swift, Fortune). Owning 3 and 5 items with a tag forms a
  **resonance** (section 12). The hand-made sets fold into these tags.

Files: `items.gd` (catalog, `stack`, tags, caps, `Items.fire` events `dash` and
`perfect_dodge`), `player.gd` (inventory as id -> count, `recalc_stats` multiplies by count,
`take_damage` armour), `worn_gear.gd`, `character_sheet.gd`, `drops.gd` (no slot logic),
`pedestal.gd` (no swap/replace), `hud.gd` (`_draw_main_gear` becomes the item strip).

### 3.2 Migration of all 238 items

Today: 166 hand-made items plus 6 element families x 12 elements (charm, ring, vial, gloves,
coating, mantle). After: about 140 (109 passives, 21 gun mods, 10 actives). Every old id maps
to a new one in `Items.LEGACY_IDS`; nothing is dropped without a successor.

**Plain stats: 72 items become 19.** Commons that only differ by name merge into one basic per
stat, with a bigger number since it now stacks.

| New item | Effect per copy | Old ids merged into it |
|---|---|---|
| Iron Heart (C) | +15 max HP | rusted_helm, leather_cap, quilted_jerkin, sturdy_boots, bone_ring, oak_ring, iron_band, chain_shirt |
| Plate Scrap (C) | +3 armour | iron_pot, padded_vest, patched_coat, hobnail_boots, riveted_plate |
| Light Boots (C) | +6% move speed | feather_cap, leather_boots, runner_wraps |
| Slipstream Cloak (U) | +6% speed, +4% dodge | slipstream_cloak, mudwaders |
| Bandage Roll (C) | +10% Mending reserve (section 10) | hide_vest, gardening_gloves, sandals, bandage_roll, jade_ring, jogging_shoes |
| Hair Trigger (C) | +8% fire rate | worn_gloves, hair_trigger, ticking_clock, quick_hands, fingerless_gloves, bandolier |
| Whetstone (C) | +8% damage | knuckle_wraps, whetstone |
| Lab Gloves (C) | +8% reaction power | lab_apron, lab_gloves, reagent_satchel, catalyst_ring |
| Copper Ring (C) | +4% crit chance | steady_gloves, copper_ring, sniper_visor |
| Spyglass (C) | +15% range | wide_brim, brass_spyglass, ring_of_reach, rifled_sleeve |
| Wishbone (C) | +8% luck | four_leaf_clover, wishbone_ring, lucky_cog, gilded_ring, ledger, seer_circlet |
| Rabbit Foot (R) | +20% luck | rabbit_foot |
| Scrap Magnet (C) | +10% scrap | cargo_vest, scrap_magnet, tin_ring, scavenger_hood, scrappers_mitts |
| Coin Purse (U) | +25% scrap, -10 max HP | coin_purse |
| Thinking Cap (U) | +15% XP | miners_lamp, treaders, thinking_cap |
| Gasket (C) | +15 vent capacity | gasket_ring, heat_gauge, bellows, hothead |
| Pressure Valve (R) | Vent charges 40% faster, +15% vent power | pressure_valve |
| Thorn Vest (U) | Attackers take 6 damage | thorn_vest, spiked_gauntlets, stompers, anvil_boots |
| Alembic (R) | Elements last 25% longer | alembic, fume_mask, pocket_watch, band_of_lingering |

Plus the 36 element charms, rings and mantles, which become **12 Sigils** (U): "+15% Fire
damage and Fire reactions" (one per element). The conditional elemental uncommons
(divers_goggles, ring_of_embers, cinder_clogs) fold into the matching Sigil. The 12 element
gloves are cut: their pierce lives in Grip of Pierce and their fire rate in Hair Trigger
(each `gloves_<el>` maps to that element's Sigil).

**Trade-offs: 15 kept as 13.** One gain, one cost, both bigger than a basic. Stack `add`.
boiler_cap, berserker_helm, blood_pact, frenzy_band, hot_rod, cold_snap, hover_greaves,
executioners_grip, big_iron (lead_shot merges in), tidewalkers (quicksilver_band merges in),
bloodstone, seven_league (L), and marksman_monocle. The Monocle rewarded standing still; it
changes to "+50% crit damage for 2 s after a dash".

**Healing: 4 items become 2.** Leech Mail (R): "Reactions within 200 px heal 1" (draws on the
reserve; leech_mail, vampiric_loop and grisly_trophy map here). Phoenix Mantle (L,
phoenix_mantle) stays.

**Behaviour items, kept and merged (59 old items, vials included, into 43).**

| Behaviour | New item(s) | Old ids |
|---|---|---|
| Homing | Seeker Lens (R, `add`: turn rate +), Godhead (L, `dim`) | seeker_lens, tracker_boots, cerebral_spark, feral_fang, godhead |
| Shards | Splinter Charm (R, +1 shard a copy), Hive Heart (L) | splinter_charm, cluster_rounds, shrapnel_vest, hive_heart |
| Splash | Powder Horn (R, +30 px a copy) | powder_horn, detonator_cap |
| Spectral | Wisp Lantern (R, `once`) | wisp_lantern, phantom_shroud |
| Orbitals | Bone Orbit (R, +1 orbital a copy), Skull Choir (L) | bone_orbit, twin_moons, skull_choir |
| Bounce | Ricochet Gloves (R, +1 a copy), Storm Halo (L) | crown_of_focus, ricochet_gloves, storm_halo |
| Pierce | Grip of Pierce (R, +1 a copy) | grip_of_pierce |
| More projectiles | Twin Triggers (E, +1 projectile, -10% damage, `dim`) | twin_triggers, ammo_harness |
| Boomerang | Mother's Blade (L, `once`) | mothers_blade |
| On-hit elements | 12 Vials (U, +15% chance a copy), Static Jar (R), Kindling Mitts (R) | vial_<el>, chilled_knuckles, puddle_jumpers, spark_plug, static_jar, kindling_mitts |
| When hurt | Tar Coat (U), Frost Treads (R), Glacier Plate (E), Spiked Cuirass (R) | tar_coat, greased_soles, frost_treads, glacier_plate, spiked_cuirass |
| Reactions and vents | 11 kept as they are | conductors_mail (storm_hood merges in), hands_of_storm, echo_loop, ring_of_multiplicity, plague_censer, heart_of_forge, permafrost_core, steam_whistle, signet_of_overload, skullcap_vented, vent_striders |
| Economy | Gilded Carapace (L) | gilded_carapace |

**New behaviour items (20).** Each changes how a gun, a reaction or the dash works, and each
shows on screen.

| Item | One line | Stack |
|---|---|---|
| Slipstream Boots | Dashing leaves a 2 s trail of your vent element | +1 s |
| Shoulder Charge | Dashing through enemies hits them for 100% gun damage | +50% |
| Second Wind | +1 dash charge | add, cap 3 |
| Pressure Kick | Each dash adds 15 pressure | +10 |
| Close Shave | Dodge a hit with a dash: +30% damage for 3 s | +1 s |
| Rear Guard | Your guns also fire one shot backward | +1 shot |
| Mortar Kit | Every 5th shot is a lob that bursts into a cloud | every 4th, 3rd |
| Gravity Shot | Shots pull enemies within 40 px | +20 px |
| Long Fuse | Shots grow up to +80% size over their flight | +40% |
| Fork | Beams and chains fork to 1 more target | +1 |
| Marking Rounds | Every 6th hit marks; marked foes take +40% from reactions | every 5th, 4th |
| Rebound | Shots that hit a wall come back once | once |
| Death Shards | Kills fire 2 shards of the dead foe's element | +1 |
| Reaction Trail | Your reactions leave a 2 s patch of their element | +1 s |
| Wide Arc | Chain Lightning jumps through any element, not only Wet | once |
| Split Reaction | A reaction fires 1 shot of each element in it | +1 |
| Overheat | At full pressure your shots carry your vent element for 3 s | +1 s |
| Ward Vent | Venting raises a 3 s ring that stops enemy shots | +1 s |
| Mirror Hide | The first hit in each room bounces back as a nova | +1 hit |
| Scavenger's Eye | Secret walls glow; secrets drop 1 more item | add |

**Count of behaviour items.** Today 86 of 238 items change behaviour (36%), but 24 of them
repeat a behaviour another item already has (five homing items, twelve gloves that add pierce).
After: 63 of 109 passives (58%), and the number of distinct behaviours rises from about
33 to about 53. The raw count falls because copies merge; what the player can discover rises.

**Gun mods: 24 become 21** (they keep their per-gun slots). sight_rail and long_barrel become
Long Barrel; oiled_bolt and gun_oil become Gun Oil; exhaust_pipes and pressure_coupler become
Pressure Coupler; heavy_barrel, piercing_rounds, arc_emitter, overclock, split_chamber,
chain_reactor and the 12 Coatings stay.

**Actives: 14 become 10.** smelling_salts merges into blood_chalice. tin_whistle ("untouchable
for 1.5 s") is cut: the dash does its job (maps to blood_chalice). dowsing_rod is cut (maps to
pocket_storm). flash_powder, pocket_storm, water_bucket, ember_flask, grease_gun,
frost_grenade, tesla_coil, overpressure, pressure_bomb and prism_engine stay.

### 3.3 Save migration

There is no mid-run save, so only meta data holds item ids. `Progress.SAVE_VERSION` goes from
4 to 5.

- `Progress.relics`, `Progress.well_saved` and the saved loadout relic (`Loadout`, read through
  `Progress`) run through `Items.LEGACY_IDS`.
- Two old relics that map to the same new item collapse to one. The dropped one's
  `Loadout.RELIC_PRICES` value is refunded in its currency, and the load prints
  `[MIGRATE] relic a+b -> c, refunded N`.
- The journal (`journal.gd`) sorts by tag instead of slot. Discovery flags keyed by old ids
  are mapped the same way.
- Telemetry keeps old ids in old runs; `tools/pressure_report.py` and
  `tools/analyze_telemetry.py` read `LEGACY_IDS` from a JSON export when they group items.
- Bot builds (`--build=storm`, `--build=mid`, relic flags) are rewritten with new ids.
- Test: load a version-4 save with every old relic id and a Well full of old items; it must
  load with 0 `SCRIPT ERROR`, print the mapping, and show the right items in the Hollow.

---

## 4. Item readability

### 4.1 The item card (Brotato style)

At the 1280 x 720 base viewport (`canvas_items` stretch), one card:

| Part | Rule |
|---|---|
| Size | 360 px wide, at most 300 px tall |
| Icon | 96 px (a 32 px tile at 3x), left, on a rarity-coloured plate |
| Name | 28 px, rarity text colour, at most 3 words and 22 characters |
| Rarity | The word ("Rare") in 18 px under the name, always printed |
| Effect | **One line**, 22 px, at most 10 words and 60 characters. Verb first for behaviour ("Shots bounce to 1 more enemy"), a signed number with a unit for stats ("+8% fire rate") |
| Tags | Up to 3 neutral chips (element badge style, `ItemCard.draw_element_badge`), 18 px |
| Stack | "You have 2. Taking this makes 3." in 18 px, dim, only when you own it |
| Deltas | Up to 3 lines, 22 px: the stats this changes on your build now, before and after. Green when better, red when worse: "Fire rate 34% -> 42%", "Max HP 140 -> 130" |
| Resonance | One line if this item completes or advances a resonance: "Vent 2/3 -> 3/3: resonance!" in the tag's chip colour |
| Price | 24 px, scrap colour; red with "need 12 more" if you can't afford it |

Removed: "Replaces X", "Keeps X", the swap prompt, set lists, and the second and third effect
lines. A behaviour item whose effect needs more than 10 words is rewritten, not wrapped.

Gun cards follow the same rules: name, tier pips, element badge, one line for the firing
type ("Beam: melts through a line"), deltas in damage per second and pressure.

Files: `item_card.gd` (new `_item_model`; most of `_compare_rows` and the set block go),
`pedestal.gd`, `levelup_screen.gd` (level-up cards use the same layout), `hub.gd`,
`well_screen.gd`.

### 4.2 Pickups in the room

- The icon stands on the pedestal at 2x (64 px) with a **rarity glow**: a soft light pool in
  the rarity colour under it (Common none, Uncommon small, Rare medium, Epic large and pulsing
  at 1 Hz, Legendary large with a thin beam of light upward). Drawn below the hostile layer and
  under the clarity pass's brightness caps.
- A **short label** is always visible: the name in 20 px, plus the price in a shop. Nothing
  else until you're close.
- The **full card** shows only for the pedestal you stand at (within 90 px) or have focused.
  Never more than one card on screen at a time.
- Scrap, hearts and keys look nothing like items: small, no pedestal, no label.

### 4.3 The build page on pause

The pause menu opens on a **Build** tab (gamepad: Start, then LB / RB between tabs):
- every item you own as a 48 px icon with a "x3" count, grouped by tag;
- resonance progress per tag ("Vent 2/3");
- your guns with tier pips and their mods;
- 8 key numbers with totals: damage, fire rate, reaction power, crit, max HP, armour (as % taken
  off), speed, dash charges, plus the Mending reserve left this floor;
- the focused icon shows its card on the right.

Files: `pause_menu.gd`, `character_sheet.gd` (most of it moves here).

### 4.4 Text rules and the test

- Body text at least 22 px, labels at least 18 px, at the 720p base. Nothing smaller anywhere
  an item is described.
- At most 25 words on a card, counting name, effect, stack, delta and resonance lines; numbers
  count as words.
- One effect line. At most two numbers in it.
- Contrast: text at least 4.5:1 on its panel (the `RARITY_TEXT_COLORS` rule stays).

**Test** (`--card-shot`, a new bot flag): render every catalog card (items, mods, actives,
guns, level-up options) with a sample build, save a contact sheet PNG per 24 cards under
`autotest/cards/`, and write `autotest/cards/cards.csv` with id, word count, effect lines,
smallest font, height. It fails on any card over 25 words, over 1 effect line, under 18 px or
over 300 px tall, and prints `[CARDS] PASS n` or the failures. Emil reviews one contact sheet.

---

## 5. Loot pacing

### 5.1 What drops where, per floor

| Source | Today | After |
|---|---|---|
| Arena, end of wave | Pick 1 of 2 to 4 (gun, item, elite cards); the rest salvaged | **No items.** Scrap from the room's budget (section 6). 35% chance of a heart |
| First two arenas of floor 1 | Same | Pick 1 of 2 guns (the build needs guns to start) |
| Elite | Banks an item card | Scrap burst (4 x m, section 6), 20% chance of a heart. No items |
| Treasure room (1 per floor) | 1 of 3: item, gun, boon | **1 free item**, treasure pool, at least Uncommon, 60% weighted to behaviour items. From floor 3, 1 of 2 |
| Boss | 1 item | **1 of 2 items**, boss pool, at least Rare: one stat-heavy, one behaviour. Plus 30 x m scrap |
| Secret room | Carry +3, a Rare item, scrap | 50% an item (Rare or better), 50% a scrap pile (25 x m). Always 1 heart |
| Challenge room (optional) | 1 of 5 | 1 of 2, Rare or better, plus 15 x m scrap (section 11) |
| Pact room (new, optional) | | 1 of 2 Epic or Legendary for max HP (section 11) |
| Shop (1 per floor) | 3 or 4 wares | 4 wares: 3 items and 1 gun or gun mod |
| Level-ups | About 1 per arena (3 to 4 a floor) | About 2 per floor (raise `Player.XP_BASE`), 3 cards each |

Hearts heal 12% of max health, are a chosen heal (outside the Mending reserve) and fly to you
when the room is cleared, like scrap does now.

### 5.2 Targets per floor

| Measure | Target | Today (run 6980a749) |
|---|---|---|
| Free items | 2 (treasure, boss), up to 4 with optional rooms | 6 on floor 1, 6 on floor 2 |
| Bought items | 1 to 3 | 2 to 3, rerolled for |
| Items gained in all | 3 to 6 | 10 on floor 1 (with guns) |
| Guns gained | 2 on floor 1, then 0 to 1 a floor; 4 guns by the end of floor 2, 6 by floor 4 | 4 on floor 1 |
| Cards shown, all screens | At most 15 | About 35 on floor 1, 50 on floor 2 |
| Run total | About 22 to 28 items, 6 guns | |

Files: `room.gd` (`_arena_reward` reduced to the floor-1 gun picks; `banked` and spoils go),
`enemy.gd` (elite drops), `floor_gen.gd` (`_stock_rooms`), `drops.gd`, `items.gd` (pools),
`levelup.gd` / `player.gd` (XP curve), `pedestal.gd` (hearts).

---

## 6. Economy and shop

### 6.1 Income: a budget per room, not per kill

Depth multiplier `m = 1 + 0.25 x (floor - 1)`: 1.0, 1.25, 1.5, 1.75, 2.0.

| Source | Scrap |
|---|---|
| Arena | 20 x m per room. 70% split over its kills in proportion to each enemy's share of the room's spawned health; the last 30% drops as the wave-end burst. More enemies means less per kill |
| Elite | 4 x m each, at most 3 elites paid per room |
| Boss | 30 x m |
| Secret pile | 25 x m (half the secrets) |
| Challenge room | 15 x m |
| Scrap gain items | +10% a copy (Scrap Magnet), total capped at +50% |

A floor of 5 arenas, about 6 elites, the boss and a secret pays about **165 x m**: about 165 on
floor 1, 250 on floor 3, 330 on floor 5. Today a strong build had 2,508 when it reached the
floor-2 shop.

`Enemy.STATS[kind][5]` stops being scrap; `Room._drop_scrap` reads the room budget. The crowd
target's build factor is capped at x1.6 (today about x2.5 for six guns and four elements); the
horde stays, it just doesn't pay more.

### 6.2 Prices

| Ware | Floor 1 | Floor 3 | Floor 5 |
|---|---|---|---|
| Common | 25 | 38 | 50 |
| Uncommon | 40 | 60 | 80 |
| Rare | 65 | 98 | 130 |
| Epic | 100 | 150 | 200 |
| Legendary | 150 | 225 | 300 |
| Gun | (20 + 10 x weight) x m: 30 to 60 on floor 1 | | |
| Repair (40% health) | 30 x m | | |
| Carry | 40 x m | | |
| Gunsmith | 45 x m | | |

So a floor's income buys about 3 average items, or 1 Epic and a repair. Buying a Legendary on
floor 3 costs nearly the whole floor.

### 6.3 Rerolls and locks

- **Reroll:** `(8 + 6 x n) x m`, where n is rerolls already made in this visit: 8, 14, 20, 26,
  32 on floor 1; 12, 21, 30, 39 on floor 3. Resets at the next shop. Four rerolls cost about
  one Rare.
- **Lock:** each ware has a lock (gamepad: Y while focused; keyboard: R, or a click on the lock
  icon). A locked ware stays through rerolls and is waiting in the next floor's shop, at that
  floor's price. Unlimited locks, up to the 4 wares.
- The lock button and reroll price are on the shop's short labels, so you see them without
  opening a card.

### 6.4 Rarity odds

Explicit per floor, not a growth formula. Shop item wares:

| Floor | Common | Uncommon | Rare | Epic | Legendary |
|---|---|---|---|---|---|
| 1 | 60% | 30% | 9% | 1% | 0% |
| 2 | 45% | 35% | 15% | 4% | 1% |
| 3 | 30% | 38% | 22% | 8% | 2% |
| 4 | 20% | 35% | 28% | 13% | 4% |
| 5 | 12% | 30% | 33% | 18% | 7% |

Luck multiplies the Rare, Epic and Legendary weights by `1 + luck` (luck capped at +60%).
Treasure rooms never roll Common; bosses never roll under Rare; Legendary in treasure is 4, 6,
9, 12, 15% by floor. `Items.RARITY_ODDS` and `rarity_chance` are replaced by these tables;
Shrine unlocks still cap the top rarity.

**Why rerolling for a Legendary stops paying:** on floor 3, three item wares show a
Legendary with about 6% chance per reroll. Ten rerolls cost about 525 scrap, twice the floor's
income, for a 45% chance. Rerolling once or twice for a specific need stays a good move.

### 6.5 Targets

- **Spent down:** at 70% or more of shop visits, the scrap left when you walk out is less than
  the cheapest ware still for sale (you bought what you could).
- **Average leftover:** the median leftover per visit stays under **45 x m** (one Uncommon at
  that depth). Why: one item's worth of savings is a real plan (lock something, save, buy it
  next floor); more than that means money has stopped being scarce. Run 6980a749 left with
  288, 1,671 and 749 scrap against items of 33 to 286.
- **Rerolls:** median at most 3 per visit.

Files: `floor_gen.gd` (`reroll_price`, `gun_price`, `roll_ware`, `_stock_rooms`), `items.gd`
(`price`, odds), `room.gd` (scrap budget, crowd cap), `main.gd` (`add_scrap` cap),
`pedestal.gd` (lock), `telemetry.gd` (new `shop_leave` event, section 13).

---

## 7. Dash

| Property | Value |
|---|---|
| Distance | 120 px in 0.15 s (800 px/s; base walk speed is 320 px/s) |
| Invulnerable | 0.20 s from the start (the dash plus 0.05 s) |
| Cooldown | 1.0 s, 1 charge. Items: up to 3 charges; cooldown never under 0.5 s |
| Direction | The move stick or WASD; with no move input, the aim direction; else facing |
| Collision | Through enemy bodies and enemy shots; not through walls, obstacles or closed doors. Floor hazards don't tick during the window |
| Guns | Keep firing during the dash |
| Gamepad | **RB** (right bumper; the thumbs stay on both sticks). LB is vent, RT fire, A interact, X active, Y swap |
| Keyboard and mouse | **Shift** or the **right mouse button**. Space stays vent |
| Rebinding | Listed in Options with the other bindings |

**Perfect dodge:** an enemy hit that lands during the invulnerable window counts as a dodge:
a soft chime, "Dodged" over the figure, and the `perfect_dodge` item event. It heals 3% of max
health from the Mending reserve.

**Visuals:** three afterimages of the figure in the player colour (40%, 25%, 10% alpha, 0.2 s),
a dust puff at the start, a stretch along the direction, a whoosh. A thin white rim on the
figure while invulnerable, never red (red is the hostile signature). A small arc under the
feet shows the cooldown only while it recharges; the HUD shows dash pips beside the vent gauge.
No screen shake.

**Item hooks:** `Items.fire` gets `dash` and `perfect_dodge` events. Dash items: Slipstream
Boots, Shoulder Charge, Second Wind, Pressure Kick, Close Shave and the Monocle (section 3.2).
The Swift resonance adds a charge (section 12). The dodge stat stays, capped at 40%.

**Bots:** the kite bot dashes when a hostile shot or ring is predicted to hit it within 0.25 s
and its dash is ready, so bot numbers stay close to a human mover. `--idle` never dashes.
**Tutorial:** one prompt in the first room ("RB: dash through danger"), dismissed after the
first dash.

Files: `player.gd` (`dash`, invulnerability, charges, `_physics_process`), `player_input.gd`
(the `dash` action), `items.gd` (events), `hud.gd` (pips), `fx.gd` (afterimages, dust),
`sfx.gd`, `tutorial.gd`, `options_menu.gd`, `main.gd` (bot dash).

---

## 8. Threats that force movement

Every one uses the hostile signature (black outline, red rim, drawn above player effects;
`hostile.gd`) and a telegraph. **The test: a strong build parked in the middle of the room
dies by the end of floor 3** (section 13).

| Threat | First appears | How it works | Telegraph | Damage (share of a 100 HP bar, before `FLOOR_DAMAGE`) |
|---|---|---|---|---|
| **Lobber** (new enemy) | Floor 1, difficulty 4 | Hangs back at 350 to 450 px; every 2.4 s lobs a shell at where you stand now | A ring at the landing spot for the whole 1.1 s flight, filling in | 10%, 48 px burst |
| **Charger** (moved earlier) | Floor 1, difficulty 5 | Winds up, then charges 500 px at 600 px/s along a fixed line; stunned 1 s if it hits a wall | A red line along the path for 0.6 s | 15% |
| **Ring swarm** | Floor 2 | 8 to 12 swarmers spawn as a ring 260 px around you and close in together, every 15 s or so | The ring telegraph (0.75 s); one 60 degree gap is lit as the way out | 4% per contact |
| **Ground swell** (room rule) | Floor 2, difficulty 7 | If you stay within 80 px of one spot for 3 s in a fight, the floor there erupts and leaves a 4 s hazard patch in the region's element | A rumble at 2 s, then a ring for 1.2 s | 10%, then 3% per 0.5 s on the patch |
| **Sower elite** (affix) | Floor 2 | Drops 3 denial circles (70 px) round itself every 4 s, lasting 5 s | Circles fill in over 0.8 s | 5% per 0.5 s |
| **Mortar elite** (affix) | Floor 3 | Lobs 3 shells at once, around where you stand | Rings as the lobber | 10% each |
| **Tether elite** (affix) | Floor 3 | If you stay within 300 px of it for 2 s, a beam links you and drains you until you break range or line of sight | The beam grows from the elite for 1 s first | 3% a second |
| **Room hazards** | Floor 2, one per arena | Region set pieces: steam vents (Rust Ruins), falling icicles (Frostvault), sweeping flame jets (the Forge), void rifts (the Rift), and so on | At least 1 s, with the hostile ring | 8 to 12% |

**Changes to what exists:**
- Spitter hits rise from about 5% to 8% from floor 3, with 20% fewer spitters, so a hit
  matters and regen can't quietly erase it. The lob moves from difficulty 14 to 8.
- Runners lunge 120 px when within 160 px (0.35 s crouch first). Melee no longer only walks
  down the gun line.
- The floor-1 arenas stay gentle: lobbers and chargers only from the third arena.

**Fairness rules** (each one checked in the bot logs):
- Nothing spawns within 140 px of a player.
- Every damaging area shows its ring at least 0.6 s before it can hurt.
- At most 2 hostile rings over a player at once; a third waits.
- Ground swell never starts in a room's first 3 s or within 1.5 s after a dash.
- The burst guard stays (0.25 of max health in 3 s under half health).
- Killing a lobber or mortar elite cancels its shells and rings, as the spitter's lob does.

Files: `enemy.gd` (lobber, charger timing, runner lunge, new affixes), `spawn_table.gd` (kinds,
weights, affixes, `DEEP_AFFIXES`), `room.gd` (ground swell, ring swarm, hazards, spawn
distance), `enemy_projectile.gd` (shells), `materials.gd` (hazard patches), `regions.gd` (which
hazard per region), `hostile.gd`, `danger_fx.gd`.

---

## 9. Power curve

**Par damage per second** a decent build has at each floor (from Emil's run, a strong build, at
160, 415 and about 1,070 on floors 1 to 3; par sits below it):

| Floor | 1 | 2 | 3 | 4 | 5 |
|---|---|---|---|---|---|
| Par dps `E(f)` | 150 | 350 | 700 | 1,100 | 1,600 |
| Floor health multiplier `F(f)` | 1.0 | 1.3 | 1.8 | 2.4 | 3.0 |

**Enemy health** = today's `base + per_diff x difficulty`, times `F(f)`, times the build factor
`B = clamp(sqrt(P / E(f)), 0.8, 2.0)`. P is the **measured** damage per second of the floor's
last three arenas (`Main.floor_arena_dps`); the first arena of a floor uses the last floor's P
scaled by `E(f) / E(f-1)`. This replaces `Room.party_power`'s estimate from carried guns.

The square root is deliberate. A build at 4x par meets enemies with 2x health, so it still kills
twice as fast as par. **A broken build must feel broken**; it just can't make the game stop.
The rest of the push comes from section 8: threats that make you move, not health that makes
you wait.

**Elites:** at least 5 s of P (today 2 s). Human target: median 8 to 15 s, long enough for the
affix to matter. **Bosses:** at least 35 s of P on **every** floor, floor 1 included (today
30 s from floor 2), at most `BOSS_HP_MAX_MULT` 9x the formula. Target for real players: 25 to
50 s, checked from the `boss` telemetry event (`secs`).

**Diminishing returns on stacked reaction power:**
- Reaction power bonus (the sum of `potency` and `potency_<el>`) counts in full up to +50%, at
  half from +50% to +150%, at a quarter beyond. +100% becomes +75%; +250% becomes +125%.
  Applied in `Gun` where `s.potency` is built.
- The same enemy reacting again within 1 s: the 2nd reaction at x0.75, the 3rd at x0.56, never
  under x0.4 (`Elements.try_react`). Fusions keep their room-wide repeat decay.
- Target: reactions, fusions and their damage over time make 50 to 65% of the damage of a
  reaction build, down from about 75%. The reaction game still carries the build.

Files: `room.gd` (`party_power`, crowd cap, elite and boss sizing: `BOSS_DPS_SECS`),
`enemy.gd` (health), `main.gd` (`floor_arena_dps`), `gun.gd` (potency), `elements.gd`
(per-target decay). **`room.gd` and `enemy.gd` have the boss session's uncommitted edits
today; session 1 starts after that work is committed.**

---

## 10. Healing

**A Mending reserve per floor, visible.** Each floor starts with a reserve of 40% of max health
(+10% per Bandage Roll). Every passive heal draws on it: regen, Leech, item and fusion heals,
the perfect-dodge heal. When it's empty, passive healing stops until the next floor. The HUD
shows it as a thin green bar under the health bar, draining as it's used. This replaces the
per-fight fade (`MEND_SOFT`), which Emil couldn't see and which refilled every fight.

**Chosen heals** stay outside the reserve: hearts (12%), the shop's repair (40% for 30 x m),
the stairs, actives (Blood Chalice) and Last Breath.

**Healing that rewards risk:**
- Leech only counts reactions on enemies within 200 px of you.
- A perfect dodge heals 3% (from the reserve).
- An elite killed while you're under 50% health always drops a heart.

**Budget per floor**, for a mover with a healing build: reserve 0.4 to 0.6 of a bar, hearts
about 0.25, a repair 0.4 if bought, stairs about 0.1: about 1.0 to 1.3 bars. Damage taken by a
mover on floors 3 to 5 should be 1.4 to 1.8 bars a floor, so health drifts down across a floor
and the shop's repair is a real purchase.

Targets: from floor 3, healing at most 0.75x damage over a floor; time under 50% at least 0.15;
at least 1 close call a floor from floor 3 (all for a mover; section 13).

Files: `player.gd` (`heal`, `mend_rate`, `_tick_mending`, regen, `on_reaction`), `hud.gd`
(reserve bar), `pressure_meter.gd` (reserve used), `main.gd` (refill at floor start).

---

## 11. Reasons to keep going

**Choices with stakes:**

| Room or offer | When | Deal |
|---|---|---|
| **Pact room** | From floor 2, 40% chance a floor, a door off the boss room | 1 of 2 Epic or Legendary items for 15 or 25 max HP. Never takes you under 40 max HP |
| **Cursed pedestal** | Treasure rooms from floor 2, 25% chance | A second pedestal one rarity higher, with a curse for the rest of the floor: Darkness (sight radius halved), Frailty (+25% damage taken), Greed (no hearts), or Haste (enemies +15% speed). You take one pedestal; the other vanishes |
| **Challenge room** | Optional, as today | Doors lock, two elite waves; 1 of 2 Rare or better plus 15 x m scrap |
| **Mystery ware** | Shops from floor 2, 30% chance, in place of a ware | 60 x m for a random item one rarity above the floor's median |

**Visible milestones:** resonances at 3 and 5 items of a tag (section 12); gun tier-ups
(merging a copy); and a **floor-end card** on the stairs: damage per second now against the
floor before ("x2.4"), items gained, resonances formed, Embers so far, and what the next floor
holds ("a boss item, a treasure room, a shop, +3 Embers for reaching it").

**Embers on quit:** leaving a run from the pause menu counts as a death. "Return to hub" calls
`Main._end_run(false)` with `abandoned = true` before the deferred scene change; it pays the
death award (rooms, elites, discoveries, fusions, bosses, floors). Run 6980a749 would have paid
about 50 instead of 0. Telemetry records `embers` on abandoned runs.

Files: `floor_gen.gd` (pact room, cursed pedestal, mystery ware), `room_data.gd` (room type),
`room.gd`, `pedestal.gd` (paired pedestals), `main.gd` (`_end_run`, floor-end card),
`pause_menu.gd`, `mastery.gd`, `telemetry.gd`, `hud.gd` (curse icon).

---

## 12. The broken-run moment

**Synergies are data.** `Items.SYNERGIES`: a list of `{ id, name, needs: [item ids or tags],
line, effect }`, about 20 at launch. Examples:

| Synergy | Needs | What changes |
|---|---|---|
| Hunting Shards | Seeker Lens + Splinter Charm | Shards home too |
| Reaper's Return | Mother's Blade + Grip of Pierce | Boomerangs pierce everything on the way back |
| Living Orbit | Bone Orbit + any Vial | Orbitals apply the vial's element |
| Wake of Ruin | Slipstream Boots + Reaction Trail | The dash trail reacts with what it touches |
| Storm Lattice | Wide Arc + Fork | Chains fork at every jump |
| Pinball | Ricochet Gloves + Gravity Shot | Bounces seek the nearest pull |

**When a synergy forms:**
- a banner in the top band of the screen: "SYNERGY: Hunting Shards", with the line under it
  ("Your shards now hunt"), 28 px and 22 px, for 2 s;
- a 0.08 s hit-stop, a rising chord, a flash on the figure;
- the change is visible at once: the shots get the new look (homing shards get a tail);
- the build page lists it, and the floor-end card shows its share of damage.

**Resonances** (3 and 5 items of a tag) are the bigger moment: 0.4 s at half speed, the banner,
an aura in the tag colour, a look change on the figure (`worn_gear.gd`), and a chip on the HUD.
Examples at 3: Vent (vent cooldown -30%, radius +25%), Guard (+3 armour, the first hit each
room halved), Gunslinger (+1 projectile on your first gun), Seeker (all shots home lightly),
Alchemy (element states last 40% longer), Swift (+1 dash charge), Fortune (a 5th shop ware),
any element (+25% reaction power for it, and your shots carry its glow). At 5, each doubles
and adds a visual tier.

**Clarity rules:**
- Banners only in the top band, never in the middle half of the screen.
- At most one banner per 8 s; others queue. None while the burst guard is active.
- Slow motion only for resonances, never while a hostile ring is within 200 px of you.
- Player effects stay under the hostile layer and under the clarity pass's brightness caps.

Files: `items.gd` (synergy and resonance data, detection on pickup), `player.gd`, `hud.gd`
(banner, chips), `fx.gd`, `sfx.gd`, `worn_gear.gd`, `gun.gd` / `projectile.gd` (looks).

---

## 13. Tests that judge by human play

### 13.1 Bots that play like the people who'll play it

- **Human-strength build.** New flag `--build=human6980`: Emil's guns, tiers, items, gun mods
  and level-up picks at the end of floor 2 of run 6980a749, read from its `floor_end` and
  `levelup` events (mapped to new ids after session 3). The storm build is kept for
  comparison, but it took 2.0 bars a minute parked on floor 3 where Emil took 1.06, so it
  isn't the bar to beat.
- **Stand-still bot:** `--idle` (never moves, never dashes) with the human build and
  `--mastery=full`, run from floor 1 on the default route.
- **Mover:** the kite bot with the dash (section 7), same build and Shrine.

### 13.2 The checks

| Check | How | Pass |
|---|---|---|
| **Stand-still dies** | 4 idle runs, human build, full Shrine | All 4 die by the end of floor 3. On floor 2, at least 0.3 of fight time under 50% health |
| **Mover survives, under pressure** | 4 kite runs, same | At least 3 of 4 reach floor 4. From floor 3: time under 50% at least 0.10 and healing at most 0.75x damage |
| **Pressure, still against moving** | `[PRESSURE]` per floor for both | Idle takes at least 2x the mover's damage per minute on floors 2 and 3 |
| **Shop spend** | New `shop_leave` telemetry event: scrap in, spent, left, cheapest unbought ware, rerolls | At least 70% of visits leave with less than the cheapest ware; median leftover under 45 x m; median rerolls at most 3 |
| **Loot count** | New `floor_loot` event per floor: items free and bought, guns, cards shown | Free 2 to 4, bought 1 to 3, cards shown at most 15 |
| **Card readability** | `--card-shot` (section 4.4) | `[CARDS] PASS`; Emil reads one contact sheet |
| **Bosses and elites** | `boss` and `elite` events, bots and Emil | Bots: bosses 25 to 60 s. Emil's next runs: 25 to 50 s, elites 8 to 15 s median |
| **Fairness** | Bot logs | 0 spawns within 140 px, 0 hostile damage without a 0.6 s telegraph, worst 3 s outside boss contact at most 0.5 of max health |
| **Old rule** | The idle six-gun bot in the first region (GDD section 0) | Still dies |

`tools/pressure_report.py` gets a `--shops` and a `--loot` view so Emil's runs report the same
numbers. Every session also runs the standard checks in the GDD's section 0: load check, bot
runs with 0 `SCRIPT ERROR`, and `tools/exe_smoke.sh` ending in `[SMOKE] ALL PASS` before
any push, then the CI "Windows release" run.

---

## 14. Build order and session briefs

Order by fun gained: the fight first (every second of play), then the economy (every shop and
every room's reward), then the items and cards (the biggest change, easiest once loot is
scarce), then the moments. Each session is a fresh session, starts from this document, and
leaves its numbers in a hand-over section here. At most 4 Godot instances at once.

**Before session 1:** the boss session (`sd-boss-presence`) has uncommitted edits in `room.gd`,
`enemy.gd`, `player.gd`, `hud.gd`, `main.gd` and others. Session 1 starts only once that work is
committed.

### Session 1: Fight (dash, threats, healing reserve, power curve)

Goal: standing still kills, moving feels great, a broken build still melts things but never
ends the danger.
- Dash (section 7) with bot dashing and the tutorial prompt.
- Lobber, earlier chargers, runner lunge, ring swarms, ground swell, Sower, Mortar and Tether
  affixes, one hazard per region from floor 2 (section 8).
- Mending reserve per floor with its HUD bar; Leech within 200 px; hearts as a pickup (dropped
  from elites at 20% and arenas at 35% for now; session 2 settles the loot table).
- Power curve: `E(f)`, `F(f)`, measured build factor, elites 5 s, bosses 35 s on every floor,
  reaction diminishing returns (section 9).
- `--build=human6980` with today's item ids.
- Files: `player.gd`, `player_input.gd`, `enemy.gd`, `spawn_table.gd`, `room.gd`,
  `enemy_projectile.gd`, `materials.gd`, `regions.gd`, `gun.gd`, `elements.gd`, `hud.gd`,
  `fx.gd`, `sfx.gd`, `tutorial.gd`, `options_menu.gd`, `main.gd`, `pressure_meter.gd`.
- Done when: the stand-still, mover, pressure, boss and fairness checks in 13.2 pass; the idle
  six-gun bot still dies in the first region; `[SMOKE] ALL PASS`; CI green.
- Out of scope: loot, prices, item catalog.

### Session 2: Loot and economy

Goal: every room's reward and every shop visit is a decision; money is tight at any power.
- Remove spoils and elite item banking; floor-1 gun picks; treasure, boss, secret and
  challenge drops as in section 5.1; level-ups about 2 a floor.
- Scrap budget per room, crowd build factor capped at x1.6, scrap gain cap (section 6.1).
- Prices, reroll formula, locks carried to the next shop, explicit rarity tables, mystery ware
  (sections 6.2 to 6.4, 11).
- Quitting pays Embers like a death (section 11).
- `shop_leave` and `floor_loot` events; `pressure_report.py --shops --loot`.
- Files: `room.gd`, `floor_gen.gd`, `items.gd` (price and odds only), `drops.gd`, `enemy.gd`
  (elite drops), `main.gd`, `pedestal.gd`, `levelup.gd`, `player.gd` (XP), `pause_menu.gd`,
  `mastery.gd`, `telemetry.gd`, `tools/pressure_report.py`.
- Done when: the shop-spend and loot-count checks pass on 4 kite runs with the human build;
  quitting on floor 2 pays the death award; `[SMOKE] ALL PASS`; CI green.
- Out of scope: the catalog and the card.

### Session 3: Items without slots and readability

Goal: every item reads in one glance and simply adds to your build.
- Inventory as id -> count; `stack` rules, caps, percentage armour; tags; `LEGACY_IDS` and the
  catalog migration of section 3.2, including the 20 new behaviour items and the dash and
  perfect-dodge events.
- The item card, pedestal glow and labels, the pause Build tab (section 4).
- `--card-shot` and the card check.
- Save version 5 with the relic and Well migration and its test (section 3.3); bot builds and
  `--build=human6980` mapped to new ids.
- Files: `items.gd`, `player.gd`, `item_card.gd`, `pedestal.gd`, `levelup_screen.gd`,
  `character_sheet.gd`, `pause_menu.gd`, `hud.gd`, `worn_gear.gd`, `drops.gd`, `progress.gd`,
  `loadout.gd`, `journal.gd`, `hub.gd`, `well_screen.gd`, `main.gd` (bot builds).
- Done when: `[CARDS] PASS`; a version-4 save loads with every old relic; the stand-still and
  mover checks from session 1 still pass; `[SMOKE] ALL PASS`; CI green.
- Out of scope: synergies and resonance effects (tags are counted, bonuses come in session 4).

### Session 4: Broken runs and risk

Goal: the run has peaks you remember and choices with stakes.
- Synergy data and detection, about 20 synergies; resonance bonuses at 3 and 5 with looks
  (section 12).
- Pact room, cursed pedestal (section 11).
- The floor-end card.
- Files: `items.gd`, `player.gd`, `hud.gd`, `fx.gd`, `sfx.gd`, `worn_gear.gd`, `gun.gd`,
  `projectile.gd`, `floor_gen.gd`, `room_data.gd`, `room.gd`, `pedestal.gd`, `main.gd`.
- Done when: every synergy fires once in a `--synergy-probe` (new flag: grant the pair, fight
  one arena, print `[SYNERGY] name ok`); banners obey the clarity rules in a `--read-shot`
  screenshot; all earlier checks still pass; `[SMOKE] ALL PASS`; CI green.

---

## 15. Defaults Emil may want to change

| Default | Alternative |
|---|---|
| One held active item | No actives at all, or actives as a second "gun" slot |
| Level-ups stay, about 2 a floor | Remove them and let items carry all stats (pure Isaac), or keep one a wave (Brotato) |
| Ground swell punishes standing 3 s in one spot | Only enemies punish standing still |
| Dash: 120 px, 0.2 s invulnerable, 1.0 s cooldown, RB / Shift | Shorter window (0.15 s), or a roll on LB with vent moved |
| Armour as a percentage, 15 / (15 + armour) | Keep flat armour with a cap |
| Leech only within 200 px | Leech anywhere, smaller |
| Quitting pays the full death award | A penalty (say 75%), so finishing a floor is worth it |
| Sets become tags and resonances | Keep named sets with their own bonuses |
| Mending reserve 40% a floor | 30% (harsher) or 50% (gentler) |

## Appendix: where the numbers come from

- Run 6980a749: `%APPDATA%/Godot/app_userdata/Pressure/telemetry/runs.jsonl`, events
  `pressure`, `damage_dealt`, `damage_taken`, `shop_view`, `purchase`, `reroll`, `spoils`,
  `levelup`, `boss`, `elite`, `floor_end`, `run_end`. Damage per second is total damage over
  the `pressure` event's `fight` seconds. Cards shown counts spoils, treasure, challenge,
  shop and level-up offers.
- The idle probe: two headless runs, `--autotest --one-floor --secs=420 --idle --build=storm
  --start-floor=3 --route=ossuary_gate,rust_ruins,frostvault --mastery=full`, instances 71 and
  72, on 2026-11-10 with the boss session's uncommitted edits in the tree. Both died on floor 3;
  `[PRESSURE]` lt50 0.78 and 0.71, damage 2.11 and 2.00 a minute, healing 1.57 and 1.65.
- The item counts: `_add` calls in `items.gd` (166) plus the 6 generated families (72).
- Code facts: `items.gd`, `floor_gen.gd`, `room.gd`, `enemy.gd`, `spawn_table.gd`,
  `player.gd`, `player_input.gd`, `item_card.gd`, `pause_menu.gd`, `telemetry.gd` at `fe8877a`.
