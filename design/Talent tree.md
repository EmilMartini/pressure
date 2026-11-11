# Talent tree

The Shrine's talent tree, rebuilt in the style of modern World of Warcraft talents (Emil, 2026-11-11).
Code: `scripts/mastery.gd` (data, effects, migration), `scripts/mastery_screen.gd` (the screen).

## Why

On 2026-11-10 Emil said "its not fun", including "no growth or reward". The Shrine before this was
eleven A/B slots of small numbers (Hades' Mirror after `reports/Roguelite meta progression analysis.md`
R4): +4% range or +5% shot speed, +1.5% potency or +4% element duration. Each pair was a fair trade,
but neither side changed what you do in a fight, so buying a rank felt like nothing.

Modern WoW trees fix exactly this. Small passive nodes are the path; the reward is a **choice node**
on that path where you pick one of two effects that change how you play ("Burning foes spread fire
when they die" or "Fire burns twice as long"). Picks swap for free out of combat. The research's other
findings still hold, so they stay: permanent stat power stays small, survival stays a cheap capped
track (Last Breath), and a full refund is free.

## Structure

Five branches, one per playstyle. Each branch is a column of five nodes, top to bottom:

| Row | Kind | Ranks | Cost (Embers) | Unlocks when |
|---|---|---|---|---|
| 1 | Passive | 3 | 3, 6, 10 | always |
| 2 | Choice | 1 | 12 | row 1 is full |
| 3 | Passive | 3 | 8, 14, 22 | row 2 is bought |
| 4 | Choice | 1 | 24 | row 3 is full |
| 5 | Capstone choice | 1 | 40 | row 4 is bought |

- **The path is the gate.** A node opens when the node above it in its branch is full, the way a WoW
  node needs its parent maxed. No separate "points spent" gates: with five short columns they add a
  rule to read without adding a decision. Costs climb by row, so the capstones are the long goals.
- **A choice node is bought once.** Then both options are yours; you pick one. Switching is free
  and unlimited in the Hollow (the Shrine screen), never during a run. A fresh choice node starts on
  option A.
- **Branches are independent.** You can rush one capstone or spread out. One branch costs 139 Embers;
  the whole tree costs 695, plus Last Breath 153: 848 in all (the old board was 775 + 153).
- **Last Breath** (3 revives, 3 / 50 / 100) is unchanged and sits under the tree.
- **Refund all** stays free and returns every Ember, picks included.

Every node ID is new, so nothing from the old board carries over by accident (see Migration).

## The tree

`P` passive, `C` choice. Effects in brackets are the code's vocabulary (Items triggers and stats).

### Pyre (fire and reactions)

| Row | Node | Effect |
|---|---|---|
| P1 | Kindling | +2% reaction potency per rank (merges Catalyst) |
| C2 | **Wildfire** | Burning foes spread fire to foes near them when they die [kill, if burning: spread fire 120 px] |
| | **Slow Burn** | Fire burns twice as long [burn_time +1.0] |
| P3 | Lingering Touch | +5% element duration per rank (merges Lingering Touch) |
| C4 | **Flashpoint** | Every 4th reaction sets off a fire blast [reaction, every 4: fire nova 110 px] |
| | **Feeding Flame** | Reactions heal you [+1 HP per reaction] |
| C5 | **Pyre Heart** | Elite kills erupt in a huge fire blast [elite_kill: fire nova 220 px, potency 14] |
| | **Ash Wake** | Kills on burning foes leave a fire cloud [kill, if burning: fire cloud 70 px, 3 s] |

### Rime (ice and control)

| Row | Node | Effect |
|---|---|---|
| P1 | Thick Skin | +4 max HP per rank (merges Thick Skin) |
| C2 | **Shatter** | Frozen foes take 30% more damage [vs_frozen 0.30] |
| | **Frostbite** | Hits on wet foes may freeze them [hit, if wet, 25%: apply ice] |
| P3 | Cold Blood | +1% dodge per rank (merges Sidestep) |
| C4 | **Cold Snap** | When you are hit, foes near you freeze [hurt: ice nova 150 px] |
| | **Bramble** | Foes that hit you take 10 damage [thorns 10] |
| C5 | **Winter's Grip** | Entering a room slows every foe near you [room_enter: slow 420 px] |
| | **Shatterburst** | Frozen foes burst into ice when they die [kill, if frozen: ice nova 120 px] |

### Stride (dash and movement)

| Row | Node | Effect |
|---|---|---|
| P1 | Light Feet | +2% move speed per rank (merges Light Feet) |
| C2 | **Frost Trail** | Your dash leaves a trail of ice [dash: ice trail 2.5 s] |
| | **Second Wind** | A kill gives back a dash charge [kill: refill one dash] |
| P3 | Quick Recovery | Dash recharges 6% faster per rank [dash_cooldown] |
| C4 | **Shoulder Charge** | Your dash hits every foe it passes through [dash_hit 1.0] |
| | **Close Shave** | Dodging a hit with a dash: +30% damage for 3 s [perfect_dodge: buff] |
| C5 | **Twin Dash** | One more dash charge [dash_charges +1] |
| | **Dash Volley** | Each dash fires 4 shots of your gun's element [dash: shoot 4] |

### Vent (pressure)

| Row | Node | Effect |
|---|---|---|
| P1 | Reinforced Tank | +4 vent capacity per rank (merges Reinforced Tank) |
| C2 | **Hard Vent** | Vents hit 20% harder [vent_power 0.20] |
| | **Quick Vent** | The vent fills 20% faster [vent_charge 0.20] |
| P3 | Wide Valve | +5% vent radius per rank |
| C4 | **Scald Cloud** | Vents leave a cloud of their element [vent: cloud 90 px, 4 s] |
| | **Venting Mend** | Vents heal you 6 HP [vent: heal 6] |
| C5 | **Overpressure** | Vents fire 6 shots of their element [vent: shoot 6] |
| | **Storm Vent** | Vents arc lightning to 4 foes [vent: chain 4] |

### Fortune (economy and choices)

| Row | Node | Effect |
|---|---|---|
| P1 | Salvager | +4% scrap per rank (merges Salvager) |
| C2 | **Cartographer** | Shop, treasure and boss show on the map [reveal_rooms 3] |
| | **Dowser** | Hidden and puzzle rooms show on the map [reveal_secrets 2] |
| P3 | Lucky Coin | +4% luck per rank (merges Lucky Coin) |
| C4 | **Second Thoughts** | Reroll the level-up offer twice per run [levelup_rerolls 2] |
| | **Heirloom** | The gunsmith is free on floors 1 and 2 [free_gunsmith 2] |
| C5 | **Wider Choice** | Every level-up offers a fourth card [levelup_extra 2] |
| | **Deep Pockets** | Carry heavier guns [carry 2] |

15 choice nodes, 30 options, 10 passive nodes.

## What merged and what went

| Old slot (A / B) | Now |
|---|---|
| Sights: Long Barrel / Hot Load | Gone. Range and shot speed are gun and item territory. |
| Catalyst: Catalyst / Lingering Touch | Pyre P1 Kindling and Pyre P3 Lingering Touch |
| Nerve: Thick Skin / High Confidence | Rime P1 Thick Skin. High Confidence is gone (a number, not a playstyle). |
| Vent: Reinforced Tank / Hard Vent | Vent P1 and the Vent C2 choice |
| Footwork: Light Feet / Sidestep | Stride P1 and Rime P3 Cold Blood |
| Salvage: Salvager / Second Thoughts | Fortune P1 and Fortune C4 |
| Fortune: Lucky Coin / Wider Choice | Fortune P3 and Fortune C5 |
| Pack: Deep Pockets / Heirloom | Fortune C5 and Fortune C4 |
| Scout: Cartographer / Dowser | Fortune C2 |
| Bite, Twilight (element sidegrades) | Gone. They did nothing until an element was unlocked. |

Twenty-two stat sides with 2 to 3 ranks each became ten passives and fifteen choices.

## Power

The GDD's budget is at most +10% damage and +20 max HP from meta stats. The passives alone, by the
old header's measured factors: Kindling 6% potency x 0.49 = 2.9% damage; Lingering Touch 15% x 0.15 =
2.3%; Thick Skin +12 HP; Cold Blood 3% dodge = 4.5 HP; vent capacity and radius about 1.5%. That is
about 7% damage and 17 HP, inside the budget. The choices' damage (novas, clouds, shots on vents and
dashes) is not measured yet: the bot probe below logs it per pick. If a capstone turns out to carry
runs on its own, cut its numbers, not the idea.

