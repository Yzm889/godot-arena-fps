extends RefCounted

const SPEED := 5.0
const FIRE_RATE_SECONDS := 0.12
const RELOAD_TICKS := 70
const PITCH_LIMIT := 1.55
const RAY_BACK := Vector3(0.0, 0.0, -50.0)
const RECORDER := preload("res://tests/recorder.gd")


class ShotRecorder extends RefCounted:
	var ticks: Array[int] = []
	var count := 0

	func on_shot() -> void:
		count += 1
		ticks.append(Engine.get_physics_frames())


class SpreadRecorder extends RefCounted:
	var emissions := 0
	var last_movement := -1.0
	var last_fire := -1.0

	func on_spread(movement: float, fire: float) -> void:
		emissions += 1
		last_movement = movement
		last_fire = fire


func run(ctx) -> void:
	await _test_movement(ctx)
	await _test_jump(ctx)
	await _test_air_control(ctx)
	await _test_weapon_data(ctx)
	await _test_weapon_switch(ctx)
	await _test_shotgun(ctx)
	await _test_single_shot(ctx)
	await _test_miss_branch(ctx)
	await _test_autofire_cadence(ctx)
	await _test_reload_gating(ctx)
	await _test_ammo_economy(ctx)
	await _test_damage_and_death(ctx)
	await _test_camera_recoil(ctx)
	await _test_viewmodel_and_crosshair_kick(ctx)
	await _test_spread(ctx)
	await _test_crosshair_spread_mapping(ctx)
	await _test_pitch_clamp(ctx)
	ctx.mark_file_done("test_player")


func _begin(ctx) -> Dictionary:
	var main: Node = await ctx.load_main()
	await ctx.remove_enemies()
	var player: Node = ctx.install_fire_seam()
	return {
		"main": main,
		"player": player,
		"camera": main.get_node("Player/Camera3D"),
		"ray": main.get_node("Player/Camera3D/RayCast3D"),
		"weapon": main.get_node("Player/Camera3D/Weapon"),
		"crosshair": main.get_node("HUD/Crosshair"),
	}


func _test_movement(ctx) -> void:
	ctx.begin_suite("player/movement")
	var refs := await _begin(ctx)
	var player: Node = refs["player"]

	await ctx.step(5)
	ctx.check_near(player.global_position.x, 0.0, 0.01, "player starts centred on x")
	ctx.check(player.is_on_floor(), "player is grounded on the arena floor")

	Input.action_press("move_forward")
	await ctx.step(20)
	ctx.check_near(Vector2(player.velocity.x, player.velocity.z).length(), SPEED, 0.01,
		"forward run reaches SPEED")
	ctx.check(player.global_position.z < -0.5, "forward input moves the player along -Z")
	Input.action_release("move_forward")

	Input.action_press("move_right")
	await ctx.step(20)
	ctx.check(player.global_position.x > 0.5, "strafe right moves along +X")
	Input.action_release("move_right")

	await ctx.step(20)
	ctx.check_near(Vector2(player.velocity.x, player.velocity.z).length(), 0.0, 0.01,
		"velocity collapses to zero with no input")

	var yaw_before: float = player.rotation.y
	Input.action_press("move_forward")
	await ctx.step(10)
	Input.action_release("move_forward")
	ctx.check_near(player.rotation.y, yaw_before, 0.0001,
		"movement never rotates the body yaw")


