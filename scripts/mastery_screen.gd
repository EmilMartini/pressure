class_name MasteryScreen
extends PanelContainer
## The mastery tree drawn as a node graph: a core circle in the middle and one spoke per
## branch. Each branch root sits on a ring around the core, its chains step outward by
## depth and are fanned into parallel lanes so they never overlap. Positions are computed
## once from `Mastery.nodes` and cached in world space; the canvas pans and zooms over them.
##
## Controls: d-pad / left stick / arrows move focus along the tree (or jump to the nearest
## node in that direction), A / Enter / Space buys, right stick or mouse drag pans,
## triggers or the wheel zoom, LB / RB / Q / E jump between branches, B / Esc closes.
## The canvas Control keeps GUI focus so MenuPad's up/down focus walking stays put.

const BOUGHT_COLOR := Color(0.6, 1.0, 0.75)
const READY_COLOR := UiTheme.BONE
const REACHABLE_COLOR := Color(0.52, 0.49, 0.44)
const LOCKED_FILL := Color(0.20, 0.19, 0.21)
const LOCKED_EDGE := Color(0.24, 0.22, 0.25)
const CORE_FILL := Color(0.12, 0.10, 0.12)
const CANVAS_BG := Color(0.035, 0.03, 0.045, 0.85)
const TEXT_OUTLINE := Color(0.03, 0.025, 0.04)

# Layout (world px at zoom 1).
const NODE_R := 16.0
const ROOT_R := 22.0
const CAP_R := 20.0
const CORE_R := 64.0
const STEP := 52.0            # radial distance between depths
const LANE := 38.0            # sideways distance between parallel chains of one branch
const MARGIN := 26.0          # empty gap between neighbouring branches
const MIN_RING := 180.0       # smallest radius for the ring of branch roots
const BRANCH_LABEL_IN := 44.0 # branch names sit this far inside the root ring...
const BRANCH_LABEL_STAGGER := 34.0 # ...and every other one a little further in

# View.
const START_ZOOM := 0.8
const MIN_ZOOM := 0.35
const MAX_ZOOM := 1.6
const LABEL_MIN_ZOOM := 0.6   # below this only the current branch is named
const FOLLOW_MARGIN := 70.0   # screen px the focused node keeps from the canvas edge
const PAN_SPEED := 700.0      # screen px per second at full right-stick tilt
const ZOOM_SPEED := 1.6       # log-zoom per second at full trigger
const DRAG_SLOP := 6.0

# Navigation.
const LINK_CONE := 0.38       # min cosine between input and a parent/child direction
const JUMP_CONE := 0.5        # min cosine for the free jump fallback
const JUMP_RANGE := 120.0     # world px
const STICK_THRESHOLD := 0.55
const REPEAT_DELAY := 0.35
const REPEAT_RATE := 0.12

enum St { LOCKED, REACHABLE, READY, BOUGHT }

var on_close: Callable
var tab := 0

var _canvas: Control
var _points_label: Label
var _count_label: Label
var _name_label: Label
var _cost_label: Label
var _desc_label: Label
var _bonus_label: Label
var _back: Button

var _branch_names: Array = []
var _ids: Array = []              # every node id, branches in order, parents first
var _index: Dictionary = {}       # id -> position in _ids
var _children: Dictionary = {}    # id -> Array of child ids
var _pos: Dictionary = {}         # id -> Vector2 world position
var _branch_of: Dictionary = {}   # id -> branch index
var _roots: Array = []            # branch index -> root id
var _branch_angle: Array = []     # branch index -> spoke angle (radians)
var _branch_color: Array = []     # branch index -> label colour
var _ring_r := MIN_RING
var _extent := 600.0
var _lane_counter := 0

var _focus := ""
var _zoom := START_ZOOM
var _cam := Vector2.ZERO          # world point at the canvas centre
var _cam_goal := Vector2.ZERO
var _time := 0.0
var _press_pos := Vector2.ZERO
var _dragged := false
var _was: Dictionary = {}
var _held: Dictionary = {}


