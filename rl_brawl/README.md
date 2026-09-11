# Brawl Training Scene

This folder adds a multi-team brawl environment where multiple Marios fight.
The environment is multi-agent with a policy per team (policy names are set to `team_0`, `team_1`, ...).

## Scene
- Main scene: res://rl_brawl/brawl_main.tscn
- Environment: res://rl_brawl/brawl_env.tscn

## Team setup
Open the environment scene and edit the exported TeamConfig array:
- team_name: label for the team
- team_color: overlay color for the team
- team_texture: optional texture overlay for the team
- team_size: number of Marios in the team

Other useful settings are in brawl_env.gd:
- attack_range, attack_cooldown, damage_wedges
- max_episode_steps
- max_enemies_observed, max_allies_observed

## Training command example
Use the Python venv and a release export of the project:

c:/Users/pedro/Downloads/libsm64-godot-master/.venv311/Scripts/python.exe rl_brawl/train.py --env_path "C:/path/to/BrawlBuild.exe" --n_parallel 4 --speedup 8 --timesteps 1000000 --experiment_dir "logs/brawl" --experiment_name "brawl_run1"

## RLlib (multi-agent, team policies)
See `rl_brawl/README.rllib.md` for MAPPO/RLlib training steps and config.
