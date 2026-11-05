# Pressure: current meta progression and unlock pacing, measured from code and bot data

Scope: the meta layer as implemented in the local Godot project at commit f2760ba (2026-11-05), read from GDScript source, plus every run record that exists: 21 telemetry records in `%APPDATA%/Godot/app_userdata/Pressure/telemetry/runs.jsonl` (all `bot: true`) and 47 autotest logs in `autotest/*.log`. No real-player data exists. Every number below is either read directly from a source file or computed from them, and the method is stated next to it. Computations were done with Python (`python -I`) scripts that re-implement `Mastery._build_tree`, parse `Progress.ACHIEVEMENTS`, and parse the logs and the JSONL file.

Source shorthand used in links:
- mastery.gd = [scripts/mastery.gd](C:/Users/emilm/Documents/pressure/scripts/mastery.gd)
- progress.gd = [scripts/progress.gd](C:/Users/emilm/Documents/pressure/scripts/progress.gd)
- main.gd = [scripts/main.gd](C:/Users/emilm/Documents/pressure/scripts/main.gd)
- telemetry = [runs.jsonl](C:/Users/emilm/AppData/Roaming/Godot/app_userdata/Pressure/telemetry/runs.jsonl)
- logs = [autotest/](C:/Users/emilm/Documents/pressure/autotest)

## 1. Mastery tree: size, costs, total power, and how points are earned

### Takeaway
The Mastery tree has 212 nodes in 17 branches and costs 326 points to complete. Fully bought it gives modest, flat, always-on power: +21% damage, +12% fire rate, +7 percentage points of crit, +32 max HP, +6 armour, +1 projectile, and +11% damage / +12% potency for each of the 12 elements. Points come only from run results: floor reached + floor(kills / 150) + 3 for a win. The bot's median run earns 1 point, so at bot pace the tree takes about 285 to 326 runs, or about 7 to 8 hours of bot-length play. A run that clears the dungeon would earn about 20 or more points (scenario estimate), which would put completion at roughly 15 to 20 runs.

### Cited Findings
**Structure and costs** (computed by re-implementing `_build_tree`, `_track` and `_add` from [mastery.gd](C:/Users/emilm/Documents/pressure/scripts/mastery.gd) line by line, then summing):
- Total: **212 nodes, 17 branches, 326 points to buy everything.** The node-cost histogram is 134 nodes at cost 1, 42 at cost 2 and 36 at cost 3. — [mastery.gd](C:/Users/emilm/Documents/pressure/scripts/mastery.gd). GDD.md also states "212 nodes in 17 branches" — [GDD.md](C:/Users/emilm/Documents/pressure/GDD.md)
- Cost rule: in a `_track` chain, node i costs `min(3, base_cost + floor(i / cost_step))`, with base_cost 1 and cost_step 3 unless the code says otherwise. Roots cost 1 and every capstone costs 3. A node can be bought only when its parent is bought. — [mastery.gd](C:/Users/emilm/Documents/pressure/scripts/mastery.gd) (`_track`, `can_buy`, `is_reachable`)
- Per branch (nodes / points: what each node gives, and the branch total):
  - **Offense, 30 nodes / 59 points.**
    - Root: +2% damage.
    - Hard Rounds ×8: +2% damage each.
    - Quick Hands ×6: +2% fire rate each.
    - Keen Eye ×5: +1% crit each.
    - Cruel Edge ×4: +0.05× crit damage each (starts at cost 2, hangs off the end of Keen Eye).
    - Punch Through ×2: +1 pierce each (cost 3).
    - Ricochet ×2: +1 bounce each (cost 3).
    - Spare Barrel: +1 projectile (cost 3).
    - Overkill capstone: +3% damage and +2% crit.
    - **Branch total: dmg +0.21, fire_rate +0.12, crit +0.07, crit_dmg +0.20, pierce +2, bounce +2, proj_count +1.**
  - **Defense, 27 nodes / 50 points.**
    - Root: +3 max HP.
    - Constitution ×8: +3 max HP each.
    - Plating ×5: +1 armour each (from cost 2).
    - Light Feet ×5: +1% dodge each.
    - Mending ×4: +0.1 HP/s regen each (from cost 2).
    - Barbs ×3: +2 thorns each.
    - Unbroken capstone: +5 max HP and +1 armour.
    - **Branch total: max_hp +32, armor +6, dodge +0.05, regen +0.4/s, thorns +6.**
  - **Pressure, 23 nodes / 34 points.**
    - Root: +2 vent capacity.
    - Reinforced Tank ×6: +3 each.
    - Quick Charge ×5: +3% vent charge each.
    - Wide Vent ×5: +2% vent radius each.
    - Hard Vent ×5: +2% vent power each.
    - Capstone: +5 capacity and +3% vent power.
    - **Branch total: pressure_limit +25, vent_charge +0.15, vent_radius +0.10, vent_power +0.13.**
  - **Economy, 20 nodes / 33 points.**
    - Root: +2% scrap.
    - Salvager ×6: +2% scrap each.
    - Deep Pockets ×2: +1 carry each (cost 3).
    - Nest Egg ×5: +5 starting scrap each.
    - Quick Study ×5: +2% XP each.
    - Capstone: +3% scrap and +5 starting scrap.
    - **Branch total: scrap_gain +0.17, carry +2, starting_scrap +30, xp_gain +0.10.**
  - **Utility, 16 nodes / 30 points.**
    - Root: +2% state duration.
    - Lingering Touch ×5: +2% state duration each.
    - Conductive Wire ×2: +1 chain jump each (cost 3).
    - Leech ×2: +1 HP per reaction each (cost 3).
    - Long Barrel ×5: +2% range each.
    - Capstone: +3% state duration and +3% range.
    - **Branch total: state_duration +0.15, chain_jumps +2, lifesteal +2, range +0.13.**
  - **12 element branches (Wet, Shock, Fire, Ice, Oil, Poison, Acid, Blood, Void, Holy, Gale, Stone), each 8 nodes / 10 points.**
    - Root: +2% damage for that element.
    - Edge ×3: +2% element damage each.
    - Potency ×3: +3% element potency each.
    - Capstone: +3% element damage and +3% potency.
    - **Per element: dmg_<el> +0.11, potency_<el> +0.12. All 12 together: 96 nodes, 120 points.**
  - Source for every node above: [mastery.gd](C:/Users/emilm/Documents/pressure/scripts/mastery.gd) `_build_offense` … `_build_element`.