func _test_jump(ctx) -> void:
	ctx.begin_suite("player/jump")
	var refs := await _begin(ctx)
	var player: Node = refs["player"]

	await ctx.step(5)
	ctx.check(player.is_on_floor(), "jump: grounded before takeoff")
	var ground_y: float = player.global_position.y
	ctx.check_near(ground_y, 0.0, 0.05, "jump: feet rest on the arena floor at y=0")

	Input.action_press("jump")
	var lifted: bool = await ctx.step_until(func() -> bool: return not player.is_on_floor(), 5)
	Input.action_release("jump")
	ctx.check(lifted, "jump: one press leaves the floor within 5 ticks")
	ctx.check(player.velocity.y > 0.0, "jump: upward velocity is applied")

	var peak: float = player.global_position.y
	var airborne_ticks := 0
	var landed: bool = false
	var descent_probed := false
	for _tick in 120:
		await ctx.step(1)
		peak = maxf(peak, player.global_position.y)
		if player.is_on_floor():
			landed = true
			break
		airborne_ticks += 1

		if not descent_probed and player.velocity.y < -1.0:
			descent_probed = true
			var vy_descending: float = player.velocity.y
			player.call("_try_jump")
			ctx.check_near(float(player.velocity.y), vy_descending, 0.0001,
				"jump: calling _try_jump during descent adds nothing")

			Input.action_press("jump")
			await ctx.step(1)
			Input.action_release("jump")
			peak = maxf(peak, player.global_position.y)
			ctx.check(player.velocity.y < 0.0, "jump: a mid-air press never restarts the ascent")
			airborne_ticks += 1

	ctx.check(landed, "jump: the player lands again within 120 ticks")

	var gravity: float = absf((player.call("get_gravity") as Vector3).y)
	var jump_v: float = float(player.get("jump_velocity"))
	var airborne_gravity: float = gravity * float(player.get("air_gravity_scale"))
	var expected_peak: float = ground_y + jump_v * jump_v / (2.0 * airborne_gravity)
	ctx.check_near(peak, expected_peak, 0.20, "jump: apex follows jump_velocity and airborne gravity")
	ctx.check_in_range(peak, 1.05, 1.55, "jump: apex clears the 1.0 m platform but not the 1.6 m crates")

	var expected_ticks: float = 2.0 * jump_v / airborne_gravity * 60.0
	ctx.check_in_range(float(airborne_ticks), expected_ticks - 10.0, expected_ticks + 10.0,
		"jump: airtime matches jump_velocity and airborne gravity")
	ctx.check_in_range(float(airborne_ticks), 27.0, 48.0,
		"jump: hang time stays inside 0.45-0.80 s")

	await ctx.step(4)
	ctx.check(player.is_on_floor(), "jump: settled back on the floor")
	Input.action_press("jump")
	var rejumped: bool = await ctx.step_until(func() -> bool: return not player.is_on_floor(), 5)
	Input.action_release("jump")
	ctx.check(rejumped, "jump: the floor accepts another jump after landing")
	await ctx.step_until(func() -> bool: return player.is_on_floor(), 120)

	player.call("take_damage", 999)
	Input.action_press("jump")
	await ctx.step(4)
	Input.action_release("jump")
	ctx.check_near(float(player.velocity.y), 0.0, 0.0001, "jump: a dead player cannot jump")
	ctx.check(player.is_on_floor(), "jump: a dead player stays on the floor")


func _test_air_control(ctx) -> void:
	ctx.begin_suite("player/air_control")
	var refs := await _begin(ctx)
	var player: Node = refs["player"]

	await ctx.step(5)
	Input.action_press("move_forward")
	await ctx.step(6)
	ctx.check_near(float(player.velocity.z), -SPEED, 0.05, "air control: ground steering still snaps to -SPEED")

	Input.action_press("jump")
	var lifted: bool = await ctx.step_until(func() -> bool: return not player.is_on_floor(), 5)
	Input.action_release("jump")
	ctx.check(lifted, "air control: airborne after the jump")

	var per_tick: float = float(player.get("air_acceleration")) / 60.0
	var z_before: float = player.velocity.z
	ctx.check_in_range(z_before, -SPEED, -SPEED + 3.0 * per_tick, "air control: horizontal speed survives takeoff")
	ctx.check(2.0 * SPEED / (per_tick * 60.0) > 0.3,
		"air control: a full reversal takes longer than 0.3 s, so air steering is not instant")

	Input.action_release("move_forward")
	Input.action_press("move_back")
	await ctx.step(3)
	var steer_gain: float = float(player.velocity.z) - z_before
	ctx.check_in_range(steer_gain, 0.5 * per_tick, 3.5 * per_tick,
		"air control: mid-air steering ramps by air_acceleration each tick")
	ctx.check(float(player.velocity.z) < 0.0,
		"air control: still steering the old way, where the ground would have snapped to +SPEED")
	Input.action_release("move_back")

	var landed: bool = await ctx.step_until(func() -> bool: return player.is_on_floor(), 120)
	ctx.check(landed, "air control: the player lands again")
	Input.action_press("move_forward")
	await ctx.step(2)
	ctx.check_near(float(player.velocity.z), -SPEED, 0.05, "air control: instant steering returns on the floor")
	Input.action_release("move_forward")


func _test_weapon_data(ctx) -> void:
	ctx.begin_suite("player/weapon_data")
	var refs := await _begin(ctx)
	var player: Node = refs["player"]
	var rifle: Resource = load("res://data/weapon_rifle.tres")
	var shotgun: Resource = load("res://data/weapon_shotgun.tres")

	ctx.check(rifle != null and shotgun != null, "weapon data: both resources load")
	ctx.check(rifle != shotgun, "weapon data: rifle and shotgun are separate resources")
	ctx.check_eq(String(rifle.resource_path), "res://data/weapon_rifle.tres",
		"weapon data: the player opens on the authored rifle resource")
	ctx.check_eq(int(player.get("_weapon_index")), 0, "weapon data: the player starts on index 0")
	ctx.check(player.call("weapon") == rifle, "weapon data: weapon() returns the equipped resource")

	# These are the pre-refactor numbers. If they moved, the tuned ammo economy moved with them.
	ctx.check_eq(int(rifle.damage), 25, "weapon data: rifle damage is still 25")
	ctx.check_eq(int(rifle.pellet_count), 1, "weapon data: rifle still casts one ray")
	ctx.check_near(float(rifle.fire_interval), 0.12, 0.0001, "weapon data: rifle cadence is still 0.12 s")
	ctx.check_near(float(rifle.reload_time), 1.0, 0.0001, "weapon data: rifle reload is still 1.0 s")
	ctx.check_eq(int(rifle.mag_size), 40, "weapon data: rifle magazine is still 40")
	ctx.check_near(float(rifle.base_spread_degrees), 0.0, 0.0001, "weapon data: rifle adds no base cone")
	ctx.check_near(float(rifle.recoil_multiplier), 1.0, 0.0001, "weapon data: rifle recoil is unchanged")
	ctx.check_eq(int(shotgun.pellet_count), 8, "weapon data: shotgun casts eight pellets")
	ctx.check_eq(int(shotgun.mag_size), 8, "weapon data: shotgun magazine is 8")


