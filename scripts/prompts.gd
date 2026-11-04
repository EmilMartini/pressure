class_name Prompts
extends RefCounted
## Draws input prompts: Xbox-style coloured face buttons and grey shoulder pills for a
## pad, square key caps for the keyboard. `kind` is "pad" or "kb".

const FACE := {
    "A": Color(0.36, 0.72, 0.22),
    "B": Color(0.85, 0.22, 0.20),
    "X": Color(0.22, 0.45, 0.85),
    "Y": Color(0.92, 0.75, 0.15),
}


static func draw(canvas: CanvasItem, center: Vector2, label: String, kind: String, size: float = 24.0) -> void:
    var font: Font = Art.FONT
    if kind == "pad":
        if FACE.has(label):
            canvas.draw_circle(center + Vector2(0, 2), size / 2.0 + 2.0, Color(0, 0, 0, 0.75))
            canvas.draw_circle(center, size / 2.0, Color(0.12, 0.12, 0.14))
            canvas.draw_circle(center, size / 2.0 - 2.0, FACE[label])
            canvas.draw_circle(center + Vector2(-size * 0.12, -size * 0.14), size * 0.16, Color(1, 1, 1, 0.25))
            canvas.draw_string(font, center + Vector2(-size, size * 0.3), label, HORIZONTAL_ALIGNMENT_CENTER, size * 2.0, int(size * 0.72), Color(1, 1, 1))
        else:
            # Shoulders, triggers, Start, Back: a dark pill.
            var w := size * 0.55 * float(label.length()) + size * 0.6
            var r := Rect2(center - Vector2(w / 2.0, size / 2.0), Vector2(w, size))
            canvas.draw_rect(r.grow(2.0), Color(0, 0, 0, 0.75))
            canvas.draw_rect(r, Color(0.3, 0.3, 0.34))
            canvas.draw_rect(Rect2(r.position, Vector2(r.size.x, 3)), Color(0.5, 0.5, 0.55))
            canvas.draw_string(font, Vector2(r.position.x, r.position.y + size * 0.72), label, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, int(size * 0.62), Color(0.95, 0.95, 0.95))
    else:
        var w := maxf(size, size * 0.5 * float(label.length()) + size * 0.5)
        var r := Rect2(center - Vector2(w / 2.0, size / 2.0), Vector2(w, size))
        canvas.draw_rect(r.grow(2.0), Color(0, 0, 0, 0.8))
        canvas.draw_rect(r, Color(0.92, 0.9, 0.85))
        canvas.draw_rect(Rect2(r.position + Vector2(0, r.size.y - 3), Vector2(r.size.x, 3)), Color(0.6, 0.58, 0.55))
        canvas.draw_string(font, Vector2(r.position.x, r.position.y + size * 0.72), label, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, int(size * 0.66), Color(0.08, 0.06, 0.08))
