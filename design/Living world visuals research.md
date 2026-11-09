# Living world visuals: research

Research for making Pressure's rooms feel alive and reactive: plants and props that answer the
elements, dressing across the whole floor, a flowing river, and things that move. The bar is The
Binding of Isaac and Ori. We take their principles, not their art.

Written November 2026. The sources were checked on the web. Where a page was blocked or members-only, or a claim could
not be confirmed, this document says so. Quotes are kept short.

How to read it:
- Part 1 lists the sources and what each one teaches.
- Part 2 turns them into Godot 4 techniques, area by area. Each section ends with **Pressure fit**,
  which says where the technique plugs into code we already have.
- Part 3 covers performance on the Web and Compatibility renderer.
- Part 4 covers readability. It is a hard rule: hostile things stay the clearest thing on screen.
- Part 5 is the prioritised implementation list.

What Pressure already has, so this document builds on it rather than reinventing it:
- `Materials`: a 6 px cell grid, drawn on the GPU from one data texture. It holds oil, water, fire,
  ice, poison gas, acid, blood, steam, charge, ash and permanent char, and it already reacts.
- `PostFx`: one screen pass with pixelation, bloom, the ENDESGA 64 palette LUT and vignette.
- `ArtPass`: per-region ambient light, point lights, grade, contact shadows and doorway spill. It
  also places dressing along the walls only, plus foreground roots.
- `Crisp`: a layer above PostFx for hostile shots and edges, so they are never lit or darkened.
- `Ambience`: a capped pixel system (110 pixels) for dust, drips, embers, snow, motes and torches.
- `Prop`: crates, barrels, fountains, braziers, crystals and vats that react to every element.
- `GrassLayer`: dry tufts over a thin oil film. A tuft whose oil is gone turns to char.
- Hit-stop, shockwave, aberration and bloom pulses.
- `ClarityShot`: measures enemy and floor contrast, and how much of the screen the player's own
  effects cover.

---

## Part 1. Sources

### 1.1 Talks that were verified

| Talk | Speaker(s) | Event, year | Link | Status |
|---|---|---|---|---|
| Juice It or Lose It | Martin Jonasson, Petri Purho | GDC Europe 2012, Independent Games Summit. Some sources say Nordic Game 2012. | https://gdcvault.com/play/1016487/contactUs | Vault listing confirmed. Free copies exist on YouTube, for example https://www.youtube.com/watch?v=Fy0aCDmgnxg (not re-checked). |
| The Art of Screenshake | Jan Willem Nijman (Vlambeer) | INDIGO Classes, November 2013. Game Developer places it at Control Conference, Amsterdam. | https://www.gamedeveloper.com/design/vlambeer-co-founder-shares-advice-on-building-better-action-games | Talk confirmed. The written summary names only 2 of its 30 tweaks. The full list is in the video (listed on https://kenney.nl/knowledge-base/learning/must-see-videos-for-indie-developers). |
| Exploring the Tech and Design of 'Noita' | Petri Purho (Nolla Games) | GDC 2019, Independent Games Summit | https://gdcvault.com/play/1025695/Exploring-the-Tech-and-Design | Confirmed. Technical detail comes from an 80.lv interview (below). |
| Animating Rain World (Animation Bootcamp) | Joar Jakobsson, James Therrien | GDC 2016 | https://www.gamedeveloper.com/art/video-animating-i-rain-world-i-and-its-many-squishy-stretchy-creatures | Confirmed through Game Developer coverage. I could not find the exact GDC Vault page. |
| Animation Bootcamp: The Animation Process of Ori | James Benson | GDC 2015 | https://www.gdcvault.com/play/1021791/contactUs | Vault listing confirmed. |
| The Art of 'Ori and the Will of the Wisps' | Jeremy Gritton, Daniel van Leeuwen (Moon Studios) | GDC 2021 | https://www.gdcvault.com/play/1027375/contactUs | Vault listing confirmed. The video is members-only, so only the abstract was read. |
| 'Hyper Light Drifter': Secrets of Kickstarter, Design, & Pizza | Teddy Dief, Alx Preston | GDC 2017 | https://gdcvault.com/play/1024062/contactUs | Confirmed. It is a design and business talk, not an environment-art talk. |
| Level Design Workshop: Designing 'Celeste' | Matt Thorson | GDC 2017 | https://gdcvault.com/play/1024307/Level-Design-Workshop-Designing-Celeste | Confirmed. |
| 'Owlboy': The Evolving Art of a 10 Year Project | Jo-Remi Madsen, Simon Stafsnes Andersen | GDC 2017, Independent Games Summit | https://gdcvault.com/play/1024144/-Owlboy-The-Evolving-Art | Confirmed. |
| Math for Game Programmers: Juicing Your Cameras With Math | Squirrel Eiserloh (SMU Guildhall) | GDC 2016 | https://gdcvault.com/play/1023146/Math-for-Game-Programmers-Juicing | Confirmed. |
| Visual Effects Bootcamp: Artistic Principles of VFX | Jason Keyser (Riot), Hadidjah Chamberlain (Blizzard) | GDC 2017 | https://www.gdcvault.com/play/1024439/Visual-Effects-Bootcamp-Artistic-Principles | Confirmed. |
| Attention Overload! Creating Readable VFX for 'Suicide Squad: Kill the Justice League' | Hanno Hinkelbein (Rocksteady) | GDC 2024 | https://gdcvault.com/play/1034360/Attention-Overload-Creating-Readable-VFX | Confirmed. |
| Water Flow in Portal 2 | Alex Vlachos (Valve) | SIGGRAPH 2010, Advances in Real-Time Rendering | https://www.advances.realtimerendering.com/s2010/Vlachos-Waterflow(SIGGRAPH%202010%20Advanced%20RealTime%20Rendering%20Course).pdf | Confirmed (slides). |

### 1.2 Written sources (articles, posts, interviews)