func _test_weapon_switch(ctx) -> void:
	ctx.begin_suite("player/weapon_switch")
	var refs := await _begin(ctx)
	var player: Node = refs["player"]
	var shotgun: Resource = load("res://data/weapon_shotgun.tres")
	var names := RECORDER.new()
	player.weapon_changed.connect(func(display_name: String) -> void: names.remember(display_name))

	# Let the deferred startup emissions land before asserting on their ordering.
	await ctx.step(2)
	for _i in 3:
		player.set("_fire_timer", 0.0)
		player.call("shoot")
	ctx.check_eq(int(player.ammo), 37, "switch: rifle down to 37 first")
	var reserve_before: int = player.reserve

	var events_before: int = names.value
	player.call("select_weapon", 1)
	ctx.check_eq(int(player.ammo), 8, "switch: the shotgun carries its own full magazine")
	ctx.check_eq(int(player.reserve), reserve_before, "switch: the reserve pool is shared, not split")
	ctx.check_eq(names.value, events_before + 1, "switch: one weapon_changed per switch")
	ctx.check_eq(String(names.events[names.events.size() - 1]), "SHOTGUN", "switch: announces SHOTGUN")
	ctx.check_eq(ctx.hud_text("WeaponLabel"), "SHOTGUN", "switch: the HUD label follows the signal alone")

	for _i in 2:
		player.set("_fire_timer", 0.0)
		player.call("shoot")
	ctx.check_eq(int(player.ammo), 6, "switch: shotgun down to 6")
	player.call("select_weapon", 0)
	ctx.check_eq(int(player.ammo), 37, "switch: back to the rifle, its spent magazine returns, not a fresh one")

	var noop_before: int = names.value
	player.call("select_weapon", 0)
	ctx.check_eq(names.value, noop_before, "switch: re-selecting the equipped weapon emits nothing")

	player.call("select_weapon", 2)
	ctx.check_eq(int(player.get("_weapon_index")), 0, "switch: index 2 is out of range and ignored")
	player.call("select_weapon", -1)
	ctx.check_eq(int(player.get("_weapon_index")), 0, "switch: a negative index is ignored")

	player.call("reload")
	ctx.check(bool(player.get("_reloading")), "switch: rifle reload started")
	player.call("select_weapon", 1)
	ctx.check_eq(int(player.get("_weapon_index")), 0, "switch: refused while reloading")
	await ctx.step(RELOAD_TICKS)
	ctx.check_eq(int(player.ammo), 40, "switch: the interrupted-by-nothing reload still completed on the rifle")

	Input.action_press("weapon_2")
	await ctx.step(2)
	Input.action_release("weapon_2")
	ctx.check_eq(int(player.get("_weapon_index")), 1, "switch: the weapon_2 action reaches the player")

	var barrel: Node = player.get_node("Camera3D/Weapon/Barrel")
	var sight: Node = player.get_node("Camera3D/Weapon/Sight")
	var shoot_sound: Node = player.get_node("ShootSound")
	ctx.check(barrel.scale == shotgun.barrel_scale, "switch: the shotgun barrel scale is applied")
	ctx.check(not sight.visible, "switch: the shotgun hides the rifle sight")
	ctx.check_near(float(shoot_sound.pitch_scale), 0.65, 0.0001, "switch: the shotgun fires at a lower pitch")

	Input.action_press("weapon_1")
	await ctx.step(2)
	Input.action_release("weapon_1")
	ctx.check_near(float(barrel.scale.x), 1.0, 0.0001, "switch: the rifle barrel scale comes back")
	ctx.check(sight.visible, "switch: the rifle sight is shown again")

	player.call("select_weapon", 1)
	player.call("take_damage", 999)
	player.call("select_weapon", 0)
	ctx.check_eq(int(player.get("_weapon_index")), 1, "switch: a dead player cannot change weapons")


