extends RefCounted

const MELEE := 0
const CHARGER := 1
const RANGED := 2

const BASE_COLOR := Color(0.75, 0.15, 0.2)
const CHARGER_COLOR := Color(0.95, 0.45, 0.1)
const RANGED_COLOR := Color(0.6, 0.25, 0.9)

const BLOCKED_AT := Vector3(-8, 0, -8)
const CLEAR_AT := Vector3(0, 0, -8)
const RECORDER := preload("res://tests/recorder.gd")


func run(ctx) -> void:
	await _test_roles(ctx)
	await _test_spawn_grace(ctx)
	await _test_detection_and_aggro(ctx)
	await _test_melee(ctx)
	await _test_line_of_sight(ctx)
	await _test_charger(ctx)
	await _test_ranged(ctx)
	await _test_deaggro(ctx)
	await _test_damage_and_death(ctx)
	ctx.mark_file_done("test_enemies")


func _begin(ctx) -> Node:
	var main: Node = await ctx.load_main()
	await ctx.remove_enemies()
	return main


func _spawn(ctx, at: Vector3, role: int) -> Node:
	return await _place(ctx, at, role, true)


func _spawn_with_grace(ctx, at: Vector3, role: int) -> Node:
	return await _place(ctx, at, role, false)


# The acquisition and combat suites clear the grace window so they can assert on
# behaviour directly; the grace itself has its own suite.
func _place(ctx, at: Vector3, role: int, skip_grace: bool) -> Node:
	var enemy: Node = load("res://enemy.tscn").instantiate()
	enemy.set("role", role)
	if skip_grace:
		enemy.set("spawn_grace", 0.0)
	enemy.position = at
	ctx.main.add_child(enemy)
	await ctx.tree.physics_frame
	return enemy


func _test_roles(ctx) -> void:
	ctx.begin_suite("enemies/roles")
	await _begin(ctx)

	var melee: Node = await _spawn(ctx, Vector3(0, 0, -30), MELEE)
	ctx.check_near(melee.speed, 4.3, 0.0001, "melee speed is 4.3 m/s")
	ctx.check_eq(int(melee.attack_damage), 10, "melee damage is 10")
	ctx.check_near(melee.attack_cooldown, 1.0, 0.0001, "melee cooldown is 1.0 s")
	ctx.check_eq(int(melee.hp), 100, "melee has 100 hp")
	ctx.check_near(melee.attack_range, 1.5, 0.0001, "melee attack range is 1.5 m")
	ctx.check(_color_is(melee.get("_material").albedo_color, BASE_COLOR),
		"melee uses the base red")
	ctx.check_eq(int(melee.get("state")), 0, "a fresh enemy starts IDLE")

	var charger: Node = await _spawn(ctx, Vector3(2, 0, -30), CHARGER)
	ctx.check_near(charger.speed, 4.6, 0.0001, "charger speed is 4.6 m/s")
	ctx.check_eq(int(charger.attack_damage), 14, "charger damage is 14")
	ctx.check_near(charger.attack_cooldown, 1.3, 0.0001, "charger cooldown is 1.3 s")
	ctx.check_eq(int(charger.hp), 80, "charger has 80 hp")
	ctx.check(_color_is(charger.get("_material").albedo_color, CHARGER_COLOR),
		"charger uses the orange telegraph colour")
	ctx.check(_color_is(charger.get_node("TelegraphLight").light_color, CHARGER_COLOR),
		"charger telegraph light is orange")

	var ranged: Node = await _spawn(ctx, Vector3(4, 0, -30), RANGED)
	ctx.check_near(ranged.speed, 3.4, 0.0001, "ranged speed is 3.4 m/s")
	ctx.check_eq(int(ranged.attack_damage), 10, "ranged damage is 10")
	ctx.check_near(ranged.attack_cooldown, 2.5, 0.0001, "ranged cooldown is 2.5 s")
	ctx.check_eq(int(ranged.hp), 75, "ranged has 75 hp")
	ctx.check(_color_is(ranged.get("_material").albedo_color, RANGED_COLOR),
		"ranged uses the purple telegraph colour")
	ctx.check(_color_is(ranged.get_node("TelegraphLight").light_color, RANGED_COLOR),
		"ranged telegraph light is purple")

	ctx.check_near(float(melee._agent.max_speed), 4.3, 0.0001,
		"nav agent max_speed is synced to the role speed")

	var melee_data: Resource = load("res://data/enemy_melee.tres")
	var charger_data: Resource = load("res://data/enemy_charger.tres")
	var ranged_data: Resource = load("res://data/enemy_ranged.tres")
	ctx.check_eq(String(melee_data.resource_path), "res://data/enemy_melee.tres",
		"melee stats are owned by data/enemy_melee.tres")
	ctx.check_eq(String(charger_data.resource_path), "res://data/enemy_charger.tres",
		"charger stats are owned by data/enemy_charger.tres")
	ctx.check_eq(String(ranged_data.resource_path), "res://data/enemy_ranged.tres",
		"ranged stats are owned by data/enemy_ranged.tres")
	ctx.check_eq(int(melee.attack_damage), int(melee_data.attack_damage),
		"the live melee enemy reads damage from the resource")
	ctx.check_eq(int(charger.attack_damage), int(charger_data.attack_damage),
		"the live charger enemy reads damage from the resource")
	ctx.check_eq(int(ranged.attack_damage), int(ranged_data.attack_damage),
		"the live ranged enemy reads damage from the resource")
	ctx.check_near(charger.speed, float(charger_data.speed), 0.0001,
		"the live charger enemy reads speed from the resource")
	ctx.check(_color_is(melee.get_node("SpawnHalo").material_override.albedo_color,
		Color(1, 0.2, 0.08)), "the melee spawn halo is tinted melee red")
	ctx.check(_color_is(charger.get_node("SpawnHalo").material_override.albedo_color,
		CHARGER_COLOR), "the charger spawn halo is tinted charger orange")
	ctx.check(_color_is(ranged.get_node("SpawnHalo").material_override.albedo_color,
		RANGED_COLOR), "the ranged spawn halo is tinted ranged purple")


