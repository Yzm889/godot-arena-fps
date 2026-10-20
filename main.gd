extends Node3D

const HIT_EFFECT_SCENE := preload("res://hit_effect.tscn")
const ENEMY_SCENE := preload("res://enemy.tscn")
const WAVE_TABLE := preload("res://data/waves.tres")
const WAVE_DELAY := 3.0
const WAVE_AMMO_SUPPLY := 60
const KILL_SCORE := 100
const WAVE_CLEAR_SCORE := 250
const HIGH_SCORE_PATH := "user://highscore.cfg"
const SPAWN_CROWD_OFFSET := 0.9
const SPAWN_POINTS := [
	Vector3(-9, 0, -9),
	Vector3(9, 0, 8),
	Vector3(-9, 0, 8),
	Vector3(0, 0, 10),
	Vector3(0, 0, -9),
]

# Sourced from data/waves.tres so the campaign table has a single owner. The names
# are kept as they were, leaving the rest of this file untouched.
var TOTAL_WAVES: int = WAVE_TABLE.waves.size()
var WAVE_COMPOSITIONS: Array = WAVE_TABLE.waves

# Tunable in the Inspector (Main node): how far a fresh spawn must be from the
# player, so a charger never appears inside its 9 m commit range.
@export_range(0.0, 20.0, 0.5) var min_spawn_distance := 11.0

@onready var _player = $Player
@onready var _hud = $HUD
@onready var _pause_menu = $PauseMenu

var _enemies_remaining := 0
var _wave := 1
var _finished := false
var _wave_break := false
var _kills := 0
var _shots := 0
var _hits := 0
var _waves_cleared := 0
var _score := 0
var _high_score := 0


func _ready() -> void:
	_high_score = _load_high_score()
	_player.hp_changed.connect(_hud.update_health)
	_player.ammo_changed.connect(_hud.update_ammo)
	_player.weapon_changed.connect(_hud.update_weapon_name)
	_player.shot_fired.connect(_on_shot_fired)
	_player.shot_fired.connect(_hud.kick_crosshair)
	_player.shot_hit.connect(_on_shot_hit)
	_player.enemy_hit.connect(_on_enemy_hit)
	_player.reload_changed.connect(_hud.set_reloading)
	_player.spread_changed.connect(_hud.set_crosshair_spread)
	_player.died.connect(_on_player_died)

	var enemies := get_tree().get_nodes_in_group("enemies")
	for enemy in enemies:
		enemy.died.connect(_on_enemy_died)

	_enemies_remaining = enemies.size()
	_hud.update_wave(_wave, TOTAL_WAVES)
	_hud.update_enemies(_enemies_remaining)


func _on_enemy_died() -> void:
	if _finished:
		return

	_kills += 1
	_enemies_remaining = maxi(_enemies_remaining - 1, 0)
	_hud.update_enemies(_enemies_remaining)

	if _enemies_remaining > 0 or _wave_break:
		return

	_waves_cleared += 1
	if _wave >= TOTAL_WAVES:
		_finish("VICTORY")
		return

	_player.add_reserve(WAVE_AMMO_SUPPLY)
	_spawn_next_wave()


func _spawn_next_wave() -> void:
	if _wave_break or _finished:
		return

	_wave_break = true
	var next_wave := _wave + 1
	for seconds_left in range(int(WAVE_DELAY), 0, -1):
		_hud.show_wave_countdown(next_wave, TOTAL_WAVES, seconds_left)
		await get_tree().create_timer(1.0, false).timeout
		if _finished or not is_inside_tree():
			return

	_hud.hide_wave_banner()
	_wave = next_wave
	_hud.update_wave(_wave, TOTAL_WAVES)
	var composition: Array = WAVE_COMPOSITIONS[_wave - 1]
	var count := 0
	for amount in composition:
		count += amount

	var positions := _spawn_positions(count)
	var spawn_index := 0
	for role in composition.size():
		for _i in composition[role]:
			var enemy := ENEMY_SCENE.instantiate() as Node3D
			enemy.set("role", role)
			enemy.position = to_local(positions[spawn_index])
			add_child(enemy)
			enemy.connect("died", _on_enemy_died)
			spawn_index += 1

	_enemies_remaining = count
	_hud.update_enemies(_enemies_remaining)
	_wave_break = false


# Spawns are ordered farthest-from-player first so a fresh wave never opens inside
# the charger's commit range, and the crowd nudge is dropped when it would pull a
# spawn back inside min_spawn_distance.
func _spawn_positions(count: int) -> Array[Vector3]:
	var origin: Vector3 = _player.global_position
	var eligible: Array[Vector3] = []
	for i in SPAWN_POINTS.size():
		var point: Vector3 = SPAWN_POINTS[i]
		if origin.distance_to(point) >= min_spawn_distance:
			eligible.append(point)

	if eligible.is_empty():
		var best: Vector3 = SPAWN_POINTS[0]
		for i in SPAWN_POINTS.size():
			var candidate: Vector3 = SPAWN_POINTS[i]
			if origin.distance_squared_to(candidate) > origin.distance_squared_to(best):
				best = candidate
		eligible.append(best)

	eligible.sort_custom(func(a: Vector3, b: Vector3) -> bool:
		return origin.distance_squared_to(a) > origin.distance_squared_to(b))

	var positions: Array[Vector3] = []
	for index in count:
		var point: Vector3 = eligible[index % eligible.size()]
		var lap := floori(float(index) / eligible.size())
		if lap > 0:
			var inward := -point
			inward.y = 0.0
			var nudged: Vector3 = point + inward.normalized() * SPAWN_CROWD_OFFSET * lap
			if origin.distance_to(nudged) >= min_spawn_distance:
				point = nudged
		positions.append(point)
	return positions


func _on_shot_fired() -> void:
	_shots += 1


func _on_enemy_hit() -> void:
	_hits += 1
	_hud.show_hit_marker()


func _on_shot_hit(point: Vector3) -> void:
	var effect := HIT_EFFECT_SCENE.instantiate() as Node3D
	add_child(effect)
	effect.global_position = point


func _on_player_died() -> void:
	_finish("GAME OVER")


func _finish(title: String) -> void:
	if _finished:
		return

	_finished = true
	_pause_menu.lock()
	_hud.hide_wave_banner()

	_score = _kills * KILL_SCORE + _waves_cleared * WAVE_CLEAR_SCORE
	var new_best := _score > _high_score
	if new_best:
		_high_score = _score
		_save_high_score(_high_score)

	_hud.show_end(title, {
		"kills": _kills,
		"hits": _hits,
		"shots": _shots,
		"waves": _waves_cleared,
		"total_waves": TOTAL_WAVES,
		"score": _score,
		"best": _high_score,
		"new_best": new_best,
	})
	get_tree().paused = true


func _load_high_score() -> int:
	var config := ConfigFile.new()
	if config.load(HIGH_SCORE_PATH) != OK:
		return 0
	return int(config.get_value("score", "best", 0))


func _save_high_score(score: int) -> void:
	var config := ConfigFile.new()
	config.set_value("score", "best", score)
	config.save(HIGH_SCORE_PATH)