func _test_shotgun(ctx) -> void:
	ctx.begin_suite("player/shotgun")
	var refs := await _begin(ctx)
	var player: Node = refs["player"]
	var ray: RayCast3D = refs["ray"]
	var shots := ShotRecorder.new()
	player.shot_fired.connect(shots.on_shot)
	var hits := RECORDER.new()
	player.shot_hit.connect(func(point: Vector3) -> void: hits.remember(point))
	var enemy_hits := RECORDER.new()
	player.enemy_hit.connect(func() -> void: enemy_hits.hit())
	var spread_log := SpreadRecorder.new()
	player.spread_changed.connect(spread_log.on_spread)

	player.call("select_weapon", 1)
	_reset_spread(player, ray)
	player.set("_fire_timer", 0.0)
	player.call("shoot")

	ctx.check_eq(shots.count, 1, "shotgun: one trigger pull is one shot_fired")
	ctx.check_eq(int(player.ammo), 7, "shotgun: a pull spends one shell, not eight")
	ctx.check_near(player.get("_fire_timer"), 0.75, 0.0001, "shotgun: the resource's 0.75 s interval gates the next pull")
	ctx.check(hits.value >= 2, "shotgun: a blast lands several pellets at once (got %d)" % hits.value)
	ctx.check(hits.value <= 8, "shotgun: never more hit reports than pellets (got %d)" % hits.value)
	ctx.check_eq(enemy_hits.value, 0, "shotgun: scenery hits are not enemy hits")
	ctx.check_near(spread_log.last_movement, 0.6, 0.0001, "shotgun: its cone is folded into the HUD spread signal")

	var cone_max := 0.0
	var beyond_rifle_cap := false
	_reset_spread(player, ray)
	for _i in 24:
		var target: Vector3 = player.call("_spread_ray_target", 4.0)
		var degrees: float = rad_to_deg(RAY_BACK.normalized().angle_to(target))
		cone_max = maxf(cone_max, degrees)
		if degrees > 1.0:
			beyond_rifle_cap = true
	ctx.check(beyond_rifle_cap, "shotgun: the base cone pushes rays past the rifle's 1.0 degree cap")
	ctx.check(cone_max <= 4.0 + 0.001, "shotgun: every ray stays inside the 4 degree cone (max %.3f)" % cone_max)
	ctx.check_eq(player.call("_spread_ray_target", 0.0), RAY_BACK,
		"shotgun: a zero cone with no dynamic spread is still dead centre")

	var enemy: Node = load("res://enemy.tscn").instantiate()
	enemy.position = Vector3(0, 0, -4)
	refs["main"].add_child(enemy)
	enemy.set("hp", 400)
	await ctx.step(2)
	var enemy_hp_before: int = enemy.hp
	var enemy_hits_before: int = enemy_hits.value
	player.set("_fire_timer", 0.0)
	player.call("shoot")
	var dealt: int = enemy_hp_before - int(enemy.hp)
	ctx.check(dealt >= 15, "shotgun: the blast lands at least one pellet (%d damage)" % dealt)
	ctx.check_eq(dealt % 15, 0, "shotgun: damage arrives in whole pellets of 15 (%d damage)" % dealt)
	ctx.check_eq(enemy_hits.value, enemy_hits_before + 1,
		"shotgun: exactly one enemy_hit per pull, however many pellets connect")

	refs["main"].remove_child(enemy)
	enemy.queue_free()
	await ctx.step(2)

	player.set("_fire_timer", 0.0)
	player.set("ammo", 1)
	player.call("shoot")
	ctx.check_eq(int(player.ammo), 0, "shotgun: the last shell still fires")
	ctx.check(bool(player.get("_reloading")), "shotgun: an empty magazine auto-reloads")
	await ctx.step(70)
	ctx.check_eq(int(player.ammo), 0, "shotgun: still reloading at 70 ticks, where the rifle would be done")
	ctx.check(bool(player.get("_reloading")), "shotgun: the reload flag holds through 70 ticks")
	await ctx.step(40)
	ctx.check_eq(int(player.ammo), 8, "shotgun: the 1.6 s reload completes by 110 ticks")


func _test_single_shot(ctx) -> void:
	ctx.begin_suite("player/single_shot")
	var refs := await _begin(ctx)
	var player: Node = refs["player"]
	var recorder := ShotRecorder.new()
	player.shot_fired.connect(recorder.on_shot)

	ctx.check_eq(int(player.ammo), 40, "magazine starts full at 40")
	player.call("shoot")
	ctx.check_eq(recorder.count, 1, "one shot fired")
	ctx.check_eq(int(player.ammo), 39, "one round consumed")

	player.call("shoot")
	ctx.check_eq(recorder.count, 1, "second call inside the cooldown is rejected")
	ctx.check_eq(int(player.ammo), 39, "no round consumed while the cooldown is live")

	player.set("_fire_timer", 0.0)
	player.call("shoot")
	ctx.check_eq(recorder.count, 2, "a shot lands again once the cooldown expires")

	var hits := RECORDER.new()
	player.shot_hit.connect(func(_p: Vector3) -> void: hits.hit())
	player.set("_fire_timer", 0.0)
	player.set("_movement_spread", 0.0)
	player.set("_fire_spread", 0.0)
	player.call("shoot")
	ctx.check_eq(hits.value, 1, "hitscan reports a hit against arena geometry")


