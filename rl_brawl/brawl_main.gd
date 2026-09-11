extends Node3D

const BrawlEnvScene = preload("res://rl_brawl/brawl_env.tscn")
const SyncScript = preload("res://addons/godot_rl_agents/sync.gd")

@export var time_scale := 1.0
@export var num_envs := 4
@export var env_spacing := 60.0
@export var auto_env_spacing := true
@export var env_margin := 10.0

var sync_node: Node
@onready var base_env: Node3D = $BrawlEnv

func _ready() -> void:
	Engine.time_scale = time_scale
	print("[BrawlMain] _ready started")
	
	var rom_path = "baserom.us.z64"
	if FileAccess.file_exists("res://baserom.us.z64") and LibSM64Global.load_rom_file("res://baserom.us.z64"):
		if LibSM64Global.init():
			print("[BrawlMain] LibSM64 initialized OK")
			_setup_envs()
		else:
			push_error("[BrawlMain] Failed to init LibSM64")
	elif FileAccess.file_exists(rom_path) and LibSM64Global.load_rom_file(rom_path):
		if LibSM64Global.init():
			print("[BrawlMain] LibSM64 initialized OK")
			_setup_envs()
		else:
			push_error("[BrawlMain] Failed to init LibSM64")
	else:
		push_error("[BrawlMain] ROM not found at " + rom_path)

func _setup_envs() -> void:
	print("[BrawlMain] _setup_envs: configuring %d environments" % num_envs)
	base_env.env_index = 0
	base_env.position = Vector3(0, 0, 0)

	var spacing = _resolve_env_spacing()
	for i in range(1, num_envs):
		var env = BrawlEnvScene.instantiate()
		env.env_index = i
		if "teams" in base_env:
			env.teams = base_env.teams.duplicate()
		if "attack_range" in base_env:
			env.attack_range = base_env.attack_range
		if "attack_cooldown" in base_env:
			env.attack_cooldown = base_env.attack_cooldown
		if "max_episode_steps" in base_env:
			env.max_episode_steps = base_env.max_episode_steps
		var x = i * spacing
		env.position = Vector3(x, 0, 0)
		add_child(env)

	call_deferred("_finish_env_setup")

func _finish_env_setup() -> void:
	print("[BrawlMain] _finish_env_setup: loading static surfaces")
	base_env.get_node("LibSM64StaticSurfacesHandler").load_static_surfaces()

	print("[BrawlMain] _finish_env_setup: initializing SM64 for base env")
	base_env.init_sm64()
	for child in get_children():
		if child != base_env and child.has_method("init_sm64"):
			print("[BrawlMain] _finish_env_setup: initializing SM64 for " + str(child.name))
			child.init_sm64()
	
	# Verify agents were created
	var all_agents = get_tree().get_nodes_in_group("AGENT")
	print("[BrawlMain] Total agents in AGENT group: %d" % all_agents.size())
	
	# Create the sync node AFTER all agents exist in the scene tree.
	# IMPORTANT: sync._ready() does `await get_parent().ready`, but since
	# Main's _ready() already completed, that await will NEVER resolve
	# (the signal was already emitted). So we must call _initialize()
	# and _attempt_connect() manually.
	print("[BrawlMain] Creating sync node...")
	sync_node = SyncScript.new()
	add_child(sync_node)
	sync_node._initialize()
	sync_node._attempt_connect()
	print("[BrawlMain] Sync node initialized and connecting...")

func _on_tree_exiting() -> void:
	LibSM64Global.terminate()

func _resolve_env_spacing() -> float:
	if not auto_env_spacing:
		return env_spacing

	var max_size = 0.0
	for node in get_tree().get_nodes_in_group(&"libsm64_static_surfaces"):
		var mesh_instance := node as MeshInstance3D
		if not mesh_instance or not base_env.is_ancestor_of(mesh_instance):
			continue
		if not mesh_instance.mesh:
			continue
		var aabb = mesh_instance.mesh.get_aabb()
		var mesh_scale = mesh_instance.global_transform.basis.get_scale()
		var size = Vector3(
			abs(aabb.size.x * mesh_scale.x),
			abs(aabb.size.y * mesh_scale.y),
			abs(aabb.size.z * mesh_scale.z)
		)
		max_size = max(max_size, max(size.x, size.z))

	if max_size <= 0.0:
		return env_spacing

	return max_size + env_margin
