from ray.rllib.models.torch.torch_modelv2 import TorchModelV2
from ray.rllib.models.torch.fcnet import FullyConnectedNetwork
from ray.rllib.utils.framework import try_import_torch

torch, nn = try_import_torch()

_DEBUG_COUNTER = 0


class CentralCriticModel(TorchModelV2, nn.Module):
    """MAPPO-style central critic using global state for value and local obs for policy."""

    def __init__(self, obs_space, action_space, num_outputs, model_config, name):
        TorchModelV2.__init__(self, obs_space, action_space, num_outputs, model_config, name)
        nn.Module.__init__(self)

        # RLlib flattens Dict spaces into Box spaces by default, but attaches the original space
        orig_space = getattr(obs_space, "original_space", obs_space)

        if "obs" not in orig_space.spaces or "state" not in orig_space.spaces:
            raise ValueError("Expected Dict obs space with 'obs' and 'state' keys")

        obs_size = orig_space.spaces["obs"].shape[0]  # 68
        state_size = orig_space.spaces["state"].shape[0]  # 54
        self._obs_size = obs_size
        self._state_size = state_size

        self.policy_model = FullyConnectedNetwork(
            orig_space.spaces["obs"], action_space, num_outputs, model_config, name + "_policy"
        )
        
        # The value model outputs a single scalar (1). It cannot use free_log_std=True
        # because free_log_std requires num_outputs to be divisible by 2.
        value_model_config = model_config.copy()
        value_model_config["free_log_std"] = False
        
        self.value_model = FullyConnectedNetwork(
            orig_space.spaces["state"], action_space, 1, value_model_config, name + "_value"
        )
        self._value_out = None

    def forward(self, input_dict, state, seq_lens):
        global _DEBUG_COUNTER

        obs_raw = input_dict["obs"]

        # Determine if obs is a dict (unprocessed) or flat tensor (preprocessed)
        if isinstance(obs_raw, dict):
            obs_tensor = obs_raw["obs"]
            state_tensor = obs_raw["state"]
        else:
            # RLlib preprocessed the Dict obs into a flat tensor: [obs | state]
            obs_tensor = obs_raw[:, :self._obs_size]
            state_tensor = obs_raw[:, self._obs_size:self._obs_size + self._state_size]

        if _DEBUG_COUNTER < 3:
            _DEBUG_COUNTER += 1
            print(f"[CentralCriticModel] obs_raw type={type(obs_raw).__name__}, "
                  f"obs_tensor shape={obs_tensor.shape}, "
                  f"state_tensor shape={state_tensor.shape}")
            print(f"[CentralCriticModel] obs_tensor[:3]={obs_tensor[0, :3].tolist()}")

        # FullyConnectedNetwork.forward() reads input_dict["obs_flat"],
        # so we must set it explicitly to the correct sub-observation.
        policy_in = {"obs": obs_tensor, "obs_flat": obs_tensor}
        value_in = {"obs": state_tensor, "obs_flat": state_tensor}

        policy_out, _ = self.policy_model(policy_in, state, seq_lens)
        value_out, _ = self.value_model(value_in, state, seq_lens)

        if _DEBUG_COUNTER <= 3:
            print(f"[CentralCriticModel] policy_out shape={policy_out.shape}, "
                  f"min={policy_out.min().item():.6f}, max={policy_out.max().item():.6f}")
            # Check for -inf in log_std positions (odd indices)
            log_std_vals = policy_out[:, 1::2]
            exp_log_std = torch.exp(log_std_vals)
            print(f"[CentralCriticModel] log_std range=[{log_std_vals.min().item():.6f}, "
                  f"{log_std_vals.max().item():.6f}], "
                  f"exp(log_std) range=[{exp_log_std.min().item():.6f}, "
                  f"{exp_log_std.max().item():.6f}]")

        self._value_out = value_out.squeeze(1)
        return policy_out, state

    def value_function(self):
        return self._value_out
