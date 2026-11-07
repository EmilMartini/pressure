# Voice sheets, phase 1: the Keeper, the Gatewarden, the Archivist

**Status: DRAFT for Emil's approval.** Nothing here is final. Section 9 of
`World and progression GDD.md` asks for a voice sheet and ten approved sample lines per NPC
before any lines are written. The game ships with short, plain placeholder lines for now
(`scripts/dialogue.gd`, every entry tagged `"placeholder": true`). The real batch is written
against these sheets after approval and goes through the section 9 review.

How to review: mark each sample **keep**, **change** (say what) or **cut**. Cut lines move to
"Not like this" under that NPC, as section 9 asks. Pronouns are left open on purpose (the
samples avoid them); say which you want for each NPC.

---

## The Keeper

Job: the Shrine. Embers buy talents at the fire.

- **Wants:** someone to come back up the stair and sit down. The fire to stay lit.
- **Fears:** the night the fire goes out with nobody there to see it.
- **Hides:** the Keeper went down once, a long time ago, and came back alone. The fire was lit
  for someone who didn't.
- **How they talk:** very short. Fragments. Often a small instruction instead of an answer
  ("Sit." "Hands out."). Talks to the fire as much as to you. Kind through actions (food, warmth,
  a seat), never through compliments.
- **Habits:** gives orders about the fire and the cold. Answers a question with something about
  wood or food. Lets a line stop halfway.
- **Never says:** "the Descent", "hero", "brave", anything about destiny, anything about
  what's at the bottom. Never praises you, and never asks how the run went.

Samples, with the state each needs:

| # | When | Line |
|---|---|---|
| 1 | First meeting | "Sit. You're letting the cold in." |
| 2 | Carrying Embers | "Put them in. Not all at once, they spit." |
| 3 | Died in Frostvault | "Your fingers are blue. Closer. No, closer." |
| 4 | 10 or more deaths | "I keep a pot on. Most nights nobody comes up for it." |
| 5 | Left without buying anything last visit | "Keep them, then. The fire's not hungry tonight." |
| 6 | Died to the Brute King again | "That big one again. Eat something before you go back." |
| 7 | Won a run | "All the way down. Well. The kettle's still warm." |
| 8 | No new state since last talk | "Mm. Wood's low." |
| 9 | About the Gatewarden | "Don't mind the counting. The Warden counted to eleven once, out loud, all the way up the stair." |
| 10 | After the Archivist moves in | "The book one reads by my fire and never adds a log. Tell them." |

---

## The Gatewarden

Job: the Gate (start a run, Vows later) and the run history until the Archivist arrives.

- **Wants:** one descender who comes back up and stays up. A full column in the tally.
- **Fears:** going back down. Hearing their old squad's names said out loud.
- **Hides:** led a squad of eleven down. Came back alone, because they ran. The tally they keep
  for you is the one they never kept for the squad.
- **How they talk:** clipped, like reporting to someone senior. Number first, then a short dry
  remark. Dry humour, never a joke with a punchline.
- **Habits:** counts things: your deaths, the stairs (112), minutes, days. Corrects a number
  ("Nine. Ten, if that counts. It counts."). Gives an order, then says they don't give orders.
- **Never says:** "good luck", "be careful", "you can do it", the squad's names (bonds may unlock
  them later), anything that sounds like a speech.

| # | When | Line |
|---|---|---|
| 1 | First meeting | "You're number thirty-eight through this gate. I'll learn the name if you come back." |
| 2 | Third death to the same boss | "Third time on the {boss}. Patient, that one. So was I, once." |
| 3 | Died in Ossuary Gate in under three minutes | "Ossuary Gate. Two minutes. I've had soup take longer." |
| 4 | Tenth death | "Ten. I stop counting out loud at ten. I don't stop counting." |
| 5 | Won a run | "Five floors down and you walked back up. I'll have to rule a new column." |
| 6 | Left a run from the pause menu | "You turned round. I did that. Once." |
| 7 | Died to the Pyre Lord | "The Pyre Lord. One of mine said he could out-burn it. We buried his boots." |
| 8 | Before a run, nothing new | "A hundred and twelve stairs. Count them on the way down." |
| 9 | About the Keeper | "The Keeper's put soup on. Eat it. That's an order, and I don't give those any more." |
| 10 | After the Archivist moves in | "The scholar asked how my squad died. In detail. I gave them the stair count instead." |

---

## The Archivist

Job: the Ledger and the Journal; later, death lessons. Met chained in a side room of the
Ossuary, recruited with the Torn Bestiary Page.

