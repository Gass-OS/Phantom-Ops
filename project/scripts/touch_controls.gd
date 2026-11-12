extends Control

const JOY_RADIUS: float = 120.0
const FIRE_RADIUS: float = 95.0
const JUMP_RADIUS: float = 65.0

var player = null

var joy_id: int = -1
var joy_origin: Vector2 = Vector2.ZERO
var joy_pos: Vector2 = Vector2.ZERO
var look_id: int = -1
var fire_id: int = -1

func _ready():
    mouse_filter = Control.MOUSE_FILTER_IGNORE

func _fire_center() -> Vector2:
    var s = get_viewport_rect().size
    return Vector2(s.x - 170.0, s.y - 190.0)

func _jump_center() -> Vector2:
    var s = get_viewport_rect().size
    return Vector2(s.x - 360.0, s.y - 110.0)

func _input(event):
    if event is InputEventScreenTouch:
        if event.pressed:
            _on_press(event.index, event.position)
        else:
            _on_release(event.index)
    elif event is InputEventScreenDrag:
        _on_drag(event.index, event.position, event.relative)

func _on_press(id: int, pos: Vector2):
    var ok = is_instance_valid(player)
    if pos.distance_to(_fire_center()) < FIRE_RADIUS + 15.0 and fire_id == -1:
        fire_id = id
        if ok:
            player.shoot_held = true
    elif pos.distance_to(_jump_center()) < JUMP_RADIUS + 15.0:
        if ok:
            player.jump_requested = true
    elif pos.x < get_viewport_rect().size.x * 0.45 and joy_id == -1:
        joy_id = id
        joy_origin = pos
        joy_pos = pos
    elif look_id == -1:
        look_id = id
    queue_redraw()

func _on_release(id: int):
    var ok = is_instance_valid(player)
    if id == fire_id:
        fire_id = -1
        if ok:
            player.shoot_held = false
    if id == joy_id:
        joy_id = -1
        if ok:
            player.mobile_move = Vector2.ZERO
    if id == look_id:
        look_id = -1
    queue_redraw()

func _on_drag(id: int, pos: Vector2, rel: Vector2):
    var ok = is_instance_valid(player)
    if id == joy_id:
        var v = pos - joy_origin
        if v.length() > JOY_RADIUS:
            v = v.normalized() * JOY_RADIUS
        joy_pos = joy_origin + v
        if ok:
            if v.length() < 12.0:
                player.mobile_move = Vector2.ZERO
            else:
                player.mobile_move = v / JOY_RADIUS
    elif id == look_id:
        if ok:
            player.mobile_look += rel
    queue_redraw()

func _draw():
    var size_v = get_viewport_rect().size
    var font = ThemeDB.fallback_font

    # Joystick
    if joy_id != -1:
        draw_circle(joy_origin, JOY_RADIUS, Color(1, 1, 1, 0.12))
        draw_arc(joy_origin, JOY_RADIUS, 0.0, TAU, 48, Color(1, 1, 1, 0.5), 4.0)
        draw_circle(joy_pos, 50.0, Color(1, 1, 1, 0.45))
    else:
        var hint = Vector2(200.0, size_v.y - 190.0)
        draw_arc(hint, JOY_RADIUS, 0.0, TAU, 48, Color(1, 1, 1, 0.25), 3.0)
        draw_circle(hint, 45.0, Color(1, 1, 1, 0.15))

    # Fire button
    var fire_alpha = 0.55
    if fire_id != -1:
        fire_alpha = 0.85
    draw_circle(_fire_center(), FIRE_RADIUS, Color(0.9, 0.15, 0.1, fire_alpha))
    draw_string(font, _fire_center() + Vector2(-FIRE_RADIUS, 12), "FIRE",
        HORIZONTAL_ALIGNMENT_CENTER, FIRE_RADIUS * 2.0, 34, Color.WHITE)

    # Jump button
    draw_circle(_jump_center(), JUMP_RADIUS, Color(0.2, 0.5, 0.9, 0.55))
    draw_string(font, _jump_center() + Vector2(-JUMP_RADIUS, 10), "JUMP",
        HORIZONTAL_ALIGNMENT_CENTER, JUMP_RADIUS * 2.0, 26, Color.WHITE)

    # Crosshair
    var c = size_v / 2.0
    draw_line(c + Vector2(-16, 0), c + Vector2(-5, 0), Color.WHITE, 2.0)
    draw_line(c + Vector2(5, 0), c + Vector2(16, 0), Color.WHITE, 2.0)
    draw_line(c + Vector2(0, -16), c + Vector2(0, -5), Color.WHITE, 2.0)
    draw_line(c + Vector2(0, 5), c + Vector2(0, 16), Color.WHITE, 2.0)
