extends CanvasLayer

@onready var label_fps: Label = $PanelContainer/VBoxContainer/LabelFPS
@onready var label_envs: Label = $PanelContainer/VBoxContainer/LabelEnvs
@onready var label_episode: Label = $PanelContainer/VBoxContainer/LabelEpisode
@onready var label_reward1: Label = $PanelContainer/VBoxContainer/LabelReward1
@onready var label_reward2: Label = $PanelContainer/VBoxContainer/LabelReward2
@onready var slider_scale: HSlider = $PanelContainer/VBoxContainer/HBoxContainer/SliderScale
@onready var label_scale_val: Label = $PanelContainer/VBoxContainer/HBoxContainer/LabelScaleVal
@onready var button_reset: Button = $PanelContainer/VBoxContainer/ButtonReset

var agent1: Node3D # Chaser or Mario
var agent2: Node3D # Runner (if in chase mode)

func _ready() -> void:
	slider_scale.value = Engine.time_scale
	label_scale_val.text = str(Engine.time_scale) + "x"
	slider_scale.value_changed.connect(_on_slider_value_changed)
	button_reset.pressed.connect(_on_button_reset_pressed)
	
	# Try to find main script to get num_envs
	var main_node = get_node_or_null("/root/Main")
	if main_node and "num_envs" in main_node:
		label_envs.text = "Environments: " + str(main_node.num_envs)
		
		# Find agents to track metrics
		for child in main_node.get_children():
			if "Env" in child.name:
				# Parkour Mode
				var mario = child.get_node_or_null("MarioAgent")
				if mario:
					agent1 = mario
					label_reward1.text = "Mario Reward: 0.0"
					label_reward2.visible = false
					break
				
				# Chase Mode
				var chaser = child.get_node_or_null("ChaserAgent")
				var runner = child.get_node_or_null("RunnerAgent")
				if chaser and runner:
					agent1 = chaser
					agent2 = runner
					label_reward1.text = "Chaser Reward: 0.0"
					label_reward2.text = "Runner Reward: 0.0"
					label_reward2.visible = true
					break

var elapsed_seconds: float = 0.0

func _process(delta: float) -> void:
	# Accumulate real time regardless of timescale
	elapsed_seconds += delta / Engine.time_scale
	
	var mins = int(elapsed_seconds) / 60
	var secs = int(elapsed_seconds) % 60
	
	label_fps.text = "FPS: " + str(Engine.get_frames_per_second()) + " | Time: %02d:%02d" % [mins, secs]
	
	if agent1:
		label_episode.text = "Episode: " + str(agent1.current_episode) + " | Steps: " + str(agent1.current_steps)
		var prefix1 = "Chaser" if agent2 else "Mario"
		label_reward1.text = prefix1 + " Reward: " + str(snapped(agent1.total_reward, 0.01))
	
	if agent2:
		label_reward2.text = "Runner Reward: " + str(snapped(agent2.total_reward, 0.01))

func _on_slider_value_changed(val: float) -> void:
	Engine.time_scale = val
	label_scale_val.text = str(val) + "x"

func _on_button_reset_pressed() -> void:
	# Force reset on all agents
	var agents = get_tree().get_nodes_in_group("AGENT")
	for agent in agents:
		if agent.has_method("reset"):
			agent.reset()