func _init(p_on_close: Callable) -> void:
    on_close = p_on_close


func _ready() -> void:
    custom_minimum_size = Vector2(1100, 640)
    _build_layout()
    var v := VBoxContainer.new()
    v.add_theme_constant_override("separation", 6)
    add_child(v)

    var header := HBoxContainer.new()
    header.add_theme_constant_override("separation", 28)
    v.add_child(header)
    var title := _text("MASTERY", 40, UiTheme.BONE)
    header.add_child(title)
    _points_label = _text("", 24, UiTheme.BONE)
    _points_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    header.add_child(_points_label)
    _count_label = _text("", 24, UiTheme.DIM)
    _count_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    header.add_child(_count_label)
    var hint := _text("A buy   LB RB branch   RS pan   LT RT zoom", 20, UiTheme.DIM)
    hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    hint.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
    header.add_child(hint)

    _canvas = Control.new()
    _canvas.custom_minimum_size = Vector2(0, 360)
    _canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
    _canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _canvas.clip_contents = true
    _canvas.focus_mode = Control.FOCUS_ALL
    _canvas.mouse_filter = Control.MOUSE_FILTER_STOP
    # Point every focus link back at the canvas itself so MenuPad's up/down walking and
    # the built-in ui_* navigation never carry focus away from the graph.
    var self_path := NodePath(".")
    _canvas.focus_next = self_path
    _canvas.focus_previous = self_path
    _canvas.focus_neighbor_top = self_path
    _canvas.focus_neighbor_bottom = self_path
    _canvas.focus_neighbor_left = self_path
    _canvas.focus_neighbor_right = self_path
    _canvas.draw.connect(_draw_graph)
    _canvas.gui_input.connect(_on_canvas_input)
    v.add_child(_canvas)

    var footer := HBoxContainer.new()
    footer.add_theme_constant_override("separation", 20)
    v.add_child(footer)
    var info := VBoxContainer.new()
    info.add_theme_constant_override("separation", 0)
    info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    footer.add_child(info)
    var top_line := HBoxContainer.new()
    top_line.add_theme_constant_override("separation", 24)
    info.add_child(top_line)
    _name_label = _text("", 28, UiTheme.BONE)
    top_line.add_child(_name_label)
    _cost_label = _text("", 22, UiTheme.DIM)
    _cost_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    _cost_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _cost_label.clip_text = true
    top_line.add_child(_cost_label)
    _desc_label = _text("", 20, UiTheme.BONE)
    _desc_label.clip_text = true
    info.add_child(_desc_label)
    _bonus_label = _text("", 20, BOUGHT_COLOR)
    _bonus_label.clip_text = true
    info.add_child(_bonus_label)
    _back = UiTheme.button("Back", func(): on_close.call())
    _back.custom_minimum_size = Vector2(150, 52)
    _back.focus_mode = Control.FOCUS_NONE
    _back.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    footer.add_child(_back)

    visibility_changed.connect(_on_visibility_changed)
    if not _roots.is_empty():
        _focus = _roots[0]
        _cam_goal = _root_view(0)
        _cam = _cam_goal
    _refresh_text()


# --- Public API ------------------------------------------------------------


## Jump to branch `i` (wrapped): focus its root and pan to it. The menu's shoulder buttons
## call this through MenuPad.on_tab.
func set_tab(i: int) -> void:
    if _branch_names.is_empty():
        _branch_names = Mastery.branches()
    if _branch_names.is_empty():
        return
    # MenuPad also routes the d-pad's left/right to on_tab; here those directions walk the
    # graph instead, so ignore a tab step that came from the d-pad rather than a shoulder.
    if _canvas != null and is_visible_in_tree() and _dpad_side_only():
        return
    tab = wrapi(i, 0, _branch_names.size())
    if _canvas == null:
        return
    _set_focus(_roots[tab], false)
    _cam_goal = _root_view(tab)
    Sfx.play("ui_move")
    if is_visible_in_tree():
        _canvas.grab_focus.call_deferred()


