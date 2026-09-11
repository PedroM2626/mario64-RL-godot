extends MarioAgent
class_name ChaseAgent

@export var is_chaser := false
@export var enemy: Node3D

func get_obs() -> Dictionary:
	var obs := []
	if mario and enemy:
		var dir_to_enemy = enemy.global_position - mario.global_position
		obs.append(dir_to_enemy.x)
		obs.append(dir_to_enemy.y)
		obs.append(dir_to_enemy.z)
		
		obs.append(mario.velocity.x)
		obs.append(mario.velocity.y)
		obs.append(mario.velocity.z)
		obs.append(mario.face_angle)
		
		obs.append(float(mario.action) / 100.0)
		obs.append(float(mario.flags) / 100.0)
		
		# Add role flag (1 for chaser, 0 for runner)
		obs.append(1.0 if is_chaser else 0.0)
		
		var ray_data = raycast_sensor.get_observation()
		obs.append_array(ray_data)
	else:
		for i in range(42):
			obs.append(0.0)
	return {"obs": obs}


func get_reward() -> float:
	var step_reward = 0.0
	if mario and enemy:
		var dist = mario.global_position.distance_to(enemy.global_position)
		if is_chaser:
			step_reward -= dist * 0.01 # Wants to be close
			if dist < 2.0 and (mario.rl_button_b or mario.rl_button_z):
				step_reward += 10.0 # Caught!
		else:
			step_reward += dist * 0.01 # Wants to be far
			var chaser_mario = enemy as ChaseMario
			if dist < 2.0 and chaser_mario and (chaser_mario.rl_button_b or chaser_mario.rl_button_z):
				step_reward -= 10.0 # Caught!
				
		if mario.global_position.y < -10.0:
			step_reward -= 10.0 # Fell off
			
	current_steps += 1
	last_reward = step_reward
	total_reward += step_reward
	return step_reward

func is_done() -> bool:
	if not mario or not enemy: return false
	
	if mario.global_position.y < -10.0:
		return true # Fell
		
	var dist = mario.global_position.distance_to(enemy.global_position)
	if dist < 2.0:
		if is_chaser and (mario.rl_button_b or mario.rl_button_z):
			return true # End condition met
		elif not is_chaser:
			var chaser_mario = enemy as ChaseMario
			if chaser_mario and (chaser_mario.rl_button_b or chaser_mario.rl_button_z):
				return true
		
	# 15 seconds timer (assuming 60 physics fps -> 900 steps)
	if current_steps >= 900:
		return true
		
	return false