func _test_spawn_grace(ctx) -> void:
	ctx.begin_suite("enemies/spawn_grace")
	var main: Node = await _begin(ctx)
	var player: Node = main.get_node("Player")

	var enemy: Node = await _spawn_with_grace(ctx, Vector3(0, 0, -5), MELEE)
	ctx.check_near(enemy.get("_spawn_grace"), 0.7, 0.06, "a fresh spawn starts with a 0.7 s grace")
	await ctx.step(10)
	ctx.check(float(enemy.get("_spawn_grace")) > 0.0, "grace is still running 10 ticks in")
	ctx.check_eq(int(enemy.get("state")), 0,
		"the player standing inside the 8 m circle does not aggro during grace")
	ctx.check(enemy.get("player") == null, "no target is acquired during grace")
	ctx.check_near(Vector2(enemy.velocity.x, enemy.velocity.z).length(), 0.0, 0.01,
		"a graced enemy cannot move")

	var halo: MeshInstance3D = enemy.get_node("SpawnHalo")
	ctx.check(halo.visible, "the spawn halo is visible during the grace window")
	ctx.check_in_range(halo.scale.x, 1.0, 1.75, "the halo starts near its full radius (%.2f)" % halo.scale.x)
	var halo_scale_early: float = halo.scale.x
	var halo_alpha_early: float = float(halo.material_override.albedo_color.a)
	await ctx.step(10)
	ctx.check(halo.scale.x < halo_scale_early,
		"the halo contracts as the grace runs out (%.2f -> %.2f)" % [halo_scale_early, halo.scale.x])
	var halo_alpha_now: float = float(halo.material_override.albedo_color.a)
	ctx.check(halo_alpha_now < halo_alpha_early,
		"the halo fades as the grace runs out (%.2f -> %.2f)" % [halo_alpha_early, halo_alpha_now])

	enemy.call("hear_gunshot", player)
	ctx.check_eq(int(enemy.get("state")), 0, "a gunshot during grace does not aggro at once")
	ctx.check(enemy.get("_pending_target") == player, "the gunshot source is remembered")

	var released: bool = await ctx.step_until(
		func() -> bool: return int(enemy.get("state")) == 1, 60)
	ctx.check(released, "the remembered target is taken when the grace ends")
	ctx.check(enemy.get("player") == player, "the deferred target becomes the active one")
	ctx.check(enemy.get("_pending_target") == null, "the pending slot clears on release")
	ctx.check(not halo.visible, "the spawn halo is hidden once the grace ends")
	ctx.check_near(halo.scale.x, 1.0, 0.02, "the halo ends at its resting radius")

	main = await _begin(ctx)
	player = main.get_node("Player")
	var shot_back: Node = await _spawn_with_grace(ctx, Vector3(0, 0, 10), MELEE)
	shot_back.call("take_damage", 10)
	ctx.check_eq(int(shot_back.get("state")), 1,
		"being shot is never deferred by the grace window")

	main = await _begin(ctx)
	var quiet: Node = await _spawn_with_grace(ctx, Vector3(0, 0, 10), MELEE)
	var start := Engine.get_physics_frames()
	var done: bool = await ctx.step_until(
		func() -> bool: return float(quiet.get("_spawn_grace")) <= 0.0, 90)
	var ticks := Engine.get_physics_frames() - start
	ctx.check(done, "grace always expires")
	ctx.check_in_range(float(ticks), 34.0, 48.0,
		"grace lasts about 0.7 s of engine time (%d ticks)" % ticks)
	ctx.check_eq(int(quiet.get("state")), 0, "with no target around, grace ends in IDLE")

	var plain: Node = await _spawn(ctx, Vector3(0, 0, 10), MELEE)
	ctx.check(not plain.get_node("SpawnHalo").visible,
		"an enemy spawned with the grace skipped shows no halo")

	var short_grace: Node = load("res://enemy.tscn").instantiate()
	short_grace.set("role", MELEE)
	short_grace.set("spawn_grace", 0.3)
	short_grace.position = Vector3(0, 0, -5)
	ctx.main.add_child(short_grace)
	await ctx.tree.physics_frame
	await ctx.step(6)
	ctx.check_eq(int(short_grace.get("state")), 0, "the shortened grace is still holding at 7 ticks")
	var quick_release: bool = await ctx.step_until(
		func() -> bool: return int(short_grace.get("state")) == 1, 24)
	ctx.check(quick_release,
		"the exported spawn_grace knob, not the 0.7 s default, sets the release time")