| Source | Author, date | Link |
|---|---|---|
| Noita: a Game Based on Falling Sand Simulation | Daria Loginova, interview with Nolla Games, 80.lv, April 2019 | https://80.lv/articles/noita-a-game-based-on-falling-sand-simulation/ |
| Art Design Deep Dive: Giving back colors to cryptic worlds in Dead Cells | Gwenaël Massé (Motion Twin), Game Developer, April 2018 | https://www.gamedeveloper.com/production/art-design-deep-dive-giving-back-colors-to-cryptic-worlds-in-i-dead-cells-i- |
| Art Design Deep Dive: Using a 3D pipeline for 2D animation in Dead Cells | Thomas Vasseur (Motion Twin), January 2018 | https://gamedeveloper.com/program/gama-archive. The original page did not load for me, so only its existence and mirror summaries are confirmed. |
| Remaking Celeste's Lighting | Noel Berry, September 2017 | https://www.noelberry.ca/posts/celeste_lighting |
| Clarity in League | Riot Games dev blog, March 2021 | https://www.leagueoflegends.com/en-au/news/dev/clarity-in-league/ |
| League VFX style guide (PDF) | Riot Games, October 2017 | https://nexus.leagueoflegends.com/en-us/2017/10/dev-leagues-vfx-style-guide/ |
| Ori and the Will of the Wisps: dynamic lighting and reactive environments | Thomas Mahler, interview reported by Wccftech, July 2018 | https://wccftech.com/ori-and-the-will-of-the-wisps-dynamic-lighting/ |
| Q&A: The guns and dungeons of Enter the Gungeon | Game Developer | https://gamedeveloper.com/design/q-a-the-guns-and-dungeons-of-i-enter-the-gungeon-i- |
| Spelunky 2 first look, with Derek Yu | PlayStation Blog, August 2018 | https://blog.playstation.com/archive/2018/08/29/first-look-at-spelunky-2-gameplay-plus-new-derek-yu-interview |
| Hollow Knight case study | Unity | https://unity.com/made-with-unity/hollow-knight |
| Postmortem: Children of Morta | Amir H. Fassihi, Game Developer, November 2020 | https://gamedeveloper.com/design/postmortem-children-of-morta |
| How Dead Mage created the art for Children of Morta | TechRaptor | https://techraptor.net/content/how-dead-mage-created-the-art-for-children-of-morta |
| Binding of Isaac rocks and obstacles (mechanics wiki) | wiki.gg | https://bindingofisaacrebirth.wiki.gg/wiki/Rock |
| Dungeon generation in Binding of Isaac | Boris the Brave, September 2020 | https://boristhebrave.com/2020/09/12/dungeon-generation-in-binding-of-isaac |
| Godot docs: 2D lights and shadows; screen-reading shaders; 2D particle systems; MultiMesh | Godot Engine | https://docs.godotengine.org/en/stable/tutorials/2d/2d_lights_and_shadows.html and sibling pages |
| Dynamic 2D Grass for Godot (MIT, Godot 4.5+) | Jomoho Games | https://jomoho.itch.io/dynamic-2d-grass |
| 2D pixel-perfect wind and sway shader | godotshaders.com | https://godotshaders.com/shader/2d-pixel-perfect-wind-sway-effect/ |

### 1.3 Searched for, but not found or not accessible

