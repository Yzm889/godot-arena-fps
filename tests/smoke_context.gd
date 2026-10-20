extends RefCounted

const HIGH_SCORE_PATH := "user://highscore.cfg"
const MAIN_SCENE := "res://main.tscn"
const FIRE_SEAM_SCRIPT := "res://tests/stub_fire_player.gd"

var tree: SceneTree
var main: Node
var suite_name := "unknown"
var passed := 0
var failed := 0
var failures: Array[String] = []
var suite_order: Array[String] = []
var suite_passed := {}
var suite_failed := {}
var finished_files: Array[String] = []

var _had_high_score := false
var _saved_high_score: PackedByteArray = PackedByteArray()
var _user_entry_names: Array[String] = []
var _guard_active := false


func configure(p_tree: SceneTree) -> void:
	tree = p_tree


func begin_suite(name: String) -> void:
	suite_name = name
	if not suite_passed.has(name):
		suite_order.append(name)
		suite_passed[name] = 0
		suite_failed[name] = 0


func mark_file_done(label: String) -> void:
	finished_files.append(label)


func check(ok: bool, label: String) -> bool:
	if ok:
		passed += 1
		suite_passed[suite_name] = int(suite_passed[suite_name]) + 1
	else:
		failed += 1
		suite_failed[suite_name] = int(suite_failed[suite_name]) + 1
		failures.append("%s::%s" % [suite_name, label])
	return ok


func check_eq(actual, expected, label: String) -> bool:
	return check(actual == expected, "%s (got %s, want %s)" % [label, actual, expected])


func check_near(actual: float, expected: float, tolerance: float, label: String) -> bool:
	return check(
		absf(actual - expected) <= tolerance,
		"%s (got %.4f, want %.4f +/-%.4f)" % [label, actual, expected, tolerance]
	)


func check_in_range(actual: float, low: float, high: float, label: String) -> bool:
	return check(
		actual >= low and actual <= high,
		"%s (got %.4f, want %.4f..%.4f)" % [label, actual, low, high]
	)


func step(ticks: int) -> void:
	for _i in ticks:
		await tree.physics_frame


func step_until(condition: Callable, max_ticks: int) -> bool:
	for _i in max_ticks:
		await tree.physics_frame
		if condition.call():
			return true
	return false


func load_main() -> Node:
	unload_main()
	Engine.time_scale = 1.0
	main = load(MAIN_SCENE).instantiate()
	tree.root.add_child(main)
	await tree.process_frame
	await tree.physics_frame
	return main


func unload_main() -> void:
	if main != null and is_instance_valid(main):
		tree.paused = false
		main.free()
	main = null


func get_node(path: String) -> Node:
	return main.get_node_or_null(path)


func remove_enemies() -> void:
	for enemy in tree.get_nodes_in_group("enemies"):
		enemy.free()
	await tree.physics_frame


func kill_enemies() -> void:
	for enemy in tree.get_nodes_in_group("enemies"):
		enemy.take_damage(9999)


func install_fire_seam() -> Node:
	var player: Node = main.get_node("Player")
	player.set_script(load(FIRE_SEAM_SCRIPT))
	player.call("_ready")
	return player


func hud_text(path: String) -> String:
	var label: Node = main.get_node_or_null("HUD/" + path)
	return "" if label == null else label.text


func guard_user_dir() -> void:
	_user_entry_names = list_user_entries()
	_had_high_score = FileAccess.file_exists(HIGH_SCORE_PATH)
	_saved_high_score = _read_high_score_bytes()
	delete_high_score()
	_guard_active = true


func release_user_guard() -> void:
	if not _guard_active:
		return

	var absolute := ProjectSettings.globalize_path(HIGH_SCORE_PATH)
	if _had_high_score:
		var file := FileAccess.open(absolute, FileAccess.WRITE)
		if file:
			file.store_buffer(_saved_high_score)
	else:
		delete_high_score()
	_guard_active = false


func delete_high_score() -> void:
	if FileAccess.file_exists(HIGH_SCORE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(HIGH_SCORE_PATH))


func write_high_score(score: int) -> void:
	var config := ConfigFile.new()
	config.set_value("score", "best", score)
	config.save(HIGH_SCORE_PATH)


func read_high_score() -> int:
	var config := ConfigFile.new()
	if config.load(HIGH_SCORE_PATH) != OK:
		return -1
	return int(config.get_value("score", "best", -1))


func list_user_entries() -> Array[String]:
	var names: Array[String] = []
	var dir := DirAccess.open("user://")
	if dir:
		dir.list_dir_begin()
		var entry := dir.get_next()
		while entry != "":
			names.append(entry)
			entry = dir.get_next()
		dir.list_dir_end()
	names.sort()
	return names


func verify_user_dir_restored() -> void:
	begin_suite("harness/user_dir")
	release_user_guard()
	var entries_after := list_user_entries()
	check_eq(entries_after, _user_entry_names,
		"user:// entry set unchanged (after=%s before=%s)" % [entries_after, _user_entry_names])
	check_eq(FileAccess.file_exists(HIGH_SCORE_PATH), _had_high_score,
		"user://highscore.cfg presence unchanged")
	check_eq(_read_high_score_bytes(), _saved_high_score,
		"user://highscore.cfg bytes unchanged")


func _read_high_score_bytes() -> PackedByteArray:
	if not FileAccess.file_exists(HIGH_SCORE_PATH):
		return PackedByteArray()
	var file := FileAccess.open(HIGH_SCORE_PATH, FileAccess.READ)
	if file == null:
		return PackedByteArray()
	return file.get_buffer(file.get_length())
