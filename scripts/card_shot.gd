class_name CardShot
extends Node
## The card-readability test (Core loop reset 4.4), run with the bot:
##   godot --headless --path . res://scenes/main.tscn -- --autotest --card-shot --instance=N
## Measures every catalog card (items, gun mods, actives), every gun and every level-up
## option against a sample build (Emil's human6980 floor-3 kit), writes
## autotest/cards/cards.csv (id, kind, words, effect lines, wrapped rows, smallest font,
## height) and prints `[CARDS] PASS n` or one `[CARDS] FAIL` line per card over the rules:
## more than ItemCard.MAX_WORDS words, more than 1 effect line, a font under 18 px, or taller
## than ItemCard.MAX_HEIGHT. With a real window it also saves a contact sheet PNG per 24
## cards (autotest/cards/sheet_N.png); headless runs have no renderer, so only the numbers.

const PER_SHEET := 24
const COLS := 6
const SAMPLE := ["lab_gloves", "ricochet_gloves", "vial_ice", "sigil_ice", "wishbone_ring", "leech_mail", "alembic", "bandage_roll", "seeker_lens"]
const MIN_FONT := 18
const LEVEL_FONT_MIN := 18

var main: Node
var _done := false
var _t := 0.0


static func wanted() -> bool:
    return OS.get_cmdline_user_args().has("--card-shot")


func _init(m: Node) -> void:
    main = m
    name = "CardShot"
    process_mode = Node.PROCESS_MODE_ALWAYS


func _process(delta: float) -> void:
    _t += delta
    if _done or _t < 1.0 or main.players.is_empty():
        return
    _done = true
    _run()


func _run() -> void:
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://autotest/cards"))
    var p: Player = main.players[0]
    for id in SAMPLE:
        p.equip(String(id))
    var rows: Array = []   # [id, kind, stats]
    var ids: Array = Items.catalog.keys()
    ids.sort()
    for id in ids:
        var it := Items.get_item(String(id))
        var opts := { "player": p, "price": Items.price_at(int(it["rarity"]), 2), "afford": true }
        rows.append([String(id), String(it.get("kind", "passive")), ItemCard.card_stats(it, opts), it, opts])
    var gids: Array = Guns.all_ids()
    gids.sort()
    for gid in gids:
        var data: GunData = Guns.make(String(gid))
        var gopts := { "player": p, "price": 60, "afford": true }
        rows.append([String(gid), "gun", ItemCard.gun_stats(data, gopts), data, gopts])
    for opt in LevelUps.options():
        rows.append([String(opt["id"]), "levelup", _levelup_stats(opt, p), opt, {}])
    var csv := FileAccess.open("res://autotest/cards/cards.csv", FileAccess.WRITE)
    csv.store_line("id,kind,words,effect_lines,wrapped,smallest_font,height")
    var fails := 0
    var worst_words := 0
    var worst_h := 0.0
    for r in rows:
        var st: Dictionary = r[2]
        csv.store_line("%s,%s,%d,%d,%d,%d,%.0f" % [r[0], r[1], int(st["words"]), int(st["effect_lines"]), int(st.get("wrapped", 1)), int(st["font"]), float(st["height"])])
        worst_words = maxi(worst_words, int(st["words"]))
        if r[1] != "levelup":
            worst_h = maxf(worst_h, float(st["height"]))
        var why: Array = []
        if int(st["words"]) > ItemCard.MAX_WORDS:
            why.append("%d words" % int(st["words"]))
        if int(st["effect_lines"]) > 1:
            why.append("%d effect lines" % int(st["effect_lines"]))
        if int(st["font"]) < MIN_FONT:
            why.append("font %d" % int(st["font"]))
        if r[1] != "levelup" and float(st["height"]) > ItemCard.MAX_HEIGHT:
            why.append("height %.0f" % float(st["height"]))
        if not why.is_empty():
            fails += 1
            print("[CARDS] FAIL %s (%s): %s" % [r[0], r[1], ", ".join(why)])
    csv.close()
    print("[CARDS] cards %d, most words %d, tallest %.0f px" % [rows.size(), worst_words, worst_h])
    if fails == 0:
        print("[CARDS] PASS %d" % rows.size())
    else:
        print("[CARDS] FAIL %d of %d" % [fails, rows.size()])
    if DisplayServer.get_name() != "headless":
        await _sheets(rows, p)
    main.get_tree().quit()


## Level-up cards keep their own layout (levelup_screen.gd: name 30 px, the headline 36 to
## 44, before -> after 30, extras 26, what it affects 24); the same word rule applies.
func _levelup_stats(opt: Dictionary, p: Player) -> Dictionary:
    var words := ItemCard._words(String(opt.get("name", "")))
    words += ItemCard._words(LevelUps.describe(opt))
    words += ItemCard._words(LevelUps.before_after(opt, p))
    for ln in LevelUps.extra_lines(opt):
        words += ItemCard._words(String(ln[0]))
    words += ItemCard._words(String(opt.get("affects", "")))
    return { "words": words, "effect_lines": 1, "font": 24, "height": 392.0, "wrapped": 1 }


## Contact sheets: 24 cards a sheet, 6 x 4, rendered in a SubViewport (windowed runs only).
func _sheets(rows: Array, p: Player) -> void:
    var cards: Array = rows.filter(func(r): return r[1] != "levelup")
    var w := int(ItemCard.DEFAULT_WIDTH) + 16
    var h := int(ItemCard.MAX_HEIGHT) + 16
    var n := 0
    for start in range(0, cards.size(), PER_SHEET):
        var vp := SubViewport.new()
        vp.size = Vector2i(w * COLS, h * ceili(float(mini(PER_SHEET, cards.size() - start)) / float(COLS)))
        vp.transparent_bg = false
        vp.render_target_update_mode = SubViewport.UPDATE_ONCE
        var canvas := Control.new()
        canvas.size = Vector2(vp.size)
        var batch: Array = cards.slice(start, start + PER_SHEET)
        canvas.draw.connect(func():
            canvas.draw_rect(Rect2(Vector2.ZERO, canvas.size), Color(0.02, 0.02, 0.03))
            for k in batch.size():
                var r: Array = batch[k]
                var at := Vector2(float(k % COLS) * float(w) + 8.0, float(k / COLS) * float(h) + 8.0)
                if r[1] == "gun":
                    ItemCard.draw_gun(canvas, Rect2(at, Vector2(ItemCard.DEFAULT_WIDTH, 0)), r[3], r[4])
                else:
                    ItemCard.draw(canvas, Rect2(at, Vector2(ItemCard.DEFAULT_WIDTH, 0)), r[3], r[4]))
        vp.add_child(canvas)
        add_child(vp)
        await RenderingServer.frame_post_draw
        await RenderingServer.frame_post_draw
        var img := vp.get_texture().get_image()
        if img != null:
            img.save_png("res://autotest/cards/sheet_%d.png" % n)
        vp.queue_free()
        n += 1
    print("[CARDS] %d contact sheets in autotest/cards/" % n)
