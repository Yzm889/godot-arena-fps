extends CharacterBody3D

signal died

const Sfx = preload("res://sfx.gd")
const PROJECTILE_SCENE := preload("res://enemy_projectile.tscn")
const BASE_COLOR := Color(0.75, 0.15, 0.2)
const GUNSHOT_HEAR_RADIUS := 15.0
const DEAGGRO_DISTANCE := 20.0
const DEAGGRO_TIME := 5.0
const RETARGET_INTERVAL := 0.25
const WINDUP_TIME := 0.25
const CHARGE_MIN_DISTANCE := 3.0
const CHARGE_MAX_DISTANCE := 9.0
const CHARGE_WINDUP_TIME := 0.5
const CHARGE_WINDUP_LIGHT := 6.0
const CHARGE_DURATION := 0.55
const CHARGE_SPEED := 11.0
const CHARGE_COOLDOWN := 3.2
const CHARGE_HIT_RANGE := 1.4
const RANGED_MIN_DISTANCE := 5.0
const RANGED_MAX_DISTANCE := 12.0
const RANGED_WINDUP_TIME := 0.45
const RANGED_WINDUP_LIGHT := 5.0
const HALO_ALPHA := 0.45
const HALO_SCALE_START := 1.45
const HALO_SCALE_END := 1.0

# Flip to true to restore the combat trace prints.
const DEBUG_LOG := false

enum State { IDLE, CHASE }
enum Role { MELEE, CHARGER, RANGED }

const ROLE_DATA := {
	Role.MELEE: preload("res://data/enemy_melee.tres"),
	Role.CHARGER: preload("res://data/enemy_charger.tres"),
	Role.RANGED: preload("res://data/enemy_ranged.tres"),
}

@export var role: Role = Role.MELEE
@export var speed := 4.3
@export var attack_range := 1.5
@export var attack_damage := 10
@export var attack_cooldown := 1.0
@export_range(0.0, 3.0, 0.05) var spawn_grace := 0.7

var state: State = State.IDLE
var player: Node3D = null
var hp := 100
var _attack_timer := 0.0
var _escape_timer := 0.0
var _retarget_timer := 0.0
var _windup_timer := 0.0
var _winding_up := false
var _charge_cooldown_timer := 0.0
var _charge_windup_timer := 0.0
var _charge_winding := false
var _charge_time := 0.0
var _charge_direction := Vector3.ZERO
var _charge_hit := false
var _aiming := false
var _aim_timer := 0.0
var _avoidance_move := false
var _dying := false
var _base_color := BASE_COLOR
var _hit_tween: Tween
var _spawn_grace := 0.0
var _pending_target: Node3D = null

@onready var detection_area: Area3D = $DetectionArea
@onready var _mesh: MeshInstance3D = $MeshInstance3D
@onready var _hit_sound: AudioStreamPlayer3D = $HitSound
@onready var _shot_sound: AudioStreamPlayer3D = $ShotSound
@onready var _agent: NavigationAgent3D = $NavigationAgent3D
@onready var _telegraph_light: OmniLight3D = $TelegraphLight
@onready var _spawn_halo: MeshInstance3D = $SpawnHalo

var _material: StandardMaterial3D
var _halo_material: StandardMaterial3D


func _ready() -> void:
	detection_area.body_entered.connect(_on_body_entered)
	_hit_sound.stream = Sfx.enemy_hit()
	_shot_sound.stream = Sfx.enemy_shoot()
	_material = _mesh.material_override.duplicate() as StandardMaterial3D
	_mesh.material_override = _material
	_halo_material = _spawn_halo.material_override.duplicate() as StandardMaterial3D
	_spawn_halo.material_override = _halo_material
	_agent.velocity_computed.connect(_on_velocity_computed)
	_apply_role()
	_spawn_grace = spawn_grace
	_spawn_halo.visible = _spawn_grace > 0.0
	_agent.max_speed = speed
	_agent.target_position = global_position


func _apply_role() -> void:
	var data = ROLE_DATA[role]
	speed = data.speed
	attack_damage = data.attack_damage
	attack_cooldown = data.attack_cooldown
	hp = data.max_hp
	_base_color = data.body_color
	_telegraph_light.light_color = data.telegraph_color
	var halo_tint: Color = data.telegraph_color
	halo_tint.a = HALO_ALPHA
	_halo_material.albedo_color = halo_tint
	_material.albedo_color = _base_color


func _on_body_entered(body: Node3D) -> void:
	if not body.is_in_group("player"):
		return

	if _spawn_grace > 0.0:
		_pending_target = body
		return

	_aggro(body)


func hear_gunshot(source: Node3D) -> void:
	if _dying or not is_instance_valid(source):
		return

	if global_position.distance_to(source.global_position) > GUNSHOT_HEAR_RADIUS:
		return

	if _spawn_grace > 0.0:
		_pending_target = source
		return

	_aggro(source)


