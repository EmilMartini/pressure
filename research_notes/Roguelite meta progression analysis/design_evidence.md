# Cross-game evidence on roguelite / survivor-like meta progression (excluding Hades, Dead Cells, RoR2)

Method note: Steam global achievement percentages were pulled on 2026-11-05 from Steam's public `GetGlobalAchievementPercentagesForApp` API and matched to names/descriptions embedded in each game's `steamcommunity.com/stats/<appid>/achievements` page. Steam's denominator is (approximately) everyone who owns the game, including people who barely played or got it in a bundle/free weekend, so absolute values understate completion among engaged players. Ratios between achievements within one game are more meaningful than raw values. Percentages are a snapshot and drift over time.

## 1. Comparable systems with numbers (Brotato, Vampire Survivors, Slay the Spire, Rogue Legacy 2, Enter the Gungeon, Binding of Isaac)

### Takeaway
The six games span a spectrum from "no stat meta at all" (Slay the Spire, Brotato; unlocks only add content and difficulty tiers) to "explicit stat shop with escalating costs" (Vampire Survivors PowerUps, Rogue Legacy 2 Manor). The stat-shop games both use a two-part cost escalation: the next rank of the same upgrade gets pricier, and every purchase also raises the price of all other upgrades. Vampire Survivors makes its whole stat shop refundable and toggleable, which turns it into a player-controlled difficulty dial. The no-stat-meta games still post high first-win rates: Brotato 72.8% Danger 0 win, Slay the Spire 56.0% Ironclad win. Enter the Gungeon's meta is mostly unlocks plus shortcuts, and it has by far the lowest "beat the main game" rate in the set (about 21%).

### Cited Findings

