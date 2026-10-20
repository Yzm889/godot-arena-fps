extends RefCounted

const TOTAL_WAVES := 10
const KILL_SCORE := 100
const WAVE_CLEAR_SCORE := 250
const WAVE_AMMO_SUPPLY := 60
const FAST := 8.0

# Includes positions that coincide with SPAWN_POINTS, which is the adversarial
# case for the farthest-first selection.
const SPAWN_SPOTS := [
	Vector3(0, 0, 0), Vector3(0, 0, -9), Vector3(9, 0, 8), Vector3(-9, 0, 8),
	Vector3(0, 0, 10), Vector3(-9, 0, -9), Vector3(6, 0, -6), Vector3(-6, 0, 3),
	Vector3(3, 0, 6),
]


func run(ctx) -> void:
	await _test_composition_table(ctx)
	await _test_wave_advance(ctx)
	await _test_spawn_distance(ctx)
	await _test_full_run_victory(ctx)
	await _test_high_score(ctx)
	await _test_game_over_no_respawn(ctx)
	await _test_restart(ctx)
	ctx.mark_file_done("test_waves")


func _consts(ctx) -> Dictionary:
	return ctx.main.get_script().get_script_constant_map()


func _test_composition_table(ctx) -> void:
	ctx.begin_suite("waves/composition")
	var main: Node = await ctx.load_main()
	var table := _consts(ctx)
	var wave_table: Resource = table["WAVE_TABLE"]
	var compositions: Array = main.get("WAVE_COMPOSITIONS")

	ctx.check(wave_table != null and String(wave_table.resource_path) == "res://data/waves.tres",
		"the campaign table is loaded from data/waves.tres")
	ctx.check_eq(compositions, wave_table.waves, "WAVE_COMPOSITIONS is the resource array itself")
	ctx.check_eq(int(main.get("TOTAL_WAVES")), wave_table.waves.size(),
		"TOTAL_WAVES is derived from the resource length")
	ctx.check_eq(int(main.get("TOTAL_WAVES")), TOTAL_WAVES, "the run is 10 waves long")
	ctx.check_eq(compositions.size(), TOTAL_WAVES, "one composition per wave")
	ctx.check_eq(int(table["KILL_SCORE"]), KILL_SCORE, "kill score constant")
	ctx.check_eq(int(table["WAVE_CLEAR_SCORE"]), WAVE_CLEAR_SCORE, "wave clear score constant")
	ctx.check_eq(int(table["WAVE_AMMO_SUPPLY"]), WAVE_AMMO_SUPPLY, "per wave ammo supply")

	var total_enemies := 0
	for wave in range(compositions.size()):
		var entry: Array = compositions[wave]
		ctx.check_eq(entry.size(), 3, "wave %d lists melee, charger and ranged" % [wave + 1])
		var size := 0
		for amount in entry:
			size += int(amount)
			ctx.check(int(amount) >= 0, "wave %d has no negative counts" % [wave + 1])
		ctx.check(size > 0, "wave %d spawns at least one enemy" % [wave + 1])
		ctx.check(size >= 3, "wave %d never shrinks below 3 enemies" % [wave + 1])
		total_enemies += size

	ctx.check_eq(compositions[0], [3, 0, 0], "wave 1 is three plain melee")
	ctx.check(total_enemies >= 40, "the campaign fields a substantial roster (%d)" % total_enemies)

	ctx.check_eq(ctx.hud_text("WaveLabel"), "WAVE 1 / 10", "HUD opens on wave 1")
	ctx.check_eq(ctx.hud_text("EnemyLabel"), "Enemies: 3", "HUD shows three enemies for wave 1")
	var banner: Control = main.get_node("HUD/WaveBanner")
	ctx.check(not banner.visible, "no countdown banner during live combat")


func _kill_n(ctx, count: int) -> void:
	var enemies: Array = ctx.tree.get_nodes_in_group("enemies")
	for i in range(mini(count, enemies.size())):
		enemies[i].take_damage(9999)


