extends Node3D
class_name BrawlEnv

const GLOBAL_FEATURES_PER_AGENT := 9

@export var env_index := 0
@export var teams: Array[TeamConfig] = []
@export var team_ring_radius := 10.0
@export var team_spread_radius := 2.5
@export var spawn_height := 2.0
@export var respawn_jitter := 0.5
@export var attack_range := 2.0
@export var attack_cooldown := 0.5
@export var damage_wedges := 1
@export var max_episode_steps := 900
@export var max_enemies_observed := 4
@export var max_allies_observed := 2

@onready var static_surfaces: LibSM64StaticSurfacesHandler = $LibSM64StaticSurfacesHandler

var agents: Array[BrawlAgent] = []
var marios: Array[BrawlMario] = []
var _episode_steps := 0
var _resetting := false

func _ready() -> void:
	_ensure_default_teams()

func init_sm64() -> void:
	_ensure_default_teams()
	_clear_spawned_nodes()
	_spawn_teams()
	for mario in marios:
		mario.create()
		mario.apply_team_appearance()

func _physics_process(_delta: float) -> void:
	if _resetting:
		return

	_episode_steps += 1
	_handle_attacks()

	if _should_end_episode():
		_request_reset()

	if _any_agent_needs_reset():
		_reset_all()

func get_team_count() -> int:
	return teams.size()

func get_global_state() -> Array:
	var state := []
	var sorted_agents = _get_sorted_agents()
	var team_count = max(1, teams.size())
	for agent in sorted_agents:
		if agent and agent.mario and not agent.is_dead:
			var pos = agent.mario.global_position
			var vel = agent.mario.velocity
			state.append(pos.x)
			state.append(pos.y)
			state.append(pos.z)
			state.append(vel.x)
			state.append(vel.y)
			state.append(vel.z)
			state.append(float(agent.mario.health_wedges) / 8.0)
			state.append(1.0)
			state.append(float(agent.team_id) / float(max(1, team_count - 1)))
		elif agent:
			state.append(0.0)
			state.append(0.0)
			state.append(0.0)
			state.append(0.0)
			state.append(0.0)
			state.append(0.0)
			state.append(0.0)
			state.append(0.0)
			state.append(float(agent.team_id) / float(max(1, team_count - 1)))
		else:
			state.append(0.0)
			state.append(0.0)
			state.append(0.0)
			state.append(0.0)
			state.append(0.0)
			state.append(0.0)
			state.append(0.0)
			state.append(0.0)
			state.append(0.0)
	return state

func get_global_state_size() -> int:
	return _get_sorted_agents().size() * GLOBAL_FEATURES_PER_AGENT

func get_enemies_for(agent: BrawlAgent) -> Array:
	var result := []
	for other in agents:
		if other != agent and other.team_id != agent.team_id and not other.is_dead:
			result.append(other)
	return result

func get_allies_for(agent: BrawlAgent) -> Array:
	var result := []
	for other in agents:
		if other != agent and other.team_id == agent.team_id and not other.is_dead:
			result.append(other)
	return result

func _ensure_default_teams() -> void:
	if not teams.is_empty():
		return

	var team_a = TeamConfig.new()
	team_a.team_name = "Red"
	team_a.team_color = Color(1, 0, 0, 0.5)
	team_a.team_size = 2

	var team_b = TeamConfig.new()
	team_b.team_name = "Blue"
	team_b.team_color = Color(0, 0, 1, 0.5)
	team_b.team_size = 2

	teams = [team_a, team_b]

func _clear_spawned_nodes() -> void:
	for agent in agents:
		if is_instance_valid(agent):
			agent.queue_free()
	for mario in marios:
		if is_instance_valid(mario):
			mario.queue_free()
	agents.clear()
	marios.clear()

