extends AIController3D
class_name MarioAgent

@export var mario: RLMario
@export var target_node: Node3D

var raycast_sensor: Node3D
var start_pos: Vector3

func _ready() -> void:
	super._ready()
	add_to_group("AGENT")
	if mario:
		start_pos = mario.global_position
	
	# Add RayCast sensor for environment awareness
	# The sensor node comes from the godot_rl_agents addon
	var RayCastSensor = load("res://addons/godot_rl_agents/sensors/sensors_3d/RaycastSensor3D.gd")
	raycast_sensor = RayCastSensor.new()
	add_child(raycast_sensor)
	raycast_sensor.n_rays_width = 8
	raycast_sensor.n_rays_height = 4
	raycast_sensor.ray_length = 10.0

func get_obs() -> Dictionary:
	var obs := []
	if mario and target_node:
		# 1. Spatial awareness (Target relative position)
		var dir_to_target = target_node.global_position - mario.global_position
		obs.append(dir_to_target.x)
		obs.append(dir_to_target.y)
		obs.append(dir_to_target.z)
		
		# 2. Physics state
		obs.append(mario.velocity.x)
		obs.append(mario.velocity.y)
		obs.append(mario.velocity.z)
		obs.append(mario.face_angle)
		
		# 3. Internal Mario state (Normalized)
		obs.append(float(mario.action) / 100.0)
		obs.append(float(mario.flags) / 100.0)
		
		# 4. RayCast sensor data (Vision)
		var ray_data = raycast_sensor.get_observation()
		obs.append_array(ray_data)
	else:
		# Fill with zeros if nodes are missing
		for i in range(41): # 3+3+1+2 + 32 rays
			obs.append(0.0)

	return {"obs": obs}

func get_action_space() -> Dictionary:
	return {
		"stick_x": {"size": 1, "action_type": "continuous"},
		"stick_y": {"size": 1, "action_type": "continuous"},
		"button_a": {"size": 1, "action_type": "continuous"},
		"button_b": {"size": 1, "action_type": "continuous"},
		"button_z": {"size": 1, "action_type": "continuous"}
	}

func set_action(action) -> void:
	if not mario: return
	
	var stick_x = _read_action_value(action.get("stick_x", 0.0))
	var stick_y = _read_action_value(action.get("stick_y", 0.0))
	var button_a = _read_action_value(action.get("button_a", 0.0))
	var button_b = _read_action_value(action.get("button_b", 0.0))
	var button_z = _read_action_value(action.get("button_z", 0.0))

	mario.rl_stick = Vector2(
		clamp(stick_x, -1.0, 1.0),
		clamp(stick_y, -1.0, 1.0)
	)
	
	mario.rl_button_a = button_a > 0.0
	mario.rl_button_b = button_b > 0.0
	mario.rl_button_z = button_z > 0.0

func _read_action_value(value) -> float:
	if value is Array:
		return float(value[0]) if value.size() > 0 else 0.0
	return float(value)

var current_steps := 0
var current_episode := 1
var last_reward := 0.0
var total_reward := 0.0

func get_reward() -> float:
	var step_reward = 0.0
	if mario and target_node:
		var dist = mario.global_position.distance_to(target_node.global_position)
		step_reward -= dist * 0.01 # Small penalty for distance
		
		if dist < 2.0:
			step_reward += 10.0 # Reached target
		
		if mario.global_position.y < -10.0:
			step_reward -= 10.0 # Fell off
	
	current_steps += 1
	last_reward = step_reward
	total_reward += step_reward
	return step_reward

func is_done() -> bool:
	if not mario or not target_node: return false
	
	if mario.global_position.y < -10.0:
		return true # Fell
		
	if mario.global_position.distance_to(target_node.global_position) < 2.0:
		return true # Reached target
		
	if current_steps > 1000:
		return true # Timeout
		
	return false

func reset() -> void:
	super.reset()
	var was_active = current_steps > 0
	current_steps = 0
	current_episode += 1
	total_reward = 0.0
	if mario:
		# Teleporting in LibSM64 can leave the C++ state machine in a corrupted state (frozen, OOB, etc).
		# To guarantee a clean reset, we completely destroy the internal Mario and recreate him.
		# However, on the VERY FIRST reset (when was_active is false), Mario was JUST created by init_sm64().
		# Deleting and recreating him before a single physics tick causes a crash in LibSM64.
		if was_active:
			mario.delete()
			mario.global_position = start_pos
			mario.global_rotation = Vector3.ZERO
			mario.create()
			
			# For ChaseMario or BrawlMario specifically, we might need to reapply team appearances
			if mario.has_method("apply_tint"):
				mario.apply_tint()
			if mario.has_method("apply_team_appearance"):
				mario.apply_team_appearance()
		else:
			mario.global_position = start_pos
			mario.global_rotation = Vector3.ZERO