func _test_miss_branch(ctx) -> void:
	ctx.begin_suite("player/miss")
	var refs := await _begin(ctx)
	var player: Node = refs["player"]
	var ray: RayCast3D = refs["ray"]
	var shots := RECORDER.new()
	var hits := RECORDER.new()
	var enemy_hits := RECORDER.new()
	player.shot_fired.connect(func() -> void: shots.hit())
	player.shot_hit.connect(func(p: Vector3) -> void: hits.remember(p))
	player.enemy_hit.connect(func() -> void: enemy_hits.hit())

	# Positive pitch looks up in this camera convention, and nothing above the
	# arena has a collision shape, so the hitscan ray comes back empty.
	_reset_spread(player, ray)
	player.set("_pitch", 1.2)
	player.call("_apply_camera_pitch")
	await ctx.step(2)
	ctx.check(not ray.is_colliding(), "an upward ray finds no collider before firing")

	var ammo_before: int = player.ammo
	player.set("_fire_timer", 0.0)
	player.call("shoot")
	ctx.check_eq(shots.value, 1, "the miss is still a real shot")
	ctx.check_eq(int(player.ammo), ammo_before - 1, "the miss still consumes a round")
	ctx.check_eq(hits.value, 0, "a miss emits no shot_hit")
	ctx.check_eq(enemy_hits.value, 0, "a miss emits no enemy_hit")
	ctx.check(not ray.is_colliding(), "the ray still reports empty after the shot")
	ctx.check_near(player.get("_recoil_pitch"), deg_to_rad(0.3), 0.0001,
		"a miss still kicks camera recoil, so the shot ran the full path")

	# Control: a level ray must hit arena geometry. Without this, the two
	# zero-count assertions above would also pass with the branches swapped.
	_reset_spread(player, ray)
	player.set("_pitch", 0.0)
	player.call("_apply_camera_pitch")
	await ctx.step(2)
	ctx.check(ray.is_colliding(), "a level ray does find arena geometry")
	player.set("_fire_timer", 0.0)
	player.call("shoot")
	ctx.check_eq(shots.value, 2, "the control shot fired")
	ctx.check_eq(hits.value, 1, "the control shot emits exactly one shot_hit")
	ctx.check_eq(enemy_hits.value, 0, "hitting scenery is not an enemy hit")
	ctx.check_near(hits.events[0].distance_to(player.global_position), 12.0, 1.5,
		"the hit point is a real world position, not the Vector3 default")

	# A miss must not be able to wound anything either.
	var enemy: Node = load("res://enemy.tscn").instantiate()
	enemy.position = Vector3(0, 0, -4)
	refs["main"].add_child(enemy)
	await ctx.step(2)
	var enemy_hp_before: int = enemy.hp
	_reset_spread(player, ray)
	player.set("_pitch", 1.2)
	player.call("_apply_camera_pitch")
	player.set("_fire_timer", 0.0)
	player.call("shoot")
	ctx.check_eq(int(enemy.hp), enemy_hp_before, "a shot into the sky wounds nobody")
	ctx.check_eq(hits.value, 1, "the sky shot beside an enemy still emits no shot_hit")


func _test_autofire_cadence(ctx) -> void:
	ctx.begin_suite("player/autofire")
	var refs := await _begin(ctx)
	var player: Node = refs["player"]
	var recorder := ShotRecorder.new()
	player.shot_fired.connect(recorder.on_shot)

	player.set("force_wants_fire", true)
	await ctx.step(50)
	player.set("force_wants_fire", false)

	ctx.check_in_range(recorder.count, 6.0, 8.0,
		"holding fire for 50 ticks yields about 50/7.2 shots")
	var deltas: Array[int] = []
	for i in range(1, recorder.ticks.size()):
		deltas.append(recorder.ticks[i] - recorder.ticks[i - 1])
	var all_on_rate := true
	for delta in deltas:
		if delta < 7 or delta > 8:
			all_on_rate = false
	ctx.check(all_on_rate, "every shot interval is 7-8 ticks (0.12 s at 60 Hz): %s" % [deltas])
	ctx.check_eq(int(player.ammo), 40 - recorder.count, "ammo tracked the autofire burst")

	var before := recorder.count
	await ctx.step(20)
	ctx.check_eq(recorder.count, before, "releasing the button stops firing immediately")

	player.set("_reloading", true)
	player.set("force_wants_fire", true)
	await ctx.step(20)
	player.set("force_wants_fire", false)
	ctx.check_eq(recorder.count, before, "holding fire while reloading produces no shots")
	player.set("_reloading", false)


