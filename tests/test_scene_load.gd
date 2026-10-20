extends RefCounted

const NODE_SPEC := [
	["Player", "CharacterBody3D"],
	["Player/CollisionShape3D", "CollisionShape3D"],
	["Player/Camera3D", "Camera3D"],
	["Player/Camera3D/RayCast3D", "RayCast3D"],
	["Player/Camera3D/Weapon", "Node3D"],
	["Player/Camera3D/Weapon/Receiver", "MeshInstance3D"],
	["Player/Camera3D/Weapon/Barrel", "MeshInstance3D"],
	["Player/Camera3D/Weapon/Grip", "MeshInstance3D"],
	["Player/Camera3D/Weapon/Magazine", "MeshInstance3D"],
	["Player/Camera3D/Weapon/Sight", "MeshInstance3D"],
	["Player/Camera3D/Weapon/Muzzle", "Node3D"],
	["Player/Camera3D/Weapon/Muzzle/MuzzleFlash", "OmniLight3D"],
	["Player/Camera3D/Weapon/Muzzle/FlashMesh", "MeshInstance3D"],
	["Player/ShootSound", "AudioStreamPlayer"],
	["Player/HurtSound", "AudioStreamPlayer"],
	["Player/DeathSound", "AudioStreamPlayer"],
	["Arena", "Node3D"],
	["Arena/WorldEnvironment", "WorldEnvironment"],
	["Arena/DirectionalLight3D", "DirectionalLight3D"],
	["Arena/Ground", "StaticBody3D"],
	["Arena/Walls", "StaticBody3D"],
	["Arena/Cover", "StaticBody3D"],
	["Arena/Platform", "StaticBody3D"],
	["Navigation", "NavigationRegion3D"],
	["HUD", "CanvasLayer"],
	["HUD/HealthBar", "ProgressBar"],
	["HUD/HealthBar/HPText", "Label"],
	["HUD/EnemyLabel", "Label"],
	["HUD/AmmoLabel", "Label"],
	["HUD/WaveLabel", "Label"],
	["HUD/WaveBanner", "Label"],
	["HUD/ReloadLabel", "Label"],
	["HUD/Crosshair", "Control"],
	["HUD/DamageFlash", "ColorRect"],
	["HUD/EndPanel", "Control"],
	["HUD/EndPanel/CenterContainer/VBoxContainer/TitleLabel", "Label"],
	["HUD/EndPanel/CenterContainer/VBoxContainer/StatsLabel", "Label"],
	["HUD/EndPanel/CenterContainer/VBoxContainer/RestartButton", "Button"],
	["PauseMenu", "CanvasLayer"],
	["PauseMenu/Root/CenterContainer/VBoxContainer/ResumeButton", "Button"],
	["PauseMenu/Root/CenterContainer/VBoxContainer/RestartButton", "Button"],
	["PauseMenu/Root/CenterContainer/VBoxContainer/QuitButton", "Button"],
]

const ENEMY_NODE_SPEC := [
	["CollisionShape3D", "CollisionShape3D"],
	["MeshInstance3D", "MeshInstance3D"],
	["SpawnHalo", "MeshInstance3D"],
	["DetectionArea", "Area3D"],
	["DetectionArea/CollisionShape3D", "CollisionShape3D"],
	["NavigationAgent3D", "NavigationAgent3D"],
	["TelegraphLight", "OmniLight3D"],
	["HitSound", "AudioStreamPlayer3D"],
	["ShotSound", "AudioStreamPlayer3D"],
]


func run(ctx) -> void:
	await _test_project_config(ctx)
	await _test_main_structure(ctx)
	await _test_collision_layers(ctx)
	await _test_groups(ctx)
	ctx.mark_file_done("test_scene_load")


func _test_project_config(ctx) -> void:
	ctx.begin_suite("scene_load/config")
	ctx.check_eq(String(ProjectSettings.get_setting("application/run/main_scene")),
		"res://main.tscn", "project main scene is main.tscn")
	ctx.check_eq(String(ProjectSettings.get_setting("physics/3d/physics_engine")),
		"Jolt Physics", "3d physics engine is Jolt")
	for layer_index in range(1, 5):
		var key := "layer_names/3d_physics/layer_%d" % layer_index
		ctx.check(ProjectSettings.get_setting(key) != null, "layer %d has a name" % layer_index)
	for action in ["move_forward", "move_back", "move_left", "move_right", "reload"]:
		ctx.check(InputMap.has_action(action), "input action exists: %s" % action)


