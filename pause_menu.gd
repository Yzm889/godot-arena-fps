extends CanvasLayer

@onready var _root: Control = $Root
@onready var _resume_button: Button = $Root/CenterContainer/VBoxContainer/ResumeButton
@onready var _restart_button: Button = $Root/CenterContainer/VBoxContainer/RestartButton
@onready var _quit_button: Button = $Root/CenterContainer/VBoxContainer/QuitButton

var _locked := false


func _ready() -> void:
	_root.visible = false
	_resume_button.pressed.connect(_on_resume_pressed)
	_restart_button.pressed.connect(_on_restart_pressed)
	_quit_button.pressed.connect(_on_quit_pressed)


func _unhandled_input(event: InputEvent) -> void:
	if _locked or not event.is_action_pressed("ui_cancel"):
		return

	if is_open():
		close()
	else:
		open()
	get_viewport().set_input_as_handled()


func is_open() -> bool:
	return _root.visible


func lock() -> void:
	_locked = true


func open() -> void:
	if _locked or is_open() or get_tree().paused:
		return

	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_root.visible = true
	_resume_button.grab_focus()


func close() -> void:
	if not is_open():
		return

	_root.visible = false
	_resume_button.release_focus()
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _on_resume_pressed() -> void:
	close()


func _on_restart_pressed() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()


func _on_quit_pressed() -> void:
	get_tree().quit()
