extends Node3D

@export var env_index := 0

@onready var static_surfaces: LibSM64StaticSurfacesHandler = $LibSM64StaticSurfacesHandler
@onready var chaser_mario: ChaseMario = $ChaserMario
@onready var chaser_agent: ChaseAgent = $ChaserAgent
@onready var runner_mario: ChaseMario = $RunnerMario
@onready var runner_agent: ChaseAgent = $RunnerAgent

func _ready() -> void:
	pass

func init_sm64() -> void:
	chaser_mario.create()
	chaser_mario.apply_tint()
	
	runner_mario.create()
	runner_mario.apply_tint()
	
	# Use the current scene node positions to keep spawns aligned with the arena.
	chaser_agent.start_pos = chaser_mario.global_position
	runner_agent.start_pos = runner_mario.global_position




func _physics_process(_delta: float) -> void:
	if chaser_agent.needs_reset or runner_agent.needs_reset:
		chaser_agent.needs_reset = false
		runner_agent.needs_reset = false
		chaser_agent.reset()
		runner_agent.reset()