func _test_reload_gating(ctx) -> void:
	ctx.begin_suite("player/reload")
	var refs := await _begin(ctx)
	var player: Node = refs["player"]
	var reload_events: Array = []
	player.reload_changed.connect(func(r: bool) -> void: reload_events.append(r))

	for _i in 6:
		player.set("_fire_timer", 0.0)
		player.call("shoot")
	ctx.check_eq(int(player.ammo), 34, "six rounds spent before reloading")

	player.call("reload")
	ctx.check(bool(player.get("_reloading")), "reload starts")
	ctx.check_eq(reload_events.size(), 1, "reload_changed emitted once on start")
	ctx.check_eq(int(player.ammo), 34, "ammo unchanged until the reload completes")

	await ctx.step(RELOAD_TICKS)
	ctx.check_eq(int(player.ammo), 40, "magazine refilled to capacity")
	ctx.check_eq(int(player.reserve), 114, "reserve paid for the refill")
	ctx.check(not bool(player.get("_reloading")), "reload flag cleared")
	ctx.check_eq(reload_events.size(), 2, "reload_changed emitted again on completion")
	ctx.check_eq(reload_events[1], false, "completion event reports reloading=false")

	player.call("reload")
	ctx.check_eq(int(player.ammo), 40, "reload with a full magazine is a no-op")
	ctx.check(not bool(player.get("_reloading")), "no reload started from a full magazine")


func _test_ammo_economy(ctx) -> void:
	ctx.begin_suite("player/ammo")
	var refs := await _begin(ctx)
	var player: Node = refs["player"]

	player.set("reserve", 0)
	player.set("ammo", 10)
	player.call("reload")
	ctx.check(not bool(player.get("_reloading")), "reload refused with an empty reserve")
	ctx.check_eq(int(player.ammo), 10, "ammo untouched when the reserve is empty")

	player.set("reserve", 20)
	player.call("reload")
	await ctx.step(RELOAD_TICKS)
	ctx.check_eq(int(player.ammo), 30, "a short reserve only refills part of the magazine")
	ctx.check_eq(int(player.reserve), 0, "reserve drained to zero by the refill")

	player.set("reserve", 230)
	player.call("add_reserve", 9999)
	ctx.check_eq(int(player.reserve), 240, "add_reserve clamps to RESERVE_MAX")
	player.call("add_reserve", -50)
	ctx.check_eq(int(player.reserve), 240, "negative add_reserve is ignored")

	var recorder := ShotRecorder.new()
	player.shot_fired.connect(recorder.on_shot)
	player.set("ammo", 1)
	player.set("reserve", 60)
	player.set("_fire_timer", 0.0)
	player.set("_reloading", false)
	player.call("shoot")
	ctx.check_eq(recorder.count, 1, "last round in the magazine still fires")
	ctx.check(bool(player.get("_reloading")), "firing the last round starts a reload")
	await ctx.step(RELOAD_TICKS)
	ctx.check_eq(int(player.ammo), 40, "dry magazine auto-reloads to full")


func _test_damage_and_death(ctx) -> void:
	ctx.begin_suite("player/damage")
	var refs := await _begin(ctx)
	var player: Node = refs["player"]
	var main: Node = refs["main"]
	var deaths := RECORDER.new()
	var health_events: Array = []
	player.died.connect(func() -> void: deaths.hit())
	player.hp_changed.connect(func(h: int, _m: int) -> void: health_events.append(h))

	player.call("take_damage", 10)
	ctx.check_eq(int(player.hp), 90, "a 10 damage hit leaves 90 hp")
	ctx.check_eq(health_events, [90], "hp_changed reported the new value")

	player.call("take_damage", 999)
	ctx.check_eq(int(player.hp), 0, "damage is clamped at zero hp")
	ctx.check_eq(deaths.value, 1, "died emitted exactly once")
	ctx.check(bool(player.get("_dead")), "dead flag set")
	ctx.check(not player.is_physics_processing(), "player stops simulating on death")
	ctx.check(not player.is_processing_unhandled_input(), "player stops taking input on death")

	var recorder := ShotRecorder.new()
	player.shot_fired.connect(recorder.on_shot)
	player.set("force_wants_fire", true)
	await ctx.step(20)
	player.set("force_wants_fire", false)
	ctx.check_eq(recorder.count, 0, "a dead player cannot fire")

	player.call("take_damage", 10)
	ctx.check_eq(deaths.value, 1, "damage after death does not re-trigger died")
	ctx.check_eq(int(player.hp), 0, "hp stays pinned at zero")

	var end_panel: Control = main.get_node("HUD/EndPanel")
	ctx.check(end_panel.visible, "GAME OVER panel is shown")
	ctx.check_eq(ctx.hud_text("EndPanel/CenterContainer/VBoxContainer/TitleLabel"), "GAME OVER",
		"end title reads GAME OVER")
	ctx.check(bool(main.get("_finished")), "main marked the run finished")
	ctx.check(ctx.tree.paused, "tree is paused for the manual restart")


