extends RLMario
class_name BrawlMario

@export var team_color := Color(1, 1, 1, 1)
@export var team_texture: Texture2D

func apply_team_appearance() -> void:
	# Delay to ensure mesh instance is ready
	await get_tree().process_frame
	for child in get_children():
		if child is MeshInstance3D:
			var mat = StandardMaterial3D.new()
			mat.albedo_color = team_color
			if team_texture:
				mat.albedo_texture = team_texture
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			child.material_overlay = mat
