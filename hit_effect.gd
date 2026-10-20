extends MeshInstance3D

const LIFETIME := 0.15


func _ready() -> void:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(1.0, 0.8, 0.25, 1.0)
	material_override = material

	var tween := create_tween().set_parallel(true)
	tween.tween_property(self, "scale", Vector3(2.5, 2.5, 2.5), LIFETIME)
	tween.tween_property(material, "albedo_color:a", 0.0, LIFETIME)
	tween.finished.connect(queue_free)