# --- Layout ----------------------------------------------------------------


## Lay every node out once. Each branch is a spoke: the root on a ring around the core,
## descendants at `ring + depth * STEP` along the spoke, offset sideways by their lane.
## Lanes come from the leaves of the branch (one per leaf, chains keep their first
## child's lane), so a branch is as wide as its number of parallel chains; each spoke gets
## an angular wedge in proportion to that width, and the ring radius is chosen so the
## wedges' arcs at depth 1 hold every lane plus a margin.
func _build_layout() -> void:
    _branch_names = Mastery.branches()
    for b in _branch_names:
        for n in Mastery.nodes_in_branch(b):
            var id: String = n["id"]
            _index[id] = _ids.size()
            _ids.append(id)
            _children[id] = []
    for id in _ids:
        var parent: String = Mastery.nodes[id]["parent"]
        if parent != "" and _children.has(parent):
            (_children[parent] as Array).append(id)

    var lanes_per_branch: Array = []
    var lane_maps: Array = []
    var weights: Array = []
    var total := 0.0
    var core_weight := 0.0
    for bi in _branch_names.size():
        var b: String = _branch_names[bi]
        var list: Array = Mastery.nodes_in_branch(b)
        var root: String = ""
        for n in list:
            _branch_of[n["id"]] = bi
            if root == "" and str(n["parent"]) == "":
                root = n["id"]
        _roots.append(root)
        var lanes: Dictionary = {}
        _lane_counter = 0
        if root != "":
            for k in _center_out(_sorted_children(root)):
                _assign_lanes(k, lanes)
        var count := maxi(_lane_counter, 1)
        lanes_per_branch.append(count)
        lane_maps.append(lanes)
        var half := (count - 1) * 0.5 * LANE + NODE_R
        var w := half * 2.0 + MARGIN
        weights.append(w)
        total += w
        _branch_color.append(_color_for_branch(b))
        if _element_index(b) < 0:
            core_weight += w

    if total <= 0.0:
        return
    var lane_r := total / TAU
    _ring_r = maxf(lane_r - STEP, MIN_RING)
    # Rotate so the general branches (listed first) sit centred at the top.
    var a := -PI * 0.5 - (core_weight / total) * PI
    for bi in _branch_names.size():
        var span: float = float(weights[bi]) / total * TAU
        _branch_angle.append(a + span * 0.5)
        a += span

    _extent = _ring_r
    for bi in _branch_names.size():
        var u := Vector2.from_angle(float(_branch_angle[bi]))
        var side := Vector2(-u.y, u.x)
        var count: int = lanes_per_branch[bi]
        var lanes: Dictionary = lane_maps[bi]
        var centre := (count - 1) * 0.5
        for n in Mastery.nodes_in_branch(_branch_names[bi]):
            var id: String = n["id"]
            var depth := int(n["depth"])
            var p := u * (_ring_r + depth * STEP)
            if depth > 0:
                p += side * (float(lanes.get(id, centre)) - centre) * LANE
            _pos[id] = p
            _extent = maxf(_extent, p.length())
    _extent += 40.0


func _assign_lanes(id: String, lanes: Dictionary) -> void:
    var kids := _sorted_children(id)
    if kids.is_empty():
        lanes[id] = _lane_counter
        _lane_counter += 1
        return
    for k in kids:
        _assign_lanes(k, lanes)
    lanes[id] = lanes[kids[0]]


## Children with the biggest subtree first (capstones win ties), so the main line of a
## chain stays straight and side branches step out of it.
func _sorted_children(id: String) -> Array:
    var kids: Array = (_children.get(id, []) as Array).duplicate()
    kids.sort_custom(func(x: String, y: String) -> bool:
        var sx := _subtree_size(x)
        var sy := _subtree_size(y)
        if sx != sy:
            return sx > sy
        var cx := _is_cap(x)
        var cy := _is_cap(y)
        if cx != cy:
            return cx
        return int(_index[x]) < int(_index[y]))
    return kids