func _test_detection_and_aggro(ctx) -> void:
	ctx.begin_suite("enemies/aggro")
	var main: Node = await _begin(ctx)
	var player: Node = main.get_node("Player")

	var near: Node = await _spawn(ctx, Vector3(0, 0, -5), MELEE)
	await ctx.step(20)
	ctx.check_eq(int(near.get("state")), 1, "an enemy inside 8 m detects the player and chases")
	ctx.check(near.get("player") == player, "detection stores the player as the target")

	main = await _begin(ctx)
	player = main.get_node("Player")
	var far: Node = await _spawn(ctx, Vector3(0, 0, -11), MELEE)
	await ctx.step(20)
	ctx.check_eq(int(far.get("state")), 0, "an enemy outside the 8 m radius stays IDLE")
	ctx.check(far.get("player") == null, "an undetected player is not a target")

	far.call("hear_gunshot", player)
	ctx.check_eq(int(far.get("state")), 1, "a gunshot inside 15 m aggroes the enemy")
	ctx.check(far.get("player") == player, "the gunshot source becomes the target")

	main = await _begin(ctx)
	player = main.get_node("Player")
	var very_far: Node = await _spawn(ctx, Vector3(0, 0, -25), MELEE)
	await ctx.step(5)
	very_far.call("hear_gunshot", player)
	ctx.check_eq(int(very_far.get("state")), 0, "a gunshot beyond 15 m is not heard")


func _test_melee(ctx) -> void:
	ctx.begin_suite("enemies/melee")
	var main: Node = await _begin(ctx)
	var player: Node = main.get_node("Player")
	var enemy: Node = await _spawn(ctx, Vector3(0, 0, -1.2), MELEE)
	await ctx.step(2)

	ctx.check_eq(int(player.hp), 100, "player starts the melee exchange at full hp")
	ctx.check(bool(enemy.get("_winding_up")), "an in-range enemy starts an attack windup")
	ctx.check(float(enemy.get("_windup_timer")) > 0.0, "the windup is still counting down")
	ctx.check_near(enemy.get_node("TelegraphLight").light_energy, 4.0, 0.001,
		"the windup lights the telegraph")
	ctx.check_near(enemy.get_node("MeshInstance3D").scale.x, 1.15, 0.001,
		"the windup inflates the body as a tell")

	var landed: bool = await ctx.step_until(func() -> bool: return player.hp < 100, 40)
	ctx.check(landed, "the windup resolves into a hit")
	ctx.check_eq(int(player.hp), 90, "the melee hit lands for exactly attack_damage")

	await ctx.step(45)
	ctx.check_eq(int(player.hp), 90, "no second hit before the 1.0 s cooldown")

	var second: bool = await ctx.step_until(func() -> bool: return player.hp < 90, 40)
	ctx.check(second, "the second hit lands after the cooldown")
	ctx.check_eq(int(player.hp), 80, "the second hit also deals exactly attack_damage")


