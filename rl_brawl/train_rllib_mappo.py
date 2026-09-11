"""RLlib MAPPO training script for the Brawl multi-agent environment.

Based on the godot_rl rllib_example.py reference implementation.
Uses tune.Tuner with raw config dict to avoid PPOConfig translation issues.

Usage:
  1. Press PLAY in the Godot editor on the brawl_main scene
  2. Run: python rl_brawl/train_rllib_mappo.py --config_file rl_brawl/rllib_config.yaml --experiment_dir logs/rllib
"""
import argparse
import os
import pathlib
import sys

import numpy as np

import ray
import yaml
from ray import tune
from ray.tune import RunConfig, CheckpointConfig
from ray.rllib.algorithms.algorithm import Algorithm
from ray.rllib.env.wrappers.pettingzoo_env import ParallelPettingZooEnv
from ray.rllib.models import ModelCatalog
from ray.rllib.policy.policy import PolicySpec

# Add repository root to path for local imports
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
REPO_ROOT = os.path.dirname(SCRIPT_DIR)
if REPO_ROOT not in sys.path:
    sys.path.insert(0, REPO_ROOT)

from godot_rl.core.godot_env import GodotEnv
from godot_rl.wrappers.petting_zoo_wrapper import GDRLPettingZooEnv
from rl_brawl.rllib_models import CentralCriticModel


def build_policy_names(num_teams: int, team_size: int, num_envs: int) -> list:
    """Build per-agent policy name list matching the order agents are spawned in Godot.

    In brawl_env.gd, _spawn_teams() iterates team_idx then member_idx, assigning
    policy_name = "team_%d" % team_idx. With 4 environments, the sync node discovers
    all agents via get_tree().get_nodes_in_group("AGENT") in tree order.

    Returns:
        A list of policy name strings, one per agent across all environments.
        e.g. for 2 teams of 3 across 4 envs: 24 entries.
    """
    per_env = []
    for team_idx in range(num_teams):
        for _member_idx in range(team_size):
            per_env.append(f"team_{team_idx}")
    # Repeat for all envs
    return per_env * num_envs


