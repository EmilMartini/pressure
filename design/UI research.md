# UI research: why Isaac and Brotato read well (2026-11-11)

Emil, after a fresh-save run: "please research why brotato and isaac UI works so well but ours doesnt". There was 15 minutes for research. Web searches found little written about either game's UI design, so most of this comes from knowing both games. The gap list is checked against our code.

## What they do

**The Binding of Isaac**
- **Almost nothing on screen during a fight.** Hearts and consumable counts sit top-left, the minimap top-right and the active item in a corner. There's no fight title and no counter of enemies left. Floor names show for a moment when you arrive, then go.
- **A pickup is one moment.** You get the item name in big letters and one short tagline under it (often a joke: "Tears up", "Pew pew!"), on a scroll at the top centre. It fades after about 2 s, shows no numbers, and only one shows at a time. You learn what the item does by playing (and from the Repentance+ description popup next to the pedestal, before you pick it up).
- **One place, one job.** The top centre is for announcements and the corners are for state. Nothing appears over the play field except things in the world (pedestals, prices under shop items).
- **Stats are optional.** The Found HUD (numbers for damage, speed and so on) is a toggle in options, off by default for new players.

**Brotato**
- **During a wave you see three things:** HP bar, XP bar and materials top-left, and the wave number and timer top centre. Level-ups don't interrupt the wave. They stack up as icons and are spent at the end of the wave, one screen after another.
- **Every card has the same layout:** icon top-left, name, rarity shown by the frame or background colour, then 2 to 4 short stat lines like "+5 Max HP" / "-3% Speed". Positive numbers are green and negative ones red. The price is always in the same place, and the buttons always sit at the same spot under the card.
- **Four cards in a row, centred, all the same size.** Your eyes go to the same spot every time, so after a few shops you read them without thinking.
- **The stats panel is a list:** name left, number right, green when above base and red when below. One column, no sentences.
- **Text is short and the font is big.** There are no paragraphs in a card. Extra detail (tags, set bonuses) sits on a second line in grey, or in a hover popup.

**Rules we can borrow**
1. During a fight, text only for things you have to act on. Everything else waits for the room to clear.
2. One announcement slot, one message at a time, short, fading.
3. Pickup: big name in its rarity colour, plus one short line. Numbers belong on the card before the pick, not in the announcement after it.
4. Cards: same layout every time, short stat lines, green and red numbers, the price and prompt always in the same place.
5. Fewer popups showing at once. When two compete, queue them.

## Our gaps (audit of the code; no window was available, so nothing was checked by eye)

| Where | What we do | Gap | Status |
|---|---|---|---|
| `hud.gd` `_draw_top` | During a fight: "REGION ROOM" title (28 px), "N LEFT" (40-48 px), "FIGHT" (40 px) in rooms without a count, `main.message` at y 150 | Up to 3 text lines at the top centre during a fight | **Fixed:** the title and "FIGHT" fade 2.5 s after a fight starts, "N LEFT" is smaller until 3 or fewer remain |
| `hud.gd` `_draw_pick` | Pickup line at the bottom-left over the gear row: name + rarity word + the full description at 20 px, up to 800 px wide, 3 s | A sentence to read while moving, next to the busiest HUD area | **Fixed:** Isaac-style banner at the top centre, name big in its rarity colour, one short line, fades out |
| `hud.gd` `_draw_banner` | Synergy banners use the same top slot but can show at the same moment as the pickup line | Two announcements at once, right after a pickup | **Fixed:** they share one slot, and a synergy banner waits until the pickup banner has gone |
| `hud.gd` discoveries | "Discovered: X" at the left edge, during fights | Fight text | **Fixed:** small discoveries wait for the room to clear (as toasts already did); cataclysm moments still show at once |
| `item_card.gd` | Brotato-style rework already done (452 cards checked, the tallest 298 px, cap 300) | Body sentences are still sentences, not stat lines; numbers inline | Open: the next step is a pass over item copy to turn effects into "+X stat" lines with green and red numbers |
| `levelup_screen.gd` | Already batched to room clear (like Brotato's end-of-wave picks). 3 cards, name 30, headline 44, delta 30, extra 26 | 26 screens in 21 minutes; each needs a fresh read | Open: show the number of picks left more prominently and keep the same card positions (already true) |
| `mastery_screen.gd` / Shrine | Detail panel from the text-readability pass | No window check yet | Open: needs a windowed look |
| Character sheet | Stats as sentences in the body font | Brotato's sheet is one list of name + number | Open |

## What changed on screen (this pass)
See the commit messages for `2026.11.11-ui-calm`. The points to look at in a run:
1. Walk into a fight room: the region and room title and "FIGHT" go away after about 2.5 s. "N LEFT" is smaller, then grows and turns orange at 3 or fewer.
2. Pick up an item or gun: a banner at the top centre with the name big, the rarity word small and one short line. It fades after about 2.5 s. The old line above the gear row is gone.
3. Pick an item that completes a synergy: the synergy banner comes after the pickup banner, in the same place, not on top of it.
4. A new reaction in a fight: "Discovered: X" shows after the room is clear, not during the fight.