- **Full-tree stat totals** (summed over all 212 nodes): dmg +21%, fire_rate +12%, crit +7 pp, crit_dmg +0.20×, pierce +2, bounce +2, proj_count +1, max_hp +32, armor +6, dodge +5%, regen +0.4 HP/s, thorns +6, pressure_limit +25, vent_charge +15%, vent_radius +10%, vent_power +13%, scrap_gain +17%, carry +2, starting_scrap +30, xp_gain +10%, state_duration +15%, chain_jumps +2, lifesteal +2, range +13%, and dmg_<el> +11% / potency_<el> +12% for each of the 12 elements. — computed from [mastery.gd](C:/Users/emilm/Documents/pressure/scripts/mastery.gd)
- How bonuses apply: `Mastery.bonus(key)` is summed into `Player.stat(key)` with gear, sets, level-ups and conditional mods, so the tree is a flat, always-on additive layer. — [scripts/player.gd](C:/Users/emilm/Documents/pressure/scripts/player.gd) line ~313
- Base player HP is 100 (autotest `[FLOOR] 1 ... hp=100`), so the tree's +32 max HP is about +32% HP. — [logs](C:/Users/emilm/Documents/pressure/autotest)

**Earning points:**
- `award(floor_number, kills, won)` = `max(floor,0) + floor(kills/150) + (3 if won)`, with `KILLS_PER_POINT = 150` and `WIN_BONUS = 3`. It is called once, at run end. — [mastery.gd](C:/Users/emilm/Documents/pressure/scripts/mastery.gd)
- `_end_run` calls `Mastery.award` only when `not autotest`, so bot runs never earn or spend mastery. Every telemetry `run_start` records `mastery_points_spent: 0`. — [main.gd](C:/Users/emilm/Documents/pressure/scripts/main.gd) lines ~207–212, [telemetry](C:/Users/emilm/AppData/Roaming/Godot/app_userdata/Pressure/telemetry/runs.jsonl)
- A run is 5 floors (`FLOORS := 5`). The maximum `floor_number` is 5, and clearing adds +3. — [main.gd](C:/Users/emilm/Documents/pressure/scripts/main.gd)

**Points per run (computed). These are hypothetical, because bots do not award points.** The formula is applied to each log's `[END] floor` and `kills`.
- **Set A** = 7 naked-Vagrant moving bot runs on 2026-11-05 builds:

  | Log | Points | Kills |
  |---|---|---|
  | run21 | 2 | 209 |
  | run22 | 1 | 41 |
  | run23 | 1 | 123 |
  | run26 | 1 | 78 |
  | load6 | 1 | 143 |
  | p_move1 | 1 | 43 |
  | q_move1 | 1 | 103 |

  Median 1, mean 1.14. Bot play time summed to 690 s, which gives 41.7 points per hour of bot play. — [logs](C:/Users/emilm/Documents/pressure/autotest)
- **Set B** = all 22 naked-Vagrant moving logs, including 2026-11-04 builds: median 1, mean 3.27, max 18 (run14: floor 4, 2,166 kills in 1,500 s). Rate: 45.9 points per hour. — [logs](C:/Users/emilm/Documents/pressure/autotest)
- **Set D** = the 10 runs in B that ended in death (a natural ending, not a time cap): median 1, mean 1.9. — [logs](C:/Users/emilm/Documents/pressure/autotest)
- **Runs to complete the tree (326 points)**, as ceil(326 / points per run):
  - Set A median (1/run): **326 runs**.
  - Set A mean (1.14/run): **about 286 runs**.
  - Set D mean (1.9/run): **about 172 runs**.
  - Set B mean (3.27/run): **about 100 runs**.
  - By play time: about 7 to 8 hours at 41.7 to 45.9 points per hour.
  - Scenario, not observed: a cleared run with run14's kill count (2,166) would earn 5 + 14 + 3 = 22 points, which gives about 15 runs.
  - All of these computed from the figures above.

### Inferences
- Even fully bought, the tree adds a moderate power layer. +21% generic damage, +11% per-element damage and +32% HP are "dozens of runs" bonuses, which matches the GDD's stated intent that it be felt "over dozens of runs, not one." The GDD itself calls it "the one deliberate exception to 'nothing makes a run easier'." — [GDD.md](C:/Users/emilm/Documents/pressure/GDD.md)
- Per-point value is front-loaded. 134 of 212 nodes cost 1, but the strongest single nodes (+1 projectile, +2 pierce, +2 bounce, +2 chain jumps, +2 lifesteal, +2 carry) are cost-3 leaves. The 120 points in element branches are only worth anything once that element is in the player's pool (see Q4).
- Point income depends on reaching floors far more than on kills. One floor is worth 150 kills. The bot's typical death on floor 1 gives a flat 1 point, so income for new or weak players is almost independent of how well they played within floor 1.

### Gaps
- No real player has ever earned or spent mastery points: no telemetry upload, and bots skip `award`. So points per run for humans, and how purchases are spread across branches, are unknown.
- No bot run has cleared the dungeon or reached floor 5, so the "+3 win" path and income from a clear are scenario estimates only.
- Whether the mastery power changes win rate is untested: bots never use mastery, and no `--mastery` probe exists.

## 2. Unlocks: achievements, reward types, goals, and estimated unlock run

### Takeaway
There are 55 achievements granting 61 unlocks: 39 guns, 12 classes, 5 obstacles, 2 rarity tiers, 2 shop upgrades and 1 room type. The base pool is 6 unlock ids: 4 guns, 1 obstacle and the Vagrant class. 32 of the 55 achievements count a specific reaction.

Resampling the bot's naked-start runs gives a median of 2 achievements in run 1, 11 by run 5, 18 by run 10 and 30 by run 50. About 23 achievements never unlock at bot skill and bot pool: floor, boss, win and most off-element reactions. The real curve depends on new guns adding elements, which bot data cannot capture.