func _aggro(source: Node3D) -> void:
	_pending_target = null
	player = source
	state = State.CHASE
	_escape_timer = 0.0
	_retarget_timer = 0.0
	_agent.target_position = source.global_position


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity += get_gravity() * delta

	if _spawn_grace > 0.0:
		_spawn_grace -= delta
		velocity.x = 0.0
		velocity.z = 0.0
		move_and_slide()
		_animate_spawn_halo()
		if _spawn_grace <= 0.0:
			_release_spawn_grace()
		return

	_attack_timer = maxf(_attack_timer - delta, 0.0)

	match state:
		State.IDLE:
			_stop_moving()
		State.CHASE:
			if not is_instance_valid(player):
				_deaggro()
				return

			var direction := player.global_position - global_position
			direction.y = 0.0
			var distance := direction.length()

			_escape_timer += delta

			if distance > DEAGGRO_DISTANCE and _escape_timer >= DEAGGRO_TIME:
				_deaggro()
			else:
				match role:
					Role.MELEE:
						_update_melee_combat(delta, distance)
					Role.CHARGER:
						_update_charger_combat(delta, distance)
					Role.RANGED:
						_update_ranged_combat(delta, distance)


func _animate_spawn_halo() -> void:
	var progress := clampf(1.0 - _spawn_grace / spawn_grace, 0.0, 1.0)
	var radius := lerpf(HALO_SCALE_START, HALO_SCALE_END, progress)
	_spawn_halo.scale = Vector3(radius, 1.0, radius)
	_halo_material.albedo_color.a = lerpf(HALO_ALPHA, 0.15, progress)


func _release_spawn_grace() -> void:
	_spawn_halo.visible = false
	var target := _pending_target
	_pending_target = null
	if is_instance_valid(target):
		_aggro(target)


func _update_melee_combat(delta: float, distance: float) -> void:
	if distance <= attack_range and _has_line_of_sight():
		_stop_moving()
		_update_attack(delta)
	else:
		_cancel_windup()
		_chase(delta)


func _update_charger_combat(delta: float, distance: float) -> void:
	if _charge_time > 0.0:
		_update_charge(delta)
		return

	_charge_cooldown_timer = maxf(_charge_cooldown_timer - delta, 0.0)

	if _charge_winding:
		if distance <= attack_range and _has_line_of_sight():
			_cancel_charge()
		else:
			_stop_moving()
			_charge_windup_timer -= delta
			if _charge_windup_timer <= 0.0:
				_start_charge()
			return

	if distance <= attack_range and _has_line_of_sight():
		_stop_moving()
		_update_attack(delta)
		return

	_cancel_windup()

	if _charge_cooldown_timer <= 0.0 and distance >= CHARGE_MIN_DISTANCE and distance <= CHARGE_MAX_DISTANCE and _has_line_of_sight():
		_begin_charge_windup()
		return

	_chase(delta)


func _begin_charge_windup() -> void:
	_charge_winding = true
	_charge_windup_timer = CHARGE_WINDUP_TIME
	_telegraph_light.light_energy = CHARGE_WINDUP_LIGHT
	_mesh.scale = Vector3.ONE * 1.25
	_stop_moving()


func _start_charge() -> void:
	_charge_winding = false
	_charge_windup_timer = 0.0
	_charge_time = CHARGE_DURATION
	_charge_hit = false
	_telegraph_light.light_energy = 2.5
	_mesh.scale = Vector3.ONE * 1.1

	var direction := player.global_position - global_position
	direction.y = 0.0
	_charge_direction = direction.normalized()
	_avoidance_move = false


func _update_charge(delta: float) -> void:
	_charge_time -= delta
	velocity.x = _charge_direction.x * CHARGE_SPEED
	velocity.z = _charge_direction.z * CHARGE_SPEED
	move_and_slide()

	if not _charge_hit and is_instance_valid(player):
		var offset := player.global_position - global_position
		offset.y = 0.0
		if offset.length() <= CHARGE_HIT_RANGE:
			_charge_hit = true
			player.call("take_damage", attack_damage)
			_attack_timer = maxf(_attack_timer, 0.6)

	if _charge_time <= 0.0:
		_end_charge()


func _end_charge() -> void:
	_charge_time = 0.0
	_charge_cooldown_timer = CHARGE_COOLDOWN
	_telegraph_light.light_energy = 0.0
	_mesh.scale = Vector3.ONE
	_stop_moving()


func _cancel_charge() -> void:
	_charge_winding = false
	_charge_windup_timer = 0.0
	_charge_time = 0.0
	_telegraph_light.light_energy = 0.0
	_mesh.scale = Vector3.ONE