func _test_line_of_sight(ctx) -> void:
	ctx.begin_suite("enemies/line_of_sight")
	var main: Node = await _begin(ctx)
	var player: Node = main.get_node("Player")

	var clear: Node = await _spawn(ctx, CLEAR_AT, MELEE)
	clear.call("_aggro", player)
	await ctx.step(2)
	ctx.check(clear.call("_has_line_of_sight"), "open ground gives line of sight")

	main = await _begin(ctx)
	player = main.get_node("Player")
	var blocked: Node = await _spawn(ctx, BLOCKED_AT, MELEE)
	blocked.call("_aggro", player)
	await ctx.step(2)
	ctx.check(not blocked.call("_has_line_of_sight"),
		"a crate between the enemy and the player blocks line of sight")
	var hp_before: int = player.hp
	await ctx.step(60)
	ctx.check_eq(int(player.hp), hp_before,
		"a blocked enemy walks toward the player instead of attacking")
	ctx.check(blocked.global_position.distance_to(player.global_position)
		< BLOCKED_AT.distance_to(Vector3.ZERO), "the blocked enemy closed the distance")


func _test_charger(ctx) -> void:
	ctx.begin_suite("enemies/charger")
	var main: Node = await _begin(ctx)
	var player: Node = main.get_node("Player")
	var enemy: Node = await _spawn(ctx, Vector3(0, 0, -6), CHARGER)
	await ctx.step(3)

	ctx.check(bool(enemy.get("_charge_winding")),
		"a charger at 6 m with line of sight winds up a charge")
	ctx.check_near(enemy.get_node("TelegraphLight").light_energy, 6.0, 0.001,
		"the charge windup lights the telegraph")
	ctx.check_near(enemy.get_node("MeshInstance3D").scale.x, 1.25, 0.001,
		"the charge windup inflates the body further than a melee swing")
	ctx.check_near(Vector2(enemy.velocity.x, enemy.velocity.z).length(), 0.0, 0.01,
		"the charger holds still during the windup")

	await ctx.step(33)
	ctx.check(not bool(enemy.get("_charge_winding")), "the windup resolves into the dash")
	ctx.check(float(enemy.get("_charge_time")) > 0.0, "the dash is running")
	ctx.check_near(Vector2(enemy.velocity.x, enemy.velocity.z).length(), 11.0, 0.01,
		"the dash moves at CHARGE_SPEED 11 m/s")

	var hit: bool = await ctx.step_until(func() -> bool: return player.hp < 100, 40)
	ctx.check(hit, "the dash connects and damages the player")
	ctx.check_eq(int(player.hp), 86, "the charge deals exactly 14 damage")

	var ended: bool = await ctx.step_until(
		func() -> bool: return float(enemy.get("_charge_time")) <= 0.0, 40)
	ctx.check(ended, "the dash stops after CHARGE_DURATION")
	ctx.check_near(enemy.get("_charge_cooldown_timer"), 3.2, 0.05,
		"the dash leaves a 3.2 s cooldown")
	ctx.check_near(enemy.get_node("MeshInstance3D").scale.x, 1.0, 0.001,
		"the body returns to normal size after the dash")
	ctx.check_near(enemy.get_node("TelegraphLight").light_energy, 0.0, 0.001,
		"the telegraph goes dark once the dash ends")


