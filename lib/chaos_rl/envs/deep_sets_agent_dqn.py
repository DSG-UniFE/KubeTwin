from typing import Optional
import gym
import numpy as np
import torch
from torch import nn
from torch.distributions import Categorical
from envs.deep_sets_agent_original import EquivariantDeepSet


class DQNDeepSetAgent(nn.Module):
    def __init__(self, envs: gym.vector.VectorEnv) -> None:
        super().__init__()
        in_channels = envs.observation_space.shape[1]

        '''
        # Actor outputs pi(a|s)
        self.actor = EquivariantDeepSet(in_channels, feature_size)
        # Critic outputs V(s)
        self.critic = InvariantDeepSet(in_channels)
        '''

        # Only one network for DQN which outputs Q-values
        self.q_network = EquivariantDeepSet(in_channels)

    def forward(self, x: torch.Tensor):
        return self.q_network(x)

    def get_value(self, x: torch.Tensor):
        return self.critic(x)

    def get_action(self, x: torch.Tensor, masks: Optional[torch.Tensor] = None, deterministic: bool = True):
        logits = self.q_network(x)
        if masks is not None:
            HUGE_NEG = torch.tensor(-1e8, dtype=logits.dtype)
            logits = torch.where(masks, logits, HUGE_NEG)
        # discrete probability distribution over a set of actions. The logits provide the unnormalized log probabilities for each action.
        dist = Categorical(logits=logits)
        # if deterministic is True, return the mode of the Categorical distribution (highest probability, selecting the action with the highest logit value)
        if deterministic:
            return dist.mode
        # if deterministic is False, return a random sample from the Categorical distribution.
        return dist.sample()

    def get_action_and_value(self, x: torch.Tensor, action: Optional[torch.Tensor],
                             masks: Optional[torch.Tensor] = None):
        logits = self.actor(x)
        if masks is not None:
            HUGE_NEG = torch.tensor(-1e8, dtype=logits.dtype)
            logits = torch.where(masks, logits, HUGE_NEG)
        dist = Categorical(logits=logits)
        if action is None:
            action = dist.sample()
        return action, dist.log_prob(action), dist.entropy(), self.critic(x)

    def get_feature_size(self):
        return self.feature_size
