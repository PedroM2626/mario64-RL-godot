extends Node3D

@export var env_index := 0

@onready var static_surfaces: LibSM64StaticSurfacesHandler = $LibSM64StaticSurfacesHandler
@onready var mario: RLMario = $RLMario
@onready var agent: MarioAgent = $MarioAgent
@onready var target: Node3D = $Target

func _ready() -> void:
	# Nodes are already in the scene!
	pass

func init_sm64() -> void:
	mario.create()
	agent.start_pos = global_position + Vector3(0, 1, 0)
