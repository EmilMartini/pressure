# World structure references for Pressure (research notes)

Method note: web search returned many SEO and aggregator pages. Claims below are tagged **[V]** (verified on a fetched page or search result I cite), **[S]** (single weak/community source), or **[U]** (from my background knowledge, no source fetched; verify before putting in the GDD). Several sub-questions had no usable search results (Gungeon, Inscryption, Divinity: Original Sin 2, Monster Hunter, Elden Ring legacy-dungeon commentary, Hades NPC reactivity, Returnal shortcut specifics). Those are flagged as gaps rather than filled with guesses.

---

## 1. Run length and structure

| Game | Typical full run | Regions per run | Time to first win / total | Source |
|---|---|---|---|---|
| Hades | Skilled run can be under 1 hour (forum comment); typical "20-30 runs" before first escape (forum players) | 4 main areas, each ending in a boss | Main story about 15-22 h (HLTB-derived) | https://www.thegamer.com/hades-game-length/ , https://twinfinite.net/guides/how-long-hades-takes-to-beat/ , search result summary of https://steamcommunity.com/app/1145350/discussions/0/600767061860353731 **[S]** |
| Hades II | Kotaku review: one successful run ~30 min; guides: 30-60 min | 4 regions per route (Underworld ending at Chronos in Tartarus, or Surface ending at Typhon) | Main story 15-25 h; HLTB range 8-22 h | https://kotaku.com/hades-ii-the-kotaku-review-2000628064 , https://space4games.com/en/games-en/hades-2-playtime-how-many-hours-youll-spend-in-the-dark-roguelike/ , https://www.spieltimes.io/news/hades-2-how-long-to-beat/ |
| Dead Cells | Not stated by any fetched source **[gap]** | Route is a chain of about 11 stages (my inference from the wiki's stage headings, not stated) out of 24 main + 12 boss biomes (base 15 main + 4 boss; DLC adds 9 main + 8 boss) | n/a | https://deadcells.wiki.gg/wiki/Biome |
| Binding of Isaac: Rebirth | Community split list: Mom at ~18 min; Boss Rush clock 20 min | 6 floors for first clear, rising to 8-10+ later; one review says 8-13 | HLTB-style: 5.5 h main, 97 h main+extras, 377.5 h completionist | https://www.gog.com/en/game/the_binding_of_isaac_rebirth?page=9 , https://gamedo-live.pages.dev/news/should-i-play-binding-of-isaac **[S]** |
| Enter the Gungeon | Gap: no usable result | Gap | Gap | none |
| Risk of Rain 2 | Clear = 20 stages in one run, then endless looping; no fixed ending | 5 stage "slots" per loop, stages repeat on loops (loop count is my knowledge **[U]**) | HLTB-derived: main ~11 h (one stage-20 clear is not what this measures; treat as aggregate playtime), main+extras ~44.5 h, completionist 145-150 h | https://www.dekudeals.com/items/risk-of-rain-2 , https://platprices.com/en-sk/game/401-risk-of-rain-2 |
| Returnal | Reviewers: runs near the end are "almost always at least about two hours"; one source says up to 4 h | 6 biomes in two groups of three (Act 1 = first trio, Acts 2-3 = second trio) | Full playthrough 10-30 h; author's ~20 h | https://www.inverse.com/gaming/returnal-game-length-how-long-to-beat-how-many-biomes-acts , https://www.gamepressure.com/returnal/game-length/z3e635 |
| Halls of Torment | Developer showcase text: runs last a maximum of 30 minutes, ending at a "tormented lord" boss | One map per run (map choice, not stage chain) **[U]** | n/a | https://godotengine.org/showcase/halls-of-torment/ |
| Brotato | 20 waves; combat time totals 1,050 s (17.5 min) from wave table; full run with shop ~25-30 min | 1 arena, 20 waves; wave 20 is the boss wave | n/a | https://brotato.wiki.spellsandguns.com/Waves (wave durations: 20 s rising by 5 s per wave to 60 s at wave 9-19, 90 s at wave 20); run time: https://earlyguides.pages.dev/brotato **[S]** |
| Vampire Survivors | Stage completes at 30 minutes | 1 stage per run | ~40 characters, ~15 secret (count varies) | https://www.tuni.fi/playlab/objective-survive-vampire-survivors , https://ggrecon.com/guides/vampire-survivors-secret-unlocks-characters-weapons-arcana-levels **[S]** |
| Slay the Spire | Anecdotal 45 min to several hours; one analysis blog says "at most one hour per run" for experienced players | 3 acts x 15 floors (+ optional Act 4 with 3 keys) | n/a | https://slaythespire.info/?p=3940 , https://www.hermitgamer.com/how-many-acts-in-slay-the-spire **[S]** |

**Why Risk of Rain 2 runs get long (verified part):** The game has no hard ending. Winning means 20 stages, after which the run loops with rising difficulty until death or voluntary end (Deku Deals/Plat Prices summaries above). A forum poster claims a 100-stage run (20 loops) **[S]**. The mechanism (time-based difficulty clock, scaling via stage count, optional "obliterate" ending) is from my knowledge **[U]**; the implication for Pressure is that the run's end condition, not its content volume, controls duration.

**Pattern across the genre:** the games that ship ~30-60 minute runs (Hades II ~30 min, Halls of Torment 30 min cap, Brotato ~25-30 min, Vampire Survivors 30 min) are all near Pressure's current 42 minutes. The 2-hour+ runs (Returnal, RoR2) are the ones the designer wants to avoid. Dead Cells and Hades are the existence proofs of large content volume (36 biomes, many weapons/areas) served through ~short runs.

---

## 2. Branching and world structure

**Dead Cells (verified from wiki)** https://deadcells.wiki.gg/wiki/Biome
- 15 main + 4 boss biomes in the base game; DLC adds 9 main + 8 boss, for 24 main + 12 boss total (page figures; the 36 is a sum).
- "Only one biome per level can be accessed in a run, so routes vary between runs." The run is a chain of stages with two or three branches at several points.
- Route graph from the first stage: Prisoners' Quarters -> Promenade of the Condemned (no rune needed) or Toxic Sewers (Vine Rune). From Promenade: Ramparts (default), Prison Depths (Spider Rune), Ossuary (Teleportation Rune), Morass of the Banished (Teleportation Rune, DLC). From Toxic Sewers: Ramparts, Corrupted Prison (Spider Rune), Ancient Sewers (Ram Rune).
- Boss Stem Cell (BSC) gates: Ancient Sewers needs 1+ BSC from Prison Depths; Ramparts from Corrupted Prison needs 1+ BSC; Insufferable Crypt needs 3+ BSC from Ramparts; Cavern needs 2+ BSC plus killing the Giant.
- Runes are permanent traversal abilities found in the world that open new routes in all future runs: https://deadcells.wiki.gg/wiki/Runes (summary of rune list; also https://earlyguides.pages.dev/dead-cells **[S]**). This is the closest genre match to "physical, persistent shortcut/route unlock."
- Boss cells: difficulty modifiers unlocked by beating the final boss; BC0 is normal, with higher cells up to BC5 for the final boss tier (https://earlyguides.pages.dev/dead-cells **[S]**; exact current maximum not verified).
- Timed doors reward speed: limits range 2 min (early biomes) to 26 min (later biomes) per the same wiki page.

**Returnal**
- 6 biomes, in two groups of three; "a path where you can swap between two sets of biomes, so you can do all six in one run" (search summary of https://allthings.how/?p=589 **[S]**; Inverse for 6 biomes).
- Persistence is light: quicker access to certain biomes (shortcuts), weapon traits, a few abilities, ether currency (search summary; sources include Softpedia/Push Square reviews, https://www.pushsquare.com/reviews/ps5/returnal ). Almost everything else is lost on death.
- Returnal has a logbook of enemies/items/lore (Inverse above). Housemarque later hinted at a save system (https://www.gfinityesports.com/Returnal/housemarque-hints-at-returnal-save-game-system-update/), which shows the cost of a 2 h run.

**Hades II two routes**
- Underworld (ends at Chronos in Tartarus) and Surface (ends at Typhon, after an incantation setup) share the same 4-region-per-route pattern; Surface is widely described as harder (https://www.gfinityesports.com/article/hades-2-supergiant-games-may-have-made-the-surface-route-too-difficult).
- The Oath of the Unseen is the difficulty system (like Heat in Hades), unlocked after first defeating Chronos, each boss has a "Fear" value (https://mobalytics.gg/hades-2/guides/oath-of-the-unseen , https://www.GameSpot.com/gallery/hades-2-nightmare-oath-of-unseen-testaments-guide/2900-5392/).
- Design relevance: two routes of equal length, one world, shared hub, different enemy sets. Cheap way to double content without lengthening any run.

**Slay the Spire:** 15 floors per act on a branching map (see table). Map as a visible graph of choices that changes risk/reward (hermitgamer link above **[S]**).

**Inscryption / genre-benders:** gap, no usable source. From memory **[U]**: Inscryption splits one run structure into three "acts" with different rules and a framing story. I would not cite it without checking.

**How each makes a run feel like part of a larger world (synthesis, partly my inference):**
1. Dead Cells: the same map graph exists permanently; each run is one path through it, and runes/BSCs let you reach branches that were closed. The unvisited biomes are visible through the passages.
2. Returnal: lore/logbook, biome-order shortcuts.
3. Hades II: same hub and cast, two destinations.

---

## 3. Dark Souls shortcut design

**What is verified**
- Article analysis (TheGamer, not a developer quote): "You don't find shortcuts in Dark Souls, you find how one area is connected to the other." Paths radiate out of Firelink Shrine and eventually loop back; deeper areas feel cut off; without early fast travel FromSoftware had to make the world circle back on itself; the Undead Parish elevator leads back down to Firelink and a lift leads down to New Londo. The piece quotes no FromSoftware developers. https://www.thegamer.com/dark-souls-1-fromsoftwares-magnum-opus-of-interconnected-level-design/
- Community analysis argues the design is claustrophobic and locally narrow but globally connected: you feel lost, then discover you were close to home. Critics also note that Dark Souls 2 shortcuts "didn't mean as much" because bonfire teleporting exists. https://www.thegamer.com/dark-souls-1-fromsoftwares-magnum-opus-of-interconnected-level-design/ , https://thehollower.blogspot.com/2023/11/the-interconnected-world-of-dark-souls-1.html **[S]**, https://selectbutton.net/t/fatigued-souls/4251?page=2 **[S]**
- Critical point that survives scrutiny: in DS1, fast travel arrives late (Lordran bonfire warp only after a mid-game item). Shortcuts matter because they replace travel; once warping is free they lose value. This is the central tension for Pressure.

**Gap / unverified:** no developer or critic statement about Elden Ring legacy dungeons specifically came back. From memory **[U]**: legacy dungeons (Stormveil Castle, Raya Lucaria) use one-way doors opened from the far side, ladders to kick down, elevators, and lead back to a site-of-grace within reach, with checkpoint placement just before each boss. Verify before relying on this.

**Roguelites with persistent physical shortcuts**
- Dead Cells runes (verified above): permanent, found in the world, open branches, and do not skip content (they reach different biomes, not later ones). Spider/Ram/Vine/Teleportation runes open specific edges of the graph.
- Returnal: unlocked shortcuts speed access to certain biomes (search summary, Softpedia/Push Square).
- Hades fast travel: gap. Hades 1 does not have real fast travel (the House Contractor changes the Underworld rooms and lets you swap keepsakes between regions, per https://www.trueachievements.com/game/Hades/walkthrough/4 and https://hades.wiki.fextralife.com/Artifacts search summaries **[S]**).
- Rogue Legacy 2 heirlooms: puzzle-chamber rewards that grant traversal abilities needed to access certain areas, and the Architect can lock the castle layout at a fee (he takes a share of gold) (https://www.gamepressure.com/S013-amp.asp?ID=17301 , https://ggrecon.com/guides/rogue-legacy-2-heirlooms ; fee details **[S]**). The Architect is a nice precedent for "pay to keep the map stable."

**How roguelites avoid trivialising (mostly inference):**
- Rune/heirloom shortcuts open lateral branches, not skip-to-end.
- Boss gating by stem cells/difficulty keeps the endpoint hard even with a short route.
- Returnal's shortcuts reach biomes but not their bosses.

---

## 4. Hub NPC design

**Hades (partly verified)**
- Mirror of Night: permanent talents, starts with three; each basic upgrade (red) has an alternative (yellow) version (search summaries of https://hades.gamepedia.com / Push Square guide). **[S]**
- House Contractor: unlocks new rooms in the House and in the Underworld; unlocks switching keepsakes between regions; Home Makeover achievement after 50 purchases (TrueAchievements walkthrough above). **[S]**
- Weapon aspects: each Infernal Arm has four aspects (one default, one hidden), unlocked with Titan Blood; hidden one costs 5 Titan Blood on that weapon (Fextralife Artifacts/guide search summaries; https://www.pushsquare.com/guides/hades-guide-how-to-play-and-everything-you-need-to-know). **[S]**
- Dialogue volume (verified): over 300,000 words, more than 2/3 of it dialogue text, per Kasavin email to Cultured Vultures (https://culturedvultures.com/?p=142587). GDC 2021 talk by Kasavin and Darren Korb: more than 22,000 lines of voiced dialogue (https://www.gdcvault.com/play/1026975/Breathing-Life-into-Greek-Myth). Hades II: more than 400,000 words and 30,000 voice lines, about 50% more (GamesRadar headline: https://www.gamesradar.com/games/hades/hades-2-has-an-epic-script-of-over-400-000-words-and-30-000-voice-lines-around-50-percent-more-than-the-original-roguelike). Stated motive (via search summary): the game can be played indefinitely, so avoid repeats too early. I did not find a count of reactive-to-death lines specifically. **[gap]**
- Reaction to deaths (that dialogue is conditional on death count, killer, etc.) is widely known **[U]**, no source fetched.

**Dead Cells**
- The Collector takes cells and blueprints and gives items; purchases persist. Blueprints must be delivered, now automatically at transitions since version 2.3; Scythe Claws blueprint costs 100 cells; on Hell difficulty the Collector is replaced by the Collector's Intern (https://deadcells.wiki.gg/wiki/The_Collector , https://deadcells.wiki.gg/wiki/Blueprint). The Blacksmith's Apprentice reforges and upgrades gear for gold. Hub is the Prisoners' Quarters, which doubles as the run start.

**Rogue Legacy 2 / original:** In the original, gold unlocks blacksmith, enchantress and architect, and unspent gold goes to Charon to enter the castle (search summary of https://en.wikipedia.com/wiki/Rogue_Legacy **[S]**). For RL2 the results only confirm Architect and Blacksmith behaviour; Enchantress detail is a gap.

**Firelink Shrine / Roundtable Hold:** gap. From memory **[U]**: Firelink NPCs (blacksmith, fire keeper, merchants) appear as you rescue them in the world; Roundtable Hold has Gideon Ofnir, Enia (remembrances for boss soul trades), Hewg, smithing, Sellen. These support the "the world feeds the hub" loop. Verify.

---

## 5. Halls of Torment

Verified/semi-verified:
- Run structure: horde survival until a tormented lord boss, max 30 min; progression is quest-based; items can be brought back to the overworld and used to customise future runs; early-access listing says 7+ heroes (Godot showcase, May 2023). https://godotengine.org/showcase/halls-of-torment/
- Characters: counts disagree by version: 11 vs 13 (store pages). https://www.dekudeals.com/items/halls-of-torment , https://www.gematsu.com/games/halls-of-torment **[S]**
- Marks: Mark of the Sword (Swordsman) gives +0.30/s health regeneration and access to Swordsman traits (search summary of attackofthefanboy guide, https://attackofthefanboy.com/guides/halls-of-torment-best-swordsman-traits-items-abilities-and-blessings/ **[S]**). 1,000+ traits cited by listings. https://www.dekudeals.com/items/halls-of-torment **[S]**
- Blessings: permanent boosts at the Shrine of Blessings, bought with gold, 5 ranks, unlocked after the first run. Counts range 16-25 across sources. (same search; https://commonsensegamer.com/halls-of-torment-how-the-level-up-faster-lvl-100-guide/ **[S]**)
- Well/Wellkeeper: during a run you "Retrieve" one inventory item by putting it in the well's bucket; if you die without retrieving, items are lost. Retrieved items can be bought from the Prisoner and carried in every run. Examples of unlock conditions: Spellcaster Gloves by buying one Wellkeeper item; Hunter's Garb as Archer by waiting 3 minutes without moving; Jade Amulet by 500 total level-ups across runs (https://primagames.com/tips/halls-of-torment-tips-and-tricks-for-beginners and https://commonsensegamer.com/ pages **[S]**). Blessing unlocks have character conditions (a Damage blessing: play Swordsman and take the Strength IV trait).

Interpretation for Pressure **[inference]**: HoT's "classes" are mostly a starting weapon/mark plus a trait pool; the loadout layer (retrieved items that persist, character-conditioned unlocks) sits above them. The conditional unlocks ("do a specific thing as character X") are the same shape as the death-driven unlocks the designer wants.

---

## 6. Loadouts instead of classes

- Hades: weapon (6) x aspect (4 each) + one keepsake (swappable between regions only after Contractor upgrade) + Mirror talents; see section 4 sources. Aspect unlocks are paid in Titan Blood, a resource from boss kills **[U]** for source of currency; unlock mechanic **[S]**.
- Risk of Rain 2: Skills 2.0 added loadouts so players mix survivor abilities before a run; each Survivor has challenges that unlock individual skills or skins; unlocking is per survivor; some variants are modifications of existing skills and some are unique (https://riskofrain2.wiki.gg/wiki/Early_Access_%27Skills_2.0%27_Content_Update , https://www.gamesradar.com/risk-of-rain-2-challenges). Four skill slots per survivor (primary, secondary, utility, special) **[U]**.
- Vampire Survivors: ~40 characters, ~15 secret; several unlock by 30-minute objectives (e.g., Bracelet requires surviving 30 minutes with Gallo or Divano) (sources in section 1). Characters are essentially a starting weapon plus passive stat bias.
- Halls of Torment: character + mark + retrieved items (section 5).
- Enter the Gungeon: gap (no source). Do not cite.

Common structure: unlock gate = a challenge tied to the thing being unlocked (RoR2 per-survivor challenge, VS objectives, HoT conditional unlocks), and what you pick in the hub is a small number of independent slots (weapon+aspect+keepsake in Hades; 4 skill slots in RoR2).

---

## 7. Elemental resistance and weakness per area

Mostly gaps; sources found:
- Noita: Enemy Immunities wiki. Stendari (Mines fire mage) is immune to fire; "no enemies innately have true fire immunity" except Toveri which can gain it; wet reduces flammability; oil/whiskey increases it; fire enemies are damaged by water; vulnerability hexes weaken enemies to water/blood/oil. https://noita.wiki.gg/wiki/Enemy_Immunities , https://noita.wiki.gg/wiki/Wet , https://www.ludo.guide/guide/noita/damage-types-and-resistances. Noita's enemies are mostly per-enemy, not per-biome **[U]**.
- Elden Ring: damage is physical plus elemental, each checked against its own negation; fire is listed as effective vs late-game bosses, God-type and holy living enemies; split-damage weapons work against mixed groups; Erdtree protection adds 35% elemental negation (10% in PvP) (https://eldenring.wiki.fextralife.com/Damage+Types , https://eldenring.wiki.gg/wiki/Fire) **[S]**. Per-region profile (e.g., Caelid fire, Mohgwyn blood) is **[U]**.
- Divinity: Original Sin 2 and Monster Hunter: gap, no usable result. Do not cite.
- Magicka and roguelite region profiles: gap.

How to keep builds viable (inference): Elden Ring's split-damage option and Noita's reaction-based vulnerability show two answers: have a generalist damage mode, and make weakness something you can create via a reaction (wet makes lightning stronger, etc.), which fits Pressure's reaction system.

---

## 8. Death-driven learning and unlocks

- Outer Wilds: discoveries recorded in a ship log; "knowledge is the only progression"; the log flags unfinished threads; death is framed as non-punitive and a learning-design essay argues dying is effectively necessary for some knowledge (https://rigdern.github.io/a/learning-about-learning/learning-design-insights-from-outer-wilds/ , GameSpot review https://Gamespot.com/reviews/outer-wilds-review-extraterrestrial-investigation/1900-6417163/ **[S]**).
- Returnal: logbook; the player keeps enemy knowledge (e.g., stagger points) across runs (https://onemoregame.ph/?p=86135 **[S]**). No in-game hint system found.
- Hades NPC hints and Dead Cells boss-specific blueprints: gap. From memory **[U]**: Dead Cells blueprints drop from enemies/bosses and must be delivered; no boss-specific counter-hint system.
- Hades/Hades II dialogue reacts to deaths and killers: **[U]**.

I found no game with exactly the "NPC names the weakness, unlock a counter weapon" mechanic. Dead Cells' blueprint delivery (above) and Halls of Torment's conditional unlocks are the nearest verifiable structures; Outer Wilds shows knowledge itself as the unlock.

---

## Implications for Pressure

1. Keep individual runs at about 30-45 minutes. Evidence (Hades II ~30 min, HoT 30 min cap, Brotato 25-30 min) shows long-lived successful games use this length, while the 2-hour runs (Returnal) and endless RoR2 loops push players to bail or to want save systems.
2. Get scale from a graph, not from length: Dead Cells shows 24 main + 12 boss biomes with one biome per stage chosen per run. Pressure can have 10-12 regions where each run visits 5 along a chosen route.
3. Make shortcuts lateral, not skipping: Dead Cells runes open specific edges (e.g., Spider Rune for Prison Depths) and do not shorten the finale; RL2 heirlooms are traversal abilities. Pressure's physical shortcut (a door opened once from the far side) should unlock an additional edge in the region graph, never remove a boss.
4. Shortcuts only matter when travel costs something. In Dark Souls the connected world replaces fast travel (TheGamer) and DS2 critics say shortcuts lost meaning once warping was free. Do not give free hub warps; the shortcut is the route to start closer.
5. Offer two parallel route families (Hades II Underworld vs Surface) as the first big content multiplier; each is a normal-length run with different regional resistance profiles.
6. Region resistances should be nudges (Elden Ring splits damage across types; Noita makes weakness a state you can create), not hard immunities, so a build survives with a fusion/reaction detour rather than a respec. This is inference, as no per-region examples were verified.
7. Use death as the loadout unlock channel: a Collector-style NPC (Dead Cells hands blueprints at transitions, 100 cells for one) or Mark-style conditional unlocks (HoT: "play Archer and stand still 3 minutes") can name the counter-tool after a boss kill.
8. Use challenge-per-unlock gating (RoR2 per-survivor challenges; VS 30-minute objectives) so loadout items are earned by play, and keep the hub choice to a few slots (Hades: weapon+aspect+keepsake).
9. Budget dialogue for repetition: Hades shipped 300k+ words and 22k voiced lines (Hades II: 400k+ words, 30k lines) to survive many runs; Pressure should plan fewer NPCs with deeper, state-keyed lines (killer, region, floor) rather than many shallow ones.
10. Let the persistent world graph show on the hub (Dead Cells passages, Returnal logbook) so unvisited regions are visible.
11. Offer a stability option akin to RL2's Architect (fee to lock layout) only if route randomness frustrates; verify the exact fee before copying.
12. Verify the gaps before the GDD: Elden Ring legacy dungeon commentary, Gungeon loadouts, Hades NPC reactivity counts, Divinity/Monster Hunter resistance design, Inscryption structure.
