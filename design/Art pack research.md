# Art pack research

Research date: 9 November 2026. Nothing was bought or downloaded. Prices are in USD as shown on the store pages on that date, and itch.io prices change often with sales.

## Bottom line

No pack or series covers everything Pressure needs. The 11 region themes, 12 enemy archetypes with full animation sets, bosses, elemental effects and UI are not all available from one artist at a size that reads like The Binding of Isaac. The two closest options are:

- **ELV Games' Rogue Adventure** has the right dark tone and bigger enemies and bosses.
- **Krishna Palacio's Minifantasy** covers the most themes, but its sprites are very small.

Either way, some art (a few themes and most elemental effects) will need an artist or code-drawn work. Lighting and glow (the Ori half of the bar) must come from Godot. None of the packs reviewed ships normal maps or light data.

**Two licence points for every option:**

1. **The public repo.** Every paid licence reviewed forbids redistributing the asset files. Committing them to the public GitHub repo would make them downloadable by anyone, and Minifantasy's author has said so directly (see below). Only CC0 packs (Kenney, Ninja Adventure, 0x72) can safely sit in the public repo. Any paid pack needs its art kept out of the public repo, for example in a git-ignored folder or a private submodule or asset repo.
2. **AI-code clauses.** Some licences ban more than AI training. **Mana Seed** forbids use "in a project alongside 'AI' generated imagery, writing, code, or anything else". Pressure's code is written with Claude, so Mana Seed is excluded. **32rogues** forbids use "in conjunction with generative artificial intelligence projects", which is ambiguous, so it is excluded too. Other licences only ban using the art to train AI, which does not affect Pressure.

## How this was checked

- Each licence was read on the creator's own page or licence page, not on a summary site. Where only a forum comment or snippet was available, the entry says so.
- AI status comes from itch.io's "No generative AI was used" content tag, or from the creator's own written policy.
- **Pages that could not be read:**
  - OpenGameArt returned 403 Forbidden, so the LPC licences were not checked there.
  - Anokolisa's Terms PDF is on Google Drive and did not render.
  - The CraftPix `/pricing/` page returned 404. Its `/membership/` page was used instead.
  - Two URLs I guessed for individual Time Fantasy and Minifantasy pages returned 404. The bundle and other pack pages were used instead.

**Scale note.** At pixel_size 3, the game view is about 426×240. A 16×16 character is then about 1/15 of the screen height. Isaac's player is roughly twice that share of the screen. So the "big readable characters" goal favours 32–48 px enemy frames. Minifantasy's 8×8 grid would need pixel_size 5–6, which shrinks the playfield.

---

## Candidates

Fit is scored from 1 to 5 against Pressure's needs: cohesion, coverage, readability and licence.

### 1. ELV Games: Rogue Adventure (pixel, 16×16 tiles)

- **Style and resolution:** Dark pixel art "inspired by games such as Dark Souls and Diablo". The tiles are 16×16.
  - Enemy frames are 32×32 and 48×48.
  - Boss frames are 64×64 (Werewolf) and 80×80 (Abysslime, Toxic Vermin, Minotaur, Molarbeast).
  - Characters and enemies face left and right only (two directions), which matches Isaac's side-facing enemies.
- **Themes (of 11):** The series has 18 tilesets: Ancient Ruins, Atlantis, Beast Interior, Cavern, Crypt, Graveyard, Hell, Interior, Jungle, Lost City, Overworld, Pyramid, Ruins, Sanctuary, Ship, Temple, Village and Wasteland. They are listed as over 15,000 tiles, including more than 1,000 animated ones. Mapped to Pressure's regions:
  - **Good fit (5):** crypt (Crypt, Graveyard), rusted ruins (Ruins, Ancient Ruins), forge/lava (Hell), chapel (Sanctuary, Temple), hub (Village, Interior).
  - **Partial (4):** cistern (Atlantis), rotting gardens (Jungle, Graveyard), void rift (Lost City, Hell), abattoir (Beast Interior; not inspected).
  - **None (3):** frozen vault, storm tower, tar swamp. The store page has no ice, swamp or storm Rogue Adventure pack. ELV's Frozen Caves and Magma Caves tilesets belong to its separate Farming Game line.
  - **Total:** about 5 good and 4 partial.
