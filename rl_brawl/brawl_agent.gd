extends MarioAgent
class_name BrawlAgent

@export var team_id := 0
@export var max_enemies_observed := 4
@export var max_allies_observed := 2
@export var damage_reward := 1.0
@export var kill_reward := 5.0
@export var damage_taken_penalty := 1.0
@export var death_penalty := 5.0
@export var survival_reward := 0.0
@export var attack_range := 2.0
@export var attack_cooldown := 0.5

var brawl_env: Node
var damage_dealt := 0
var damage_taken := 0
var kills := 0
var deaths := 0
var is_dead := false
var attack_timer := 0.0
var ray_obs_size := 32

func _ready() -> void:
	super._ready()

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if attack_timer > 0.0:
		attack_timer = max(0.0, attack_timer - delta)

func can_attack() -> bool:
	return attack_timer <= 0.0

func register_attack() -> void:
	attack_timer = attack_cooldown

func register_damage_dealt(amount: int) -> void:
	damage_dealt += amount

func register_damage_taken(amount: int) -> void:
	damage_taken += amount

func register_kill() -> void:
	kills += 1

func register_death() -> void:
	deaths += 1
	is_dead = true
	done = true

func get_obs() -> Dictionary:
	if not mario or not brawl_env:
		return {"obs": _empty_obs(), "state": _empty_global_state()}

	var obs := []
	var team_count = brawl_env.get_team_count()
	obs.append(mario.velocity.x)
	obs.append(mario.velocity.y)
	obs.append(mario.velocity.z)
	obs.append(mario.face_angle)
	obs.append(float(mario.action) / 100.0)
	obs.append(float(mario.flags) / 100.0)
	obs.append(float(mario.health_wedges) / 8.0)
	obs.append(float(team_id) / float(max(1, team_count - 1)))

	var enemies = brawl_env.get_enemies_for(self)
	_append_agent_slots(obs, enemies, max_enemies_observed)

	var allies = brawl_env.get_allies_for(self)
	_append_agent_slots(obs, allies, max_allies_observed)

	var ray_data: Array = []
	if raycast_sensor:
		ray_data = raycast_sensor.get_observation()

	if ray_data.is_empty():
		ray_data.resize(ray_obs_size)
		for i in range(ray_obs_size):
			ray_data[i] = 0.0
	else:
		ray_obs_size = ray_data.size()

	obs.append_array(ray_data)
	var global_state = brawl_env.get_global_state()
	return {"obs": obs, "state": global_state}

func get_obs_space() -> Dictionary:
	var obs = get_obs()
	return {
		"obs": {"size": [len(obs["obs"])], "space": "box"},
		"state": {"size": [len(obs["state"])], "space": "box"},
	}

func get_reward() -> float:
	var step_reward = survival_reward
	step_reward += damage_dealt * damage_reward
	step_reward += kills * kill_reward
	step_reward -= damage_taken * damage_taken_penalty
	step_reward -= deaths * death_penalty

	damage_dealt = 0
	damage_taken = 0
	kills = 0
	deaths = 0

	current_steps += 1
	last_reward = step_reward
	total_reward += step_reward
	return step_reward

func reset() -> void:
	super.reset()
	damage_dealt = 0
	damage_taken = 0
	kills = 0
	deaths = 0
	is_dead = false
	done = false
	attack_timer = 0.0
	if mario and mario.has_method("apply_team_appearance"):
		mario.apply_team_appearance()

func _append_agent_slots(obs: Array, agents: Array, max_count: int) -> void:
	agents.sort_custom(Callable(self, "_sort_by_distance"))
	for i in range(max_count):
		if i < agents.size() and agents[i].mario:
			var other = agents[i]
			var rel = other.mario.global_position - mario.global_position
			obs.append(rel.x)
			obs.append(rel.y)
			obs.append(rel.z)
			obs.append(float(other.mario.health_wedges) / 8.0)
		else:
			obs.append(0.0)
			obs.append(0.0)
			obs.append(0.0)
			obs.append(0.0)

func _sort_by_distance(a, b) -> bool:
	if not mario or not a.mario or not b.mario:
		return false
	return a.mario.global_position.distance_to(mario.global_position) < b.mario.global_position.distance_to(mario.global_position)

func _empty_obs() -> Array:
	var total_size = 8 + (max_enemies_observed * 4) + (max_allies_observed * 4) + ray_obs_size
	var obs := []
	obs.resize(total_size)
	for i in range(total_size):
		obs[i] = 0.0
	return obs

func _empty_global_state() -> Array:
	if brawl_env and brawl_env.has_method("get_global_state_size"):
		var total_size = brawl_env.get_global_state_size()
		var state := []
		state.resize(total_size)
		for i in range(total_size):
			state[i] = 0.0
		return state
	return []