### Cited Findings
**Counts** (parsed from `ACHIEVEMENTS` and `BASE_UNLOCKS` in [progress.gd](C:/Users/emilm/Documents/pressure/scripts/progress.gd)):
- 55 achievements and 61 reward ids. By reward type: **gun 39, class 12, obstacle 5, rarity 2 (epic, legendary), shop 2 (shop:items "Third shop item", shop:extra "Fourth shop slot"), room 1 (challenge).**
- `BASE_UNLOCKS` = water_pistol, arc_rifle, flare_pistol, slick_wand, obstacle:pool, class:vagrant.
- Every one of the 43 guns is obtainable (4 base + 39 rewards, no duplicates).
- Achievement stats by family:

  | Stat | Achievements |
  |---|---|
  | specific reaction | 32 |
  | kills | 5 |
  | floors | 3 |
  | bosses | 3 |
  | runs_started | 2 |
  | elites | 2 |
  | items_picked | 2 |
  | hidden_rooms | 1 |
  | reactions_fire | 1 |
  | vents | 1 |
  | reactions (total) | 1 |
  | reactions_discovered | 1 |
  | runs_won | 1 |

- Each of the 12 non-Vagrant classes is gated by a 60 to 90 count of its element's signature reaction, for example Pyromancer = 90 Infernos and Stonewarden = 60 Muds. — [progress.gd](C:/Users/emilm/Documents/pressure/scripts/progress.gd), [scripts/classes.gd](C:/Users/emilm/Documents/pressure/scripts/classes.gd)
- Design comment on the order: "The first four land in a first run; after that roughly one per run, then one every two or three." — [progress.gd](C:/Users/emilm/Documents/pressure/scripts/progress.gd)

**Full list (id: stat goal → reward)** — [progress.gd](C:/Users/emilm/Documents/pressure/scripts/progress.gd)
- first_blood: kills 50 → gun blowtorch
- tourist: floors 3 → vein_pistol
- plumber: hidden_rooms 1 → obstacle valve + mist_sprayer
- regular: runs_started 2 → spark_needler
- sparkplug: Ignition 50 → cinder_flak
- kettle: Steam 50 → oil_slinger
- arsonist: reactions_fire (Inferno + Ignition) 30 → obstacle thicket
- bloodied: kills 375 → etcher_beam
- conductor: Chain Lightning 60 → frost_caster
- class_tarsmith: Ignition 60 → Tarsmith
- slayer: elites 12 → ember_carbine
- thermal: Thermal Shock 50 → duality_burst
- plasma: Plasma 50 → storm_seeker
- floor_breaker: bosses 2 → room challenge + tar_mortar
- class_stormcaller: Chain Lightning 90 → Stormcaller
- butcher: kills 625 → blood_lance
- collector: items_picked 20 → rarity epic
- black_ice: Black Ice 50 → rime_chakram
- chemist: Steam 75 → venom_spitter
- polluter: Contamination 50 → blight_seeker
- fumigator: Noxious Flame 50 → plague_mortar
- hemophile: Thin Blood 50 → clot_orb
- maelstrom: Whirlpool 50 → rift_seeker
- baptist: Baptism 50 → prayer_burst
- windbreaker: Monsoon 50 → cyclone_flak
- class_tidecaller: Steam 90 → Tidecaller
- venter: vents 30 → hydro_cannon
- class_frostbinder: Deep Freeze 60 → Frostbinder
- catalyst: reactions 900 → null_wand
- alchemist: Inferno 75 → acid_flask + obstacle rubble
- annihilator: Annihilation 15 → eclipse_carbine
- class_voidwalker: Singularity 50 → Voidwalker
- class_plaguewright: Contamination 60 → Plaguewright
- class_pyromancer: Inferno 90 → Pyromancer
- class_bloodletter: Thin Blood 60 → Bloodletter
- class_alchemist: Caustic Splash 60 → Alchemist
- class_templar: Baptism 60 → Templar
- class_windrunner: Monsoon 60 → Windrunner
- class_stonewarden: Mud 60 → Stonewarden
- exterminator: kills 1500 → corrosion_burst
- stormcaller: Chain Lightning 240 → gale_blaster + obstacle miasma
- pressure_cooker: Steam 180 → kettle_gun
- abyss: bosses 6 → void_orb
- deep_freezer: Deep Freeze 120 → glacier_lance
- explorer: floors 20 → zephyr_rang
- hoarder: items_picked 60 → rarity legendary
- mason: elites 50 → stone_sling
- reactionary: reactions_discovered 20 → shop items
- veteran: runs_started 12 → gravel_shotgun
- pyromaniac: Inferno 180 → napalm_lobber
- survivor: runs_won 1 → storm_pike + shop extra
- sunbreaker: bosses 12 → sun_cannon
- zealot: Deep Freeze 240 → radiant_ray + obstacle ward
- reaper: kills 3750 → railgun
- spelunker: floors 50 → boulder_mortar

**Implementation details that change pacing** (read from code):
- **"floors" counts floors completed, not floors reached.** `Progress.add("floors")` is called only in `next_floor()`, which runs after a floor's boss. "Reach 3 floors" (Tourist) therefore needs three floor completions in total across runs. Mastery, in contrast, pays per floor reached. — [main.gd](C:/Users/emilm/Documents/pressure/scripts/main.gd) `next_floor`, [progress.gd](C:/Users/emilm/Documents/pressure/scripts/progress.gd)
- **12 achievement descriptions disagree with their goals.** "Fire 30 X" is shown while the goal is 50, for sparkplug, kettle, thermal, plasma, black_ice, polluter, fumigator, hemophile, maelstrom, baptist, windbreaker and class_voidwalker. The run-over and Trophy goal bars print `desc` together with "progress / goal", so a player would see e.g. "Fire 30 Ignitions … 12 / 50". — computed by comparing the first number in `desc` with `goal` in [progress.gd](C:/Users/emilm/Documents/pressure/scripts/progress.gd); display code in [scripts/hub.gd](C:/Users/emilm/Documents/pressure/scripts/hub.gd) `draw_goal`
- **Two non-reaction popups count as reactions.** `add_reaction` excludes ELITE, Shield broken!, Shield restored!, Path opened!, Fire Nova and Frost Nova, but not "Shield cracked" or "ENRAGED". Both therefore add to `reactions` (Catalyst, 900) and `reactions_discovered` (Reactionary, 20). Across Set B logs they appeared 654 and 13 times. — [progress.gd](C:/Users/emilm/Documents/pressure/scripts/progress.gd), [logs](C:/Users/emilm/Documents/pressure/autotest)
- `next_goals(3)` shows the first 3 open achievements **in list order**, not the nearest ones. After a typical bot first run (First Blood and Arsonist done), the "Next" panel would show Tourist, Plumber and Regular. Tourist cannot be reached without completing floors. — [progress.gd](C:/Users/emilm/Documents/pressure/scripts/progress.gd) `next_goals`