- **Wants:** a complete bestiary. Every monster, every way it kills, in order.
- **Fears:** dying before it's finished, and someone else finishing it.
- **Hides:** used to pay descenders to go down with questions, and stopped writing down how many
  came back. The chain was put on by people who did the sums.
- **How they talk:** fast, long run-on lines that stop to correct themselves. Clinical words next
  to plain ones. Treats your death as data, with real pleasure, and doesn't notice that's rude.
- **Habits:** corrects a word mid-line ("bitten, no, chewed"). Stops to take a note. Asks for a
  detail of how you died, and then answers it themselves.
- **Never says:** sorry, that a death is sad, anything comforting. Never calls a monster evil:
  they're specimens.

| # | When | Line |
|---|---|---|
| 1 | First meeting, chained | "Don't touch the chain, it's the only thing down here that hasn't tried to eat me. One of the elites tore a page out of my bestiary, and I want it back." |
| 2 | Met before, no page | "You again. You smell of bone dust and you don't have my page." |
| 3 | Giving the page | "Look at the tooth marks. Lovely. The left shackle, the right one's just for show." |
| 4 | First talk in the Hollow | "Your Keeper says I can have the corner if I stop reading aloud. I've agreed to the corner." |
| 5 | Died to the Hive Mother | "Swarmed or stung? It matters. Swarmed. I'll put swarmed." |
| 6 | Died to burning | "Burned, floor three. They go black at the edges first. You won't have noticed, you were busy burning." |
| 7 | First fusion in the last run | "Steam, then shock, and that oil slinger came apart at the seams. I need the order. The exact order." |
| 8 | Many deaths | "Forty-one. The Warden counts them, I sort them. We should compare." |
| 9 | Won a run | "All five of them dead and you brought back nothing I can use. Next time, a tooth." |
| 10 | About the Keeper | "The Keeper threw my notes on the fire. In fairness, they were notes on the Keeper." |

---

## What the game says today (placeholders)

In `scripts/dialogue.gd`: 14 lines, each one plain and functional, tagged `"placeholder": true`.
They cover what the systems need: a first meeting and an idle line for each NPC, the Keeper's
Embers line, the Gatewarden's death count after a fall and a win, and the Archivist's lines in
the Ossuary (asks for the page, met again without it, given it, freed) and at home (the
Journal). One more player-facing text arrived in this phase: the toast "Archivist freed: the
Journal is in the Hollow's library".

## Line review of the samples

A cheaper model (Haiku) checked the 30 samples above against the section 9 rules, given only
those rules and this sheet. Its findings and what was done with them are under "Review notes"
below.

## Review notes

The reviewer flagged 19 of 44 lines (Keeper 4 of 14, Gatewarden 7 of 14, Archivist 8 of 16,
samples and placeholders together). No banned words, no "in the depths of", no praise of the
player. Applied above:

- Keeper 8: "Mm." could be anyone's; now "Mm. Wood's low."
- Keeper 9 explained the Warden's feelings; rewritten as subtext that points at the squad.
- Gatewarden 1 and Archivist 8 both used "forty-one"; the Gatewarden's is now thirty-eight.
- Gatewarden 2 named no boss; it now takes the boss's name from the run (`{boss}`).
- Gatewarden 6 comforted the player ("nothing wrong with that"); cut to "I did that. Once."
- Gatewarden 8 and Archivist 1 ran to three sentences; cut to two.
- Archivist 6 asked the player a question; now a statement.
- Archivist 7 said "the thing"; it now names an oil slinger.
- Placeholders `archivist_again` (an order, against the sheet) and `archivist_give` (three
  sentences) were reworded in `scripts/dialogue.gd`.

Kept, for Emil to decide:

- **Gatewarden 3** ("I've had soup take longer"): flagged as a punchline. I read it as dry, but
  it is the most joke-shaped line in the set.
- **Gatewarden 4** ("I stop counting out loud at ten. I don't stop counting."): flagged as the
  banned "not X, it's Y" in disguise. It isn't that construction, but it does have the same
  neat turn.
- **Archivist 5** ("Swarmed or stung? It matters. Swarmed."): flagged as a rhetorical question.
  It is the habit the sheet gives them (ask, then answer it yourself). If the rule should win,
  the fix is "Swarmed. That matters. I'll put swarmed."
- **The other placeholders** (keeper_first, keeper_embers, warden_won, warden_idle,
  archivist_freed, archivist_home) were flagged as generic or explanatory. That is deliberate:
  they are functional stand-ins until the real batch is written.