## Reorder a size-sorted list so the largest sits in the middle and the rest alternate
## outward: the long chains run along the spoke's axis.
func _center_out(sorted: Array) -> Array:
    var out: Array = []
    for i in sorted.size():
        if i % 2 == 0:
            out.push_back(sorted[i])
        else:
            out.push_front(sorted[i])
    return out


func _subtree_size(id: String) -> int:
    var s := 1
    for c in _children.get(id, []):
        s += _subtree_size(c)
    return s


func _is_cap(id: String) -> bool:
    return id.ends_with("_cap") or str(Mastery.nodes[id]["desc"]).begins_with("Capstone")


func _element_index(branch: String) -> int:
    return Mastery.ELEMENT_KEYS.find(branch.to_lower())


func _color_for_branch(branch: String) -> Color:
    var idx := _element_index(branch)
    if idx < 0 or idx >= Element.ALL.size():
        return UiTheme.BONE
    return Element.COLORS[Element.ALL[idx]]


func _radius(id: String) -> float:
    if str(Mastery.nodes[id]["parent"]) == "":
        return ROOT_R
    if _is_cap(id):
        return CAP_R
    return NODE_R


## Camera target that shows a branch: its root plus a little of the spoke beyond it.
func _root_view(bi: int) -> Vector2:
    var root: String = _roots[bi]
    var p: Vector2 = _pos.get(root, Vector2.ZERO)
    return _clamp_cam(p + Vector2.from_angle(float(_branch_angle[bi])) * 160.0)


# --- State -----------------------------------------------------------------


func _state(id: String) -> int:
    if Mastery.is_bought(id):
        return St.BOUGHT
    if Mastery.can_buy(id):
        return St.READY
    if Mastery.is_reachable(id):
        return St.REACHABLE
    return St.LOCKED


func _state_color(st: int) -> Color:
    match st:
        St.BOUGHT:
            return BOUGHT_COLOR
        St.READY:
            return READY_COLOR
        St.REACHABLE:
            return REACHABLE_COLOR
    return LOCKED_FILL


func _links(id: String) -> Array:
    var out: Array = (_children.get(id, []) as Array).duplicate()
    var parent: String = Mastery.nodes[id]["parent"]
    if parent != "":
        out.append(parent)
    return out


func _set_focus(id: String, follow: bool = true) -> void:
    if id == "" or not _pos.has(id):
        return
    _focus = id
    tab = int(_branch_of.get(id, tab))
    _refresh_text()
    if follow:
        _follow_focus()
    if _canvas != null:
        _canvas.queue_redraw()


func _refresh_text() -> void:
    if _points_label == null:
        return
    _points_label.text = "Points %d" % Mastery.points
    _count_label.text = "Bought %d / %d" % [Mastery.purchased_count(), Mastery.total_nodes()]
    if _focus == "" or not Mastery.nodes.has(_focus):
        _name_label.text = ""
        _cost_label.text = ""
        _desc_label.text = ""
        _bonus_label.text = ""
        return
    var n: Dictionary = Mastery.nodes[_focus]
    var st := _state(_focus)
    _name_label.text = str(n["name"])
    _name_label.add_theme_color_override("font_color", BOUGHT_COLOR if st == St.BOUGHT else UiTheme.BONE)
    var note := ""
    match st:
        St.BOUGHT:
            note = "owned"
        St.READY:
            note = "press A to buy"
        St.REACHABLE:
            note = "not enough points"
        St.LOCKED:
            note = "needs %s" % Mastery.get_node_data(n["parent"]).get("name", "?")
    _cost_label.text = "Cost %d   %s" % [int(n["cost"]), note]
    _desc_label.text = str(n["desc"])
    _bonus_label.text = Mastery.mods_text(n["mods"])


func _buy_focused() -> void:
    if _focus == "":
        return
    if Mastery.buy(_focus):
        Sfx.play("ui_confirm")
    else:
        Sfx.play("error")
    _refresh_text()
    _canvas.queue_redraw()