- **Enemies:** 24 unique enemies, each in 4 variants, sold as Enemy Sprites Packs 1–4. Each has six-frame **idle, walk, attack, damage and death** animations. Pack 1 also has jump and fall. Enemy names are not listed on the page.
- **Heroes and NPCs:** 30 hero sprites with idle, walk, attack, jump, fall and dead animations, plus a Hero Creator tool.
- **Bosses:** 10, among them Werewolf, Ancient Bear, Osiris, Minotaur, Molarbeast, Titan Guard, Pumpkin Jack, Abysslime and Toxic Vermin.
- **Effects and UI:** More than 1,000 item icons and a UI set. Spell effects are not included; a vendor comment says they are sold separately.
- **Price:**
  - Rogue Adventure World (everything above): **$39.99**.
  - Single tilesets: $5.99–7.99. Enemy packs: $4.99 each.
  - The Game Assets Mega Bundle (290 ELV packs) showed **$59.99** on the pack pages but **$120** on the store front, so check before buying.
  - The All-Access Pass is $189.99.
  - URLs: https://elvgames.itch.io/rogue-adventure-world, https://elvgames.itch.io/ra-enemies-01, https://elvgames.itch.io/
- **Licence** (https://elvgames.itch.io/terms):
  - Commercial use is allowed, and assets may be edited if you "make sure it's clearly stated they have been modified".
  - Assets "may not be resold, published, or distributed in any way except as an integral part of the project".
  - Crypto and NFT use is banned. No credit is required. No engine limit is stated, and the pages list Godot.
  - Pack pages (seen in search results) also bar use for "Training/Generative AI".
  - **Public repo:** not addressed. Keep the art out of the public repo.
- **AI status:** "No generative AI was used" tag on the World, Enemy Pack 1 and Crypt pages.
- **Maintenance:** Active. The World pack was released in December 2024 and updated about 20 days before this check. Enemy Pack 1 was updated in March 2025.
- **Fit: 4/5.** It has the right mood, mid-size enemies, real bosses and full animation sets, and one studio made it all. It lacks elemental effects and 3 themes, and its 16×16 tiles keep rooms busy rather than chunky.

### 2. Krishna Palacio: Minifantasy (pixel, 8×8 grid)

- **Style and resolution:** Very low-resolution chibi pixel art on an 8×8 grid ("8x8 super low-res"). Characters face four diagonal directions (NW, NE, SW, SE). The style is extremely consistent across more than 80 packs.
- **Themes (of 11):** about 10 at least partly; only abattoir is missing.
  - crypt: Crypt of the Forgotten, Necropolis
  - cistern: Sewers, Sunken City
  - rotting gardens: Ancient Forests, Plants & Foliage
  - rusted ruins: Lost Civilization, Raided Village
  - frozen vault: Icy Wilderness (outdoor)
  - tar swamp: Silent Swamp
  - storm tower: Towers, Wizards Academy
  - forge/lava: Hellscape, Dwarven Workshop
  - chapel: Temples and Shrines
  - void rift: Warp Lands, Nightmare Realm, Fae Depths
  - hub: Towns I and II, Medieval City
  - abattoir: none
- **Enemies:** many packs.
  - Creatures (free), Undead Creatures, Forest Dwellers, Dark Orc Army, Dark Brotherhood, True Villains I and II, and Enchanted Companions.
  - Monster Creatures has 14 creatures with idle, walk, attack, damage and die. The first four animations come in 4 directions; die is 1 direction.
  - Nightmare Creatures has 10 creatures with appear, idle, move, attack, damage and die.
  - Enemy coverage is the widest of any candidate. I verified two packs in detail.
- **Bosses:** No dedicated boss pack. The closest are multi-phase creatures such as Bicephalous (Nightmare Creatures), and large ones such as the Giant and the Centaur King.
- **Effects:**
  - Spell Effects covers fire, ice, poison and electric (burst, aura and tileable versions, plus 12 premade patterns).
  - Spell Effects II and Magic Weapons and Effects add more.
  - No water or explosion category is listed.
- **UI:** UI Overhaul ($9.99) has panels, bars, buttons, icons, controller and keyboard glyphs and cursors in 3 styles. Fonts are not included. A Portrait Generator and A Myriad of NPCs cover NPCs.
- **Price:** **Complete Bundle $69.99 for 82 packs**, as shown on the pack pages. It includes packs released up to the purchase date only. Single packs cost $4.99–9.99. URLs: https://krishna-palacio.itch.io/, https://krishna-palacio.itch.io/minifantasy-dungeon
- **Licence** (on each pack page and in license.txt):
  - The commercial licence allows use in commercial games and editing.
  - It is "NOT allowed to re-distribute or re-sell any of the assets ... or any altered versions".
  - **Credit to Krishna Palacio is required**, and you must send the author a link to the finished project.
  - No engine restriction: the author said "the license doesn't have any engine restriction".
  - **Public repo:** the author said the assets are not publicly licensed and **advised a private repo** (itch.io forum reply, found via search). Keep the art out of the public repo.
  - No AI clause in the licence.
- **AI status:** "No generative AI was used" on every page checked.
- **Maintenance:** Very active. New packs come out regularly, Nightmare Creatures v1.1 came out in May 2026, and the bundle price rose in February 2026.
- **Fit: 3/5.** It covers the most themes from a single artist, with a coherent look, effects and UI. But the 8×8 scale works against "big readable characters", and boss art is thin.

### 3. Pixel-Boy and AAA: Ninja Adventure (pixel, 16×16, CC0)

- **Style and resolution:** Bright, Zelda-like 16×16 pixel art. Many characters have 4-direction animations.
- **Themes (of 11):** about 2–3. Village, desert town, ancient ruins, water, interiors and towers are shown. A dungeon or cave set was requested and is not confirmed. Snow, swamp and lava are not mentioned. The tone is cheerful, not grim.
- **Enemies:** 30+ monsters and 9 bosses, all animated. Named examples include a slime, a dragon, a bear, a frog, a fire creature and a tentacled creature.
- **Other contents:** 50+ characters with facesets (useful for NPCs), 30+ visual effects, UI elements, 60+ items, 2 fonts, 100+ sound effects, 37 music tracks, and a Godot 4 example project.
- **Price:** free (name your own price). https://pixel-boy.itch.io/ninja-adventure-asset-pack
- **Licence:** **CC0 1.0**. No credit is required, but it is appreciated. **Public repo: allowed.** The authors keep their own Godot project on GitHub.
- **AI status:** "No generative AI was used."
- **Maintenance:** Active. Update #8 came out on 29 March 2026.
- **Fit: 3/5.** It is the best free and public-repo-safe all-rounder, with enemies, bosses, effects and UI from one team. But its cute tone and missing dark themes are far from Pressure's world.

### 4. GameDeveloperStudio (Robert Brooks): hand-drawn vector

- **Style and resolution:** "Hand drawn 2D game assets, all created in one cohesive style by a single artist". Clean cartoon vector art delivered as HD PNG and SVG. This is the only non-pixel source found that covers characters as well as environments.
- **Themes (of 11):** about 2–3.
  - The Top-down dungeon environment pack has about 300 128 px pieces: walls, floors, holes, grills, traps and torches.
  - There are also the Castle and dungeon stone tiles and the Top down creepy environmental pack.
  - Grass and military packs exist but are off-theme.
- **Enemies:**
  - The Four-directional dungeon enemy bundle has 8 packs: eyeball monster, dungeon soldier, bat, ghost, skeleton soldiers, mimic chest, rat and slimes.
  - Dungeon guards have idle, move, attack, hurt, defend and defeated animations.
  - Top-down bug, larva, slug and tentacle monsters have idle, move, attack (spit or fire), and death animations.
  - Rigs are Spriter files.
- **Bosses:** none found. **Effects and UI:** the site sells some, but they were not evaluated.
- **Price:** Dungeon enemy bundle **$55** ($48 for GDS supporters). Other packs are priced individually, and some are free. https://www.gamedeveloperstudio.com/graphics/viewgraphic.php?page-name=Four-directional-dungeon-enemy-bundle&item=1q6a978n7k3c6w4k5r
- **Licence** (https://www.gamedeveloperstudio.com/license.php):
  - Commercial use and modification are allowed, and no credit is required.
  - "You may NOT redistribute, share or make available for download any asset obtained from this site." **Keep it out of the public repo.**
- **AI status:** "Not a single piece of art here is generated by AI" (https://www.gamedeveloperstudio.com/no-ai.php).
- **Maintenance:** The site is active. Dates of individual packs were not checked.
- **Fit: 2.5/5.** This is the cohesive hand-drawn route, but it covers few themes and has no bosses. The generic cartoon look would need strong art direction to reach the Isaac bar.

### 5. Anokolisa: Pixel Crawler (pixel, 16×16)

- **Style and resolution:** Clean 16×16 top-down pixel art.
- **Themes (of 11):** about 5.
  - crypt: Cemetery
  - cistern: Sewer
  - gardens: Garden, Fairy Forest
  - forge: Forge
  - chapel: the Cemetery church, partly
  - Also Desert, Castle, Hideout, Library and Cave.
- **Enemies:**
  - The free pack has 8: four skeleton types and four orc types, with idle, run and death only.
  - Cemetery adds four zombies (the Banshee has a hit animation) and a Hunter with 3 attacks.
  - Two bat packs are included.
  - Enemy attack animations are mostly missing.
- **Bosses:** none. **Effects and UI:** none seen.
- **Price:** **Pixel Crawler Complete Collection: $20 for 13 packs** (regular price $110). https://itch.io/s/81883/pixel-crawler-complete-collection
- **Licence:** **Not verified.** The store pages link a "Terms" PDF on Google Drive that would not render (https://drive.google.com/file/d/17y1gjuwVirE8V79WcTL9tgTUtMu6R1je/view). Buyers asking about commercial use in the Q&A thread got no reply. Treat it as unknown until the PDF is read.
- **AI status:** "No generative AI was used."
- **Maintenance:** Active (free pack devlog of 10 July 2026). Several packs are marked as in progress.
- **Fit: 2/5.**

### 6. Penusbmic: DARK Series and others (pixel)

- **Style and resolution:** Moody, detailed pixel art, mostly **side-view** (metroidvania). Top-down content is limited:
  - Top Down Monster Pack 1: 3 monsters with idle, 4-direction move, attack, hit and death.
  - Top Down Hero, The Hunter.
  - Dungeon Enemy Packs 1–3.
  - Top-down Homes & Shelters (16×16).
- **Themes (of 11):** about 1 top-down.
- **Bosses:** many (Bone Reaper, Lord of Flames, Colossal, Shadow of Storms and others), but they are side-view.
- **Effects:** FX packs, also side-view.
- **Price:** Top Down Monster Pack 1 costs $2.55. The **Complete Library Bundle costs $99.99 for 223 packs**. https://penusbmic.itch.io/the-dark-series-top-down-monster-pack-1
- **Licence:** The pack page says "Feel free to use for commercial projects and modify", and "Please do not resell the assets individually". Credit is optional, as "Penusbmic". There is no formal licence file, and public repos are not addressed. Keep the art out of the public repo.
- **AI status:** "No generative AI was used."
- **Fit: 1.5/5.** The art is good, but it is the wrong perspective for Pressure.

### 7. 0x72: DungeonTileset II (pixel, 16×16, CC0)

- **Contents:** 1 theme (dungeon), with autotiles since v1.7. Monsters include slugs, dwarfs, a zombie and a pumpkin character. The author says there is **no attack animation**, and death animations are not made.
- **Price:** free. **Licence:** CC0 (art) and MIT (code). **Public repo: allowed.** https://0x72.itch.io/dungeontileset-ii
- **AI status:** "No generative AI was used." **Last update:** v1.7, March 2024.
- **Fit: 1.5/5.**

### 8. Szadi art (pixel, 16×16 and 32×32)

- **Contents:** Environment-only tilesets. Rogue Fantasy Catacombs and Castle, Magic Pixels Dungeon, the RPG Worlds series (Snowy Lands, Marshland and others), and many side-scroller sets. **No enemies, bosses or effects.**
- **Price:** single packs cost $2.40–18. Bundles are linked, but their totals were not shown. https://szadiart.itch.io/
- **Licence** (Rogue Fantasy Catacombs page): "Public domain and free to use, personal or commercial". Credit is not required. "You can edit, but not resell the asset pack (original or changed)". Despite the "public domain" wording, the resale ban means it is not true public domain, so redistribution in a public repo is unclear.
- **AI status:** "No generative AI was used" (Catacombs).
- **Fit: 1.5/5.**

### 9. Time Fantasy / Time Elements (finalbossblues; pixel, 16×16)

- **Style:** Classic SNES JRPG. Characters are about two tiles high.
- **Themes (of 11):** about 3–4. Castle and Catacombs, Caves and Mines, Ruined Dungeons, Final Tower, Dark Dimension (free) and Winter tiles.
- **Enemies:** The Action RPG Monsters pack ($50) has 20+ monsters with variants and elites. Most are not 4-directional, and some have 2 flippable diagonals. RPG Sprites 2 also includes monsters.
- **Effects and UI:** Pixel Animations and Effects ($6), 1000+ icons ($6) and Faces ($8).
- **Price:** **RPG Pixel Art Asset Full Bundle: Time Fantasy Elements, $180 for 22 packs.** https://finalbossblues.itch.io/tf-rpg-charactersprites-1
- **Licence:** No formal licence on the pages. The author says in comments "commercial use is fine! No restrictions!" and "My terms disallow redistribution". The RPG Maker store versions are restricted to RPG Maker; the itch.io versions are engine-free. Keep the art out of the public repo.
- **AI status:** "No generative AI was used."
- **Maintenance:** Ongoing via Patreon.
- **Fit: 2/5.** It is cohesive, but the cozy JRPG look and small enemies do not suit a shooter.

### 10. Seliel the Shaper: Mana Seed (pixel, 16×16): **EXCLUDED**

- **Contents:**
  - Dungeon and castle tilesets, e.g. Eternal Dungeon at $14.99. The Exotic Locales bundle is shown at $69.95 for 9 assets.
  - 9 animated monster packs at $5.99–9.99 each.
  - No bosses and no UI pack.
  - The style is cozy farming-sim.
- **Licence:** Commercial use and editing are allowed, and credit is optional. Redistribution is forbidden. The licence also bans use "in a project alongside 'AI' generated imagery, writing, code, or anything else". **Pressure's code is AI-assisted, so this licence is incompatible.** https://selieltheshaper.weebly.com/user-license.html
- **AI status:** "100% HUMAN-MADE".
- **Fit: 0** (licence conflict).

### 11. Kenney: Tiny Dungeon and others (pixel, CC0)

- **Contents:** Tiny Dungeon is 16×16, 130 files, v1.0 from 2022. Sprites are **static**, with no animations.
- **Price:** free. **Licence:** CC0. **Public repo: allowed.** https://kenney.nl/assets/tiny-dungeon
- **AI status:** No AI statement on the asset page. Kenney has publicly opposed generative AI assets, for example by banning them on r/gameassets in 2024, and his account is listed under itch.io's no-AI tag.
- **Fit: 1/5.** Good for placeholders only, and it is part of the current mismatch.

### 12. CraftPix: **EXCLUDED (AI status unclear)**

- **Contents:** The RPG Top-Down Pixel Art Assets Collection lists a very wide theme range (dungeon, sewer, swamp, winter, cave, chapel, blacksmith, mage tower and more), plus monsters, a slime boss, elemental projectiles and UI. But it is many artists' work, so cohesion varies.
- **Price:** Membership costs $15 per month or $24 per year. Assets downloaded during the membership stay usable after it ends.
- **Licence** (https://craftpix.net/file-licenses/): Commercial use and modification are allowed. "Distribution of source files is NOT permitted", so keep the art out of the public repo. The art may not be used to train AI.
- **AI status:** The product pages checked have **no AI statement**. The only "no AI" claim found was second-hand, from an itch.io forum post quoting a CraftPix reply. Per the hard rule, it is excluded.

### 13. Smaller or supplementary finds

- **Pimen: elemental effects (pixel).** Good for filling effects gaps.
  - Effects: Mega Pack Elemental Spell Effects 01 ($12.75 on sale) has 50+ animations covering thunder, fire, water, earth and wind. Mega Pack 02 adds wood, dark and acid. Separate packs cover ice and holy, plus buff and debuff status packs.
  - Bundles: the **All VFX Bundle costs $70.54 for 17 packs** (https://itch.io/s/183490). It contains Mega Packs 01 and 02, smoke, hits, slashes, projectiles, explosions and 9 buff/debuff packs. Separate element packs may not all be in it.
  - Licence (author comment only): commercial use and modification allowed; "You can't resell or redistribute them."
  - AI status: "No generative AI was used."
  - Gaps: no blood or poison packs (acid is the nearest).
- **Daniel Thomas: 2D Hand Painted Tileset Pack (hand-painted, 128×128).**
  - Contents: 7 tilesets (Dungeon, Mine, Snowland, Town, Interior, Grassland, Extra Objects) for **$65** (https://itch.io/s/10610/2d-hand-painted-tileset-pack). The dungeon set has 55 floor and 72 wall tiles.
  - No characters.
  - Licence text is not on the itch.io page, so it is unverified. AI status: "No generative AI was used."
  - Fit 2 for a hand-painted route.
- **bobddadoo: Tiny Questers Character Bundle Vol. 1 (pixel).**
  - Contents: 3 heroes, 8 town NPCs, 9 monsters; idle, walk, 4-direction attack, hit and die. **$24.99.** No tiles or bosses.
  - Licence: commercial use and editing allowed; no redistribution; no AI training.
  - AI status: "No generative AI was used."
  - Link: https://bobddadoo.itch.io/tiny-questers-character-bundle-vol1
- **Kenmi: Cute Fantasy RPG (pixel, 16×16).**
  - Contents: a cozy farm-RPG style with a few enemies (skeletons, slime, bombshroom).
  - Licence: the Premium version ($3.99+) is commercial; no redistribution; credit requested.
  - AI status: "No generative AI was used." Fit 1.
- **Oryx Design Lab (pixel, mostly static).**
  - Contents: the Sprite Mega Pack costs $40.
  - Licence (https://www.oryxdesignlab.com/license): credit to oryxdesignlab.com is required. The files "MAY NOT BE REDISTRIBUTED", and the licensee should "protect the game artwork", e.g. inside archives. **This rules out the public repo.**
  - AI status: no AI statement found, so it is unclear under the rule. Fit 1.
- **Seth: 32rogues (pixel, 32×32, static).** Excluded for its generative-AI-project clause (see the top of this report).
- **Unity Asset Store.**
  - Unity's support article says Asset Store assets may be used with other engines under the EULA (https://unity.com/legal/as_terms).
  - The EULA allows distribution only "as incorporated and embedded in that Licensed Product" (§2.2.1(b)) and reserves all other rights (§9.2). So **keep any such assets out of the public repo.**
  - The Daniel Thomas hand-painted dungeon is also sold there. No Unity-store pack was found that beats the itch.io options for top-down roguelite coverage.
- **Humble Bundle.** Its 2D asset bundles are time-limited mixes of many artists, and none was running for top-down pixel art. Not a basis for a cohesive look.
- **LPC (Liberated Pixel Cup).** Not checked, because OpenGameArt returned 403.

---

## Ranked shortlist

### 1. ELV Games: Rogue Adventure World ($39.99; or the Mega Bundle, $59.99–120)

Best match for tone and readability. It has dark Diablo-like themes, 32–48 px enemies with idle, walk, attack, damage and death, 10 bosses at 64–80 px, 30 heroes, a hero creator, 1,000+ icons and UI, all from one studio. It is no-AI tagged and actively updated.

**Gaps for an artist or code:**
- **Themes:** frozen vault, storm tower and tar swamp have no tileset. Abattoir and void rift need re-dressing or recolours (Beast Interior, Lost City or Hell).
- **Effects:** all elemental effects and projectiles. Use code-drawn effects in the pack's palette, or ELV's separate spell packs (not evaluated).
- **Enemy roles:** check the 24 enemies against Pressure's 12 archetypes. Bomber, splitter, swarmer and wisp may need edits.
- **Licence handling:** the art must stay out of the public repo, and edits should be marked as modified.

### 2. Minifantasy Complete Bundle ($69.99, 82 packs)

Widest coverage from one artist. About 10 of the 11 themes plus the hub, dozens of 4-direction enemies with full animation sets, fire, ice, poison and electric effects, a full UI kit and NPCs. All no-AI, and very actively maintained.

**Gaps for an artist or code:**
- **Scale:** the 8×8 scale is the big cost. Characters will not read as "big" without zooming to pixel_size 5–6, and a smaller playfield changes the gameplay.
- **Missing art:**
  - the abattoir theme
  - dedicated bosses
  - effects for water, oil, gale, stone, blood, holy and void
- **Licence handling:** credit and a link-back are mandatory, and the art must stay out of the public repo.

### 3. Ninja Adventure (free, CC0)

The only option that is complete enough, free, and **safe to commit to the public repo**. It has 30+ monsters, 9 bosses, 50+ characters, 30+ effects, UI, fonts, sounds and music, from one team, with a Godot 4 sample.

**Gaps for an artist or code:**
- **Tone:** cheerful and Zelda-like, the opposite of Pressure's crypt and abattoir mood.
- **Themes:** most of the 11 are missing (crypt, abattoir, forge, void, frozen vault, tar swamp, storm tower).
- **Scale:** 16×16 sprites are small for the Isaac bar.

Use it if keeping the repo fully public and asset-complete matters more than tone.

**Non-pixel alternative:** GameDeveloperStudio's hand-drawn vector art (no-AI guaranteed, a single artist) is the only cohesive non-pixel source with animated top-down enemies. It covers too few themes and has no bosses, so it would mostly mean commissioning the rest from the same artist.

---

## Sources

- Minifantasy: https://krishna-palacio.itch.io/ · https://krishna-palacio.itch.io/minifantasy-dungeon · https://krishna-palacio.itch.io/minifantasy-nightmare-creatures · https://krishna-palacio.itch.io/minifantasy-monster-creatures · https://krishna-palacio.itch.io/minifantasy-spell-effects · https://krishna-palacio.itch.io/minifantasy-ui-overhaul · https://krishna-palacio.itch.io/minifantasy-true-heroes · https://krishna-palacio.itch.io/minifantasy-crypt-of-the-forgotten · https://krishna-palacio.itch.io/minifantasy-dungeon/devlog/701876/how-to-get-the-most-out-of-minifantasy
- ELV Games: https://elvgames.itch.io/ · https://elvgames.itch.io/rogue-adventure-world · https://elvgames.itch.io/terms · https://elvgames.itch.io/ra-enemies-01 · https://elvgames.itch.io/rogue-adventure-crypt · https://elvgames.itch.io/rogue-adventure-boss-abysslime
- Ninja Adventure: https://pixel-boy.itch.io/ninja-adventure-asset-pack
- GameDeveloperStudio: https://www.gamedeveloperstudio.com/ · https://www.gamedeveloperstudio.com/license.php · https://www.gamedeveloperstudio.com/no-ai.php
- Anokolisa: https://anokolisa.itch.io/ · https://anokolisa.itch.io/crawler-dungeon-prison · https://anokolisa.itch.io/pixel-crawler-cemetery · https://itch.io/s/81883/pixel-crawler-complete-collection · https://itch.io/t/4585143/pixel-crawler-qa
- Penusbmic: https://penusbmic.itch.io/ · https://penusbmic.itch.io/the-dark-series-top-down-monster-pack-1
- 0x72: https://0x72.itch.io/dungeontileset-ii
- Szadi art: https://szadiart.itch.io/ · https://szadiart.itch.io/rogue-fantasy-catacombs
- Time Fantasy: https://timefantasy.net/ · https://finalbossblues.itch.io/ · https://finalbossblues.itch.io/action-rpg-monsters · https://finalbossblues.itch.io/tf-rpg-charactersprites-1
- Mana Seed: https://seliel-the-shaper.itch.io/ · https://seliel-the-shaper.itch.io/eternal-dungeon · https://selieltheshaper.weebly.com/user-license.html
- Kenney: https://kenney.nl/assets/tiny-dungeon
- CraftPix: https://craftpix.net/file-licenses/ · https://craftpix.net/membership/ · https://craftpix.net/sets/rpg-top-down-pixel-art-assets-collection/ · https://itch.io/post/15953382
- Pimen: https://pimen.itch.io/ · https://pimen.itch.io/mega-pack-elemental-spell-effects · https://itch.io/s/183490
- Daniel Thomas: https://danielthomasart.itch.io/dungeon-tileset · https://itch.io/s/10610/2d-hand-painted-tileset-pack
- bobddadoo: https://bobddadoo.itch.io/tiny-questers-character-bundle-vol1
- Kenmi: https://kenmi-art.itch.io/cute-fantasy-rpg
- Oryx: https://www.oryxdesignlab.com/products · https://www.oryxdesignlab.com/license
- 32rogues: https://sethbb.itch.io/32rogues
- Unity: https://unity.com/legal/as_terms · https://support.unity.com/hc/en-us/articles/34387186019988-Can-I-use-assets-from-the-Asset-Store-with-other-engines
