extends SceneTree

const SUITES := [
	"res://tests/test_scene_load.gd",
	"res://tests/test_player.gd",
	"res://tests/test_enemies.gd",
	"res://tests/test_waves.gd",
]
const WATCHDOG_SECONDS := 240.0

# The suite is 517 checks. If a nested test function dies from a runtime error the
# awaiting run() still resumes and marks its file done, so checks silently vanish
# while everything that did run passes. Comparing against this number turns that
# into a loud failure; bump it deliberately whenever cases are added or removed.
const EXPECTED_CHECKS := 543

var _ctx
var _timed_out := false


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	print("=== arena demo smoke tests ===")
	_ctx = load("res://tests/smoke_context.gd").new()
	_ctx.configure(self)
	_ctx.guard_user_dir()

	create_timer(WATCHDOG_SECONDS, false).timeout.connect(_on_watchdog)
	var started := Time.get_ticks_msec()

	for path in SUITES:
		var label := String(path).get_file().get_basename()
		print("-- %s" % label)
		var script: GDScript = load(path)
		if script == null or not script.can_instantiate():
			_ctx.begin_suite(label)
			_ctx.check(false, "suite script failed to compile: %s" % path)
			continue
		var suite = script.new()
		await suite.run(_ctx)
		if _timed_out:
			return
		if not _ctx.finished_files.has(label):
			_ctx.begin_suite(label)
			_ctx.check(false, "suite aborted before finishing (a runtime error stopped it silently)")

	_ctx.unload_main()
	_ctx.verify_user_dir_restored()

	var ran: int = _ctx.passed + _ctx.failed
	if ran != EXPECTED_CHECKS:
		_ctx.begin_suite("harness/coverage")
		_ctx.check(false, "expected %d checks but ran %d - either a test function aborted part-way, or EXPECTED_CHECKS needs a deliberate update" % [
			EXPECTED_CHECKS, ran])

	var elapsed := float(Time.get_ticks_msec() - started) / 1000.0
	print("")
	for name in _ctx.suite_order:
		var ok_count := int(_ctx.suite_passed[name])
		var bad_count := int(_ctx.suite_failed[name])
		var mark := "ok  " if bad_count == 0 else "FAIL"
		print("  [%s] %-28s %3d/%3d" % [mark, name, ok_count, ok_count + bad_count])

	if _ctx.failed > 0:
		print("")
		print("failures:")
		for line in _ctx.failures:
			print("  - ", line)

	print("")
	print("%d passed, %d failed, %d total in %.2f s" % [
		_ctx.passed, _ctx.failed, _ctx.passed + _ctx.failed, elapsed])
	print("RESULT: %s" % ("PASS" if _ctx.failed == 0 and not _timed_out else "FAIL"))
	quit(1 if (_ctx.failed > 0 or _timed_out) else 0)


func _on_watchdog() -> void:
	_timed_out = true
	# Quitting here would otherwise strand user:// with whatever scratch value the
	# high score suite last wrote, clobbering a real player save.
	if _ctx != null:
		_ctx.release_user_guard()
	print("RESULT: FAIL (watchdog fired after %s s - a suite never finished)" % WATCHDOG_SECONDS)
	quit(1)