func _test_camera_recoil(ctx) -> void:
	ctx.begin_suite("player/recoil")
	var refs := await _begin(ctx)
	var player: Node = refs["player"]
	var camera: Camera3D = refs["camera"]

	player.set("_pitch", 0.0)
	player.set("_recoil_pitch", 0.0)
	player.call("_apply_camera_pitch")

	player.call("shoot")
	ctx.check_near(rad_to_deg(player.get("_recoil_pitch")), 0.3, 0.0001,
		"one shot lifts the camera pitch by recoil_per_shot_degrees")
	ctx.check_near(rad_to_deg(camera.rotation.x), 0.3, 0.0001,
		"Camera3D rotation.x carries the recoil (real aim offset)")
	ctx.check_near(player.rotation.x, 0.0, 0.0001, "player body pitch is never touched")

	var peak := 0.0
	for _i in 12:
		player.set("_fire_timer", 0.0)
		player.call("shoot")
		peak = maxf(peak, rad_to_deg(player.get("_recoil_pitch")))
	ctx.check(peak <= 1.5 + 0.0001, "recoil never exceeds the 1.5 degree cap (peak %.3f)" % peak)
	ctx.check_in_range(peak, 1.49, 1.5001, "rapid fire saturates exactly at the cap")

	player.set("_fire_timer", 0.0)
	player.call("shoot")
	var zeroed: bool = await ctx.step_until(
		func() -> bool: return absf(player.get("_recoil_pitch")) < 0.0000001, 14)
	ctx.check(zeroed, "recoil returns to exactly zero within 14 ticks of the last shot")

	var settled: bool = await ctx.step_until(
		func() -> bool: return absf(camera.rotation.x) < 0.0000001, 4)
	ctx.check(settled, "camera pitch settles back onto the aim value")

	var recorder := ShotRecorder.new()
	player.shot_fired.connect(recorder.on_shot)
	player.set("force_wants_fire", true)
	var burst_peak := 0.0
	for _i in 40:
		await ctx.tree.physics_frame
		burst_peak = maxf(burst_peak, rad_to_deg(player.get("_recoil_pitch")))
	player.set("force_wants_fire", false)
	ctx.check(burst_peak <= 1.5 + 0.0001,
		"sustained autofire stays under the cap (peak %.3f)" % burst_peak)
	ctx.check(burst_peak > 0.9, "sustained autofire visibly accumulates (peak %.3f)" % burst_peak)


func _test_viewmodel_and_crosshair_kick(ctx) -> void:
	ctx.begin_suite("player/viewmodel")
	var refs := await _begin(ctx)
	var player: Node = refs["player"]
	var weapon: Node3D = refs["weapon"]
	var crosshair: Control = refs["crosshair"]

	var rest_position: Vector3 = player.get("_weapon_rest_position")
	var rest_rotation: Vector3 = player.get("_weapon_rest_rotation")
	await ctx.step(10)
	ctx.check_near(weapon.position.distance_to(rest_position), 0.0, 0.001,
		"weapon rests at its authored position before firing")

	player.call("shoot")
	ctx.check_near(weapon.position.z, rest_position.z + 0.05, 0.0001,
		"batch D viewmodel kick still moves the weapon +0.05 m")
	ctx.check_near(weapon.rotation.x, rest_rotation.x - 0.08, 0.0001,
		"batch D viewmodel kick still tilts the weapon -0.08 rad")
	ctx.check_near(crosshair.scale.x, 1.4, 0.0001,
		"batch D crosshair kick still punches to 1.4x")

	await ctx.step(15)
	ctx.check_near(weapon.position.distance_to(rest_position), 0.0, 0.001,
		"weapon returns to rest after the recoil tween")
	ctx.check_near(crosshair.scale.x, 1.0, 0.01, "crosshair punch decays back to 1.0")

	var flash: Node = player.get_node("Camera3D/Weapon/Muzzle/FlashMesh")
	ctx.check(not flash.visible, "muzzle flash mesh hidden again after the flash")


func _test_spread(ctx) -> void:
	ctx.begin_suite("player/spread")
	var refs := await _begin(ctx)
	var player: Node = refs["player"]
	var ray: RayCast3D = refs["ray"]
	var spread_log := SpreadRecorder.new()
	player.spread_changed.connect(spread_log.on_spread)

	_reset_spread(player, ray)
	player.call("shoot")
	ctx.check_eq(ray.target_position, RAY_BACK,
		"a standing single shot leaves the ray dead centre (zero deviation)")
	ctx.check_near(player.get("_fire_spread"), 0.3, 0.0001,
		"fire spread steps by 0.3 after the ray cast, not before")

	var max_angle := 0.0
	for _i in 12:
		player.set("_fire_timer", 0.0)
		player.call("shoot")
		max_angle = maxf(max_angle, _ray_angle(ray))
	ctx.check_near(player.get("_fire_spread"), 1.0, 0.0001, "fire spread saturates at 1.0")
	ctx.check(max_angle <= 1.0 + 0.0001,
		"no burst ray leaves the 1.0 degree cone (max %.3f)" % max_angle)
	ctx.check(max_angle > 0.3, "burst rays actually scatter (max %.3f degrees)" % max_angle)

	await ctx.step_until(func() -> bool: return player.get("_fire_spread") < 0.0001, 40)
	ctx.check_near(player.get("_fire_spread"), 0.0, 0.0001,
		"fire spread decays back to zero after the burst")

	Input.action_press("move_forward")
	var emissions_before_move := spread_log.emissions
	var reached: bool = await ctx.step_until(
		func() -> bool: return player.get("_movement_spread") > 0.99, 40)
	Input.action_release("move_forward")
	ctx.check(reached, "movement spread rises to full at run speed")
	ctx.check_near(player.get("_movement_spread"), 1.0, 0.02,
		"movement spread follows horizontal speed")
	ctx.check(spread_log.emissions > emissions_before_move,
		"spread_changed pushed the movement value to the HUD")

	Input.action_press("move_forward")
	await ctx.step(6)
	_reset_spread(player, ray)
	max_angle = 0.0
	for _i in 6:
		player.set("_fire_timer", 0.0)
		player.call("shoot")
		max_angle = maxf(max_angle, _ray_angle(ray))
	Input.action_release("move_forward")
	ctx.check(max_angle > 0.5, "moving shots deviate well beyond centre (max %.3f)" % max_angle)
	ctx.check(max_angle <= 1.0 + 0.0001, "moving shots stay inside the cone (max %.3f)" % max_angle)
	await ctx.step(30)
	ctx.check_near(player.get("_movement_spread"), 0.0, 0.05,
		"movement spread collapses once the player stops")

	var settled := spread_log.emissions
	await ctx.step(20)
	ctx.check_eq(spread_log.emissions, settled,
		"a settled player emits no further spread signals")

	player.call("take_damage", 999)
	ctx.check_near(player.get("_recoil_pitch"), 0.0, 0.0000001, "death clears camera recoil")
	ctx.check_near(player.get("_movement_spread"), 0.0, 0.0000001, "death clears movement spread")
	ctx.check_near(player.get("_fire_spread"), 0.0, 0.0000001, "death clears fire spread")
	ctx.check_near(spread_log.last_movement, 0.0, 0.0001,
		"death publishes a zeroed spread to the HUD")


