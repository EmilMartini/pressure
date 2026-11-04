class_name UiTheme
extends RefCounted
## One dark theme for every menu: big pixel font, bone text, element-coloured focus.

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


static func label(text: String, size: int = 24, color: Color = BONE) -> Label:
    var l := Label.new()
    l.text = text
    l.add_theme_font_size_override("font_size", size)
    l.add_theme_color_override("font_color", color)
    l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    return l