# --- View ------------------------------------------------------------------


func _to_screen(p: Vector2) -> Vector2:
    return (p - _cam) * _zoom + _canvas.size * 0.5


func _to_world(s: Vector2) -> Vector2:
    return (s - _canvas.size * 0.5) / _zoom + _cam


func _clamp_cam(c: Vector2) -> Vector2:
    if c.length() > _extent:
        return c.normalized() * _extent
    return c


func _zoom_at(new_zoom: float, screen_pos: Vector2) -> void:
    var before := _to_world(screen_pos)
    _zoom = clampf(new_zoom, MIN_ZOOM, MAX_ZOOM)
    _cam = _clamp_cam(before - (screen_pos - _canvas.size * 0.5) / _zoom)
    _cam_goal = _cam


## Nudge the camera target just enough that the focused node sits inside the canvas.
func _follow_focus() -> void:
    if _canvas == null or not _pos.has(_focus):
        return
    var p: Vector2 = _pos[_focus]
    var sz := _canvas.size
    if sz.x < 2.0 * FOLLOW_MARGIN or sz.y < 2.0 * FOLLOW_MARGIN:
        _cam_goal = _clamp_cam(p)
        return
    var half := sz * 0.5 - Vector2(FOLLOW_MARGIN, FOLLOW_MARGIN)
    var rel := (p - _cam_goal) * _zoom
    var shift := Vector2.ZERO
    if rel.x > half.x:
        shift.x = rel.x - half.x
    elif rel.x < -half.x:
        shift.x = rel.x + half.x
    if rel.y > half.y:
        shift.y = rel.y - half.y
    elif rel.y < -half.y:
        shift.y = rel.y + half.y
    _cam_goal = _clamp_cam(_cam_goal + shift / _zoom)


# --- Navigation ------------------------------------------------------------


## Move focus along `dir` (screen space, y down): the parent or child whose direction
## matches best, else the nearest node in that direction within JUMP_RANGE.
func _move(dir: Vector2) -> void:
    if _focus == "" or dir == Vector2.ZERO:
        return
    dir = dir.normalized()
    var from: Vector2 = _pos[_focus]
    var best := ""
    var best_cos := -INF
    for id in _links(_focus):
        if not _pos.has(id):
            continue
        var off: Vector2 = (_pos[id] as Vector2) - from
        if off.length() < 0.001:
            continue
        var c := off.normalized().dot(dir)
        if c > LINK_CONE and c > best_cos:
            best_cos = c
            best = id
    if best == "":
        var best_score := INF
        for id in _ids:
            if id == _focus:
                continue
            var off: Vector2 = (_pos[id] as Vector2) - from
            var dist := off.length()
            if dist < 0.001 or dist > JUMP_RANGE:
                continue
            var c := off.normalized().dot(dir)
            if c < JUMP_CONE:
                continue
            var score := dist * (2.0 - c)
            if score < best_score:
                best_score = score
                best = id
    if best == "":
        return
    _set_focus(best)
    Sfx.play("ui_move")


func _process(delta: float) -> void:
    if _canvas == null or not is_visible_in_tree():
        return
    _time += delta
    _poll_pad(delta)
    _cam = _cam.lerp(_cam_goal, 1.0 - exp(-12.0 * delta))
    _canvas.queue_redraw()