- **Hades.** I found no art or readability GDC talk. The GDC talks I did find cover narrative and
  voice. The only readability statement is from a Supergiant Reddit AMA (September 2020): an
  environment artist said the scenery never obscures the action or hurts combat readability. I
  read it through a mirror of the thread
  (https://www.reddit.com/r/NintendoSwitch/comments/ixri6b/), so it is paraphrased, not quoted.
- **Enter the Gungeon.** I found no GDC talk on table flips or room interaction. The Game Developer
  Q&A is the source used here.
- **The Binding of Isaac.** Edmund McMillen's postmortem is in Game Developer Magazine, November 2012
  (https://media.gdcvault.com/GD_Mag_Archives/GDM_November_2012.pdf). I did not read the PDF, so
  nothing below claims McMillen's intent on rocks and poop. Those points come from the mechanics
  wiki.
- **Hollow Knight.** I found no Team Cherry talk on environment art, only Unity's case study and
  fan commentary.
- **Children of Morta.** No source confirms that they used normal maps. Their lighting is described
  only as "advanced lighting techniques" and "a customized rendering pipeline".
- **Spelunky 2.** BlitWorks' fluid implementation is not documented in anything I found. Only the
  design intent is (Derek Yu).
- **GDC Vault.** Most videos are members-only. For those, only the public abstract was read.

### 1.4 What each source teaches

- **Juice It or Lose It (Jonasson and Purho, 2012).** They take a plain block-breaker and add tweening,
  squash and stretch, particles, sound and screen shake one at a time, live. The game is the same,
  but the feel is not. The lesson for the world: every object that gets hit should answer, even when
  nothing happens to it mechanically.
- **The Art of Screenshake (Nijman, 2013).** Thirty small tweaks to a dull shooter. The written
  summary confirms two of them: the screen shakes slightly opposite to the direction of fire, and
  enemies sometimes explode harmlessly on death. From the video, as I remember it (please check it
  against the video): bigger bullets, muzzle flash, impact frames, knockback on hit, hit-stop
  ("sleep"), camera lerp and kick, and **permanence**: bodies and shell casings stay on the floor.
  Permanence is the one that matters most for an alive world.
- **Noita (Purho, 2019; 80.lv, 2019).** Every pixel follows simple rules, and complex behaviour comes
  from combining them. The tricks that make it run: 64x64 chunks, each with a dirty rectangle, so
  only cells that change are visited. A burning pixel tries to ignite a random neighbour. Wood burns
  for a set time and is then destroyed. Fire that reaches water turns it into steam. Steam is a gas
  that rises. Pressure's `Materials` already follows this model, with its active queue and a step
  rate of 12 per second.
- **Rain World (Jakobsson and Therrien, GDC 2016).** Procedural animation means points in space joined
  at set distances, not drawn frames. For us that means vines, banners, chains and roots built as
  short point chains that react to forces, such as gale, explosions, a passing player or burning
  through, without hand-made animation.
- **Ori (Mahler 2018; GDC 2015 and 2021).** Two quotes from Mahler: "every texture in the game reacts
  to lighting sources", and the art team painted light masks on every asset. He also says
  "everything is alive", meaning that what Ori stands on "moves in time with Ori". Principle: the
  world answers the player's presence (contact, passing by, landing), not only the player's weapons.
- **Dead Cells (Massé, 2018).** This is the clearest written rule for readability. Enemies,
  projectiles and spells get high saturation, contrast and brightness, so "the immediate danger is
  quickly identifiable". Interactive pieces (ladders, platforms) sit between the background and the
  threats. Textures are drawn in greyscale and tinted with gradient maps, so changing the biome palette
  is one edit. Particles that thicken the air, and foreground layers, add depth.
- **Dead Cells (Vasseur, 2018).** This is a pipeline for pixel art without hand-redrawing every retake:
  animate in 3D, then render to low-resolution sprites. It is not a direct fit for Pressure. The
  lesson worth keeping: make the art cheap to redo, so reactive states (burnt, frozen, wilted) do
  not each need hand-drawn frames. That is the case for shaders over new sprite sheets.
- **Celeste lighting (Berry, 2017).** The first version built a lighting mesh per light on the CPU,
  and that cost CPU time. The final version draws each light's cut-out mask into one channel of a
  shared texture: four channels, cells of 256 px, 256 lights in one 2048 texture. A second pass
  colours them. He calls the GPU cost "only a minor hit". If Pressure ever wants lights blocked by
  walls, this is the cheap way.
- **Hollow Knight (Unity case study).** Flat 2D layers placed at depth, with particle systems and simple
  shaders and no complex lighting. Depth comes from layering and parallax, not from technology.
- **Children of Morta (Fassihi 2020; TechRaptor).** The pixel art is scaled up about 4x, so lighting and
  post-processing run at a higher resolution than the sprites. Pressure does the opposite: PostFx
  pixelates everything under it, lights included. That keeps the look unified. Do not break it by
  adding unpixelated soft light.
- **Enter the Gungeon (Q&A).** The first chamber lets you flip tables, roll explosive barrels and drop
  chandeliers. The team wanted the player to feel that where the fight happens matters. Interactive
  props are combat tools, not decoration.
- **The Binding of Isaac (wiki; Boris the Brave).** Rooms are hand-made templates arranged on a
  grid. Obstacles form a family: rocks, tinted rocks (a visible reward tell), bomb rocks, spiked
  rocks, and poop that can spawn projectiles. Each looks different enough to read at a glance, and
  each is destructible in a way that changes the room. Pressure's `room_layouts` plus `Prop` already
  work this way.
- **Spelunky 2 (Yu, 2018 and 2019).** Liquids and destructible terrain together create emergent
  lavafalls and floods. In the first game, Yu says, lava was "kind of faked". For a river: let it carry
  things, not only look like it flows.
- **Readability: Riot (2021), Keyser and Chamberlain (2017), Hinkelbein (2024).** The most important
  thing should draw the most attention. Noise must be kept low. "Gameplay is King" comes first in
  Keyser and Chamberlain's principles. Hinkelbein's talk treats VFX as a way to direct attention, and
  says VFX artists should join design early.

---

## Part 2. Techniques for Godot 4 2D

General rules for every technique here, from how Pressure is built:
- Animate in the shader with `TIME`, not with `queue_redraw()` every frame. `Materials` already does
  this: the CPU writes texels only when cells change.
- One material per family (all foliage, all water), shared, so the batches stay together.
- Pass per-object variation through vertex `COLOR`, world-position hashes or a data texture, not through
  unique materials.
- Move in whole texels. PostFx snaps the world to a 2 to 4 px cell, so sub-texel motion shimmers.
  Snap offsets to `Themes.texel`, and step animation time (for example 8 to 12 Hz) so motion reads as
  pixel-art frames.
- Everything here draws **under** `Crisp`. Nothing environmental may go on the Crisp layer.

### 2.1 Water and the river

**What a good 2D river needs:** (1) surface motion that follows the channel, (2) a visible bank with
foam, (3) depth shading from shallow edge to deep middle, (4) a response to things in it, and (5)
element reactions.

**Flow map (Vlachos, SIGGRAPH 2010).** Artists author a low-resolution texture of 2D flow vectors, and
the shader distorts a tiling texture along them. Valve's flow maps were about 4 texels per metre.
Distorting along a vector field smears the texture over time. The standard fix, from the same deck:
run two copies half a cycle apart and cross-fade, so one resets while the other is at full weight.
Portal 2 also flowed a colour map, to carry debris on dirty water.

How to do it in Pressure:
1. **Build the flow field from the river's path at room build.** Author the river as a `Curve2D`, or
   as a chain of cells in `room_layouts`. For each 6 px grid cell inside the river, store the
   tangent of the nearest curve point (RG), the speed (B, faster in narrow parts) and the distance to
   the bank (A, 0 at the bank and 1 in the middle). Compute the distance with a breadth-first
   search over cells from the bank cells. Upload it once as an `Image` of size
   `cols x rows` → `ImageTexture`. This is the same grid as `Materials`, so the river shader can
   read both textures with the same UV.
2. **Draw the river as one polygon or quad** with a single `ShaderMaterial`.
3. **Shader sketch** (canvas_item, Compatibility-safe):

```glsl
shader_type canvas_item;
// One quad over the room. UV 0..1 maps to the Materials grid.
uniform sampler2D flow_tex : filter_linear;     // RG flow*0.5+0.5, B speed, A bank distance
uniform sampler2D noise_tex : repeat_enable, filter_linear; // 64-128 px seamless noise
uniform vec2 room_px = vec2(1120.0, 720.0);
uniform float cycle = 1.4;          // seconds per flow phase
uniform float tile_px = 48.0;       // noise repeats every 48 world px
uniform vec4 deep : source_color;
uniform vec4 shallow : source_color;
uniform vec4 foam : source_color;
uniform vec4 glint : source_color;

void fragment() {
    vec4 f = texture(flow_tex, UV);
    if (f.a <= 0.0) discard;                      // outside the river
    vec2 flow = (f.rg * 2.0 - 1.0) * f.b;
    vec2 p = UV * room_px / tile_px;
    float t = TIME / cycle;
    float a = fract(t), b = fract(t + 0.5);
    float w = abs(a - 0.5) * 2.0;                 // cross-fade weight
    float n = mix(texture(noise_tex, p - flow * a).r,
                  texture(noise_tex, p - flow * b + 0.37).r, w);
    float depth = f.a;                            // 0 bank .. 1 mid-channel
    vec3 col = mix(shallow.rgb, deep.rgb, smoothstep(0.0, 0.6, depth));
    // light streaks along the flow
    col = mix(col, glint.rgb, step(0.78, n) * 0.6 * depth);
    // bank foam: a band near the bank, broken up by the same moving noise
    float band = 1.0 - smoothstep(0.0, 0.25, depth);
    col = mix(col, foam.rgb, step(0.55 - band * 0.5, n) * band);
    COLOR = vec4(col, 1.0);
}
```

   Pick the colours from ENDESGA 64, because the PostFx LUT will snap them to the palette anyway.
   The PostFx pixelation already gives the pixel-art look, so the shader does not need its own snapping.
4. **Shoreline shading.** Darken the bank tiles in a one-texel rim where the land meets the water: a
   wet edge and a contact shadow, the same idea as ArtPass's contact shadow towards walls. Add a
   foam band that moves faster on the outside of bends: scale B up where the curve's curvature is high.
5. **Rocks in the stream.** Where a rock or prop sits in the river, write a short wake into the flow
   texture at build (flow bends around it), and add foam on its upstream side. This is cheap and
   tells you the water moves.
6. **Ripples from bodies and shots.** Keep a small uniform array, `vec4 ripples[12]`, holding
   (x, y, start_time, strength). Fill it from code when a body walks into water, a shot lands in it,
   or a drip lands (Ambience already has drips). In the shader, add a ring:
   `ring = smoothstep(0.8, 1.0, 1.0 - abs(dist - radius(t)) / width) * fade(t)`. The ring brightens
   the colour by one palette step and slightly bends the noise lookup. Twelve slots on a round-robin
   is enough. Bodies wading also leave a V-shaped wake: spawn a ripple every 0.15 s while they move.
7. **Fake reflections.** Avoid a second screen read. PostFx already reads the screen, and each
   `hint_screen_texture` use after the first needs another `BackBufferCopy`, which is a copy of the
   screen (Godot docs). Instead, draw a mirrored copy (scale.y = -1, alpha 0.2 to 0.3, slight
   `sin(TIME + y)` x-wobble in whole texels) of the bank props, banners, torches and the player.
   Draw it inside the river, clipped by `clip_children`, or by the river shader's alpha through a
   child `CanvasGroup`. Torches matter most: a flickering streak of their colour on the water
   sells "wet" more than anything else.
8. **Element reactions.** Read the `Materials` data texture in the same shader at the same UV:
   - **Ice (freeze):** where a cell is ICE, set the flow speed to 0 and draw a flat pale surface
     with crack lines (noise thresholded at a fine scale, plus a dark one-texel line) and a few
     static glints. The river visibly stops where it froze. `Materials` already creeps ice through
     water and melts it with fire, so the river gets this for free once it is WATER in the grid. When
     the ice melts, flow resumes, with a short burst of foam at the melt edge.
   - **Shock (crackle):** where a cell is CHARGED, add an additive pass: high-frequency noise
     thresholded hard, re-hashed at about 15 Hz (`floor(TIME * 15.0)` in the hash), in the
     shock element colour. It flickers over the whole charged pool, which the grid already spreads
     through water. Add one PostFx bloom pulse on the first charge only.
   - **Fire (steam):** where FIRE touches WATER, the grid already makes STEAM and throws steam
     puffs. On the river surface, add boiling: small bright bubble dots (hashed per cell, popping
     at 6 to 8 Hz) in cells next to fire, and a lighter, desaturated surface colour for 1 to 2 s.
   - **Oil on water:** keep oil as its own grid material floating on top. Its sheen draws above the
     river (thin bright bands), and it drifts downstream (below).
   - **Poison:** TOXIC water gets a green tint and slow bubbles. **Blood** clouds the water red for a
     few seconds as it carries downstream.
9. **Let the river carry things (Spelunky 2's lesson).** This changes gameplay, so it is Emil's call. In
   the `Materials` step, river cells could move OIL, BLOOD, TOXIC and ASH one cell along the flow
   every few steps. Then an oil slick poured upstream reaches enemies downstream and can be lit as it
   arrives. This fits the grid exactly, and its cost is linear in the active river cells, as now.

**Pressure fit:** the river is a new layer reading `Materials`' texture, with a new flow texture on the
same grid. The reactions come from the existing grid. Carrying things downstream is a small
addition to the grid step.

### 2.2 Foliage: sway, contact and reacting to elements

**Wind sway.** Two common ways to do it (godotshaders examples):
- *Vertex shear:* move the top vertices of each quad sideways with `sin(TIME + phase)`. Because a
  Sprite2D quad has only 4 vertices, the bottom stays put and the top leans. This is the cheapest, and
  it is right for tufts and small plants.
- *UV offset in the fragment shader,* scaled by height in the sprite. This keeps pixel art crisp and
  supports multi-row bends. The godotshaders "2D Pixel perfect wind & sway" shader does this in
  region-local UV. It uses the `REGION_RECT` built-in (Godot 4.5+), which matters for atlas sprites.
- *Stepped animation with a per-blade phase offset* (Dynamic 2D Grass, MIT). It looks like hand
  animation, and it suits pixel art better than smooth motion.

```glsl
shader_type canvas_item;
// One material for every plant. COLOR.a carries the sway weight per vertex
// (0 at the root, 1 at the tip), set in _draw via draw_polygon colours.
uniform float amp_px = 2.3;       // one texel at the tip
uniform float speed = 1.4;
uniform float step_hz = 8.0;
uniform float texel = 2.3;
uniform vec2 gust = vec2(0.0);    // world push from gale, eased back to 0 by code
uniform vec4 pushers[12];         // xy world pos, z radius, w strength (bodies, shots)
varying float tip;

void vertex() {
    tip = COLOR.a;
    vec2 world = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
    float t = floor(TIME * step_hz) / step_hz;
    float phase = dot(world, vec2(0.05, 0.031));
    vec2 off = vec2(sin(t * speed + phase) * amp_px, 0.0) + gust;
    for (int i = 0; i < 12; i++) {
        vec2 d = world - pushers[i].xy;
        float k = pushers[i].w * (1.0 - smoothstep(0.0, pushers[i].z, length(d)));
        off += normalize(d + 0.001) * k;
    }
    VERTEX += round(off * tip * tip / texel) * texel;
    COLOR.a = 1.0;
}
```

How this fits Pressure:
- `GrassLayer` draws every tuft in one `_draw()`. Draw each tuft with `draw_polygon` and per-vertex
  colours, with the tip vertices at alpha 1 and the root at 0. Then one canvas item and one material
  animate every tuft on the GPU, and the CPU redraws only when a tuft changes state, as now.
- **Contact (Ori's "moves in time with Ori").** Fill `pushers` from code each physics frame with the
  players, the nearest enemies and fast shots, up to 12, nearest to the camera first. A shot flying
  through a grass bed parts it. That is the cheapest "the world noticed" effect in this document.
- **Gale.** A gale shot or cloud sets `gust` in the direction of the wind and eases it back with
  a damped spring (one spring per room, not per blade). For a local gust, add a pusher with large
  radius and negative strength (pull) or positive strength (push). Void rifts can pull plants
  towards them the same way.

**State changes (burn, freeze, wilt, electrify).** Give each plant a byte state, as `GrassLayer.burnt`
already does. Read the grid under it at the layer's existing 2 Hz check, and on hits through
`apply_element`:

| Trigger | Visual (shader or `_draw` change) | Then |
|---|---|---|
| FIRE in the cell, or oil film burning (exists) | Tip flickers orange (stepped), then black stub. Sway amplitude 0. A few embers through `Fx`. | Char stays (`_char` layer). It may regrow (below). |
| ICE in the cell, or an ice hit | Pale blue tint, a white top-pixel rim, sway 0 (frozen stiff) | Any hit shatters it: 2 or 3 white pixels and a stub. Melts back after the ice's life. |
| POISON, TOXIC or ACID in the cell | Fades towards olive or brown over about 1.5 s, droops (tip shifted down one texel), sway at half speed. Acid also eats noise holes. | A wilted plant is dry: it lights more easily (raise the oil film). |
| CHARGED in the cell, or a shock hit | Whole-plant white or cyan flash for 1 frame, then 1-texel jitter at 15 Hz for 0.5 s | If wet, the grid's charge has already spread. |
| GALE | Lean with the gust, spring back | Dry or ash plants drop leaves: a few pixels blown downwind. |
| STONE hit or heavy landing | Flattened (tip y squashed to 30%) for 3 s, then springs up | |
| BLOOD | Darkened tips (a decal on the plant) | |
| HOLY | A short glow, and wilted plants recover (a nice tell) | |

**Spreading damage.** Do not write a second fire system. Plants lay a thin oil film into the grid,
as `GrassLayer` already does, so the grid's flame front carries fire bed to bed. That is Noita's
rule: a burning cell tries a neighbour. For **wall vines**, lay the film along the wall cells under
the vine. The fire then climbs it at the grid's speed, and the vine (a point chain, see 2.5) burns
segment by segment as each segment's cell turns to ash.

**Regrowth.** After a quiet time (about 20 s with no fire, acid or ice in the cell, or straight away
when the room is cleared), stubs grow back: stub, then a 1-texel sprout, then a tuft, over about 3 s.
Dynamic 2D Grass does this. Re-lay the oil film as each one regrows. Char stays on the floor, so
the burnt area is still visible: the world remembers, but heals. Keep regrowth out of combat, so a
cleared lane does not close mid-fight.

**Pressure fit:** fully inside the grid and the reactions. The new pieces are the shader, the per-vertex
weights and the state table.

### 2.3 Props, debris and decals

Lessons:
- **Isaac.** Obstacles are a family with readable variants. A tinted rock is a visible reward tell, a
  bomb rock explodes and a spiked rock leaves spikes. Destroying them changes the room.
- **Gungeon.** Flip tables for cover, roll barrels, drop chandeliers. Props are combat tools.
- **Nijman.** Permanence: what breaks stays broken, and what dies leaves something.

Techniques:
1. **Every hit gets an answer.** Even a prop that cannot break should flash white for 1 frame
   (`hit_flash` uniform, `mix(COLOR.rgb, vec3(1.0), flash)`), shake 1 texel for 2 or 3 frames and
   puff a few dust pixels. Do the same for plants. This is the single biggest "it's alive" gain for the effort.
2. **Damage states.** Draw a crack overlay at 66% and 33% HP, using a noise-threshold mask in the
   prop shader, so no new art is needed. Crates lean or splinter, and crystals cloud over.
3. **Element states on props reuse the plant table.** A burning crate chars progressively (darken from
   the bottom up with a noise edge). A frozen prop gets an ice shell (pale overlay, white rim, a
   sliding glint). A shocked metal prop gets arcs between two points for 0.3 s. A prop in a gale
   rocks. Acid pits and wilts it.
4. **Debris that stays.** When a prop breaks, throw 3 to 6 chunk pixels along short arcs (one bounce),
   then **bake them into the floor** instead of keeping nodes. Two options:
   - a byte layer on the `Materials` grid, like `_char` (6 px cells, so blocky, which is fine for rubble);
   - a decal render target: a `SubViewport` with `render_target_clear_mode = CLEAR_MODE_NEVER`, which
     draws only when something new lands (`UPDATE_ONCE`), and is shown as one texture under the
     actors. Draw cost is one texture read per floor pixel, whatever the number of decals.
     `RoomData` already remembers broken props. Store the decal list too, and replay it on re-entry.
5. **Decals that accumulate.** Scorch already exists (permanent char). Add:
   - frost rims where ice melted (white-blue ring, fading over 30 s);
   - blast marks from explosions (radial char, with a ring of debris pixels);
   - acid etching (permanent pitting, as dark dots);
   - void scars (purple hairline cracks, slowly pulsing);
   - holy burns (pale gold, fading);
   - wet footprints after walking through water or blood (5 to 8 s).

   Cap the total, and fade the oldest ones.
6. **Cover props (Gungeon).** This is a gameplay question, not an art one, so it is listed in Part 5 only
   as an option.

**Pressure fit:** `Prop` already routes every element. The work is the hit answer, crack and state
overlays in one shared prop shader, and a decal layer next to `_char`.

### 2.4 Ambient life

The ambient pixel system already exists (`Ambience`, capped at 110 pixels). Add:
- **Critters that flee.** Rats, beetles, moths and birds as 1 to 3 texel creatures. They idle with
  small hops, flee from the player and from bangs (explosions, shockwaves), and hide under props or
  in wall cracks. Move them as boids-lite on the CPU, stepped at 15 to 20 Hz. Element answers: they
  burn into a puff, freeze mid-step, get blown by a gale, and scatter from a shock. Give them
  0 HP and no collision. Rule: they **never** move towards the player and never use hostile colours
  or shapes (Part 4).
- **Steam vents.** A periodic puff (every 3 to 6 s) that drops STEAM into the grid. Fire near a vent
  makes it hiss harder, and ice caps it shut until it melts.
- **Drips** already exist and land as puddles. Add a ripple (2.1) where they land in the river.
- **Flicker.** Torches already flicker. Add lights that react: a gale gust bends and dims a flame for
  0.3 s, water puts a brazier out (it relights from fire), and shock makes a lantern buzz-flicker.
- **Banners, chains and hanging roots.** These are point chains (2.5) that move with the wind and gale.
  A fire shot can burn the banner from the bottom up, leaving a ragged edge.
- **Idle details.** Water dripping from the ceiling into a bucket, a spider lowering on a thread,
  moss spores pulsing, a far-wall crack leaking dust when the room shakes. Pick 2 or 3 per theme,
  not all of them.
- **Combat dim.** While hostile enemies are alive, halve the spawn rates of decorative ambience and
  slow critters. The room is alive when you walk in and quiet down when the fight starts, which
  helps readability (Part 4).

**Pressure fit:** extend `Ambience` (new kinds `K_CRITTER` and `K_VENT`, with vents already listed as
`vents`). Critters read `material_at()` for the element answers.

### 2.5 Secondary animation and juice

From Juice It or Lose It, Nijman and Eiserloh, applied to the world as well as to actors:
- **Squash and stretch.** Props squash 1 texel on hit. Plants bend on contact. Debris stretches along
  its arc, then lands squashed. A pickup bounces in with a squash.
- **Anticipation.** A barrel about to blow swells and flashes faster. A cracked pillar sheds dust
  before it falls. A vent puffs a small cloud just before its big one. Anticipation doubles as a
  telegraph for any prop that can hurt.
- **Hit-flash.** One frame white, on everything that can be hit (2.3).
- **Knockback.** Small props (bottles, bones, pots) slide when shot, using simple velocity with friction.
  Ice floors make them glide (`ICE_KEEP` already exists for bodies).
- **Screen shake, used sparingly.** Eiserloh's camera talk is commonly summarised as follows (please
  check the video): store "trauma" from 0 to 1, add to it on events, let it decay over time, shake by
  trauma squared, and drive the shake with smooth noise rather than random jumps. Nijman shakes
  slightly against the direction of fire. For Pressure: the world's own events (a prop breaking, a
  barrel blowing) add only a little trauma. Big shake is for things that hurt the player and for bosses.
- **Hit-stop.** It already exists. Use it for world events only when the player caused something big
  (a chain reaction that clears a pool), never for ambient things.
- **Point chains (Rain World).** A chain is 6 to 12 points with fixed lengths between them (Verlet:
  `p += (p - prev) * damping + gravity + wind`, then 2 or 3 constraint passes). Use them for vines,
  banners, roots, chains and cobwebs. Step at 30 Hz in one manager node, and draw as `draw_polyline` in
  whole texels. Twenty chains of 10 points is trivial GDScript work. Forces are gust, pushers,
  explosions (a radial impulse) and a burning segment that falls off.

### 2.6 Room composition: dress the whole floor, keep the lanes

Right now, `ArtPass` places dressing along the walls only, never in the middle. To dress the interior
without hurting readability:
1. **Islands, not scatter.** Group interior dressing into 2 to 4 clusters per room, anchored on
   something: a pillar, a pool, a grass bed, the river bank, a broken statue, a drain. Leave the space
   between clusters clean. A uniform scatter reads as noise.
2. **Lanes.** Keep lanes at least 2 to 3 player-widths wide between clusters and from every door
   to the room centre. Dressing that blocks movement must be a real obstacle (`Prop`, readable as
   one). Never put a non-blocking thing that looks solid in a lane.
3. **Value band for floor dressing.** Floor decor (cracks, moss, tiles, stains, leaves) stays within a
   narrow brightness range of the floor (about ±10% luminance) and below its saturation. Threats get
   the top of the range (Dead Cells). Dressing with more contrast belongs on walls and edges, or in the
   foreground overhang, where nothing hostile moves.
4. **One landmark per room.** A big, unique feature (a dead tree, a fallen bell, a river bend with a
   bridge, a statue with an offering) gives the room an identity and helps the player find their way
   in a roguelite with many rooms. Put it off-centre (on a third), so it never sits where the fight
   centres.
5. **Environmental storytelling in clusters.** One arrangement tells one event: a burnt camp (ash ring,
   charred bedroll, scattered bones), a barricade facing a door, drag marks of dried blood into an
   alcove. Isaac and Gungeon rooms are templates. Pressure's `room_layouts` can carry "story stamps" the
   way they carry pools and grass beds now.
6. **Reactive dressing earns its space.** Interior dressing that also reacts (dry grass that burns,
   puddles that conduct, hanging vines that burn, oil jars) is gameplay terrain as well as decoration.
   Prefer it over inert clutter in the middle of the room. Inert clutter goes to the edges.

### 2.7 Lighting and atmosphere

Pressure's lighting already lives in PostFx and ArtPass (ambient multiply, point lights, scatter,
emissive pass-through, grade, vignette), and Crisp stays unlit above it. Recommendations:
- **Keep the custom lighting. Do not switch to `PointLight2D`.** Built-in 2D lights cost more as they get
  larger (Godot docs: "Larger lights have a higher performance cost"). Forum reports also describe a
  cap of about 15 lights per canvas item, and the third-party fix for that (Lit) does not support
  Compatibility.
- **Normal maps.** Godot supports them through `CanvasTexture` (diffuse, normal, specular). But Pressure
  lights in screen space after the world draws, so normals would need a normal buffer, which means
  a second render of the scene. That is too costly for the target. Cheaper alternatives:
  - *Rim from the alpha edge.* In the prop shader, sample the alpha 1 texel towards the nearest light
    (`light_dir` uniform per prop, set when the prop is placed). Where the neighbour is transparent,
    the pixel is an edge facing the light: brighten it one palette step. That gives a lit side with
    no new art.
  - *Hand-painted light masks (Ori).* Mahler says Moon painted light masks on every asset. For
    Pressure, that means one extra greyscale texture per important prop, for "lit from above", used
    by the same shader. Do it for landmarks only.
- **Light pools.** These exist (scatter inside lights). Give fire on the floor a light: burning grid
  cells already count as emissive. Add a soft warm pool around large fire clusters by feeding the
  2 to 4 biggest fire areas into ArtPass lights as temporary entries.
- **Volumetric shafts.** ArtPass has a `shafts` colour. Draw shafts as additive trapezoids from a top
  wall gap, with a slow noise scroll along the shaft and dust pixels (Ambience `K_DRIFT`) visible only
  inside them. Fade them to near nothing in combat if they cross a lane.
- **Fog layers.** Two low-alpha noise layers scrolling at different speeds and directions, drawn above
  the floor and below the actors. Better still, fold fog into the PostFx pass as a term, which costs
  no extra full-screen draw. Thicker fog in corners and over the river, thin in lanes. A gale pushes it,
  and fire thins it locally. Feed in fire and gale positions with the same `pushers` array.
- **Colour grading.** This already exists: lift and gain per region, plus the palette LUT. Add
  *event grading*: a short cool shift when a large ice reaction lands, warm when a big fire catches,
  desaturation during hit-stop. Keep each one subtle (0.2 to 0.4 s) and never on the Crisp layer.
- **Lights blocked by walls**, if wanted later: use Celeste's packed-mask method (each light's
  cut-out mask in one channel of a shared texture, then one colour pass). Not needed now.

