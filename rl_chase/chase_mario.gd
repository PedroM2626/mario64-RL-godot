extends RLMario
class_name ChaseMario

@export var tint_color := Color(1, 1, 1, 1)

func apply_tint() -> void:
	# Add a slight delay to ensure mesh instance is fully ready by SM64 wrapper
	await get_tree().process_frame
	for child in get_children():
		if child is MeshInstance3D:
			var mat = StandardMaterial3D.new()
			mat.albedo_color = tint_color
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			child.material_overlay = mat