func _update_ranged_combat(delta: float, distance: float) -> void:
	if distance < RANGED_MIN_DISTANCE:
		_cancel_aim()
		_cancel_windup()
		_retreat()
		return

	if distance > RANGED_MAX_DISTANCE or not _has_line_of_sight():
		_cancel_aim()
		_cancel_windup()
		_chase(delta)
		return

	_stop_moving()

	if _attack_timer > 0.0:
		_cancel_aim()
		return

	if not _aiming:
		_aiming = true
		_aim_timer = RANGED_WINDUP_TIME
		_telegraph_light.light_energy = RANGED_WINDUP_LIGHT
		_mesh.scale = Vector3.ONE * 1.18
		return

	_aim_timer -= delta
	if _aim_timer > 0.0:
		return

	_aiming = false
	_aim_timer = 0.0
	_telegraph_light.light_energy = 3.0
	_mesh.scale = Vector3.ONE
	_fire_projectile()
	_attack_timer = attack_cooldown

	var tween := create_tween()
	tween.tween_property(_telegraph_light, "light_energy", 0.0, 0.08)


func _retreat() -> void:
	var away := global_position - player.global_position
	away.y = 0.0
	if away.length() < 0.1:
		away = -global_transform.basis.z

	_avoidance_move = true
	_agent.set_velocity(away.normalized() * speed)


func _cancel_aim() -> void:
	if not _aiming:
		return

	_aiming = false
	_aim_timer = 0.0
	_telegraph_light.light_energy = 0.0
	_mesh.scale = Vector3.ONE


func _fire_projectile() -> void:
	if not is_instance_valid(player) or not is_inside_tree():
		return

	var origin := global_position + Vector3(0, 1.3, 0)
	var target := player.global_position + Vector3(0, 1.0, 0)
	var projectile := PROJECTILE_SCENE.instantiate() as Node3D
	var parent := get_parent() as Node3D
	projectile.position = parent.to_local(origin)
	parent.add_child(projectile)
	projectile.call("setup", (target - origin).normalized(), attack_damage)
	_shot_sound.play()


func _update_attack(delta: float) -> void:
	if _attack_timer > 0.0:
		_cancel_windup()
		return

	if not _winding_up:
		_winding_up = true
		_windup_timer = WINDUP_TIME
		_telegraph_light.light_energy = 4.0
		_mesh.scale = Vector3.ONE * 1.15
		return

	_windup_timer -= delta
	if _windup_timer > 0.0:
		return

	_winding_up = false
	_windup_timer = 0.0
	_telegraph_light.light_energy = 0.0
	_mesh.scale = Vector3.ONE
	player.call("take_damage", attack_damage)
	_attack_timer = attack_cooldown


func _cancel_windup() -> void:
	if not _winding_up:
		return

	_winding_up = false
	_windup_timer = 0.0
	_telegraph_light.light_energy = 0.0
	_mesh.scale = Vector3.ONE


func _cancel_attacks() -> void:
	_cancel_windup()
	_cancel_charge()
	_cancel_aim()


func _chase(delta: float) -> void:
	_retarget_timer -= delta
	if _retarget_timer <= 0.0:
		_retarget_timer = RETARGET_INTERVAL
		_agent.target_position = player.global_position

	var direction := Vector3.ZERO
	if not _agent.is_navigation_finished():
		direction = _agent.get_next_path_position() - global_position
		direction.y = 0.0

	if direction.length() < 0.1:
		direction = player.global_position - global_position
		direction.y = 0.0

	_avoidance_move = true
	_agent.set_velocity(direction.normalized() * speed)


func _stop_moving() -> void:
	_avoidance_move = false
	velocity.x = 0.0
	velocity.z = 0.0
	_agent.set_velocity(Vector3.ZERO)
	move_and_slide()


func _deaggro() -> void:
	_cancel_attacks()
	player = null
	state = State.IDLE
	_escape_timer = 0.0
	_retarget_timer = 0.0
	_stop_moving()


func _has_line_of_sight() -> bool:
	if not is_instance_valid(player):
		return false

	var from := global_position + Vector3(0, 1.2, 0)
	var to := player.global_position + Vector3(0, 1.0, 0)
	var query := PhysicsRayQueryParameters3D.create(from, to, 1)
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()


func _on_velocity_computed(safe_velocity: Vector3) -> void:
	if not _avoidance_move:
		return

	_avoidance_move = false
	if _dying or not is_inside_tree():
		return

	velocity.x = safe_velocity.x
	velocity.z = safe_velocity.z
	move_and_slide()


func take_damage(amount: int) -> void:
	if _dying:
		return

	var attacker := get_tree().get_first_node_in_group("player") as Node3D
	if attacker:
		_aggro(attacker)

	hp -= amount
	if DEBUG_LOG:
		print("Enemy hp = ", hp)
	_flash_hit()
	_hit_sound.play()

	if hp <= 0:
		_dying = true
		_cancel_attacks()
		collision_layer = 0
		set_physics_process(false)
		detection_area.set_deferred("monitoring", false)
		died.emit()
		get_tree().create_timer(0.12).timeout.connect(queue_free)


func _flash_hit() -> void:
	if _hit_tween and _hit_tween.is_valid():
		_hit_tween.kill()
	_material.albedo_color = Color(1, 1, 1)
	_hit_tween = create_tween()
	_hit_tween.tween_property(_material, "albedo_color", _base_color, 0.15)