**Observed first-run unlocks.** Every autotest run starts from a wiped `save_autotest.json` (`Progress.reset()`), so each log's "unlocked this run" line is exactly what a first-ever run earned. — [main.gd](C:/Users/emilm/Documents/pressure/scripts/main.gd) lines ~87–91
- **Set A** (7 runs, 11-05 builds), achievements per first run [5, 0, 2, 4, 4, 0, 2], median 2, mean 2.4:
  - run21: first_blood, sparkplug, arsonist, conductor, class_tarsmith
  - run22: none
  - run23: first_blood, arsonist
  - run26: first_blood, arsonist, alchemist, class_pyromancer (in 75 s, from 142 Infernos)
  - load6: first_blood, plumber, conductor, class_stormcaller
  - p_move1: none
  - q_move1: first_blood, arsonist
  - Frequency across the 7 runs: first_blood 5/7, arsonist 4/7, conductor 2/7, the others 1/7. Tourist and Regular: 0/7.
  - — [logs](C:/Users/emilm/Documents/pressure/autotest)
- Older 11-04 logs (run3, run4, run5, run14) reached 27 to 33 achievements in one 600 to 1,500 s run. **Those builds had a different achievement table** (classes were added at commit 17de392, 22:51 on 11-04) **and easier floors** (floors 3–5 were hardened at 74a0e9c, 23:13). — [logs](C:/Users/emilm/Documents/pressure/autotest), `git log`

**Estimated unlock run, method 1 (deterministic):** ceil(goal / Set A per-run rate). Medians, with means in brackets. — computed from [logs](C:/Users/emilm/Documents/pressure/autotest)
- kills, rate 103/run:
  - Bloodied (375): 4
  - Butcher (625): 7 (mean 6)
  - Exterminator (1,500): 15
  - Reaper (3,750): 37 (mean 36)
- Ignition, rate 17/run:
  - Sparkplug (50): 3
  - Tarsmith (60): 4 (mean 3)
- Chain Lightning, rate 25/run:
  - Conductor (60): 3 (mean 2)
  - Stormcaller class (90): 4 (mean 3)
  - Stormcaller achievement (240): 10 (mean 7)
- Steam, rate 4/run (mean 9):
  - Kettle (50): 13 (mean 6)
  - Chemist (75): 19 (mean 9)
  - Tidecaller (90): 23 (mean 10)
  - Pressure Cooker (180): 45 (mean 20)
- Inferno, rate 4/run (mean 26):
  - Alchemist (75): 19 (mean 3)
  - Pyromancer (90): 23 (mean 4)
  - Pyromaniac (180): 45 (mean 7)
- Deep Freeze, rate 3/run (mean 5.4):
  - Frostbinder (60): 20 (mean 12)
  - Deep Freezer (120): 40 (mean 23)
  - Zealot (240): 80 (mean 45)
- Black Ice, rate 1/run (mean 1.7): 50 runs (mean 30).
- Plasma, rate 0 median (mean 1.9): mean only, 27 runs.
- vents, rate 8/run: Venter (30): 4.
- reactions, rate 99/run: Catalyst (900): 10.
- runs_started: Regular 2, Veteran 12.

**Estimated unlock run, method 2 (Monte Carlo, 4,000 simulated save files).**
- Method:
  - Each simulated run is drawn i.i.d. from the 7 Set A runs, using their kills, floors completed, per-reaction counts, vents, hidden rooms and discovered names.
  - Elites, bosses and items picked are drawn separately from the 4 Set A runs that also have telemetry (run26, load6, p_move1, q_move1).
  - Cumulative save stats are then checked against goals exactly as `_check_achievements` does.
  - — computed from [logs](C:/Users/emilm/Documents/pressure/autotest) and [telemetry](C:/Users/emilm/AppData/Roaming/Godot/app_userdata/Pressure/telemetry/runs.jsonl)
- Achievements completed by run N, as median [p10–p90] of 55:

  | Run N | Achievements |
  |---|---|
  | 1 | 2 [0–5] |
  | 2 | 5 [3–8] |
  | 3 | 7 [4–10] |
  | 5 | 11 [8–14] |
  | 10 | 18 [15–20] |
  | 20 | 25 [23–26] |
  | 30 | 27 [26–28] |
  | 50 | 30 [29–31] |
  | 100 | 32 |
  | 200 | 32 (plateau) |

- Median unlock run per achievement:

  | Median run | Achievements |
  |---|---|
  | 1 | first_blood, arsonist |
  | 2 | regular, conductor |
  | 3 | sparkplug, class_stormcaller |
  | 4 | bloodied, class_tarsmith |
  | 5 | plumber, venter, alchemist, class_pyromancer |
  | 6 | kettle |
  | 7 | butcher, stormcaller |
  | 8 | pyromaniac |
  | 9 | chemist, catalyst |
  | 11 | class_tidecaller |
  | 12 | class_frostbinder, veteran |
  | 15 | slayer, collector, exterminator |
  | 21 | pressure_cooker |
  | 23 | deep_freezer |
  | 27 | plasma |
  | 30 | black_ice |
  | 36 | reaper |
  | 45 | zealot |
  | 47 | hoarder |
  | 67 | mason |

