class_name Dialogue
extends RefCounted
## Lines keyed to state (World and progression GDD, section 9). Each line has an NPC, an
## id, the conditions it needs (`when`), a priority, and its text. `pick` takes the
## highest-priority line whose conditions hold, preferring the one heard least; `once`
## lines are never shown twice.
##
## Conditions read a context (`context()`): a plain key must equal the value, `<key>_min`
## and `<key>_max` bound a number. Keys: where ("hub" / "ossuary"), talks (lines this NPC
## has said before), runs, deaths, won, last ("" / "won" / "fell"), last_floor,
## last_region, embers, archivist (""/"met"/"recruited"), page (carrying the Torn
## Bestiary Page this run). Text may use {deaths}, {last_floor}, {embers}, {runs}.
##
## PLACEHOLDER: every line below is a plain, functional stand-in, written only so the
## systems can be built and tested. The real batch is written after the designer approves
## the voice sheets in `design/Voice sheets, phase 1.md`, and goes through the review in
## section 9. Replace whole entries; keep the ids the code uses (none are referenced by
## name, so ids are free to change).

const LINES := [
    # --- The Keeper (the Shrine) ---
    { "npc": "keeper", "id": "keeper_first", "when": { "talks": 0 }, "pri": 9, "once": true, "placeholder": true,
        "text": "Embers you bring back buy talents here. Sit when you want to spend them." },
    { "npc": "keeper", "id": "keeper_embers", "when": { "embers_min": 1 }, "pri": 2, "placeholder": true,
        "text": "{embers} Embers. The talents are on the board." },
    { "npc": "keeper", "id": "keeper_back", "when": { "last": "fell" }, "pri": 1, "placeholder": true,
        "text": "You're back. Warm your hands first." },
    { "npc": "keeper", "id": "keeper_idle", "when": {}, "pri": 0, "placeholder": true,
        "text": "The fire's lit." },

    # --- The Gatewarden (the Gate, the run history until the Archivist arrives) ---
    { "npc": "gatewarden", "id": "warden_first", "when": { "talks": 0 }, "pri": 9, "once": true, "placeholder": true,
        "text": "The Gate goes down. I count who comes back up." },
    { "npc": "gatewarden", "id": "warden_fell", "when": { "last": "fell" }, "pri": 3, "placeholder": true,
        "text": "Floor {last_floor}. That's {deaths} on my count." },
    { "npc": "gatewarden", "id": "warden_won", "when": { "last": "won" }, "pri": 3, "placeholder": true,
        "text": "All the way down and back. I'll write that one in." },
    { "npc": "gatewarden", "id": "warden_idle", "when": {}, "pri": 0, "placeholder": true,
        "text": "Gate's open." },

    # --- The Archivist, chained in the Ossuary ---
    { "npc": "archivist", "id": "archivist_meet", "when": { "where": "ossuary", "archivist": "", "page": false }, "pri": 5, "placeholder": true,
        "text": "An elite down here tore a page from my bestiary. Bring it back and I'll come up with you." },
    { "npc": "archivist", "id": "archivist_again", "when": { "where": "ossuary", "archivist": "met", "page": false }, "pri": 5, "placeholder": true,
        "text": "Still chained. Still no page. One of the elites has it." },
    { "npc": "archivist", "id": "archivist_give", "when": { "where": "ossuary", "page": true }, "pri": 8, "placeholder": true,
        "text": "That's my page. Undo the chain and I'll find the way up." },
    { "npc": "archivist", "id": "archivist_freed", "when": { "where": "ossuary", "archivist": "recruited" }, "pri": 6, "placeholder": true,
        "text": "Go on. I'll be in your library." },

    # --- The Archivist in the Hollow (the Journal, the full ledger) ---
    { "npc": "archivist", "id": "archivist_home", "when": { "where": "hub", "archivist": "recruited" }, "pri": 9, "once": true, "placeholder": true,
        "text": "Everything you've set off down there goes in the Journal." },
    { "npc": "archivist", "id": "archivist_idle", "when": { "where": "hub" }, "pri": 0, "placeholder": true,
        "text": "The Journal's open. So is the ledger." },
]


static func context(extra: Dictionary = {}) -> Dictionary:
    var last: Dictionary = Progress.history.back() if not Progress.history.is_empty() else {}
    var ctx := {
        "where": "hub",
        "runs": Progress.stat("runs_started"),
        "deaths": Progress.deaths(),
        "won": Progress.stat("runs_won"),
        "last": "" if last.is_empty() else ("won" if bool(last.get("won", false)) else "fell"),
        "last_floor": int(last.get("floor", 0)),
        "last_region": String(last.get("region", "")),
        "embers": Mastery.embers,
        "archivist": Progress.npc_state("archivist"),
        "page": false,
    }
    ctx.merge(extra, true)
    return ctx


static func matches(when: Dictionary, ctx: Dictionary) -> bool:
    for k in when.keys():
        var key := String(k)
        var v = when[k]
        if key.ends_with("_min"):
            if float(ctx.get(key.trim_suffix("_min"), 0)) < float(v):
                return false
        elif key.ends_with("_max"):
            if float(ctx.get(key.trim_suffix("_max"), 0)) > float(v):
                return false
        elif ctx.get(key) != v:
            return false
    return true


## The line `npc` says now: { id, text, placeholder }, or {} when nothing fits.
static func pick(npc: String, ctx: Dictionary) -> Dictionary:
    ctx = ctx.duplicate()
    ctx["talks"] = Progress.npc_talks(npc)
    var best: Array = []
    var best_pri := -INF
    for line in LINES:
        if line["npc"] != npc or not matches(line["when"], ctx):
            continue
        if line.get("once", false) and Progress.seen_lines.has(line["id"]):
            continue
        var pri := float(line.get("pri", 0))
        if pri > best_pri:
            best_pri = pri
            best = [line]
        elif pri == best_pri:
            best.append(line)
    if best.is_empty():
        return {}
    var least := INF
    var pool: Array = []
    for line in best:
        var n := float(Progress.seen_lines.get(line["id"], 0))
        if n < least:
            least = n
            pool = [line]
        elif n == least:
            pool.append(line)
    var chosen: Dictionary = pool.pick_random()
    return { "id": chosen["id"], "text": String(chosen["text"]).format(ctx), "placeholder": chosen.get("placeholder", false) }


## Pick a line and count it as heard.
static func say(npc: String, ctx: Dictionary) -> Dictionary:
    var line := pick(npc, ctx)
    if not line.is_empty():
        Progress.note_line(npc, String(line["id"]))
    return line
