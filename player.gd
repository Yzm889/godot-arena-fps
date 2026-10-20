extends CharacterBody3D

signal hp_changed(current: int, max_hp: int)
signal died
signal shot_fired
signal shot_hit(point: Vector3)
signal enemy_hit
signal ammo_changed(ammo: int, mag_size: int, reserve: int)
signal reload_changed(reloading: bool)
signal spread_changed(movement: float, fire: float)

const Sfx = preload("res://sfx.gd")

# Flip to true to restore the combat trace prints.
const DEBUG_LOG := false

const MAX_HP := 100
const SPEED := 5.0
const MOUSE_SENSITIVITY := 0.002
const PITCH_LIMIT := 1.55
const DAMAGE := 25
const MAG_SIZE := 40
const RESERVE_START := 120
const RESERVE_MAX := 240
const FIRE_RATE := 0.12
const RELOAD_TIME := 1.0
const MUZZLE_FLASH_TIME := 0.05
const MUZZLE_FLASH_ENERGY := 2.5
const WEAPON_RECOIL_OFFSET := Vector3(0.0, 0.0, 0.05)
const WEAPON_RECOIL_PITCH := -0.08
const WEAPON_RECOVER_TIME := 0.1
const FLASH_SCALE_MIN := 0.5
const FLASH_SCALE_MAX := 1.9
const RAY_LENGTH := 50.0
const SHOT_SETTLE_DELAY := 0.1
const SHOT_RECOVER_TIME := 0.1
const FIRE_SPREAD_STEP := 0.3
const FIRE_SPREAD_DECAY := 3.0
const MOVEMENT_SPREAD_LERP := 10.0
const SPREAD_EMIT_EPSILON := 0.005

var hp := MAX_HP
var ammo := MAG_SIZE
var reserve := RESERVE_START
var _fire_timer := 0.0
var _reloading := false
var _pitch := 0.0
var _dead := false
var _muzzle_tween: Tween
var _flash_tween: Tween
var _weapon_tween: Tween
var _weapon_rest_position := Vector3.ZERO
var _weapon_rest_rotation := Vector3.ZERO
var _flash_material: StandardMaterial3D
var _recoil_pitch := 0.0
var _camera_recoil_tween: Tween
var _movement_spread := 0.0
var _fire_spread := 0.0
var _settle_timer := 0.0
var _emitted_movement_spread := -1.0
var _emitted_fire_spread := -1.0

@onready var _camera: Camera3D = $Camera3D
@onready var _ray: RayCast3D = $Camera3D/RayCast3D
@onready var _weapon: Node3D = $Camera3D/Weapon
@onready var _muzzle_flash: OmniLight3D = $Camera3D/Weapon/Muzzle/MuzzleFlash
@onready var _flash_mesh: MeshInstance3D = $Camera3D/Weapon/Muzzle/FlashMesh
@onready var _shoot_sound: AudioStreamPlayer = $ShootSound
@onready var _hurt_sound: AudioStreamPlayer = $HurtSound
@onready var _death_sound: AudioStreamPlayer = $DeathSound

# Tunable in the Inspector (Player node).
@export_range(0.0, 5.0, 0.05) var recoil_per_shot_degrees := 0.3
@export_range(0.0, 10.0, 0.1) var recoil_max_degrees := 1.5
@export_range(0.0, 5.0, 0.1) var max_spread_angle_degrees := 1.0


func _ready() -> void:
	_ray.add_exception(self)
	_shoot_sound.stream = Sfx.shoot()
	_hurt_sound.stream = Sfx.player_hurt()
	_death_sound.stream = Sfx.player_death()
	_weapon_rest_position = _weapon.position
	_weapon_rest_rotation = _weapon.rotation
	_flash_material = _flash_mesh.material_override as StandardMaterial3D
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	hp_changed.emit.call_deferred(hp, MAX_HP)
	ammo_changed.emit.call_deferred(ammo, MAG_SIZE, reserve)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * MOUSE_SENSITIVITY)
		_pitch = clampf(_pitch - event.relative.y * MOUSE_SENSITIVITY, -PITCH_LIMIT, PITCH_LIMIT)
		_apply_camera_pitch()
	elif event.is_action_pressed("reload"):
		reload()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		else:
			shoot()