- **Not reached within 200 simulated runs (23 achievements):**
  - Floors, bosses and wins: tourist, explorer, spelunker, floor_breaker, abyss, sunbreaker, survivor.
  - Reaction totals: reactionary (Set A's union of discovered names is only 9: Black Ice, Chain Lightning, Cryoshock, Deep Freeze, Ignition, Inferno, Plasma, Shield cracked, Steam).
  - Specific reactions never seen in Set A: thermal, polluter, fumigator, hemophile, maelstrom, baptist, windbreaker, annihilator, and the voidwalker, plaguewright, bloodletter, alchemist, templar, windrunner and stonewarden classes.
- Pool size by run (Monte Carlo median):

  | Run N | Guns (of 43) | Classes (of 13) | Unlock ids (of 67) |
  |---|---|---|---|
  | 1 | 5 | 1 | 8 |
  | 2 | 8 | 2 | 12 |
  | 5 | 12 | 3 | 19 |
  | 10 | 17 | 5 | 27 |
  | 20 | 22 | 6 | 34 |
  | 50 | 27 | 6 | 40 |
  | 100 | 28 | 6 | 42 |

### Inferences
- The early curve matches the design comment from run 2 onward: about 2 to 3 achievements per run through run 5, about 1.4 per run through run 10, then one every 2 to 5 runs. The first run lands about 2, not the intended 4, because Tourist ("3 floors" = 3 floor completions) and Regular (2 runs) cannot land in run 1. Regular is reached at run 2 by definition. Tourist needs the player to finish floors, which the bot never does on current builds.
- The resampling plateau at 32 is an artefact: the method assumes a constant pool. In real play, unlocks feed back:
  - frost_caster (ice) by about run 2, etcher_beam (acid) by about 4, blood_lance (blood) by about 7, gale_blaster (gale) by about 7, venom_spitter (poison) and null_wand (void) by about 9, gravel_shotgun (stone) by 12, radiant_ray (holy) by about 45.
  - Each new element makes new signature reactions possible.
  - So the 12 class unlocks and the off-element reaction achievements are a second tier. They are gated on gun unlocks that arrive around runs 2 to 12 (holy around 45), and their pacing after that cannot be measured from naked-start bot data.
- Reaction-count goals have very high variance. One lucky fire + oil pairing gave 142 Infernos in a 75 s run (run26), which meets Alchemist and Pyromancer in run 1. The median Inferno run gave 4. Classes and guns tied to these counts can unlock on run 1 or run 20+ depending on the opening gun offer. Medians and means differ by 5–10× for Inferno, Steam and Plasma.
- Boss-, floor- and win-gated rewards are the deepest content: challenge room, tar_mortar, void_orb, sun_cannon, storm_pike, the fourth shop slot, vein_pistol, zephyr_rang and boulder_mortar. They depend entirely on run success, which bot data puts at floor 1 for the median run.

### Gaps
- No human data, so real skill (floors per run, bosses) is unknown, and floor/boss/win unlock timings cannot be estimated at all.
- The Monte Carlo ignores pool growth between runs and the class a player picks. It is a constant-pool lower bound for reaction achievements and an upper bound on nothing.
- Elites, bosses and items per run come from only 4 telemetry runs (elites 0, 3, 0, 0; items 0, 5, 0, 0; bosses 0). Slayer, Mason, Collector and Hoarder estimates are therefore very rough.

## 3. Per-run rates measured from telemetry and autotest logs (bot only)

### Takeaway
All existing data is bot data: 21 telemetry records (all `bot: true`) and 47 logs, of which 22 are usable naked-Vagrant runs. On current builds the median bot run lasts about 99 s, kills about 103 enemies, fires about 99 reactions, never completes floor 1 or meets a boss, and earns 1 mastery point. The bot plays a naked Vagrant, never uses mastery, is given 5 gear items at 45 s, and most runs are cut by a time cap, not by death. These are probe measurements, not player behaviour.

### Cited Findings
**Data provenance** (from file headers, `[CLASS]`, `[LOADOUT]` and `[VETERAN]` lines, gun counts at floor 1, and matching telemetry `run_end` kills/floor to log `[END]` lines):
- The telemetry file has 21 records: 20 complete runs plus 1 partial (`d02d3a`, only `floor_start`). All are `bot: true` and `uploaded: false`, all from build 2026.11.05, one `device_id`, and `players: 1`. — [telemetry](C:/Users/emilm/AppData/Roaming/Godot/app_userdata/Pressure/telemetry/runs.jsonl)
- `ENDPOINT := ""` in telemetry.gd, so nothing uploads. Bot runs are flagged `bot` and "never uploaded". — [scripts/telemetry.gd](C:/Users/emilm/Documents/pressure/scripts/telemetry.gd)
- **Telemetry records are mostly balance probes, not normal runs.** Telemetry `start_time` is UTC; logs are local time (UTC+1). Matched records:
  - 1 normal naked run (run26).
  - 3 more naked-moving runs (load6, p_move1, q_move1).
  - 3 stand-still `--idle` runs (idle1, p_idle1, q_idle1).
  - 3 `--veteran` runs with every gun and class unlocked (vet1–3).
  - 8 `--loadout=` runs starting with 6 guns (load1–5, p_idle6, p_move6, q_idle6, q_move6; load2 matched by 165 vs 166 kills).
  - 1 Pyromancer class run (fig1).
  - 1 partial.
  - — [telemetry](C:/Users/emilm/AppData/Roaming/Godot/app_userdata/Pressure/telemetry/runs.jsonl), [logs](C:/Users/emilm/Documents/pressure/autotest)
- Log sets used:
  - **Set A** = 7 naked-Vagrant moving runs on 11-05 builds: run21, 22, 23, 26, load6, p_move1, q_move1.
  - **Set B** = Set A plus 15 such runs on 11-04 builds (run2, 3, 4, 5, 7, 8, 10, 12, 13, 14, 18, 19, 20, short, short2).
  - **Set D** = the death-ended subset of B (10 runs).
  - Excluded: arsenal or class runs (run1 started with 29 guns, run15/16/24/25/fig1 used classes), loadout, veteran and idle runs, and logs with no `[END]` line (run6, 9, 11, 17).
  - — [logs](C:/Users/emilm/Documents/pressure/autotest)

**Bot behaviour and biases** (from code):
- The bot uses a fresh, separate save (`save_autotest.json`, `Progress.reset()`) and plays the Vagrant unless given `--class=`. Every run is effectively a first-ever run with only the base pool. — [main.gd](C:/Users/emilm/Documents/pressure/scripts/main.gd)
- Mastery is never awarded in autotest, so no bot run has mastery bonuses. — [main.gd](C:/Users/emilm/Documents/pressure/scripts/main.gd)
- Runs stop at `--secs=N` or 300 s by default (70 s with `--short`), or at death or victory. In Set A, 3 of 7 runs were time-capped at 120 to 150 s. In Set B, 12 of 22 were capped (caps of 70, 120, 150, 330, 600, 900 and 1,500 s). "Run length" therefore mostly reflects the cap chosen by the tester. — [main.gd](C:/Users/emilm/Documents/pressure/scripts/main.gd) `_autotest_tick`, [logs](C:/Users/emilm/Documents/pressure/autotest)
- At 45 s the bot is force-equipped with conductors_mail, ring_shock, vial_shock, lucky_cog and quick_hands so a character-sheet screenshot has content. These raise Chain Lightning potency and jumps, add 12% shock application, and add +20% shock damage, luck, crit and fire rate. Shock-reaction counts (Chain Lightning, Ignition, Plasma) in any run longer than 45 s are inflated. These equips do not add to `items_picked`. — [main.gd](C:/Users/emilm/Documents/pressure/scripts/main.gd), [scripts/items.gd](C:/Users/emilm/Documents/pressure/scripts/items.gd)
- Movement is scripted kiting (orbit at range, flee below 50% HP). The bot vents every 6 s, uses its active item every 9 s, takes the first candidate for mods, and picks automatically at the entrance gun choice. — [main.gd](C:/Users/emilm/Documents/pressure/scripts/main.gd)

**Measured per-run values** (median, mean, min–max). Values come from `[END] t=`, `kills=` and `floor=`, and from the cumulative `reactions:` dict printed after `[END]`. Reactions are counted the way `Progress.add_reaction` counts them, with only the 65 real reaction names in the "real" column. — [logs](C:/Users/emilm/Documents/pressure/autotest)

| Metric | Set A (n=7) | Set B (n=22) | Set D (n=10) |
|---|---|---|---|
| Run time t (s) | 99, 98.6, 44–150 | 110, 256, 21–1,500 | 71, 123, 21–612 |
| Kills | 103, 105.7, 41–209 | 105.5, 325, 8–2,166 | 60.5, 145, 8–857 |
| Floor reached | 1, 1.0, 1–1 | 1, 1.6, 1–4 | 1, 1.4, 1–4 |
| Floors completed (achievement stat) | 0 | 0, 0.6, 0–3 | 0, 0.4, 0–3 |
| Reactions (real) | 99, 101.7, 2–199 | 112.5, 1,001, 0–7,057 | 28, 420, 0–3,752 |
| Distinct reactions in run | 6, 5.3, 2–7 | 6, 9.7, 0–39 | 3, 4.7, 0–19 |
| Vents (Fire/Frost Nova) | 8, 6.9 | 6, 11.5 | 5.5, 13.2 |
| Hidden rooms opened | 0, 0.14 | 0, 0.2 | 0, 0 |
| Kills per minute (median) | 61.5 | 62.0 | 57.4 |
| Reactions per minute (median) | 51.2 | 69.0 | 28.2 |
| Ended in death | 4/7 | 10/22 | 10/10 |
| Mastery points (formula) | 1, 1.14 | 1, 3.27 | 1, 1.9 |

**Reactions per run by name, Set A** (median / mean / runs with at least one, of 7):

| Reaction | Median | Mean | Runs |
|---|---|---|---|
| Chain Lightning | 25 | 37.3 | 6 |
| Inferno | 4 | 26.0 | 6 |
| Ignition | 17 | 20.1 | 6 |
| Steam | 4 | 9.0 | 6 |
| Deep Freeze | 3 | 5.4 | 5 |
| Plasma | 0 | 1.9 | 3 |
| Black Ice | 1 | 1.7 | 4 |
| Cryoshock | 0 | 0.3 | 1 |

No other reaction occurred in Set A. In Set B, 54 distinct names occurred, but almost all non-base reactions come from the long 11-04 runs (run3, 4, 5, 14). — [logs](C:/Users/emilm/Documents/pressure/autotest)

**Elites and bosses** (telemetry `elite` events = elite kills with `secs_to_kill`; `boss` events with `won`):
- Naked-moving runs (run26, load6, p_move1, q_move1): elites killed 0, 3, 0, 0; boss fights 0; bosses killed 0.
- Across all 20 complete telemetry runs: 44 elite kills and 6 boss fights, 3 won. All 3 boss wins were in 6-gun loadout runs (load1, load5, q_move6).
- — [telemetry](C:/Users/emilm/AppData/Roaming/Godot/app_userdata/Pressure/telemetry/runs.jsonl)
- Log reaction dicts also count "ELITE" popups, which mark elites appearing, not kills: Set A had 5, 2, 4, 3, 4, 2, 3. — [logs](C:/Users/emilm/Documents/pressure/autotest)

**Telemetry room_clear undercounts reactions.** The per-room `reactions` dict is a delta flushed at room clear, so reactions in the room where the bot dies are lost. For run26, telemetry room_clear summed to 83 reactions against 175 real reactions in the log. — [scripts/telemetry.gd](C:/Users/emilm/Documents/pressure/scripts/telemetry.gd) `room_clear`, [telemetry](C:/Users/emilm/AppData/Roaming/Godot/app_userdata/Pressure/telemetry/runs.jsonl), [logs](C:/Users/emilm/Documents/pressure/autotest)

**Room difficulty seen.**
- Telemetry `room_enter` diff values: floor 1 at 2–5 (276 entries), floor 2 at 6 (4 entries).
- Difficulty formula: `2 + (floor-1)*4 + min(rooms_cleared,6)/2`, which gives floor 1 = 2–5, floor 2 = 6–9, floor 5 = 18–21.
- — [main.gd](C:/Users/emilm/Documents/pressure/scripts/main.gd) `difficulty`, [telemetry](C:/Users/emilm/AppData/Roaming/Godot/app_userdata/Pressure/telemetry/runs.jsonl)

### Inferences
- The numbers describe a scripted bot dying on floor 1 in a kiting pattern. They are a floor (minimum) for a competent human on kills per run and floors, and probably a ceiling on shock reactions because of the 45 s gear injection.
- Kills per minute (about 60) is the most transferable rate, since it is stable across Sets A, B and D. Per-run totals are not transferable, because they are set by the tester's time caps.
- Because every bot run uses a reset save, no data shows how pacing changes once unlocks accumulate.

### Gaps
- No human runs, so there are no real distributions of run length, floors, deaths per floor, or class choice.
- Set A is n=7 and its telemetry subset is n=4. All statistics have wide uncertainty.
- 11-04 logs (most of Set B) are from earlier builds with different floors, achievement tables and economy. They are kept only as context.
- No bot run reached floor 5 or won, so clear time and clear rate are unknown.

## 4. Items, guns, classes, and how much of the pool a new player sees

### Takeaway
The content pool is 238 gear items, 43 guns, 13 classes, 65 reactions, 6 obstacle kinds, plus shop and room upgrades. A brand-new save opens 4 of 43 guns (9%), 1 of 13 classes (8%), 1 of 6 obstacles, and gear up to Rare: 183 of 238 items (77%). Epic and Legendary unlock through items picked (20 and 60). Even when unlocked, they cannot roll on floor 1: difficulty must reach 6 for epic and 9 for legendary.

### Cited Findings
**Items.**
- 172 `_add(` calls in `_build_catalog`. 166 are hand-written; 6 sit inside a loop over the 12 elements (charm C, ring U, vial U, gloves R, coating R, mantle E), which yields 72 items. Total **238 items**. — counted with regex over [scripts/items.gd](C:/Users/emilm/Documents/pressure/scripts/items.gd)
- By rarity (hand-written + element family = total), same source:

  | Rarity | Hand-written | Element family | Total |
  |---|---|---|---|
  | Common | 43 | 12 | 55 |
  | Uncommon | 41 | 24 | 65 |
  | Rare | 39 | 24 | 63 |
  | Epic | 27 | 12 | 39 |
  | Legendary | 16 | 0 | 16 |

- Hand-written items by slot: head 23, chest 23, hands 20, feet 19, ring 25, trinket 30, mod 12, active 14. — [scripts/items.gd](C:/Users/emilm/Documents/pressure/scripts/items.gd)
- `max_rarity_unlocked()` returns RARE unless `rarity:epic` or `rarity:legendary` is unlocked. `roll()` caps every roll at that rarity. — [scripts/items.gd](C:/Users/emilm/Documents/pressure/scripts/items.gd)
- Rarity odds use `[min difficulty, growth per difficulty, cap]`, with chance = clamp(growth × (d − min + 1) × (1 + luck), 0, cap): Uncommon [1, 0.07, 0.55], Rare [3, 0.03, 0.25], Epic [6, 0.012, 0.10], Legendary [9, 0.005, 0.04]. Rarities are checked from legendary down. — [scripts/items.gd](C:/Users/emilm/Documents/pressure/scripts/items.gd)
- Prices by rarity: 22 / 38 / 62 / 98 / 150 scrap. — [scripts/items.gd](C:/Users/emilm/Documents/pressure/scripts/items.gd)

**Guns.**
- 43 guns in `Guns.ORDER`. `Guns.ids()` returns only those with a `gun:` unlock; `all_ids()` returns all 43. — [scripts/gun_library.gd](C:/Users/emilm/Documents/pressure/scripts/gun_library.gd)
- Elements (parsed from `g.element`): Fire 5; Wet, Shock, Ice and Holy 4 each; Oil, Poison, Acid, Blood, Void, Gale and Stone 3 each; railgun has no element. — [scripts/gun_library.gd](C:/Users/emilm/Documents/pressure/scripts/gun_library.gd)
- Base guns cover only wet, shock, fire and oil (water_pistol, arc_rifle, flare_pistol, slick_wand). — [progress.gd](C:/Users/emilm/Documents/pressure/scripts/progress.gd)
- First gun unlock per new element, with its gating achievement and Monte Carlo median run (Q2):

  | Element | Gun | Achievement | Median run |
  |---|---|---|---|
  | ice | frost_caster | Conductor | 2 |
  | acid | etcher_beam | Bloodied | 4 |
  | blood | blood_lance | Butcher | 7 |
  | gale | gale_blaster | Stormcaller | 7 |
  | poison | venom_spitter | Chemist | 9 |
  | void | null_wand | Catalyst | 9 |
  | stone | gravel_shotgun | Veteran | 12 |
  | holy | radiant_ray | Zealot | 45 |

  Other guns of these elements are gated on floors, bosses or off-element reactions. — [progress.gd](C:/Users/emilm/Documents/pressure/scripts/progress.gd); timing computed (Q2)

**Reactions.**
- 65 reactions are defined in elements.gd, one per unordered pair of the 12 elements, except **wet+oil, which has none** (66 pairs, 65 reactions). — [scripts/elements.gd](C:/Users/emilm/Documents/pressure/scripts/elements.gd)
- The base guns' four elements directly pair into 5 reactions: Chain Lightning (wet+shock), Steam (wet+fire), Plasma (shock+fire), Inferno (fire+oil), Ignition (oil+shock). Items such as vials and coatings, vents and props can add others; Set A also saw Deep Freeze, Black Ice and Cryoshock. — [scripts/elements.gd](C:/Users/emilm/Documents/pressure/scripts/elements.gd), [logs](C:/Users/emilm/Documents/pressure/autotest)

**Classes.**
- 13 classes: Vagrant (always unlocked) and 12 elemental classes, each unlocked by `class:<id>`.
- A class grants: a start gun, a start item, an affinity (+20% potency and +10% damage for its element), and a quirk such as Pyromancer −10 max HP or Stonewarden +2 carry.
- The class start gun is added even if that gun is still locked in the pool. Stormcaller, for example, starts with spark_needler.
- Vagrant has no start gun (it picks 1 of 2 at the entrance) and gets +1 carry and +10% scrap.
- — [scripts/classes.gd](C:/Users/emilm/Documents/pressure/scripts/classes.gd)

**Obstacles, rooms, shop.**
- Obstacle kinds: pool (base), plus valve, thicket, rubble, miasma and ward, which are unlocked.
- The challenge room is gated by Floor Breaker (2 bosses).
- "Third shop item" is gated by Reactionary; "Fourth shop slot" by Survivor (win).
- — [progress.gd](C:/Users/emilm/Documents/pressure/scripts/progress.gd) `unlock_label`

**New-player share of the pool** (base unlocks divided by totals):
- guns 4/43 = 9.3%
- classes 1/13 = 7.7%
- obstacles 1/6 = 16.7%
- items 183/238 = 76.9% by rarity cap
- unlock ids 6/67 = 9.0%
- (6 base + 61 rewards = 67)
- After 10 runs (Monte Carlo median): 17/43 guns (40%), 5/13 classes (38%), 27/67 unlock ids (40%). The pool plateaus at about 28 guns and 6 classes under the constant-pool assumption (Q2).

**Documentation drift.** GDD.md still says "Ten achievements today", "Eleven guns in the pool so far" and "Seventy items exist today", and titles the section "Meta progression (proposal, not built)", while its subsections say BUILT. The code has 55 achievements, 43 guns and 238 items. — [GDD.md](C:/Users/emilm/Documents/pressure/GDD.md)

### Inferences
- The unlock layer gates breadth (guns, classes, elements) heavily, about 9% at start. The gear layer is mostly open, about 77%, and its two locked tiers are additionally gated by depth (difficulty 6+ only from floor 2 onward), so they matter little to a player who dies on floor 1.
- Element coverage, not gun count, is the effective gate on half the achievement list: 32 reaction achievements, including all 12 class unlocks. A player's first 2 to 12 runs mostly widen the element set.

### Gaps
- How often each unlocked gun actually appears in a run (shop, treasure and pedestal weights) was not measured.
- Item pool weights and pools per room type were not tabulated.
- Exact counts of room types beyond "challenge is gated" were not tallied.

## 5. How the meta layer shows up in the hub and on the run-over screen

### Takeaway
Between runs, meta progression lives in one hub room. The **Shrine** opens the Mastery node graph, the **Trophy Wall** shows one tile per achievement (55) plus the next three goals with progress bars, the **Ledger** shows the last 5 runs and lifetime totals including mastery, and the **Armory** opens the Journal (achievements, arsenal, gear, reactions). At run end, the **run-over screen** reports what happened this run, the unlocks it earned, the next 3 goals, and mastery gained. During a run, unlocks pop as toasts.

### Cited Findings
- Hub stations:
  - THE GATE: start a run, after a class picker.
  - ARMORY: Journal, opening on the guns-and-gear tab.
  - SHRINE: Mastery, verb "kneel".
  - MIRROR: player names.
  - WORKSHOP: options.
  - LEDGER: run history.
  - The trophy wall at the top: opens the Journal achievements tab.
  - — [scripts/hub.gd](C:/Users/emilm/Documents/pressure/scripts/hub.gd) `STATIONS`, `_use_station`
- Hub explainer text: "A run is five floors. Each floor ends in a boss." / "Dying keeps your achievements, unlocks and mastery." / "Unlocks widen what a run can offer; mastery adds small permanent power." / "Classes only change how a run starts." — [scripts/hub.gd](C:/Users/emilm/Documents/pressure/scripts/hub.gd) `EXPLAINER`
- **Trophy Wall:** a plaque with one tile per achievement (2 rows), lit when done, showing the first reward's gun icon or a class icon. Below it: "TROPHIES n / 55" and `goal_rows(3)` progress bars ("Name: desc", "unlocks <reward>", a bar and "progress / goal"). When none remain: "Every achievement earned." — [scripts/hub.gd](C:/Users/emilm/Documents/pressure/scripts/hub.gd) `_draw_trophy_wall`, `draw_goal`
- **Ledger:**
  - The last 5 runs: "Run N, floor F, K kills, CLEARED/fell, +U unlocks".
  - Totals: runs, cleared, floors, bosses / kills, elites, reactions / achievements n/55, guns n/43 / "Mastery: P points to spend, E earned, B / 212 nodes" / play-data count and sharing status.
  - `Progress.history` keeps up to 50 runs.
  - — [scripts/hub.gd](C:/Users/emilm/Documents/pressure/scripts/hub.gd) `_fill_ledger`, [progress.gd](C:/Users/emilm/Documents/pressure/scripts/progress.gd) `end_run`
- **Shrine / Mastery screen:**
  - A Path-of-Exile-style radial node graph: a core plus 17 spokes.
  - Node states are bought, buyable, reachable or locked.
  - Header text: "Points P" and "Bought n / 212". The focused node shows cost, with "not enough points" or "needs <parent>".
  - Pad, mouse and keyboard can navigate, pan, zoom and jump between branches.
  - — [scripts/mastery_screen.gd](C:/Users/emilm/Documents/pressure/scripts/mastery_screen.gd)
- **Run-over screen.** Its title is "RUN OVER" or "DUNGEON CLEARED". It has three sections:
  - THIS RUN: "Floor F of 5, K kills, m:ss, class, player levels".
  - YOU UNLOCKED: each `run_unlocks` entry with a kind blurb, for example "a new gun in the pool", "a new class at the Gate", "rarer gear can drop", "bigger shops". If there were none: "Nothing new this time. Every run still counts toward the goals below."
  - NEXT: 3 goal bars, then "Mastery +N this run, P to spend at the Shrine, E earned in all".
  - An unlock sound plays if anything unlocked. Buttons: Restart run and Return to hub.
  - — [scripts/pause_menu.gd](C:/Users/emilm/Documents/pressure/scripts/pause_menu.gd) `_fill_report`, `show_menu`
- **In-run surfacing:**
  - Each unlock fires `Progress.unlocked`, which shows a HUD toast "<Achievement>: unlocked <thing>" and plays an "unlock" sound.
  - At run end, `announce("+N mastery points")`.
  - The run-over screen appears 1.6 s after death.
  - — [main.gd](C:/Users/emilm/Documents/pressure/scripts/main.gd) `_on_unlocked`, `_end_run`
- The README describes the same loop: points per floor, per 150 kills and per win, spent in the Mastery tree; the run-end screen shows unlocks and what is next. — [README.md](C:/Users/emilm/Documents/pressure/README.md)

### Inferences
- Pressure shows meta progress through three channels: the Trophy Wall's next-3 bars, the run-over NEXT bars, and the Ledger totals. Mastery is a separate, purely numeric currency, spent only at the Shrine. No persistent currency other than mastery points exists. In-run scrap does not carry over, and the GDD says "Nothing carries out except unlocks".
- Because `next_goals` follows list order, both the Trophy Wall and the run-over screen will show Tourist ("Reach 3 floors", i.e. 3 floor completions) to a player who keeps dying on floor 1. Meanwhile, faster goals later in the list (Conductor, Sparkplug, the class unlocks) progress unseen. With the 30-vs-50 description mismatches, some bars also show a goal different from the text.

### Gaps
- There is no playtest or telemetry data on whether players visit the Shrine, Ledger or Trophy Wall, or spend points. Telemetry records no hub events beyond settings/session records.
- The Journal's content (journal.gd: achievements, arsenal, gear, reaction compendium) was not inventoried in detail.
