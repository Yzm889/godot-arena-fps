extends Control

const GAP := 4.0
const LENGTH := 8.0
const THICKNESS := 2.0
const MOVING_SPREAD_SCALE := 0.5
const FIRE_SPREAD_SCALE := 0.3
const MAX_SPREAD_SCALE := 1.8
const SPREAD_LERP_SPEED := 14.0
const HIT_MARKER_TIME := 0.12
const HIT_MARKER_SIZE := 6.0
const HIT_MARKER_COLOR := Color(1, 0.2, 0.2, 1)

var _tween: Tween
var _movement_target := 0.0
var _fire_target := 0.0
var _movement := 0.0
var _fire := 0.0
var _hit_timer := 0.0


func _ready() -> void:
	pivot_offset = size / 2.0


func kick() -> void:
	if _tween and _tween.is_valid():
		_tween.kill()
	scale = Vector2(1.4, 1.4)
	_tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_tween.tween_property(self, "scale", Vector2.ONE, 0.12)


func set_spread(movement: float, fire: float) -> void:
	_movement_target = clampf(movement, 0.0, 1.0)
	_fire_target = clampf(fire, 0.0, 1.0)


func spread_scale() -> float:
	return clampf(
		1.0 + MOVING_SPREAD_SCALE * _movement + FIRE_SPREAD_SCALE * _fire,
		1.0,
		MAX_SPREAD_SCALE
	)


func flash_hit() -> void:
	_hit_timer = HIT_MARKER_TIME
	queue_redraw()


func _process(delta: float) -> void:
	var weight := clampf(delta * SPREAD_LERP_SPEED, 0.0, 1.0)
	var next_movement := lerpf(_movement, _movement_target, weight)
	var next_fire := lerpf(_fire, _fire_target, weight)
	if absf(next_movement - _movement) > 0.001 or absf(next_fire - _fire) > 0.001:
		_movement = next_movement
		_fire = next_fire
		queue_redraw()
	if _hit_timer > 0.0:
		_hit_timer = maxf(_hit_timer - delta, 0.0)
		queue_redraw()


func _draw() -> void:
	var center := size / 2.0
	var spread := spread_scale()
	var gap := GAP * spread
	var length := LENGTH * spread
	_draw_arm(center, Vector2(-1, 0), gap, length)
	_draw_arm(center, Vector2(1, 0), gap, length)
	_draw_arm(center, Vector2(0, -1), gap, length)
	_draw_arm(center, Vector2(0, 1), gap, length)
	if _hit_timer > 0.0:
		_draw_hit_marker(center)


func _draw_arm(center: Vector2, direction: Vector2, gap: float, length: float) -> void:
	var start := center + direction * gap
	var end := center + direction * (gap + length)
	draw_line(start, end, Color(0, 0, 0, 0.5), THICKNESS + 2.0, true)
	draw_line(start, end, Color(1, 1, 1, 0.9), THICKNESS, true)


func _draw_hit_marker(center: Vector2) -> void:
	var corner := Vector2(HIT_MARKER_SIZE, HIT_MARKER_SIZE)
	var a := center - corner
	var b := center + corner
	var c := center + Vector2(-corner.x, corner.y)
	var d := center + Vector2(corner.x, -corner.y)
	draw_line(a, b, Color(0, 0, 0, 0.6), THICKNESS + 2.0, true)
	draw_line(c, d, Color(0, 0, 0, 0.6), THICKNESS + 2.0, true)
	draw_line(a, b, HIT_MARKER_COLOR, THICKNESS, true)
	draw_line(c, d, HIT_MARKER_COLOR, THICKNESS, true)