func _wants_fire() -> bool:
	return Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)


func shoot() -> void:
	if _dead or _reloading or _fire_timer > 0.0:
		return

	if ammo <= 0:
		reload()
		return

	ammo -= 1
	_fire_timer += FIRE_RATE
	ammo_changed.emit(ammo, MAG_SIZE, reserve)
	shot_fired.emit()
	_shoot_sound.play()
	_alert_nearby_enemies()
	_flash_muzzle()
	_kick_weapon()
	_apply_ray_spread()
	_ray.force_raycast_update()

	if _ray.is_colliding():
		var collider := _ray.get_collider()
		if DEBUG_LOG:
			print("Hit: ", collider)
		shot_hit.emit(_ray.get_collision_point())
		if collider and collider.has_method("take_damage"):
			collider.take_damage(DAMAGE)
			enemy_hit.emit()
	else:
		if DEBUG_LOG:
			print("Miss")

	_kick_camera_recoil()
	_settle_timer = SHOT_SETTLE_DELAY
	_fire_spread = minf(_fire_spread + FIRE_SPREAD_STEP, 1.0)
	_publish_spread()

	if ammo <= 0:
		reload()


func _apply_ray_spread() -> void:
	var angle := deg_to_rad(max_spread_angle_degrees) * clampf(_movement_spread + _fire_spread, 0.0, 1.0)
	if angle <= 0.00001:
		_ray.target_position = Vector3(0.0, 0.0, -RAY_LENGTH)
		return

	var theta := angle * sqrt(randf())
	var phi := randf() * TAU
	var lateral := tan(theta)
	_ray.target_position = Vector3(cos(phi) * lateral, sin(phi) * lateral, -1.0).normalized() * RAY_LENGTH


func _alert_nearby_enemies() -> void:
	for enemy in get_tree().get_nodes_in_group("enemies"):
		enemy.hear_gunshot(self)


func reload() -> void:
	if _dead or _reloading or reserve <= 0 or ammo == MAG_SIZE:
		return

	_reloading = true
	reload_changed.emit(true)
	await get_tree().create_timer(RELOAD_TIME, false).timeout
	if not is_inside_tree():
		return

	var take := mini(MAG_SIZE - ammo, reserve)
	ammo += take
	reserve -= take
	_reloading = false
	reload_changed.emit(false)
	ammo_changed.emit(ammo, MAG_SIZE, reserve)


func add_reserve(amount: int) -> void:
	if _dead or amount <= 0:
		return

	var new_reserve := mini(reserve + amount, RESERVE_MAX)
	if new_reserve == reserve:
		return

	reserve = new_reserve
	ammo_changed.emit(ammo, MAG_SIZE, reserve)


func take_damage(amount: int) -> void:
	if _dead:
		return

	hp = maxi(hp - amount, 0)
	hp_changed.emit(hp, MAX_HP)
	if DEBUG_LOG:
		print("Player hp = ", hp)

	if hp <= 0:
		die()
	else:
		_hurt_sound.play()