func _poll_pad(delta: float) -> void:
    var up := false
    var down := false
    var left := false
    var right := false
    var accept := false
    var stick := Vector2.ZERO
    var pan := Vector2.ZERO
    var zoom_in := 0.0
    var zoom_out := 0.0
    for d in Input.get_connected_joypads():
        up = up or Input.is_joy_button_pressed(d, JOY_BUTTON_DPAD_UP)
        down = down or Input.is_joy_button_pressed(d, JOY_BUTTON_DPAD_DOWN)
        left = left or Input.is_joy_button_pressed(d, JOY_BUTTON_DPAD_LEFT)
        right = right or Input.is_joy_button_pressed(d, JOY_BUTTON_DPAD_RIGHT)
        accept = accept or Input.is_joy_button_pressed(d, JOY_BUTTON_A)
        var s := Vector2(Input.get_joy_axis(d, JOY_AXIS_LEFT_X), Input.get_joy_axis(d, JOY_AXIS_LEFT_Y))
        if s.length() > stick.length():
            stick = s
        var r := Vector2(Input.get_joy_axis(d, JOY_AXIS_RIGHT_X), Input.get_joy_axis(d, JOY_AXIS_RIGHT_Y))
        if r.length() > pan.length():
            pan = r
        zoom_in = maxf(zoom_in, Input.get_joy_axis(d, JOY_AXIS_TRIGGER_RIGHT))
        zoom_out = maxf(zoom_out, Input.get_joy_axis(d, JOY_AXIS_TRIGGER_LEFT))

    if _edge("up", up, delta, true):
        _move(Vector2.UP)
    if _edge("down", down, delta, true):
        _move(Vector2.DOWN)
    if _edge("left", left, delta, true):
        _move(Vector2.LEFT)
    if _edge("right", right, delta, true):
        _move(Vector2.RIGHT)
    var stick_on := stick.length() > STICK_THRESHOLD
    if _edge("stick", stick_on, delta, true):
        _move(stick)
    if _edge("accept", accept, delta, false):
        _buy_focused()

    var tilt := pan.length()
    if tilt > 0.2:
        var amount := (tilt - 0.2) / 0.8
        _cam_goal = _clamp_cam(_cam_goal + pan / tilt * amount * PAN_SPEED * delta / _zoom)
        _cam = _cam_goal
    var z := zoom_in - zoom_out
    if absf(z) > 0.1:
        _zoom_at(_zoom * exp(z * ZOOM_SPEED * delta), _canvas.size * 0.5)


## True on the press, and again on repeat while held when `repeat` is set.
func _edge(key: String, down: bool, delta: float, repeat: bool) -> bool:
    var was: bool = _was.get(key, false)
    _was[key] = down
    if not down:
        _held[key] = 0.0
        return false
    if not was:
        _held[key] = 0.0
        return true
    if not repeat:
        return false
    var h: float = float(_held.get(key, 0.0)) + delta
    if h >= REPEAT_DELAY:
        _held[key] = h - REPEAT_RATE
        return true
    _held[key] = h
    return false


## A d-pad side is held but no shoulder: a MenuPad on_tab call came from the d-pad.
func _dpad_side_only() -> bool:
    var side := false
    for d in Input.get_connected_joypads():
        if Input.is_joy_button_pressed(d, JOY_BUTTON_LEFT_SHOULDER) or Input.is_joy_button_pressed(d, JOY_BUTTON_RIGHT_SHOULDER):
            return false
        if Input.is_joy_button_pressed(d, JOY_BUTTON_DPAD_LEFT) or Input.is_joy_button_pressed(d, JOY_BUTTON_DPAD_RIGHT):
            side = true
    return side


func _on_visibility_changed() -> void:
    if not visible:
        return
    # Buttons still held from opening the screen (A on the menu) must be released first.
    for k in ["up", "down", "left", "right", "stick", "accept"]:
        _was[k] = true
    _refresh_text()
    if _canvas != null:
        _canvas.grab_focus.call_deferred()


func _input(event: InputEvent) -> void:
    if _canvas == null or not is_visible_in_tree() or not event is InputEventKey:
        return
    var k := event as InputEventKey
    if not k.pressed:
        return
    var handled := true
    match k.physical_keycode:
        KEY_UP:
            _move(Vector2.UP)
        KEY_DOWN:
            _move(Vector2.DOWN)
        KEY_LEFT:
            _move(Vector2.LEFT)
        KEY_RIGHT:
            _move(Vector2.RIGHT)
        KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
            if not k.echo:
                _buy_focused()
        KEY_Q:
            if not k.echo:
                set_tab(tab - 1)
        KEY_E:
            if not k.echo:
                set_tab(tab + 1)
        KEY_EQUAL, KEY_KP_ADD:
            _zoom_at(_zoom * 1.15, _canvas.size * 0.5)
        KEY_MINUS, KEY_KP_SUBTRACT:
            _zoom_at(_zoom / 1.15, _canvas.size * 0.5)
        _:
            handled = false
    if handled:
        get_viewport().set_input_as_handled()