func _spawn_teams() -> void:
	var team_count = teams.size()
	for team_idx in range(team_count):
		var team_cfg = teams[team_idx]
		for member_idx in range(team_cfg.team_size):
			var spawn_pos = _get_spawn_position(team_idx, member_idx, team_cfg.team_size, team_count)
			var mario = BrawlMario.new()
			mario.name = "BrawlMario_T%02d_M%02d" % [team_idx, member_idx]
			mario.team_color = team_cfg.team_color
			mario.team_texture = team_cfg.team_texture
			add_child(mario)
			mario.global_position = spawn_pos

			var agent = BrawlAgent.new()
			agent.name = "BrawlAgent_T%02d_M%02d" % [team_idx, member_idx]
			agent.mario = mario
			agent.team_id = team_idx
			agent.policy_name = "team_%d" % team_idx
			agent.brawl_env = self
			agent.attack_range = attack_range
			agent.attack_cooldown = attack_cooldown
			agent.max_enemies_observed = max_enemies_observed
			agent.max_allies_observed = max_allies_observed
			agent.reset_after = max_episode_steps
			agent.start_pos = spawn_pos
			add_child(agent)

			agents.append(agent)
			marios.append(mario)

func _get_spawn_position(team_idx: int, member_idx: int, team_size: int, team_count: int) -> Vector3:
	var angle = TAU * float(team_idx) / float(max(1, team_count))
	var team_center = global_position + Vector3(cos(angle) * team_ring_radius, spawn_height, sin(angle) * team_ring_radius)

	var member_angle = TAU * float(member_idx) / float(max(1, team_size))
	var offset = Vector3(cos(member_angle) * team_spread_radius, 0.0, sin(member_angle) * team_spread_radius)
	var jitter = Vector3(randf_range(-respawn_jitter, respawn_jitter), 0.0, randf_range(-respawn_jitter, respawn_jitter))
	return team_center + offset + jitter

func _handle_attacks() -> void:
	for agent in agents:
		if agent.is_dead or not agent.mario:
			continue
		if not agent.can_attack():
			continue

		if not (agent.mario.rl_button_b or agent.mario.rl_button_z):
			continue

		var target = _find_nearest_enemy(agent)
		if not target or not target.mario:
			continue

		var dist = agent.mario.global_position.distance_to(target.mario.global_position)
		if dist <= attack_range:
			_apply_damage(agent, target)
			agent.register_attack()

func _find_nearest_enemy(agent: BrawlAgent) -> BrawlAgent:
	var best: BrawlAgent = null
	var best_dist := INF
	for other in agents:
		if other == agent:
			continue
		if other.team_id == agent.team_id:
			continue
		if other.is_dead or not other.mario:
			continue
		var dist = other.mario.global_position.distance_to(agent.mario.global_position)
		if dist < best_dist:
			best_dist = dist
			best = other
	return best

func _apply_damage(attacker: BrawlAgent, target: BrawlAgent) -> void:
	var target_health = target.mario.health_wedges
	target.mario.take_damage(damage_wedges, 0, attacker.mario.global_position)
	target.register_damage_taken(damage_wedges)
	attacker.register_damage_dealt(damage_wedges)

	if target_health <= damage_wedges:
		target.mario.kill()
		target.register_death()
		attacker.register_kill()

func _should_end_episode() -> bool:
	if _episode_steps >= max_episode_steps:
		return true

	if teams.size() > 1 and _alive_team_count() <= 1:
		return true

	return false

func _alive_team_count() -> int:
	var alive := {}
	for agent in agents:
		if agent.is_dead:
			continue
		alive[agent.team_id] = true
	return alive.size()

func _request_reset() -> void:
	for agent in agents:
		agent.done = true
		agent.needs_reset = true

func _any_agent_needs_reset() -> bool:
	for agent in agents:
		if agent.needs_reset:
			return true
	return false

func _reset_all() -> void:
	_resetting = true
	_episode_steps = 0

	var team_count = teams.size()
	for team_idx in range(team_count):
		var team_agents = _get_agents_for_team(team_idx)
		for i in range(team_agents.size()):
			var spawn_pos = _get_spawn_position(team_idx, i, team_agents.size(), team_count)
			team_agents[i].start_pos = spawn_pos
			team_agents[i].reset()

	_resetting = false

func _get_agents_for_team(team_id: int) -> Array:
	var result := []
	for agent in agents:
		if agent.team_id == team_id:
			result.append(agent)
	result.sort_custom(Callable(self, "_sort_agent_name"))
	return result

func _get_sorted_agents() -> Array:
	var result = agents.duplicate()
	result.sort_custom(Callable(self, "_sort_agent_name"))
	return result

func _sort_agent_name(a, b) -> bool:
	return String(a.name) < String(b.name)
