extends Node3D

const ParkourEnv = preload("res://rl_parkour/parkour_env.gd")
const SyncScript = preload("res://addons/godot_rl_agents/sync.gd")

@export var time_scale := 1.0
@export var num_envs := 4
@export var env_spacing := 20.0

var sync_node: Node
@onready var base_env: Node3D = $ParkourEnv

func _ready() -> void:
	Engine.time_scale = time_scale
	
	# Add Sync node
	sync_node = SyncScript.new()
	add_child(sync_node)
	
	# Attempt to load ROM
	var rom_path = "baserom.us.z64" # Assume it's in the root folder
	if FileAccess.file_exists("res://baserom.us.z64") and LibSM64Global.load_rom_file("res://baserom.us.z64"):
		if LibSM64Global.init():
			_setup_envs()
		else:
			push_error("Failed to init LibSM64")
	elif FileAccess.file_exists(rom_path) and LibSM64Global.load_rom_file(rom_path):
		if LibSM64Global.init():
			_setup_envs()
		else:
			push_error("Failed to init LibSM64")
	else:
		push_error("ROM not found at " + rom_path)

func _setup_envs() -> void:
	# We already have 1 in the tree (the one the user edits)
	base_env.env_index = 0
	base_env.position = Vector3(0, 0, 0)
	
	# 1. Duplicate and place all environments
	for i in range(1, num_envs):
		var env = base_env.duplicate()
		env.env_index = i
		var x = i * env_spacing
		env.position = Vector3(x, 0, 0)
		add_child(env)

	# Defer setup to ensure all duplicated envs are fully ready and positioned.
	call_deferred("_finish_env_setup")


func _finish_env_setup() -> void:
	# 2. Load all static surfaces AT ONCE so internal C++ floor triangles don't get corrupted
	base_env.get_node("LibSM64StaticSurfacesHandler").load_static_surfaces()

	# 3. Create all Marios
	base_env.init_sm64()
	for child in get_children():
		if child != base_env and child.has_method("init_sm64"):
			child.init_sm64()

func _on_tree_exiting() -> void:
	LibSM64Global.terminate()
