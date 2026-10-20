extends CharacterBody3D

const HIT_EFFECT_SCENE := preload("res://hit_effect.tscn")
const LIFETIME := 3.0

var speed := 14.0
var damage := 10
var direction := Vector3.FORWARD
var _life := LIFETIME
var _spent := false


func setup(new_direction: Vector3, new_damage: int) -> void:
	direction = new_direction.normalized()
	damage = new_damage


func _physics_process(delta: float) -> void:
	if _spent:
		return

	_life -= delta
	if _life <= 0.0:
		queue_free()
		return

	var collision := move_and_collide(direction * speed * delta)
	if collision == null:
		return

	_spent = true
	var collider := collision.get_collider()
	if collider and collider.is_in_group("player") and collider.has_method("take_damage"):
		collider.take_damage(damage)
	_spawn_impact(collision.get_position())
	queue_free()


func _spawn_impact(point: Vector3) -> void:
	var effect := HIT_EFFECT_SCENE.instantiate() as Node3D
	get_parent().add_child(effect)
	effect.global_position = point
