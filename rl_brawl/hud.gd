extends CanvasLayer

@onready var label_fps: Label = $PanelContainer/VBoxContainer/LabelFPS
@onready var label_envs: Label = $PanelContainer/VBoxContainer/LabelEnvs
@onready var label_episode: Label = $PanelContainer/VBoxContainer/LabelEpisode
@onready var label_reward1: Label = $PanelContainer/VBoxContainer/LabelReward1
@onready var label_reward2: Label = $PanelContainer/VBoxContainer/LabelReward2
@onready var slider_scale: HSlider = $PanelContainer/VBoxContainer/HBoxContainer/SliderScale
@onready var label_scale_val: Label = $PanelContainer/VBoxContainer/HBoxContainer/LabelScaleVal
@onready var button_reset: Button = $PanelContainer/VBoxContainer/ButtonReset

var agents: Array = []

func _ready() -> void:
	slider_scale.value = Engine.time_scale
	label_scale_val.text = str(Engine.time_scale) + "x"
	slider_scale.value_changed.connect(_on_slider_value_changed)
	button_reset.pressed.connect(_on_button_reset_pressed)

	var main_node = get_node_or_null("/root/Main")
	if main_node and "num_envs" in main_node:
		label_envs.text = "Environments: " + str(main_node.num_envs)

	if main_node:
		for child in main_node.get_children():
			if child is BrawlEnv:
				for agent in child.agents:
					if agent is BrawlAgent:
						agents.append(agent)

	if agents.size() > 0:
		label_reward1.text = "Team 0 Reward: 0.0"
		label_reward2.text = "Team 1 Reward: 0.0"
	else:
		label_reward1.visible = false
		label_reward2.visible = false

var elapsed_seconds: float = 0.0

func _process(delta: float) -> void:
	elapsed_seconds += delta / Engine.time_scale
	var mins = int(elapsed_seconds) / 60
	var secs = int(elapsed_seconds) % 60
	label_fps.text = "FPS: " + str(Engine.get_frames_per_second()) + " | Time: %02d:%02d" % [mins, secs]

	if agents.size() > 0:
		var team_rewards = [0.0, 0.0]
		var steps = 0
		var episode = 0
		for agent in agents:
			team_rewards[agent.team_id] += agent.total_reward
			steps = agent.current_steps
			episode = agent.current_episode
		label_episode.text = "Episode: " + str(episode) + " | Steps: " + str(steps)
		label_reward1.text = "Team 0 Reward: " + str(snapped(team_rewards[0], 0.01))
		if team_rewards.size() > 1:
			label_reward2.text = "Team 1 Reward: " + str(snapped(team_rewards[1], 0.01))

func _on_slider_value_changed(val: float) -> void:
	Engine.time_scale = val
	label_scale_val.text = str(val) + "x"

func _on_button_reset_pressed() -> void:
	var all_agents = get_tree().get_nodes_in_group("AGENT")
	for agent in all_agents:
		if agent.has_method("reset"):
			agent.reset()