## Migration

`mastery.json` goes from version 2 to version 3.

- **Version 2 (the A/B board).** Every rank bought on every side is refunded at its old price
  (the old cost tables stay in `mastery.gd` as `LEGACY_V2_COSTS`), added to the unspent Embers. Last
  Breath ranks, lifetime Embers, bounties and the income breakdown carry over untouched. Nothing is
  bought for you: the tree is new and the picks are yours.
- **Version 1 (the 212-node tree).** As before: 8 Embers per old point.
- **Backup.** Before writing the migrated file, the old file is copied to `mastery_v2_backup.json`
  next to it.
- **Telling the player.** The migration stores how many Embers came back; the Shrine shows "Your
  talents were rebuilt. N Embers refunded." once, the first time it opens.

Emil's save on 2026-11-11 had 47 unspent Embers and 224 in the board (Catalyst 3, Lucky Coin 3,
Thick Skin 3, Deep Pockets 2, Second Thoughts 3, Reinforced Tank 2), so it migrates to 271 Embers and
an empty tree, Last Breath 0, lifetime 316.

## The screen

Five columns, one per branch, five nodes each, joined by lines. A passive node is a square icon with
rank pips; a choice node is a wider tile showing both options' icons side by side, the picked one lit
and the other dimmed. Locked nodes are dark, open nodes are outlined, full nodes glow. Under the tree:
one detail panel for the focused node (name, one line of what it does, cost), Last Breath, Refund all
and Back. Text is the body font; names only in the detail panel, so the tree itself is icons, pips
and the Ember cost of the next rank.

Controls: arrows / d-pad move through the grid, A / Enter / E buys the focused node, X / Tab / Q flips
a bought choice node, B / Esc goes back. Mouse: click buys, or on a choice node clicks the option you
point at; right-click flips.

## Measure

- Load check and `tools/exe_smoke.sh`.
- Migration: a copy of a version 2 save under `--instance=5xx`, loaded by the hub bot with
  `--keep-save`; the log must show the refund and the new file must hold every Ember.
- Bots with `--mastery=full --mastery-side=a`, `=b` and `=mix` (alternating picks): zero SCRIPT ERRORs.