if __name__ == "__main__":
    parser = argparse.ArgumentParser(allow_abbrev=False)
    parser.add_argument("--config_file", default=os.path.join(SCRIPT_DIR, "rllib_config.yaml"), type=str)
    parser.add_argument("--restore", default=None, type=str)
    parser.add_argument("--experiment_dir", default="logs/rllib", type=str)
    parser.add_argument("--experiment_name", default="brawl_mappo", type=str)
    parser.add_argument("--timesteps", default=None, type=int)
    # Brawl team configuration (must match the Godot scene)
    parser.add_argument("--num_teams", default=2, type=int, help="Number of teams (must match Godot scene)")
    parser.add_argument("--team_size", default=3, type=int, help="Members per team (must match Godot scene)")
    parser.add_argument("--num_envs", default=4, type=int, help="Number of parallel envs (must match Godot scene)")
    args, extras = parser.parse_known_args()

    # Load config from YAML
    with open(args.config_file) as f:
        exp = yaml.safe_load(f)

    is_multiagent = exp["env_is_multiagent"]

    # Register custom model for MAPPO central critic
    ModelCatalog.register_custom_model("central_critic_model", CentralCriticModel)

    # ---- Register env creator ----
    # With num_workers=0, only the local worker (worker_index=0) runs.
    # Port = 0 * 1 + 0 + 11008 = 11008 (DEFAULT_PORT), matching Godot's default.
    env_name = "godot"

    def _patch_godot_obs_spaces(pz_env):
        """Patch the GDRLPettingZooEnv observation spaces from Box(-1,1) to Box(-inf,inf).

        GodotEnv hardcodes obs space bounds to [-1, 1] but BrawlAgent returns raw
        positions/velocities that exceed that range. We patch the spaces BEFORE
        wrapping with ParallelPettingZooEnv so it picks up the correct bounds.
        """
        from gymnasium import spaces as gym_spaces
        for i, agent_name in enumerate(pz_env.possible_agents):
            old_space = pz_env.observation_spaces[agent_name]
            if isinstance(old_space, gym_spaces.Dict):
                new_subspaces = {}
                for k, sub in old_space.spaces.items():
                    if isinstance(sub, gym_spaces.Box):
                        new_subspaces[k] = gym_spaces.Box(
                            low=-np.inf, high=np.inf,
                            shape=sub.shape, dtype=np.float32,
                        )
                    else:
                        new_subspaces[k] = sub
                pz_env.observation_spaces[agent_name] = gym_spaces.Dict(new_subspaces)
        # Clear the lru_cache on observation_space() so it returns the patched spaces
        if hasattr(pz_env.observation_space, 'cache_clear'):
            pz_env.observation_space.cache_clear()

    class NumpyObsParallelEnv(ParallelPettingZooEnv):
        """Wraps ParallelPettingZooEnv to convert list observations to numpy arrays.

        Godot sends observations as JSON (Python lists). RLlib's `tree` library
        treats lists as sequences but numpy arrays as leaves, causing a structure
        mismatch during preprocessing. This wrapper converts to float32 arrays.
        """
        @staticmethod
        def _convert_obs(obs):
            if isinstance(obs, dict):
                return {k: np.array(v, dtype=np.float32) if isinstance(v, list) else v
                        for k, v in obs.items()}
            return obs

        def reset(self, **kwargs):
            obs, infos = super().reset(**kwargs)
            return {k: self._convert_obs(v) for k, v in obs.items()}, infos

        def step(self, actions):
            obs, rewards, terms, truncs, infos = super().step(actions)
            return {k: self._convert_obs(v) for k, v in obs.items()}, rewards, terms, truncs, infos

    def env_creator(env_config):
        index = env_config.worker_index * exp["config"].get("num_envs_per_env_runner", 1) + env_config.vector_index
        port = index + GodotEnv.DEFAULT_PORT
        seed = index
        if is_multiagent:
            pz_env = GDRLPettingZooEnv(config=env_config, port=port, seed=seed)
            _patch_godot_obs_spaces(pz_env)
            return NumpyObsParallelEnv(pz_env)
        else:
            from godot_rl.wrappers.ray_wrapper import RayVectorGodotEnv
            return RayVectorGodotEnv(config=env_config, port=port, seed=seed)

    tune.register_env(env_name, env_creator)

    # ---- Build policy names without connecting to Godot ----
    # We build the per-agent policy mapping programmatically based on the known
    # team configuration, avoiding a temporary Godot connection that would send
    # a "close" message and shut down the Godot editor.
    policy_names = build_policy_names(args.num_teams, args.team_size, args.num_envs)
    unique_policies = sorted(set(policy_names))
    print(f"Policy mapping: {len(policy_names)} agents -> {unique_policies}")

    # ---- Build multiagent config ----
    def policy_mapping_fn(agent_id: int, episode, worker, **kwargs) -> str:
        return policy_names[agent_id]

    if is_multiagent:
        exp["config"]["multiagent"] = {
            "policies": {p: PolicySpec() for p in unique_policies},
            "policy_mapping_fn": policy_mapping_fn,
        }

    # Override timesteps if provided via CLI
    if args.timesteps:
        exp["stop"]["timesteps_total"] = args.timesteps

    # Disable new API stack to allow custom_model (ModelV2 API)
    exp["config"]["enable_rl_module_and_learner"] = False
    exp["config"]["enable_env_runner_and_connector_v2"] = False

    # ---- Initialize Ray and run training ----
    ray.init(
        _temp_dir=os.path.abspath(os.path.join(args.experiment_dir, "ray_tmp")),
        ignore_reinit_error=True,
    )

    tuner = None
    if not args.restore:
        tuner = tune.Tuner(
            trainable=exp["algorithm"],
            param_space=exp["config"],
            run_config=RunConfig(
                name=args.experiment_name,
                storage_path=os.path.abspath(args.experiment_dir),
                stop=exp["stop"],
                checkpoint_config=CheckpointConfig(
                    checkpoint_frequency=exp.get("checkpoint_frequency", 10),
                    checkpoint_at_end=True,
                ),
            ),
        )
    else:
        tuner = tune.Tuner.restore(
            trainable=exp["algorithm"],
            path=args.restore,
            resume_unfinished=True,
        )

    try:
        result = tuner.fit()
    except KeyboardInterrupt:
        print("\nTraining interrupted by user.")
        result = None

    # ---- ONNX export ----
    if result is not None:
        try:
            checkpoint = result.get_best_result().checkpoint
            if checkpoint:
                result_path = result.get_best_result().path
                ppo = Algorithm.from_checkpoint(checkpoint)
                if is_multiagent:
                    for policy_name in unique_policies:
                        export_path = os.path.join(result_path, "onnx_export", f"{policy_name}_onnx")
                        ppo.get_policy(policy_name).export_model(export_path, onnx=12)
                        print(f"Saving onnx policy to {pathlib.Path(export_path).resolve()}")
                else:
                    export_path = os.path.join(result_path, "onnx_export", "single_agent_policy_onnx")
                    ppo.get_policy().export_model(export_path, onnx=12)
                    print(f"Saving onnx policy to {pathlib.Path(export_path).resolve()}")
            else:
                print("No checkpoint found. Skipping ONNX export.")
        except Exception as e:
            print(f"Failed to export ONNX model: {e}")

    print("Training complete.")
