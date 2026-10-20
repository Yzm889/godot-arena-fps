extends CharacterBody3D

signal hp_changed(current: int, max_hp: int)
signal died
signal shot_fired
signal shot_hit(point: Vector3)
signal enemy_hit
signal ammo_changed(ammo: int, mag_size: int, reserve: int)
signal reload_changed(reloading: bool)
signal spread_changed(movement: float, fire: float)
signal weapon_changed(display_name: String)

const Sfx = preload("res://sfx.gd")

# Flip to true to restore the combat trace prints.
const DEBUG_LOG := false

const MAX_HP := 100
const SPEED := 5.0
const MOUSE_SENSITIVITY := 0.002
const PITCH_LIMIT := 1.55
const RESERVE_START := 120
const RESERVE_MAX := 240
const WEAPONS := [
	preload("res://data/weapon_rifle.tres"),
	preload("res://data/weapon_shotgun.tres"),
]
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
var ammo: int = WEAPONS[0].mag_size
var reserve := RESERVE_START
var _weapon_index := 0
var _mags: Array[int] = [WEAPONS[0].mag_size, WEAPONS[1].mag_size]
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
@onready var _barrel: MeshInstance3D = $Camera3D/Weapon/Barrel
@onready var _sight: MeshInstance3D = $Camera3D/Weapon/Sight
@onready var _muzzle_flash: OmniLight3D = $Camera3D/Weapon/Muzzle/MuzzleFlash
@onready var _flash_mesh: MeshInstance3D = $Camera3D/Weapon/Muzzle/FlashMesh
@onready var _shoot_sound: AudioStreamPlayer = $ShootSound
@onready var _hurt_sound: AudioStreamPlayer = $HurtSound
@onready var _death_sound: AudioStreamPlayer = $DeathSound

# Tunable in the Inspector (Player node).
@export_range(0.0, 5.0, 0.05) var recoil_per_shot_degrees := 0.3
@export_range(0.0, 10.0, 0.1) var recoil_max_degrees := 1.5
@export_range(0.0, 5.0, 0.1) var max_spread_angle_degrees := 1.0
@export_range(3.0, 8.0, 0.1) var jump_velocity := 7.0
@export_range(4.0, 40.0, 0.5) var air_acceleration := 18.0
@export_range(1.0, 3.0, 0.05) var air_gravity_scale := 2.0


func _ready() -> void:
	_ray.add_exception(self)
	_shoot_sound.stream = Sfx.shoot()
	_hurt_sound.stream = Sfx.player_hurt()
	_death_sound.stream = Sfx.player_death()
	_weapon_rest_position = _weapon.position
	_weapon_rest_rotation = _weapon.rotation
	_flash_material = _flash_mesh.material_override as StandardMaterial3D
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_apply_weapon_look()
	hp_changed.emit.call_deferred(hp, MAX_HP)
	ammo_changed.emit.call_deferred(ammo, weapon().mag_size, reserve)
	weapon_changed.emit.call_deferred(weapon().display_name)


func weapon() -> Resource:
	return WEAPONS[_weapon_index]


func _apply_weapon_look() -> void:
	var data := weapon()
	_barrel.scale = data.barrel_scale
	_sight.visible = not data.hide_sight
	_shoot_sound.pitch_scale = data.sound_pitch


func select_weapon(index: int) -> void:
	if _dead or _reloading or index < 0 or index >= WEAPONS.size() or index == _weapon_index:
		return

	_mags[_weapon_index] = ammo
	_weapon_index = index
	ammo = _mags[index]
	_fire_timer = 0.0
	_apply_weapon_look()
	ammo_changed.emit(ammo, weapon().mag_size, reserve)
	weapon_changed.emit(weapon().display_name)


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

	var data := weapon()
	ammo -= 1
	_fire_timer += data.fire_interval
	ammo_changed.emit(ammo, data.mag_size, reserve)
	shot_fired.emit()
	_shoot_sound.play()
	_alert_nearby_enemies()
	_flash_muzzle()
	_kick_weapon()

	var wounded := false
	for _pellet in data.pellet_count:
		_ray.target_position = _spread_ray_target(data.base_spread_degrees)
		_ray.force_raycast_update()
		if not _ray.is_colliding():
			if DEBUG_LOG:
				print("Miss")
			continue

		var collider := _ray.get_collider()
		if DEBUG_LOG:
			print("Hit: ", collider)
		shot_hit.emit(_ray.get_collision_point())
		if collider and collider.has_method("take_damage"):
			collider.take_damage(data.damage)
			wounded = true

	if wounded:
		enemy_hit.emit()

	_kick_camera_recoil()
	_settle_timer = SHOT_SETTLE_DELAY
	_fire_spread = minf(_fire_spread + FIRE_SPREAD_STEP, 1.0)
	_publish_spread()

	if ammo <= 0:
		reload()