func _on_canvas_input(event: InputEvent) -> void:
    if event is InputEventMouseButton:
        var mb := event as InputEventMouseButton
        match mb.button_index:
            MOUSE_BUTTON_WHEEL_UP:
                if mb.pressed:
                    _zoom_at(_zoom * 1.12, mb.position)
                _canvas.accept_event()
            MOUSE_BUTTON_WHEEL_DOWN:
                if mb.pressed:
                    _zoom_at(_zoom / 1.12, mb.position)
                _canvas.accept_event()
            MOUSE_BUTTON_LEFT:
                if mb.pressed:
                    _press_pos = mb.position
                    _dragged = false
                    _canvas.grab_focus()
                elif not _dragged:
                    _click(mb.position)
                _canvas.accept_event()
            MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE:
                _canvas.accept_event()
    elif event is InputEventMouseMotion:
        var mm := event as InputEventMouseMotion
        var mask := MOUSE_BUTTON_MASK_LEFT | MOUSE_BUTTON_MASK_RIGHT | MOUSE_BUTTON_MASK_MIDDLE
        if (mm.button_mask & mask) == 0:
            return
        if mm.button_mask == MOUSE_BUTTON_MASK_LEFT and not _dragged and mm.position.distance_to(_press_pos) < DRAG_SLOP:
            return
        _dragged = true
        _cam = _clamp_cam(_cam - mm.relative / _zoom)
        _cam_goal = _cam
        _canvas.accept_event()


## Click on a node: focus it, or buy it when it already has focus.
func _click(screen_pos: Vector2) -> void:
    var hit := ""
    var best := INF
    for id in _ids:
        var d := _to_screen(_pos[id]).distance_to(screen_pos)
        if d <= _radius(id) * _zoom + 6.0 and d < best:
            best = d
            hit = id
    if hit == "":
        return
    if hit == _focus:
        _buy_focused()
    else:
        _set_focus(hit)
        Sfx.play("ui_move")


# --- Drawing ---------------------------------------------------------------


