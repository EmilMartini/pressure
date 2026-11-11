class_name UiTheme
extends RefCounted
## One dark theme for every menu: pixel font for titles, buttons and numbers, the clean body
## font (Art.FONT_BODY, see the text rule in art.gd) for sentences and tooltips, bone text,
## element-coloured focus. `label` makes pixel-font labels; `body` makes sentence labels.

const BONE := Color(0.90, 0.86, 0.78)
const DIM := Color(0.55, 0.52, 0.50)
const PANEL := Color(0.07, 0.06, 0.08, 0.98)
const FOCUS := Color(1.0, 0.45, 0.15)


static func make() -> Theme:
    var theme := Theme.new()
    theme.set_font("font", "Button", Art.FONT)
    theme.set_font_size("font_size", "Button", 34)
    theme.set_color("font_color", "Button", BONE)
    theme.set_color("font_hover_color", "Button", Color.WHITE)
    theme.set_color("font_focus_color", "Button", Color.WHITE)
    theme.set_color("font_pressed_color", "Button", FOCUS)
    theme.set_stylebox("normal", "Button", _box(Color(0.12, 0.10, 0.12, 0.9), Color(0.35, 0.30, 0.30)))
    theme.set_stylebox("hover", "Button", _box(Color(0.18, 0.14, 0.16, 0.95), BONE))
    theme.set_stylebox("focus", "Button", _box(Color(0.18, 0.14, 0.16, 0.95), FOCUS, 3))
    theme.set_stylebox("pressed", "Button", _box(Color(0.25, 0.12, 0.10, 0.95), FOCUS, 3))
    theme.set_font("font", "Label", Art.FONT)
    theme.set_font_size("font_size", "Label", 24)
    theme.set_color("font_color", "Label", BONE)
    theme.set_stylebox("panel", "PanelContainer", _box(PANEL, Color(0.30, 0.26, 0.28), 2, 16))
    if Art.FONT_BODY != null:
        theme.set_font("font", "TooltipLabel", Art.FONT_BODY)
        theme.set_font_size("font_size", "TooltipLabel", Art.BODY_SIZE)
        theme.set_color("font_color", "TooltipLabel", BONE)
        theme.set_stylebox("panel", "TooltipPanel", _box(PANEL, Color(0.45, 0.40, 0.40), 2, 6))
        theme.set_font("normal_font", "RichTextLabel", Art.FONT_BODY)
        theme.set_font_size("normal_font_size", "RichTextLabel", Art.BODY_SIZE)
    return theme


static func _box(fill: Color, border: Color, width: int = 2, pad: int = 10) -> StyleBoxFlat:
    var s := StyleBoxFlat.new()
    s.bg_color = fill
    s.border_color = border
    s.set_border_width_all(width)
    s.set_content_margin_all(pad)
    s.content_margin_left = pad * 2
    s.content_margin_right = pad * 2
    return s


static func button(text: String, on_pressed: Callable) -> Button:
    var b := Button.new()
    b.text = text
    b.custom_minimum_size = Vector2(360, 56)
    b.pressed.connect(on_pressed)
    return b


## A sentence label in the body font at `size` (Art.BODY_SIZE by default, never under
## Art.SMALL_SIZE), word-wrapped, left-aligned.
static func body(text: String, size: int = Art.BODY_SIZE, color: Color = BONE) -> Label:
    var l := Label.new()
    l.text = text
    to_body(l, size, color)
    l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    return l


## Switches an existing label to the body font at `size` (and `color` when given).
static func to_body(l: Label, size: int = Art.BODY_SIZE, color: Color = Color(0, 0, 0, 0)) -> void:
    if Art.FONT_BODY != null:
        l.add_theme_font_override("font", Art.FONT_BODY)
    # Literal sizes were written for the first, larger text pass: scale them (Art.bpx).
    l.add_theme_font_size_override("font_size", size if size == Art.BODY_SIZE else Art.bpx(size))
    if color.a > 0.0:
        l.add_theme_color_override("font_color", color)


static func label(text: String, size: int = 24, color: Color = BONE) -> Label:
    var l := Label.new()
    l.text = text
    l.add_theme_font_size_override("font_size", size)
    l.add_theme_color_override("font_color", color)
    l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    return l


## Applies the text rule (art.gd) to every Label under `root`: sentence text (Art.is_prose)
## moves to the body font at Art.body_px of its pixel size. Titles, names and numbers keep
## the pixel font; a label with the meta "pixel" is never changed. Screens call this after
## filling their text (labels made empty and filled later are switched when first filled).
static func apply_text_rule(root: Node) -> void:
    if Art.FONT_BODY == null or root == null:
        return
    for n in root.find_children("*", "Label", true, false):
        var l := n as Label
        if l.has_meta("pixel") or l.get_theme_font("font") == Art.FONT_BODY or not Art.is_prose(l.text):
            continue
        to_body(l, Art.body_px(l.get_theme_font_size("font_size")))
    for n in root.find_children("*", "Button", true, false):
        var b := n as Button
        if b.has_meta("pixel") or b.get_theme_font("font") == Art.FONT_BODY or not Art.is_prose(b.text):
            continue
        b.add_theme_font_override("font", Art.FONT_BODY)
        b.add_theme_font_size_override("font_size", Art.body_px(b.get_theme_font_size("font_size")))
