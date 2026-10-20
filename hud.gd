extends CanvasLayer

const DAMAGE_FLASH_ALPHA := 0.5
const LOW_AMMO_THRESHOLD := 5
const AMMO_COLOR := Color(1, 1, 1, 1)
const LOW_AMMO_COLOR := Color(1, 0.25, 0.2, 1)
const VICTORY_COLOR := Color(1, 0.85, 0.3, 1)
const DEFEAT_COLOR := Color(1, 0.4, 0.35, 1)

@onready var _health_bar: ProgressBar = $HealthBar
@onready var _hp_text: Label = $HealthBar/HPText
@onready var _enemy_label: Label = $EnemyLabel
@onready var _ammo_label: Label = $AmmoLabel
@onready var _wave_label: Label = $WaveLabel
@onready var _wave_banner: Label = $WaveBanner
@onready var _reload_label: Label = $ReloadLabel
@onready var _flash: ColorRect = $DamageFlash
@onready var _crosshair = $Crosshair
@onready var _end_panel: Control = $EndPanel
@onready var _title_label: Label = $EndPanel/CenterContainer/VBoxContainer/TitleLabel
@onready var _stats_label: Label = $EndPanel/CenterContainer/VBoxContainer/StatsLabel
@onready var _restart_button: Button = $EndPanel/CenterContainer/VBoxContainer/RestartButton

var _last_hp := -1
var _flash_tween: Tween


func _ready() -> void:
	_flash.modulate.a = 0.0
	_restart_button.pressed.connect(_on_restart_pressed)


func update_health(current: int, max_hp: int) -> void:
	_health_bar.max_value = max_hp
	_health_bar.value = current
	_hp_text.text = "HP %d / %d" % [current, max_hp]

	if _last_hp > current:
		_flash_damage()
	_last_hp = current


func update_enemies(remaining: int) -> void:
	_enemy_label.text = "Enemies: %d" % remaining


func update_ammo(current: int, _mag_size: int, reserve: int) -> void:
	_ammo_label.text = "%d / %d" % [current, reserve]
	var color := LOW_AMMO_COLOR if current <= LOW_AMMO_THRESHOLD else AMMO_COLOR
	_ammo_label.add_theme_color_override("font_color", color)


func update_wave(wave: int, total: int) -> void:
	_wave_label.text = "WAVE %d / %d" % [wave, total]


func show_wave_countdown(next_wave: int, total: int, seconds_left: int) -> void:
	_wave_banner.text = "WAVE %d / %d - IN %d" % [next_wave, total, seconds_left]
	_wave_banner.visible = true


func hide_wave_banner() -> void:
	_wave_banner.visible = false


func set_reloading(reloading: bool) -> void:
	_reload_label.visible = reloading


func show_hit_marker() -> void:
	_crosshair.flash_hit()


func kick_crosshair() -> void:
	_crosshair.kick()


func set_crosshair_spread(movement: float, fire: float) -> void:
	_crosshair.set_spread(movement, fire)


func show_end(title: String, stats: Dictionary) -> void:
	var shots: int = stats["shots"]
	var hits: int = stats["hits"]
	var accuracy := 0.0 if shots == 0 else float(hits) / float(shots) * 100.0
	var new_best := "  (NEW BEST)" if stats["new_best"] else ""

	_title_label.text = title
	var title_color := VICTORY_COLOR if title == "VICTORY" else DEFEAT_COLOR
	_title_label.add_theme_color_override("font_color", title_color)
	_stats_label.text = "KILLS  %d\nACCURACY  %.0f%%  (%d/%d)\nWAVES SURVIVED  %d / %d\nSCORE  %d\nBEST  %d%s" % [
		stats["kills"], accuracy, hits, shots,
		stats["waves"], stats["total_waves"],
		stats["score"], stats["best"], new_best,
	]

	_end_panel.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _flash_damage() -> void:
	if _flash_tween and _flash_tween.is_valid():
		_flash_tween.kill()
	_flash.modulate.a = DAMAGE_FLASH_ALPHA
	_flash_tween = create_tween()
	_flash_tween.tween_property(_flash, "modulate:a", 0.0, 0.35)


func _on_restart_pressed() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()