func _test_wave_advance(ctx) -> void:
	ctx.begin_suite("waves/advance")
	var main: Node = await ctx.load_main()

	var player: Node = main.get_node("Player")
	var compositions: Array = ctx.main.get("WAVE_COMPOSITIONS")
	Engine.time_scale = FAST
	var reserve_before: int = player.reserve

	for wave in range(1, 4):
		var entry: Array = compositions[wave - 1]
		var size := 0
		for amount in entry:
			size += int(amount)
		ctx.check_eq(ctx.hud_text("WaveLabel"), "WAVE %d / 10" % wave,
			"HUD wave label for wave %d" % wave)
		ctx.check_eq(ctx.tree.get_nodes_in_group("enemies").size(), size,
			"wave %d spawned %d enemies" % [wave, size])
		ctx.check_eq(ctx.hud_text("EnemyLabel"), "Enemies: %d" % size,
			"HUD enemy counter matches wave %d" % wave)

		var roles := _role_counts(main)
		ctx.check_eq(roles[0], int(entry[0]), "wave %d melee count" % wave)
		ctx.check_eq(roles[1], int(entry[1]), "wave %d charger count" % wave)
		ctx.check_eq(roles[2], int(entry[2]), "wave %d ranged count" % wave)

		player.hp = 100000
		ctx.kill_enemies()
		var advanced: bool = await ctx.step_until(func() -> bool:
			return ctx.hud_text("WaveLabel") == "WAVE %d / 10" % (wave + 1), 200)
		ctx.check(advanced, "clearing wave %d advances to wave %d" % [wave, wave + 1])
	Engine.time_scale = 1.0

	ctx.check(player.reserve > reserve_before,
		"clearing waves topped up the reserve (%d -> %d)" % [reserve_before, player.reserve])
	var banner: Control = main.get_node("HUD/WaveBanner")
	ctx.check(not banner.visible, "the countdown banner is hidden once the wave starts")


func _test_spawn_distance(ctx) -> void:
	ctx.begin_suite("waves/spawn_distance")
	var main: Node = await ctx.load_main()
	var player: Node = main.get_node("Player")
	var min_distance: float = ctx.main.get("min_spawn_distance")

	Engine.time_scale = FAST
	var worst := 999.0
	for wave in range(1, TOTAL_WAVES):
		var spot: Vector3 = SPAWN_SPOTS[(wave - 1) % SPAWN_SPOTS.size()]
		player.global_position = spot
		player.hp = 100000
		var before: String = ctx.hud_text("WaveLabel")
		ctx.kill_enemies()
		var advanced: bool = await ctx.step_until(
			func() -> bool: return ctx.hud_text("WaveLabel") != before, 200)
		ctx.check(advanced, "wave %d advanced so its spawns could be measured" % wave)
		var nearest := _nearest_enemy_distance(ctx, player)
		ctx.check(nearest < 900.0,
			"wave %d actually produced enemies to measure" % wave)
		worst = minf(worst, nearest)
		ctx.check(nearest >= min_distance - 0.05,
			"wave %d nearest spawn %.2f m with the player at %s" % [wave, nearest, spot])
	Engine.time_scale = 1.0

	ctx.check(worst >= min_distance - 0.05,
		"no wave ever spawned closer than %.1f m (worst %.2f m)" % [min_distance, worst])
	ctx.check(worst > 9.0,
		"no spawn lands inside the charger commit range (worst %.2f m)" % worst)

	# Exercise the fallback branch: push the knob past every spawn point.
	player.global_position = Vector3.ZERO
	main.set("min_spawn_distance", 14.0)
	var fallback: Array = main.call("_spawn_positions", 3)
	ctx.check_eq(fallback.size(), 3, "the fallback still returns one position per enemy")
	ctx.check(player.global_position.distance_to(fallback[0]) > 12.0,
		"with nothing eligible at 14 m it falls back to the farthest point (%.2f m)"
			% player.global_position.distance_to(fallback[0]))
	main.set("min_spawn_distance", 11.0)