**Vampire Survivors: PowerUps shop (measured / datamined)**
- PowerUp list (max ranks, initial cost, effect per rank). Might: 5 ranks, 200g, +5%/rank (+25% max). Armor: 3 ranks, 600g, -1 damage/rank. Max Health: 3 ranks, 200g, +10%/rank (multiplicative, +33.1% max). Recovery: 5 ranks, 200g, +0.1 HP/s. Cooldown: 2 ranks, 900g, -2.5%/rank. Area: 2 ranks, 300g, +5%. Speed: 2 ranks, 300g, +10% projectile speed. Duration: 2 ranks, 300g, +15%. Amount: 1 rank, 5,000g, +1 projectile. Move Speed: 2 ranks, 600g, +5%. Magnet: 2 ranks, 300g, +25%. Luck: 3 ranks, 600g, +10%. Growth: 5 ranks, 900g, +3% XP. Greed: 5 ranks, 200g, +10% gold. Curse: 5 ranks, 1,666g, +10% enemy speed/HP/quantity/frequency (an opt-in *difficulty* upgrade sold in the same shop). Revival: 1 rank, 10,000g. Omni: 5 ranks, 1,000g, +2% Might/speed/duration/area. Charm: 5 ranks, 10,000g, +20 enemy spawn quantity. Defang: 5 ranks, 10g, +3% harmless spawns. Reroll, Skip and Banish: 5 ranks each, 1,000/100/100g, +2 per rank. Preserve: 5 ranks, 500g. Seals I-III and Seal All: 10 ranks each, 10,000g, item banishes (pool control). Fever: 5 ranks, 50,000g. — [Vampire Survivors Wiki: PowerUps](https://vampire.survivors.wiki/w/PowerUps)
- Cost formula: Price = InitialPrice x (1 + ranks already bought of that PowerUp) + floor(20 x 1.1^TotalBought), where TotalBought counts ranks bought across *all* PowerUps. The first purchase has no fee. Since v0.7.2 (9 June 2022) the fee is additive, so purchase order no longer matters; before that it was multiplicative. — [Vampire Survivors Wiki: PowerUps](https://vampire.survivors.wiki/w/PowerUps)
- Example: a 200g PowerUp costs 200/400/600/800/1,000 base across its 5 ranks (3,000 total) before fees. — [Vampire Survivors Wiki: PowerUps](https://vampire.survivors.wiki/w/PowerUps)
- Buying every rank costs 42,965,380 gold: 3,219,640 in base cost and 39,745,740 in fees. The global-purchase fee is about 92% of the total, so the cross-upgrade escalation dominates. — [Vampire Survivors Wiki: PowerUps](https://vampire.survivors.wiki/w/PowerUps)
- Refunds: a "Refund PowerUps" button returns all ranks and (slightly less than) all gold spent. After maxing a PowerUp (except Reroll/Skip/Banish/Seals), it can be disabled individually without refunding. — [Vampire Survivors Wiki: PowerUps](https://vampire.survivors.wiki/w/PowerUps)
- Fee growth, derived from the wiki formula (my arithmetic): the fee is about 51g at the 10th rank bought, 134g at the 20th, 348g at the 30th, 905g at the 40th, 2,347g at the 50th and 6,090g at the 60th. The first few dozen ranks are cheap; later ranks are gated mostly by the global fee, not by their own base price. — derived from [Vampire Survivors Wiki: PowerUps](https://vampire.survivors.wiki/w/PowerUps)
- Steam achievements (Vampire Survivors, app 1794680, 243 achievements). Survive 1 min: 97.8%. Survive 10 min: 93.5%. Survive 20 min: 84.0%. Reach Lv20 in Mad Forest: 88.4%. Unlock Hyper for 1 stage: 76.4%; for all 5 stages: 35.6%. Survive 20 min with at least +10% Curse: 58.4% (players opting into harder settings). Find the Randomazzo (the Arcana unlock item): 55.2%. Obtain all standard relics: 21.8%. — [Steam API](https://api.steampowered.com/ISteamUserStats/GetGlobalAchievementPercentagesForApp/v0002/?gameid=1794680&format=json) / [Steam stats page](https://steamcommunity.com/stats/1794680/achievements)

**Brotato: no permanent stat meta; characters plus Danger levels**
- Steam achievements (app 1942280). Die for the first time: 92.9%. Win Danger 0: 72.8%. Danger 1: 60.8%. Danger 2: 54.6%. Danger 3: 48.6%. Danger 4: 42.3%. Danger 5: 36.5%. Best-performing character wins ("Crash Zone"): Ranger 38.1%, Well-Rounded 36.6%, Engineer 32.6%. Most characters fall in the 18-30% range. — [Steam API](https://api.steampowered.com/ISteamUserStats/GetGlobalAchievementPercentagesForApp/v0002/?gameid=1942280&format=json) / [Steam stats page](https://steamcommunity.com/stats/1942280/achievements)
- Each Danger step keeps about 85-90% of the previous step's winners (60.8/72.8 = 0.84, 54.6/60.8 = 0.90, 48.6/54.6 = 0.89, 42.3/48.6 = 0.87, 36.5/42.3 = 0.86). Half of everyone who ever won (36.5 of 72.8) went on to clear the maximum Danger. — derived from Steam data above
- Not verified this session: the exact per-level Danger modifiers and the unlock rule (believed to be: win with a character at level N to unlock N+1 for that character). The Brotato wiki Danger page returned 404. See Gaps.

**Slay the Spire: no stat meta; card/relic unlocks plus Ascension 1-20**
- Steam achievements (app 646570, 46 achievements). Act 1 bosses: Guardian 84.9%, Hexaghost 81.5%, Slime Boss 78.1%. Act 2 bosses: Champ 70.7%, Automaton 65.8%, Collector 64.0%. Act 3 bosses: Donu & Deca 55.4%, Awakened One 54.8%, Time Eater 49.3%. Beat the game with Ironclad 56.0%, Silent 50.4%, Defect 44.0%, Watcher 26.0%. Unlock Ascension (requires a win): 66.3%. Ascension 10 complete: 14.8%. Ascension 20 complete: 7.3%. True ending (Act 4/Heart) with Ironclad 17.2%, with all three base characters 13.1%. Win a Daily Climb: 23.9%. — [Steam API](https://api.steampowered.com/ISteamUserStats/GetGlobalAchievementPercentagesForApp/v0002/?gameid=646570&format=json) / [Steam stats page](https://steamcommunity.com/stats/646570/achievements)
- Note an inconsistency: "Ascend 0 – Unlock Ascension mode" (66.3%) is higher than any single-character win (Ironclad 56.0%). The unlock condition may be broader than "win with this character", or achievement timing may differ. Flag as uncertain.
- Commentary: Slay the Spire's unlocks act like a gradual tutorial for cards and relics. Every win unlocks the next Ascension level, up to 20 (blogger opinion). — [hamatti notes](https://notes.hamatti.org/Gaming/Video-games/Meta-progression-with-gradual-tutorial-in-roguelike-games)
- Mega Crit took a metrics-driven approach to balance from early in development and through Early Access (GDC 2019 talk "Slay the Spire: Metrics Driven Design and Balance", Anthony Giovannetti). The preview article publishes no specific metrics. — [Game Developer](https://www.gamedeveloper.com/design/learn-i-slay-the-spire-i-s-metrics-driven-approach-to-game-balancing-at-gdc-2019); talk on [GDC Vault](https://www.gdcvault.com/browse/gdc-19/play/1025731)

**Rogue Legacy 2: Manor stat upgrades with global cost inflation; House Rules; NG+**
- Manor cost mechanic: each further level of a multi-level upgrade costs more gold, and every upgrade bought raises the cost of all other upgrades. — [Digital Trends guide](https://digitaltrends.com/gaming/rogue-legacy-2-beginners-guide). Game Informer: more ranks cost more for the same flat stat gain. — [Game Informer review](https://gameinformer.com/review/rogue-legacy-2/generations-of-greatness)
- Example price: the Repurposed Mining Shaft costs 900 gold base ("not counting inflation costs") and needs Manor level 12. Each Manor purchase counts as one level. — [Gamepur](https://gamepur.com/?p=344987)
- Anecdotal: in Rogue Legacy 1, each skill purchase seemed to raise all other skill costs by about 10 gold (2013 forum post, not verified). — [Steam discussion (RL1)](https://steamcommunity.com/app/241600/discussions/0/846957366716742648/?l=tchinese)
- Steam achievements (app 1253920, 39 achievements). First Estuary (Lamech): 56.6%. Void Beasts: 46.9%. Naamah: 38.7%. Enoch: 32.0%. Irad: 26.4%. Tubal: 22.9%. Traitor: 22.2%. Immortal King: 20.3%. Enter Topside: 20.3%. Enable House Rules (assist/difficulty settings) at least once: 22.3%. At least 1 point in every Manor skill: 10.7%. NG+ ("Prime") boss kills: Lamech Prime 11.8%, Immortal King Prime 4.3%. Thanatophobia (few-lives challenge) completion: 0.7%. — [Steam API](https://api.steampowered.com/ISteamUserStats/GetGlobalAchievementPercentagesForApp/v0002/?gameid=1253920&format=json) / [Steam stats page](https://steamcommunity.com/stats/1253920/achievements)
- The share of players who enabled House Rules (22.3%) is about the same as the share who beat the final bosses (about 20-22%). This is a correlation only; the data does not show these are the same players.

**Enter the Gungeon: Hegemony Credits buy unlocks (pool expansion), shortcuts cost credits/items**
- Steam achievements (app 311690, 54 achievements). Complete the tutorial: 84.4%. Open the Chamber 2 shortcut: 21.0%. Defeat the Fifth Chamber boss (beat the main game): 20.9%. Spend big at the Acquisitions Department (Hegemony shop): 26.4%. Kill a character's Past: 13.3-14.0% per character. All 4 Pasts: 12.4%. Clear the Sixth Chamber: 10.0%. Advanced boss: 5.8%. — [Steam API](https://api.steampowered.com/ISteamUserStats/GetGlobalAchievementPercentagesForApp/v0002/?gameid=311690&format=json) / [Steam stats page](https://steamcommunity.com/stats/311690/achievements)
- Players complain that drops are so rare that run outcome feels luck-dominated, and suggest spending credits to raise rare drop rates (forum opinion). — [Steam discussion](https://steamcommunity.com/app/311690/discussions/0/364040166689929248). Farming credits is described as tedious. — [Steam discussion](https://steamcommunity.com/app/311690/discussions/0/364040166668726797)
- A 2026 retrospective blog calls Gungeon's meta "stingy": credits add guns and items to the pool without making the player stronger (opinion, commercial blog). — [Choost](https://choost-site.pages.dev/blog/enter-the-gungeon-worth-playing-2026)
- No source found that quantifies "pool dilution" in Gungeon (for example, how much each unlock lowers the chance of strong items).

**The Binding of Isaac: Rebirth: unlocks via achievements (641 achievements)**
- Steam achievements (app 250900). "The Womb – Chapter 4 unlocked" (unlocked by the first Mom kill): 65.7%. "Monstro's Tooth" (first item unlock): 84.6%. "It Lives!" (Mom's Heart kills): 39.2%. "???" character unlocked: 39.9%. "The D6" (Isaac's starting item): 32.1%. "The Polaroid": 33.9%. "The Negative": 33.8%. "Options? – Complete the final chapter with Isaac": 18.5%. Character unlocks: Lazarus 70.2%, Magdalene 60.1%, Cain 59.9%, Judas 44.8%. — [Steam API](https://api.steampowered.com/ISteamUserStats/GetGlobalAchievementPercentagesForApp/v0002/?gameid=250900&format=json) / [Steam stats page](https://steamcommunity.com/stats/250900/achievements)
- Most Isaac achievement descriptions just say "Unlocked a new item", so the boss behind most of them comes from my own knowledge, not this data. The Womb (=Mom) mapping is explicit in the description. Treat the boss mapping for It Lives/Polaroid/Negative/D6 as medium confidence.

### Inferences
- Escalating global costs (Vampire Survivors' 1.1^n fee; Rogue Legacy 2's "every purchase raises all prices") make early stat purchases cheap and frequent and later ones slow. That front-loads the felt progress and caps the total power curve without a hard cap.
- Vampire Survivors sells its difficulty in the same shop (Curse, Charm) and allows full refund plus per-upgrade disabling. Meta stats become a player-set difficulty knob rather than a one-way ratchet. 58.4% of owners survived 20 min with at least +10% Curse, which suggests many players do opt into harder settings when offered.
- Brotato has no stat meta, only characters and opt-in Danger tiers, yet keeps about 85-90% of players from one Danger step to the next, and half of all winners clear max Danger. Optional difficulty with clear per-character goals appears to sustain long engagement without stat grind.
- In both Slay the Spire and Brotato, roughly 55-75% of owners win at least once, without stat meta. Gungeon's unlock meta does not raise power and its win rate is only about 21%. In this sample, stat meta is not required for high first-win rates; base difficulty tuning matters more. (Cross-game comparisons are confounded by genre, run length and audience.)

### Gaps
- Exact Rogue Legacy 2 Manor cost formula and inflation percentage: the wiki was not retrievable; only qualitative descriptions were found.
- Brotato Danger 1-5 per-level modifiers and unlock rules: the wiki page was not reachable. Not stated here to avoid relying on memory.
- Vampire Survivors Arcana count and unlock pacing were not researched beyond the Randomazzo figure (55.2%).
- Enter the Gungeon Hegemony credit unlock costs and total pool size before and after unlocks: not found.
- Isaac: a clean Steam mapping from achievement to boss for Satan, Isaac, ???, Lamb and Mega Satan.

## 2. Design analyses and talks: arguments for and against stat meta progression

### Takeaway
I found few rigorous published analyses. Most commentary is developer blogs, forum threads and press interviews. The recurring arguments: stat meta can trivialise the skill challenge, and it reads as "grind more" rather than "play better". Meta should add variety (sidegrades, new pool content) rather than raw power. Unlocks work well as a gradual tutorial (Slay the Spire). Recently, the Enter the Gungeon creators publicly criticised the genre's drift.

### Cited Findings
- Dodge Roll (Enter the Gungeon creators) said in a 10th-anniversary interview that the genre, post–Vampire Survivors and Balatro, has become "a little bit … cash-grabby" (opinion; the remark is about the genre's direction generally, not specifically stat meta). — [PC Gamer](https://pcgamer.com/games/roguelike/as-enter-the-gungeon-celebrates-its-10th-anniversary-its-creators-have-some-choice-words-for-the-modern-roguelike-were-seeing-it-mutate-to-the-version-of-itself-that-popularity-obfuscates); [Kotaku](https://kotaku.com/enter-the-gungeon-balatro-vampire-survivors-roguelikes-gambling-dodge-roll-cash-grab-2000690804)
- Design guide: permanent upgrades must enhance the experience without trivialising run-to-run skill. If upgrades make runs trivial, meta progression undermines the skill-based core (opinion). — [Bugnet blog](https://bugnet.io/blog/how-to-design-a-roguelite-meta-progression)
- Developer blog: separates in-run power (skill and decisions) from accumulated meta-power. Notes that growing meta-power trivialises the early game, which that developer counters with shortcuts (opinion and practice). — [Echoes of Myth devblog](https://echoesofmyth-devblog.blogspot.com/2025/02/roguelite-meta-progression-and.html)
- "Meta as variety, not power" design pattern write-up. — [saschb2b game-mechanics](https://saschb2b.github.io/game-mechanics/concepts/meta-as-variety-not-power)
- Metasystems essay on roguelites. — [jwittsf design blog](https://jwittsf.design.blog/2020/04/06/metasystems-matter-in-roguelite-games)
- Player sentiment: a widely shared thread title says meta progression "was fun for a while, but it's starting to feel unrewarding" (opinion). — [Lemmy/PieFed thread](https://piefed.keyboardvagabond.com/c/games/p/232999/meta-progression-in-roguelites-was-fun-for-a-while-but-it-s-starting-to-f). A Reddit r/roguelites thread is titled "I really hate meta progression in modern..." — [Reddit mirror](https://redlib.reallyaweso.me/r/roguelites/comments/17u524f/i_really_hate_meta_progression_in_modern/k92zeys/?context=3)
- Steam discussion (Tiny Rogues): game-changing meta needs a smooth progression or players get frustrated when unlocks take many runs (opinion). — [Steam discussion](https://steamcommunity.com/app/2088570/discussions/2/3361397532265670884)
- Slay the Spire's meta is "very limited ... basically works as a tutorial" (forum opinion). Common community definition: a roguelite makes you stronger run to run, a roguelike doesn't. — summarised in search results from [lemm.ee comment](https://lemm.ee/comment/11446768) and [r/gamedesign mirror](https://redlib.ssps.io/r/gamedesign/comments/1kfz99v/can_a_roguelike_have_unlockables)
- Slay the Spire 2 ties unlocks to achievements grouped into "Epochs" on a Timeline feature (secondary source). — [blacknerdproblems](https://blacknerdproblems.com/videos/an-oral-history-inspired-by-the-slay-the-spire-2-timeline/)

### Inferences
- In the sources I found, the anti-stat-meta position is mostly about felt skill expression and avoiding grind. It is not backed by published retention data. The pro-meta position (players who keep losing still feel progress) is mostly implied by market success, not by data.
- The "unlocks as tutorial" framing (Slay the Spire, Isaac) gives a design rule: unlock complexity in the order players can absorb it, and tie unlocks to milestones rather than currency.

### Gaps
- Not retrieved this session, so no claims are made: GDC talks specifically on roguelite meta progression, Derek Yu's Spelunky writing, Josh Ge/Grid Sage meta-progression posts (the URL tried returned 404), Tanya X. Short (Kitfox) talks, and Game Maker's Toolkit videos on meta progression.
- No published A/B or retention data comparing stat meta vs. no stat meta was found.

## 3. Patterns: sidegrades vs stats, choice-based talents, optional difficulty, run modifiers, pool control, unlock pacing

### Takeaway
The datasets above show a few concrete patterns. Optional difficulty ladders with rewards (Brotato Danger, Slay the Spire Ascension, Vampire Survivors Curse/Hyper/Inverse, Rogue Legacy 2 Burdens/NG+, Gungeon Pasts) consistently engage a large minority to half of winners. Pool control as a purchasable meta (Vampire Survivors Banish/Seals/Skip/Reroll) is an alternative to stat power. Assist toggles (Rogue Legacy 2 House Rules) are used by about 1 in 5 owners.

### Cited Findings
- Optional difficulty retention, measured as achievement ratios:
  - Brotato: Danger 5 winners / Danger 0 winners = 36.5/72.8 ≈ 50%.
  - Slay the Spire: A10 / Ascension unlocked = 14.8/66.3 ≈ 22%; A20 / Ascension unlocked ≈ 11%.
  - Rogue Legacy 2: first NG+ Prime boss / Immortal King kill = 11.8/20.3 ≈ 58%.
  - Vampire Survivors: all 5 Hyper stages / at least 1 Hyper stage = 35.6/76.4 ≈ 47%.
  - Enter the Gungeon: all 4 Pasts / beat Fifth Chamber = 12.4/20.9 ≈ 59%.
  - Sources: Steam API links in section 1 (derived ratios).
- Pool control as meta: Vampire Survivors sells Reroll (+2/rank, 5 ranks), Skip, Banish and Seals (up to +40 banishes per Seal type, 10 ranks, 10,000g base). Players can permanently remove items from level-up and light-source pools. — [Vampire Survivors Wiki: PowerUps](https://vampire.survivors.wiki/w/PowerUps)
- Opt-in harder-for-reward: the Vampire Survivors Curse PowerUp (+10% enemy speed/HP/quantity/frequency per rank) is bought in the meta shop, and Greed raises gold gain. Curse is a voluntary difficulty-for-reward ratchet. — [Vampire Survivors Wiki: PowerUps](https://vampire.survivors.wiki/w/PowerUps)
- Assist/House Rules: 22.3% of Rogue Legacy 2 owners enabled House Rules at least once. — [Steam API, app 1253920](https://api.steampowered.com/ISteamUserStats/GetGlobalAchievementPercentagesForApp/v0002/?gameid=1253920&format=json)
- Unlock pacing via cheap early purchases: the Vampire Survivors fee formula keeps the first ~20-30 rank purchases cheap (fee under about 350g) and the curve gets steep after about 40 ranks (derived from the wiki formula). — [Vampire Survivors Wiki: PowerUps](https://vampire.survivors.wiki/w/PowerUps)
- Isaac unlock pacing shows a front-loaded funnel. The first item unlock reaches 84.6%. Most early character/challenge unlocks sit at 55-70%. Deeper unlocks (Polaroid, Negative, D6) cluster at about 32-34%. — [Steam API, app 250900](https://api.steampowered.com/ISteamUserStats/GetGlobalAchievementPercentagesForApp/v0002/?gameid=250900&format=json)

### Inferences
- About 50-60% of winners in Brotato, Rogue Legacy 2 and Gungeon go on to engage with at least one tier of post-win difficulty. Post-win content therefore reaches roughly half of the winning audience, not a niche. Slay the Spire's steep A20 ladder retains far fewer (about 11% of those who unlocked Ascension), which suggests 20 fine-grained tiers lose more players than 5 coarser ones. This is a confounded comparison.
- For a game deciding between stat meta and sidegrades: Vampire Survivors shows a hybrid where stat purchases are reversible and difficulty is sold alongside them. That reduces the "trivialisation" objection while keeping the "progress after a loss" feeling.

### Gaps
- No measured data on choice-based A/B talents (for example, how often players switch, or the effect on retention).
- No published per-run unlock timelines (unlocks per run over the first 10-30 runs) for these games. Reconstructing them needs wiki unlock-condition tables that were not retrieved.

## 4. Published data on runs/hours before first win and before abandoning

### Takeaway
No developer-published "runs to first win" data was found for these games. Steam achievement funnels are the best available proxy. Share of owners who ever got a first win: Brotato about 73%, Slay the Spire about 56% (Ironclad), Rogue Legacy 2 about 20-22% (final bosses), Enter the Gungeon about 21%. For Isaac, about 66% killed Mom at least once. Vampire Survivors is hard to compare because it has no single "win" achievement; 84% survived 20 minutes.

### Cited Findings
- Brotato: died once 92.9% → won Danger 0 72.8%. About 78% of players who ever died went on to win. — [Steam API, app 1942280](https://api.steampowered.com/ISteamUserStats/GetGlobalAchievementPercentagesForApp/v0002/?gameid=1942280&format=json)
- Slay the Spire funnel: Act 1 boss (best) 84.9% → Act 2 boss 70.7% → Act 3 boss 55.4% → Ironclad win 56.0% → Heart 17.2% → A20 7.3%. — [Steam API, app 646570](https://api.steampowered.com/ISteamUserStats/GetGlobalAchievementPercentagesForApp/v0002/?gameid=646570&format=json)
- Rogue Legacy 2 funnel: first Estuary 56.6% → sixth Estuary 22.9% → final bosses about 20-22% → NG+ Prime 4-12% → challenge modes under 1%. — [Steam API, app 1253920](https://api.steampowered.com/ISteamUserStats/GetGlobalAchievementPercentagesForApp/v0002/?gameid=1253920&format=json)
- Enter the Gungeon funnel: tutorial 84.4% → Chamber 2 shortcut 21.0% → Fifth Chamber boss 20.9% → Sixth Chamber 10.0%. The steep drop happens between the tutorial and any deep progress. — [Steam API, app 311690](https://api.steampowered.com/ISteamUserStats/GetGlobalAchievementPercentagesForApp/v0002/?gameid=311690&format=json)
- Vampire Survivors funnel: 1 min 97.8% → 10 min 93.5% → 20 min 84.0% → first Hyper unlock 76.4% → all relics 21.8%. — [Steam API, app 1794680](https://api.steampowered.com/ISteamUserStats/GetGlobalAchievementPercentagesForApp/v0002/?gameid=1794680&format=json)
- Isaac: first Mom kill (Womb unlock) 65.7% → It Lives 39.2% → final chapter with Isaac 18.5%. — [Steam API, app 250900](https://api.steampowered.com/ISteamUserStats/GetGlobalAchievementPercentagesForApp/v0002/?gameid=250900&format=json)

### Inferences
- The two games with the fewest power-granting meta systems (Brotato, Slay the Spire) have the highest first-win rates. The two with the most structural meta and grind (Rogue Legacy 2 Manor, Gungeon credits/shortcuts) have the lowest. This contradicts any simple claim that stat meta guarantees more players see the ending. Large confounders apply: run length (Brotato about 20-30 min), base difficulty, game length (Rogue Legacy 2 has six biomes and is a longer metroidvania-style campaign), price and bundle exposure.
- In games with a heavy drop after the first milestone (Gungeon: 84% tutorial vs 21% shortcut), most abandonment seems to happen before the first meaningful meta milestone, not after.

### Gaps
- No runs or hours to first win were found from developers or telemetry. HowLongToBeat was not queried this session.
- Steam achievement percentages cannot separate "abandoned" from "never launched", and do not give time or run counts.
- Steam review sentiment was not quantified for these games in this session.
