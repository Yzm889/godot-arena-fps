extends Resource

@export var display_name := ""
@export var damage := 25
@export var pellet_count := 1
@export var fire_interval := 0.12
@export var reload_time := 1.0
@export var mag_size := 40
@export var base_spread_degrees := 0.0
@export_range(0.0, 1.0, 0.05) var crosshair_spread := 0.0
@export var recoil_multiplier := 1.0
@export var sound_pitch := 1.0
@export var barrel_scale := Vector3.ONE
@export var hide_sight := false