func _nearest_enemy_distance(ctx, player: Node) -> float:
	var nearest := 999.0
	var from := Vector2(player.global_position.x, player.global_position.z)
	for enemy in ctx.tree.get_nodes_in_group("enemies"):
		var to := Vector2(enemy.global_position.x, enemy.global_position.z)
		nearest = minf(nearest, from.distance_to(to))
	return nearest


func _test_full_run_victory(ctx) -> void:
	ctx.begin_suite("waves/victory")
	var main: Node = await ctx.load_main()

	var player: Node = main.get_node("Player")
	var compositions: Array = ctx.main.get("WAVE_COMPOSITIONS")
	var expected_kills := 0
	Engine.time_scale = FAST

	for wave in range(1, TOTAL_WAVES + 1):
		var entry: Array = compositions[wave - 1]
		var size := 0
		for amount in entry:
			size += int(amount)
		expected_kills += size
		var label := "WAVE %d / 10" % wave
		var reached: bool = await ctx.step_until(func() -> bool:
			return ctx.hud_text("WaveLabel") == label, 200)
		ctx.check(reached, "reached %s" % label)
		player.hp = 100000
		ctx.kill_enemies()
	Engine.time_scale = 1.0

	ctx.check(bool(main.get("_finished")), "the run finishes after wave 10")
	var panel: Control = main.get_node("HUD/EndPanel")
	ctx.check(panel.visible, "the results panel is shown on victory")
	ctx.check_eq(ctx.hud_text("EndPanel/CenterContainer/VBoxContainer/TitleLabel"), "VICTORY",
		"the end title reads VICTORY")

	var stats: String = ctx.hud_text("EndPanel/CenterContainer/VBoxContainer/StatsLabel")
	ctx.check(stats.contains("KILLS  %d" % expected_kills),
		"results report every kill of the campaign (%d)" % expected_kills)
	ctx.check(stats.contains("WAVES SURVIVED  10 / 10"), "results report all 10 waves survived")
	var expected_score := expected_kills * KILL_SCORE + TOTAL_WAVES * WAVE_CLEAR_SCORE
	ctx.check(stats.contains("SCORE  %d" % expected_score),
		"score is kills*100 + waves*250 = %d" % expected_score)
	ctx.check(stats.contains("ACCURACY"), "results report accuracy")
	ctx.check(ctx.tree.paused, "the tree is paused at the end of the run")


func _test_high_score(ctx) -> void:
	ctx.begin_suite("waves/high_score")
	await ctx.load_main()
	ctx.delete_high_score()
	await ctx.unload_main()

	ctx.check_eq(ctx.read_high_score(), -1, "no saved score before the run")

	var main: Node = await ctx.load_main()
	var player: Node = main.get_node("Player")
	_kill_n(ctx, 2)
	await ctx.step(2)
	player.call("take_damage", 9999)
	await ctx.step(2)
	var score := 2 * KILL_SCORE
	ctx.check_eq(ctx.read_high_score(), score,
		"the first finished run saves its score (%d)" % score)
	var stats: String = ctx.hud_text("EndPanel/CenterContainer/VBoxContainer/StatsLabel")
	ctx.check(stats.contains("KILLS  2"), "results count only the kills actually made")
	ctx.check(stats.contains("BEST  %d" % score), "results show the new best")
	ctx.check(stats.contains("NEW BEST"), "results flag the record as new")
	ctx.check(ctx.tree.paused, "tree left paused by the game over")
	ctx.tree.paused = false

	ctx.delete_high_score()
	ctx.write_high_score(5000)
	await ctx.unload_main()
	main = await ctx.load_main()
	player = main.get_node("Player")
	_kill_n(ctx, 2)
	await ctx.step(2)
	player.call("take_damage", 9999)
	await ctx.step(2)
	ctx.check_eq(ctx.read_high_score(), 5000, "a lower score never overwrites the saved best")
	stats = ctx.hud_text("EndPanel/CenterContainer/VBoxContainer/StatsLabel")
	ctx.check(stats.contains("BEST  5000"), "results still display the stored best")
	ctx.check(not stats.contains("NEW BEST"), "a lower score is not flagged as new")