func _test_main_structure(ctx) -> void:
	ctx.begin_suite("scene_load/structure")
	var main: Node = await ctx.load_main()
	ctx.check(main != null, "main.tscn instantiates")
	ctx.check_eq(main.get_class(), "Node3D", "Main root is a Node3D")

	for spec in NODE_SPEC:
		var path := String(spec[0])
		var expected := String(spec[1])
		var node: Node = main.get_node_or_null(path)
		ctx.check(node != null, "node present: %s" % path)
		if node:
			ctx.check_eq(node.get_class(), expected, "node class: %s" % path)

	var enemy: Node = main.get_node_or_null("Enemy")
	ctx.check(enemy != null, "pre-placed Enemy present")
	if enemy:
		for spec in ENEMY_NODE_SPEC:
			var path := String(spec[0])
			var node: Node = enemy.get_node_or_null(path)
			ctx.check(node != null, "enemy node present: %s" % path)
			if node:
				ctx.check_eq(node.get_class(), String(spec[1]), "enemy node class: %s" % path)

	ctx.check_eq(main.get_node_or_null("Player").rotation.x, 0.0,
		"player body has no pitch rotation (pitch lives on the camera)")
	await ctx.unload_main()


func _test_collision_layers(ctx) -> void:
	ctx.begin_suite("scene_load/collision")
	var main: Node = await ctx.load_main()

	var player: Node = main.get_node("Player")
	ctx.check_eq(player.collision_layer, 2, "Player collision layer is World|Player bit (2)")
	ctx.check_eq(player.collision_mask, 5, "Player mask covers World+Enemy (5)")

	var ray: RayCast3D = main.get_node("Player/Camera3D/RayCast3D")
	ctx.check_eq(ray.collision_mask, 5, "hitscan RayCast3D mask is 5")
	ctx.check(ray.enabled, "hitscan RayCast3D is enabled")
	ctx.check_near(ray.target_position.length(), 50.0, 0.001, "hitscan ray length is 50 m")

	var enemy: Node = main.get_node("Enemy")
	ctx.check_eq(enemy.collision_layer, 4, "Enemy body layer bit is 4")
	ctx.check_eq(enemy.collision_mask, 7, "Enemy body mask is 7")

	var detection: Area3D = enemy.get_node("DetectionArea")
	ctx.check_eq(detection.collision_layer, 0, "DetectionArea layer is 0 (detects only)")
	ctx.check_eq(detection.collision_mask, 2, "DetectionArea mask is Player (2)")
	ctx.check(detection.monitoring, "DetectionArea is monitoring")

	var projectile_scene: PackedScene = load("res://enemy_projectile.tscn")
	var projectile: Node = projectile_scene.instantiate()
	main.add_child(projectile)
	ctx.check_eq(projectile.collision_layer, 8, "Enemy projectile layer is 8")
	ctx.check_eq(projectile.collision_mask, 3, "Enemy projectile mask is World+Player (3)")
	projectile.free()

	await ctx.unload_main()


func _test_groups(ctx) -> void:
	ctx.begin_suite("scene_load/groups")
	var main: Node = await ctx.load_main()

	ctx.check(main.get_node("Player").is_in_group("player"), "Player is in group player")
	var placed: Array = ctx.tree.get_nodes_in_group("enemies")
	ctx.check_eq(placed.size(), 3, "three enemies pre-placed for wave 1")
	for enemy in placed:
		ctx.check(enemy.is_in_group("enemies"), "enemy registered in group enemies")
		ctx.check_eq(int(enemy.get("role")), 0, "pre-placed enemy role is MELEE")
	ctx.check(main.get_node("Arena").is_in_group("navmesh_source"),
		"Arena is the navmesh source group")

	await ctx.unload_main()