func _draw_graph() -> void:
    var c := _canvas
    var z := _zoom
    var view := Rect2(Vector2.ZERO, c.size)
    var cull := view.grow(48.0)
    var lw := maxf(1.5, 3.0 * z)
    var pulse := 0.5 + 0.5 * sin(_time * 4.0)
    var origin := _to_screen(Vector2.ZERO)
    c.draw_rect(view, CANVAS_BG)

    # Spokes from the core to each root.
    for bi in _roots.size():
        var rid: String = _roots[bi]
        if rid == "":
            continue
        var u := Vector2.from_angle(float(_branch_angle[bi]))
        var col := Color(BOUGHT_COLOR, 0.5) if Mastery.is_bought(rid) else Color(_branch_color[bi], 0.25)
        c.draw_line(origin + u * CORE_R * z, _to_screen(_pos[rid]), col, lw * 0.7, true)

    # Edges to parents.
    for id in _ids:
        var parent: String = Mastery.nodes[id]["parent"]
        if parent == "" or not _pos.has(parent):
            continue
        var a := _to_screen(_pos[parent])
        var b := _to_screen(_pos[id])
        if not cull.has_point(a) and not cull.has_point(b):
            continue
        var col := LOCKED_EDGE
        if Mastery.is_bought(id):
            col = BOUGHT_COLOR
        elif Mastery.is_reachable(id):
            col = Color(UiTheme.BONE, 0.75)
        c.draw_line(a, b, col, lw, true)

    # Core.
    c.draw_circle(origin, CORE_R * z, CORE_FILL)
    c.draw_arc(origin, CORE_R * z, 0.0, TAU, 64, Color(UiTheme.BONE, 0.6), lw, true)
    if cull.has_point(origin):
        var big := 32 if z >= 0.7 else 24
        _draw_text(origin + Vector2(0, big * 0.3), str(Mastery.points), big, UiTheme.BONE, [])
        if z >= 0.7:
            _draw_text(origin + Vector2(0, big * 0.3 + 22), "pts", 20, UiTheme.DIM, [])

    # Nodes.
    for id in _ids:
        var p := _to_screen(_pos[id])
        if not cull.has_point(p):
            continue
        var r := _radius(id) * z
        var st := _state(id)
        var fill := _state_color(st)
        c.draw_circle(p, r, fill)
        c.draw_arc(p, r, 0.0, TAU, 32, Color(0, 0, 0, 0.6), maxf(1.0, 2.0 * z), true)
        if str(Mastery.nodes[id]["parent"]) == "":
            var bi: int = _branch_of[id]
            c.draw_circle(p, r * 0.4, _branch_color[bi] if _element_index(_branch_names[bi]) >= 0 else Color(0, 0, 0, 0.35))
        if _is_cap(id):
            c.draw_arc(p, r + 5.0 * z, 0.0, TAU, 40, fill, maxf(1.5, 2.5 * z), true)
        if st == St.READY:
            c.draw_arc(p, r + (4.0 + 3.0 * pulse) * z, 0.0, TAU, 40,
                Color(UiTheme.BONE, 0.3 + 0.55 * pulse), maxf(1.5, 2.0 * z), true)
        if id == _focus:
            c.draw_arc(p, r + 10.0 * z, 0.0, TAU, 48, UiTheme.FOCUS, maxf(2.0, 3.0 * z), true)

    # Text, highest priority first; a label that would overlap one already drawn is skipped.
    var taken: Array = []
    if _focus != "" and _pos.has(_focus):
        var fp := _to_screen(_pos[_focus])
        _draw_text(fp + Vector2(0, _radius(_focus) * z + 32), str(Mastery.nodes[_focus]["name"]), 24, Color.WHITE, taken)
        for id in _links(_focus):
            var np := _to_screen(_pos[id])
            _draw_text(np + Vector2(0, _radius(id) * z + 26), str(Mastery.nodes[id]["name"]), 20, UiTheme.DIM, taken)
    for bi in _roots.size():
        if z < LABEL_MIN_ZOOM and bi != tab:
            continue
        var rad := _ring_r - BRANCH_LABEL_IN - (bi % 2) * BRANCH_LABEL_STAGGER
        var lp := _to_screen(Vector2.from_angle(float(_branch_angle[bi])) * rad)
        var px := 24 if bi == tab else 20
        _draw_text(lp + Vector2(0, px * 0.35), str(_branch_names[bi]), px, _branch_color[bi], taken)


## Pixel-font text centred on `at` (baseline), outlined for contrast. Skipped when it would
## overlap a rectangle in `taken` (pass a shared array to enable that); off-canvas text is skipped.
func _draw_text(at: Vector2, text: String, px: int, col: Color, taken: Array) -> void:
    var w := Art.FONT.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
    var rect := Rect2(at.x - w * 0.5 - 4.0, at.y - px * 0.8, w + 8.0, px * 1.0)
    if not Rect2(Vector2.ZERO, _canvas.size).intersects(rect):
        return
    for t in taken:
        if (t as Rect2).intersects(rect):
            return
    taken.append(rect)
    var pos := Vector2(at.x - w * 0.5, at.y)
    _canvas.draw_string_outline(Art.FONT, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, px, 6, TEXT_OUTLINE)
    _canvas.draw_string(Art.FONT, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, px, col)


func _text(text: String, px: int, color: Color) -> Label:
    var l := UiTheme.label(text, px, color)
    l.add_theme_font_override("font", Art.FONT)
    l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
    return l