func _test_crosshair_spread_mapping(ctx) -> void:
	ctx.begin_suite("player/crosshair_spread")
	var refs := await _begin(ctx)
	var player: Node = refs["player"]
	var crosshair: Control = refs["crosshair"]

	crosshair.call("set_spread", 0.0, 0.0)
	await ctx.step(30)
	ctx.check_near(crosshair.call("spread_scale"), 1.0, 0.005, "no spread leaves the crosshair at 1.0x")

	crosshair.call("set_spread", 1.0, 0.0)
	await ctx.step(40)
	ctx.check_near(crosshair.call("spread_scale"), 1.5, 0.01, "full movement spread gives 1.5x")

	crosshair.call("set_spread", 0.0, 1.0)
	await ctx.step(40)
	ctx.check_near(crosshair.call("spread_scale"), 1.3, 0.01, "full fire spread gives +30%")

	crosshair.call("set_spread", 1.0, 1.0)
	await ctx.step(40)
	ctx.check_near(crosshair.call("spread_scale"), 1.8, 0.01,
		"combined spread is clamped by MAX_SPREAD_SCALE (1.8x)")

	crosshair.call("set_spread", 9.0, -3.0)
	await ctx.step(40)
	ctx.check_near(crosshair.call("spread_scale"), 1.5, 0.01,
		"out-of-range inputs are clamped into 0..1")

	Input.action_press("move_forward")
	var converged: bool = await ctx.step_until(
		func() -> bool: return crosshair.call("spread_scale") > 1.45, 60)
	Input.action_release("move_forward")
	ctx.check(converged, "the HUD crosshair widens from the player signal alone")
	await ctx.step(40)
	ctx.check_near(crosshair.call("spread_scale"), 1.0, 0.02,
		"the HUD crosshair relaxes once the player stops")


func _reset_spread(player: Node, ray: RayCast3D) -> void:
	player.set("_movement_spread", 0.0)
	player.set("_fire_spread", 0.0)
	player.set("_settle_timer", 0.0)
	player.set("_recoil_pitch", 0.0)
	player.set("_fire_timer", 0.0)
	ray.target_position = RAY_BACK


func _test_pitch_clamp(ctx) -> void:
	ctx.begin_suite("player/pitch")
	var refs := await _begin(ctx)
	var player: Node = refs["player"]
	var camera: Camera3D = refs["camera"]

	player.set("_pitch", PITCH_LIMIT * 2)
	player.set("_recoil_pitch", 0.0)
	player.call("_apply_camera_pitch")
	ctx.check_near(camera.rotation.x, PITCH_LIMIT, 0.0001,
		"camera pitch clamps at +PITCH_LIMIT")

	player.set("_pitch", -PITCH_LIMIT * 2)
	player.call("_apply_camera_pitch")
	ctx.check_near(camera.rotation.x, -PITCH_LIMIT, 0.0001,
		"camera pitch clamps at -PITCH_LIMIT")

	player.set("_pitch", 0.0)
	player.set("_recoil_pitch", deg_to_rad(80.0))
	player.call("_apply_camera_pitch")
	ctx.check(camera.rotation.x <= PITCH_LIMIT + 0.0001,
		"recoil can never push the camera past the pitch limit")


func _ray_angle(ray: RayCast3D) -> float:
	return rad_to_deg(RAY_BACK.normalized().angle_to(ray.target_position))