func _test_game_over_no_respawn(ctx) -> void:
	ctx.begin_suite("waves/game_over")
	var main: Node = await ctx.load_main()
	var player: Node = main.get_node("Player")

	player.call("take_damage", 9999)
	await ctx.step(3)
	ctx.check(bool(main.get("_finished")), "death finishes the run immediately")
	ctx.check_eq(ctx.hud_text("EndPanel/CenterContainer/VBoxContainer/TitleLabel"), "GAME OVER",
		"the end title reads GAME OVER")
	ctx.check(main.get_node("HUD/EndPanel").visible, "the results panel opens on death")
	ctx.check(not player.is_physics_processing(), "the dead player is not simulated")
	ctx.check_eq(int(player.hp), 0, "hp is not restored")

	var enemies_after_death: int = ctx.tree.get_nodes_in_group("enemies").size()
	await ctx.step(120)
	ctx.check_eq(int(player.hp), 0, "no respawn heals the player over 2 s of waiting")
	ctx.check(not player.is_physics_processing(), "the player never comes back on its own")
	ctx.check_eq(ctx.tree.get_nodes_in_group("enemies").size(), enemies_after_death,
		"no new wave spawns after death")
	ctx.check(ctx.tree.paused, "the game stays paused awaiting a manual restart")


func _test_restart(ctx) -> void:
	ctx.begin_suite("waves/restart")
	ctx.tree.paused = false
	ctx.unload_main()
	ctx.tree.change_scene_to_file("res://main.tscn")
	var attached: bool = await ctx.step_until(
		func() -> bool: return ctx.tree.current_scene != null, 120)
	ctx.check(attached, "the main scene can be loaded as the current scene")
	if not attached:
		return

	var first: Node = ctx.tree.current_scene
	var first_id: int = first.get_instance_id()
	ctx.tree.paused = false
	var player: Node = first.get_node("Player")
	player.call("take_damage", 9999)
	await ctx.step(3)
	ctx.check(ctx.tree.paused, "the run is paused on the results screen")

	var button: Button = first.get_node("HUD/EndPanel/CenterContainer/VBoxContainer/RestartButton")
	ctx.check(button.pressed.get_connections().size() > 0,
		"the restart button is wired to a handler")
	button.emit_signal("pressed")

	var reloaded: bool = await ctx.step_until(func() -> bool:
		var scene: Node = ctx.tree.current_scene
		return scene != null and scene.get_instance_id() != first_id, 120)
	ctx.check(reloaded, "pressing restart reloads the main scene")
	if not reloaded:
		return

	var second: Node = ctx.tree.current_scene
	ctx.check(second.get_instance_id() != first_id, "restart builds a fresh scene instance")
	ctx.check_eq(int(second.get_node("Player").hp), 100, "restart restores full health")
	ctx.check_eq(int(second.get_node("Player").ammo), 40, "restart refills the magazine")
	ctx.check_eq(int(second.get_node("Player").reserve), 120, "restart resets the reserve")
	ctx.check_eq(_hud_text_of(second, "WaveLabel"), "WAVE 1 / 10", "restart returns to wave 1")
	ctx.check_eq(_hud_text_of(second, "EnemyLabel"), "Enemies: 3", "restart respawns wave 1")
	ctx.check(not second.get_node("HUD/EndPanel").visible, "restart hides the results panel")
	ctx.check(not ctx.tree.paused, "restart unpauses the tree")

	ctx.tree.paused = false
	ctx.tree.unload_current_scene()


func _hud_text_of(node_root: Node, path: String) -> String:
	var label: Node = node_root.get_node_or_null("HUD/" + path)
	return "" if label == null else label.text


func _role_counts(main: Node) -> Array[int]:
	var counts: Array[int] = [0, 0, 0]
	for enemy in main.get_tree().get_nodes_in_group("enemies"):
		counts[int(enemy.get("role"))] += 1
	return counts
