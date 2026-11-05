extends SceneTree
## Builds the palette textures the post-process and UI icons quantize to:
##   res://assets/palette/endesga64.png      64x1, the palette itself
##   res://assets/palette/endesga64_lut.png  1024x32, a 32^3 RGB lookup table: texel
##       (b * 32 + r, g) holds the nearest palette colour (OKLab distance) to (r, g, b) / 31.
## Palette: ENDESGA 64 by Endesga (lospec.com/palette-list/endesga-64).
## Run: godot --headless --path . --script tools/make_palette_lut.gd

const PALETTE := [
    "ff0040", "131313", "1b1b1b", "272727", "3d3d3d", "5d5d5d", "858585", "b4b4b4",
    "ffffff", "c7cfdd", "92a1b9", "657392", "424c6e", "2a2f4e", "1a1932", "0e071b",
    "1c121c", "391f21", "5d2c28", "8a4836", "bf6f4a", "e69c69", "f6ca9f", "f9e6cf",
    "edab50", "e07438", "c64524", "8e251d", "ff5000", "ed7614", "ffa214", "ffc825",
    "ffeb57", "d3fc7e", "99e65f", "5ac54f", "33984b", "1e6f50", "134c4c", "0c2e44",
    "00396d", "0069aa", "0098dc", "00cdf9", "0cf1ff", "94fdff", "fdd2ed", "f389f5",
    "db3ffd", "7a09fa", "3003d9", "0c0293", "03193f", "3b1443", "622461", "93388f",
    "ca52c9", "c85086", "f68187", "f5555d", "ea323c", "c42430", "891e2b", "571c27",
]
const N := 32


static func _lin(c: float) -> float:
    return c / 12.92 if c <= 0.04045 else pow((c + 0.055) / 1.055, 2.4)


static func oklab(c: Color) -> Vector3:
    var r := _lin(c.r)
    var g := _lin(c.g)
    var b := _lin(c.b)
    var l := pow(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b, 1.0 / 3.0)
    var m := pow(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b, 1.0 / 3.0)
    var s := pow(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b, 1.0 / 3.0)
    return Vector3(
        0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
        1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
        0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s)


func _init() -> void:
    var cols: Array[Color] = []
    var labs: Array[Vector3] = []
    for h in PALETTE:
        var c := Color.html(String(h))
        cols.append(c)
        labs.append(oklab(c))
    var pal := Image.create_empty(cols.size(), 1, false, Image.FORMAT_RGBA8)
    for i in cols.size():
        pal.set_pixel(i, 0, cols[i])
    pal.save_png("res://assets/palette/endesga64.png")
    var lut := Image.create_empty(N * N, N, false, Image.FORMAT_RGBA8)
    for b in N:
        for g in N:
            for r in N:
                var q := oklab(Color(float(r) / float(N - 1), float(g) / float(N - 1), float(b) / float(N - 1)))
                var best := 0
                var best_d := INF
                for i in labs.size():
                    var d := (labs[i] - q).length_squared()
                    if d < best_d:
                        best_d = d
                        best = i
                lut.set_pixel(b * N + r, g, cols[best])
    lut.save_png("res://assets/palette/endesga64_lut.png")
    print("palette %d colours, lut %dx%d" % [cols.size(), lut.get_width(), lut.get_height()])
    quit()