---

## Part 3. Performance on the Web and Compatibility renderer

The target is 98 to 100 fps, which is a budget of about 10 ms per frame. The web build is single-threaded, and
the materials grid is drawn per cell from a data texture.

- **Fill rate is the main cost of 2D shaders.** Every full-room quad runs its fragment shader on every
  covered pixel. Draw the river only over the river (a polygon, or `discard` outside the mask, with the
  quad clipped to the river's bounding box). Fold fog and grading into the existing PostFx pass instead
  of adding full-screen quads.
- **Screen reads.** The first `hint_screen_texture` use copies the screen. Later overlapping uses need a
  `BackBufferCopy`, another copy (Godot docs). PostFx already reads the screen, so avoid a second
  read for water reflections. Use mirrored sprite copies.
- **Batching.** In Godot 3, the docs listed texture changes, material changes, z-index, canvas layers
  and lights as batch breakers. I could not find the equivalent Godot 4 Compatibility page, so treat
  this as likely, not confirmed, and measure. Practical rules: one shared `ShaderMaterial` per
  family; per-instance variation through vertex `COLOR` or world-position hashes; draw many small
  things from one `_draw()` (as `GrassLayer` and `Materials` do), or with `MultiMeshInstance2D`
  (one draw call; its culling is all-or-none, per the Godot docs, so split it by room area).
- **No per-frame redraws.** Animate with `TIME` in shaders. Call `queue_redraw()` only on state changes.
  `Materials` already follows this rule. The foliage plan above keeps to it.
- **Uniform arrays.** Keep `pushers` and `ripples` arrays small (12 to 16 entries). A loop over 12
  entries per vertex is cheap. Per fragment, over a whole-room quad, it is not: run ripples per
  fragment only on the river polygon.
- **Noise textures.** Use small seamless textures (64 to 128 px), baked to PNG, not
  `NoiseTexture2D` generated at load on the web.
- **Particles.** The docs say `CPUParticles2D` has lower performance with large particle counts than
  GPU particles. On the web, forum reports describe first-spawn hitches from shader compilation, and
  particles missing on some GPUs. Pressure's own `Fx` system with hard caps (`FX_CAP`) avoids both.
  Keep new effects (embers, steam, debris, leaves) in `Fx`, not in particle nodes.
- **Shader warm-up.** On the web, new shaders compile on first use, which causes a hitch. Draw each new
  material (river, foliage, prop, decal) once off-screen during loading. The boss-music preload fix
  in a recent commit is the same idea.
- **CPU budget for new systems.** Critters: at most 20 per room, stepped at 15 to 20 Hz. Chains:
  at most 20 x 10 points at 30 Hz. Plant state checks: stay at 2 Hz. River advection: inside the
  12 Hz grid step, under `STEP_CAP`.
- **Measure on an idle PC.** Use the bot and fps tools from the late-build fps work, before and after
  each item, with the same seeds.

---

## Part 4. Readability: hostile things stay the clearest

Sources: Dead Cells (Massé 2018), Riot (Clarity in League 2021, VFX style guide 2017), Keyser and
Chamberlain (GDC 2017), Hinkelbein (GDC 2024), Supergiant's AMA (paraphrased).

1. **A value and saturation hierarchy, written down.** From lowest to highest:
   - floor and floor dressing;
   - walls and edge dressing;
   - interactive and reactive things (props, grass, river, critters);
   - player effects;
   - **hostiles and hostile shots** (most saturated, most contrast, and on Crisp, unlit).

   This is Dead Cells' rule.
2. **Attention follows importance** (Riot). A reaction on the environment may be bright for a moment,
   because it is feedback, but it must be shorter-lived and smaller than anything hostile.
3. **Looks dangerous means is dangerous.** If burning grass hurts, it must look like the existing floor
   fire. If a visual fire on a plant tip does not hurt, it must look clearly different: small, no flame
   front, no glow on the floor. The same goes for floating motes. They must never resemble shots
   (round, glowing, moving with intent). Ambience already keeps them as single low-alpha pixels.
4. **Reserve the hostile hue and shape language.** Whatever colours and shapes Crisp uses for hostiles,
   no dressing, critter, decal or water effect may use them. Write that list into the art direction
   doc, and check new dressing against it.
5. **Motion budget.** Ambient motion is slow and small (at most 1 texel per frame, stepped). Threats
   are fast. Combat dims ambience (2.4) and could halve sway amplitude.
6. **Lanes stay clean** (2.6), and fog thins over lanes.
7. **Measure it.** `ClarityShot` already measures enemy and floor contrast and the coverage of own effects.
   Add two numbers: `dress%`, the share of screen pixels changed by environment dressing and ambience
   (the frame with them on against off), and the enemy contrast with dressing on. Rule for every
   change in this document: **mean enemy contrast must not drop**, and `dress%` stays under an agreed
   cap in the arena shots.

---

## Part 5. Prioritised implementation list

Impact: H (high), M (medium), L (low). Effort: S (small, under a day), M (medium, 1 to 3 days),
L (large, more than 3 days). **Grid fit** says whether the item plugs into the existing `Materials`
grid and reaction system: Yes, Partial, or No (a new system).

| # | Item | Impact | Effort | Grid fit | Notes |
|---|---|---|---|---|---|
| 1 | Hit answer on everything (1-frame flash, 1-texel shake, dust) for props, plants and walls | H | S | Partial | Rides on `Prop.apply_element` and `take_damage`. The cheapest "alive" gain. |
| 2 | Foliage sway shader (stepped, texel-snapped) plus a `pushers` array for contact | H | S–M | No | One material for `GrassLayer`, with per-vertex weights. Shots part the grass. |
| 3 | Plant state table: burn, freeze-shatter, wilt, electrify, gale lean, flatten, then regrow | H | M | **Yes** | Reads `material_at`. Fire spreads through the existing oil film. Regrowth re-lays the film. |
| 4 | River shader: flow texture, two-phase noise, bank foam, depth | H | M | **Yes** | Same grid as `Materials`. Read the data texture for ice (flow stops), charge (crackle) and steam (boil). |
| 5 | Decal layer: debris that stays, frost rims, blast marks, acid etch, footprints | H | M | **Yes** | A byte layer next to `_char`, or a never-clear decal target. Replay from `RoomData`. |
| 6 | Interior dressing rules in ArtPass: islands, lanes, value band, one landmark | H | M | No | Gate with the new `ClarityShot` numbers. |
| 7 | Ripples and wakes in water from bodies, shots and drips | M | S | **Yes** | 12-slot uniform array. Triggers come from `material_at == WATER`. |
| 8 | Gale gust uniform and void pull for plants, fog, banners and flames | M | S | Partial | One room-level spring. Gale and void events already exist. |
| 9 | Point chains (Verlet) for vines, banners, roots and cobwebs. They burn segment by segment. | M | M | Partial | Burning follows the grid's ash under each segment. |
| 10 | Critters that flee and react to elements; steam vents | M | M | Partial | New kinds in `Ambience`. Never hostile-looking. |
| 11 | Fake reflections (mirrored bank props and torch streaks) | M | S | No | Clipped to the river. No second screen read. |
| 12 | Prop damage and element overlays (cracks, char creep, ice shell, arcs) | M | M | **Yes** | One shared prop shader. No new art. |
| 13 | River carries oil, blood, toxic and ash downstream | M (gameplay) | S–M | **Yes** | A design decision for Emil. It is very much in Pressure's spirit. |
| 14 | Rim light from the alpha edge towards the nearest light | M | S | No | Gives props a lit side without normal maps. |
| 15 | Fog folded into the PostFx pass, pushed by gale and thinned by fire | M | M | Partial | No extra full-screen draw. |
| 16 | Combat dim of ambience and sway | M | S | No | Readability insurance for everything above. |
| 17 | Event grading (cool after a big freeze, warm after a big fire) | L | S | Partial | Subtle, short, never on Crisp. |
| 18 | Volumetric shafts with dust inside | L | S | No | `shafts` already exists in ArtPass. |
| 19 | Story stamps in `room_layouts` (burnt camp, barricade, drag marks) | M | M | Partial | Use reactive pieces where possible. |
| 20 | Cover props (Gungeon table flip) | ? | M | No | Gameplay, not visuals. Listed for completeness only. |
| 21 | Lights blocked by walls (Celeste packed masks) | L | L | No | Not needed at the current look. |

Suggested order: 1, 2 and 3 together (they share the foliage work), then 16 and the `ClarityShot`
numbers as a guard, then 4 and 7 (the river), then 5, 6, 12, 8, 9, 10, 11, then the rest.
