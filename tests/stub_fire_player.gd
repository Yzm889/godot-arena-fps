extends "res://player.gd"

# Headless has no window, so Input.mouse_mode never becomes CAPTURED and
# Input.is_mouse_button_pressed() is always false. This seam replaces only that
# engine-level query; the real _physics_process polling and shoot() cooldown
# path stay untouched.
var force_wants_fire := false


func _wants_fire() -> bool:
	return force_wants_fire