func _test_ranged(ctx) -> void:
	ctx.begin_suite("enemies/ranged")
	var main: Node = await _begin(ctx)
	var player: Node = main.get_node("Player")
	var enemy: Node = await _spawn(ctx, Vector3(0, 0, -7), RANGED)
	await ctx.step(2)

	ctx.check(bool(enemy.get("_aiming")), "a ranged enemy at 7 m starts aiming")
	ctx.check_near(enemy.get_node("TelegraphLight").light_energy, 5.0, 0.001,
		"the aim windup lights the telegraph")
	ctx.check_near(enemy.get_node("MeshInstance3D").scale.x, 1.18, 0.001,
		"the aim inflates the body as a tell")
	ctx.check_near(Vector2(enemy.velocity.x, enemy.velocity.z).length(), 0.0, 0.01,
		"the ranged enemy holds its ground inside the firing band")

	var fired: bool = await ctx.step_until(
		func() -> bool: return float(enemy.get("_attack_timer")) > 2.0, 60)
	ctx.check(fired, "the aim resolves into a shot after the 0.45 s windup")
	ctx.check_eq(ctx.tree.get_nodes_in_group("enemy_projectiles").size(), 1,
		"exactly one projectile is in flight")
	ctx.check_near(enemy.get("_attack_timer"), 2.5, 0.1,
		"firing sets the 2.5 s ranged cooldown")
	ctx.check(not bool(enemy.get("_aiming")), "the aim state clears once the shot is away")

	var hit: bool = await ctx.step_until(func() -> bool: return player.hp < 100, 60)
	ctx.check(hit, "the projectile reaches the player")
	ctx.check_eq(int(player.hp), 90, "the projectile deals 10 damage")

	main = await _begin(ctx)
	player = main.get_node("Player")
	var crowded: Node = await _spawn(ctx, Vector3(0, 0, -3), RANGED)
	crowded.call("_aggro", player)
	await ctx.step(2)
	var start_distance: float = crowded.global_position.distance_to(player.global_position)
	ctx.check(not bool(crowded.get("_aiming")), "a ranged enemy inside 5 m does not aim")
	ctx.check_eq(ctx.tree.get_nodes_in_group("enemy_projectiles").size(), 0,
		"it does not shoot while crowded")

	var backed_off: bool = await ctx.step_until(func() -> bool:
		return crowded.global_position.distance_to(player.global_position) >= 5.0, 90)
	var end_distance: float = crowded.global_position.distance_to(player.global_position)
	ctx.check(backed_off,
		"a ranged enemy inside 5 m retreats (%.2f m -> %.2f m)" % [start_distance, end_distance])
	ctx.check(end_distance < 6.5,
		"it stops at the edge of the firing band instead of running away (%.2f m)" % end_distance)


func _test_deaggro(ctx) -> void:
	ctx.begin_suite("enemies/deaggro")
	var main: Node = await _begin(ctx)
	var player: Node = main.get_node("Player")
	var enemy: Node = await _spawn(ctx, Vector3(0, 0, -5), MELEE)
	await ctx.step(10)
	ctx.check_eq(int(enemy.get("state")), 1, "enemy is chasing before the test")

	enemy.global_position = Vector3(0, 0, -25)
	enemy.set("_escape_timer", 4.9)
	await ctx.step(20)
	ctx.check_eq(int(enemy.get("state")), 0, "an enemy 20 m+ away for 5 s returns to IDLE")
	ctx.check(enemy.get("player") == null, "the de-aggroed enemy drops its target")
	ctx.check_near(Vector2(enemy.velocity.x, enemy.velocity.z).length(), 0.0, 0.01,
		"a de-aggroed enemy stops moving")

	await _begin(ctx)
	var close: Node = await _spawn(ctx, Vector3(0, 0, -5), MELEE)
	await ctx.step(10)
	close.set("_escape_timer", 6.0)
	await ctx.step(10)
	ctx.check_eq(int(close.get("state")), 1, "a nearby enemy never de-aggroes from the timer")


func _test_damage_and_death(ctx) -> void:
	ctx.begin_suite("enemies/death")
	var main: Node = await _begin(ctx)
	var player: Node = main.get_node("Player")
	var enemy: Node = await _spawn(ctx, Vector3(0, 0, -20), MELEE)
	var deaths := RECORDER.new()
	enemy.died.connect(func() -> void: deaths.hit())

	enemy.call("take_damage", 30)
	ctx.check_eq(int(enemy.hp), 70, "damage reduces hp")
	ctx.check_eq(int(enemy.get("state")), 1, "being shot aggroes the enemy even at 20 m")
	ctx.check(enemy.get("player") == player, "the shooter group becomes the target")

	ctx.check(_color_is(enemy.get("_material").albedo_color, Color(1, 1, 1)),
		"a hit flashes the body white")
	await ctx.step(15)
	ctx.check(_color_is(enemy.get("_material").albedo_color, BASE_COLOR),
		"the hit flash decays back to the role colour")

	enemy.call("take_damage", 999)
	ctx.check_eq(deaths.value, 1, "a lethal hit emits died once")
	ctx.check(bool(enemy.get("_dying")), "the dying flag is set")
	ctx.check_eq(enemy.collision_layer, 0, "a dead enemy leaves the collision world")
	ctx.check(not enemy.is_physics_processing(), "a dead enemy stops simulating")

	enemy.call("take_damage", 999)
	ctx.check_eq(deaths.value, 1, "damage after death cannot re-trigger died")

	await ctx.step(20)
	ctx.check(not is_instance_valid(enemy), "the corpse is freed after the death delay")


func _color_is(actual: Color, expected: Color) -> bool:
	return absf(actual.r - expected.r) < 0.01 and absf(actual.g - expected.g) < 0.01 \
		and absf(actual.b - expected.b) < 0.01