func die() -> void:
	_dead = true
	_death_sound.play()
	if DEBUG_LOG:
		print("Player died")
	velocity = Vector3.ZERO
	_reset_aim_feedback()
	set_physics_process(false)
	set_process_unhandled_input(false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	died.emit()


func _reset_aim_feedback() -> void:
	if _camera_recoil_tween and _camera_recoil_tween.is_valid():
		_camera_recoil_tween.kill()
	_recoil_pitch = 0.0
	_apply_camera_pitch()
	_movement_spread = 0.0
	_fire_spread = 0.0
	_settle_timer = 0.0
	_emitted_movement_spread = -1.0
	_emitted_fire_spread = -1.0
	_publish_spread()


func _flash_muzzle() -> void:
	if _muzzle_tween and _muzzle_tween.is_valid():
		_muzzle_tween.kill()
	_muzzle_flash.light_energy = MUZZLE_FLASH_ENERGY
	_muzzle_tween = create_tween()
	_muzzle_tween.tween_property(_muzzle_flash, "light_energy", 0.0, MUZZLE_FLASH_TIME)

	_flash_mesh.visible = true
	_flash_mesh.scale = Vector3.ONE * FLASH_SCALE_MIN
	_flash_material.albedo_color.a = 1.0
	if _flash_tween and _flash_tween.is_valid():
		_flash_tween.kill()
	_flash_tween = create_tween().set_parallel(true)
	_flash_tween.tween_property(_flash_mesh, "scale", Vector3.ONE * FLASH_SCALE_MAX, MUZZLE_FLASH_TIME)
	_flash_tween.tween_property(_flash_material, "albedo_color:a", 0.0, MUZZLE_FLASH_TIME)
	_flash_tween.finished.connect(_hide_flash)


func _hide_flash() -> void:
	_flash_mesh.visible = false


func _kick_weapon() -> void:
	if _weapon_tween and _weapon_tween.is_valid():
		_weapon_tween.kill()

	_weapon.position = _weapon_rest_position + WEAPON_RECOIL_OFFSET
	_weapon.rotation = _weapon_rest_rotation + Vector3(WEAPON_RECOIL_PITCH, 0.0, 0.0)
	_weapon_tween = create_tween()
	_weapon_tween.set_parallel(true)
	_weapon_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_weapon_tween.tween_property(_weapon, "position", _weapon_rest_position, WEAPON_RECOVER_TIME)
	_weapon_tween.tween_property(_weapon, "rotation", _weapon_rest_rotation, WEAPON_RECOVER_TIME)


func _kick_camera_recoil() -> void:
	_recoil_pitch = minf(_recoil_pitch + deg_to_rad(recoil_per_shot_degrees), deg_to_rad(recoil_max_degrees))
	_apply_camera_pitch()

	if _camera_recoil_tween and _camera_recoil_tween.is_valid():
		_camera_recoil_tween.kill()
	_camera_recoil_tween = create_tween()
	_camera_recoil_tween.tween_interval(SHOT_SETTLE_DELAY)
	_camera_recoil_tween.tween_method(_set_recoil_pitch, _recoil_pitch, 0.0, SHOT_RECOVER_TIME)


func _set_recoil_pitch(value: float) -> void:
	_recoil_pitch = value
	_apply_camera_pitch()


func _apply_camera_pitch() -> void:
	_camera.rotation.x = clampf(_pitch + _recoil_pitch, -PITCH_LIMIT, PITCH_LIMIT)


func _update_spread(delta: float) -> void:
	var speed := Vector2(velocity.x, velocity.z).length()
	var target := clampf(speed / SPEED, 0.0, 1.0)
	_movement_spread = lerpf(_movement_spread, target, clampf(delta * MOVEMENT_SPREAD_LERP, 0.0, 1.0))

	if _settle_timer > 0.0:
		_settle_timer = maxf(_settle_timer - delta, 0.0)
	elif _fire_spread > 0.0:
		_fire_spread = maxf(_fire_spread - FIRE_SPREAD_DECAY * delta, 0.0)

	_publish_spread()


func _publish_spread() -> void:
	if absf(_movement_spread - _emitted_movement_spread) < SPREAD_EMIT_EPSILON \
			and absf(_fire_spread - _emitted_fire_spread) < SPREAD_EMIT_EPSILON:
		return

	_emitted_movement_spread = _movement_spread
	_emitted_fire_spread = _fire_spread
	spread_changed.emit(_movement_spread, _fire_spread)


func _physics_process(delta: float) -> void:
	_fire_timer = maxf(_fire_timer - delta, -delta)
	if _wants_fire() and _fire_timer <= 0.0:
		shoot()

	if not is_on_floor():
		velocity += get_gravity() * delta

	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")

	var camera_basis := _camera.global_transform.basis
	var forward := Vector3(-camera_basis.z.x, 0.0, -camera_basis.z.z).normalized()
	var right := Vector3(camera_basis.x.x, 0.0, camera_basis.x.z).normalized()
	var direction := (right * input_dir.x - forward * input_dir.y).normalized()

	velocity.x = direction.x * SPEED
	velocity.z = direction.z * SPEED
	move_and_slide()
	_update_spread(delta)