func _spread_ray_target(base_degrees: float) -> Vector3:
	var angle := deg_to_rad(base_degrees) \
			+ deg_to_rad(max_spread_angle_degrees) * clampf(_movement_spread + _fire_spread, 0.0, 1.0)
	if angle <= 0.00001:
		return Vector3(0.0, 0.0, -RAY_LENGTH)

	var theta := angle * sqrt(randf())
	var phi := randf() * TAU
	var lateral := tan(theta)
	return Vector3(cos(phi) * lateral, sin(phi) * lateral, -1.0).normalized() * RAY_LENGTH


func _alert_nearby_enemies() -> void:
	for enemy in get_tree().get_nodes_in_group("enemies"):
		enemy.hear_gunshot(self)


func reload() -> void:
	if _dead or _reloading or reserve <= 0 or ammo == weapon().mag_size:
		return

	_reloading = true
	reload_changed.emit(true)
	await get_tree().create_timer(weapon().reload_time, false).timeout
	if not is_inside_tree():
		return

	var take := mini(weapon().mag_size - ammo, reserve)
	ammo += take
	reserve -= take
	_reloading = false
	reload_changed.emit(false)
	ammo_changed.emit(ammo, weapon().mag_size, reserve)


func add_reserve(amount: int) -> void:
	if _dead or amount <= 0:
		return

	var new_reserve := mini(reserve + amount, RESERVE_MAX)
	if new_reserve == reserve:
		return

	reserve = new_reserve
	ammo_changed.emit(ammo, weapon().mag_size, reserve)


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
	var step := deg_to_rad(recoil_per_shot_degrees) * float(weapon().recoil_multiplier)
	_recoil_pitch = minf(_recoil_pitch + step, deg_to_rad(recoil_max_degrees))
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
	var movement := minf(_movement_spread + weapon().crosshair_spread, 1.0)
	if absf(movement - _emitted_movement_spread) < SPREAD_EMIT_EPSILON \
			and absf(_fire_spread - _emitted_fire_spread) < SPREAD_EMIT_EPSILON:
		return

	_emitted_movement_spread = movement
	_emitted_fire_spread = _fire_spread
	spread_changed.emit(movement, _fire_spread)


func _try_jump() -> void:
	if _dead or not is_on_floor():
		return

	velocity.y = jump_velocity


func _physics_process(delta: float) -> void:
	_fire_timer = maxf(_fire_timer - delta, -delta)
	if _wants_fire() and _fire_timer <= 0.0:
		shoot()

	if Input.is_action_just_pressed("jump"):
		_try_jump()

	if Input.is_action_just_pressed("weapon_1"):
		select_weapon(0)
	elif Input.is_action_just_pressed("weapon_2"):
		select_weapon(1)

	if not is_on_floor():
		velocity += get_gravity() * air_gravity_scale * delta

	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")

	var camera_basis := _camera.global_transform.basis
	var forward := Vector3(-camera_basis.z.x, 0.0, -camera_basis.z.z).normalized()
	var right := Vector3(camera_basis.x.x, 0.0, camera_basis.x.z).normalized()
	var direction := (right * input_dir.x - forward * input_dir.y).normalized()

	if is_on_floor():
		velocity.x = direction.x * SPEED
		velocity.z = direction.z * SPEED
	else:
		velocity.x = move_toward(velocity.x, direction.x * SPEED, air_acceleration * delta)
		velocity.z = move_toward(velocity.z, direction.z * SPEED, air_acceleration * delta)
	move_and_slide()
	_update_spread(delta)
