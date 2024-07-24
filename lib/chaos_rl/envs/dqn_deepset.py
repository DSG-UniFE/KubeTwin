import random
import time
#import gym
#import gym.spaces
import gymnasium as gym
import numpy as np
import numpy.typing as npt
import torch
import torch.nn as nn
import torch.optim as optim
from env import ChaosEnv
from typing import Optional, Union
from copy import deepcopy
import torch.nn.functional as F
from torch.distributions.categorical import Categorical
from stable_baselines3.common.vec_env.dummy_vec_env import DummyVecEnv
from stable_baselines3.common.vec_env.subproc_vec_env import SubprocVecEnv
from stable_baselines3.common.buffers import ReplayBuffer
from stable_baselines3.common.utils import safe_mean

from envs.ppo_deepset import Algorithm
from envs.deep_sets_agent_dqn import DQNDeepSetAgent


def make_env(env_id, seed, rank):
    """
    Utility function for multiprocessed envs.
    
    :param env_id: (str) the environment ID
    :param seed: (int) the initial seed for RNG
    :param rank: (int) index of the subprocess
    """

    def _init():
        env = gym.make(env_id)  # Replace this with your custom env if not using gym.make
        env.seed(seed + rank)  # Make sure each environment instance has a unique seed
        return env

    return _init


def linear_schedule(start_e: float, end_e: float, duration: int, t: int):
    slope = (end_e - start_e) / duration
    return max(slope * t + start_e, end_e)


class DQN_DeepSets(Algorithm):
    def __init__(
            self,
            env = ChaosEnv(config={}),
            seed=1,
            torch_deterministic=True,
            num_steps: int = 100,
            learning_rate=2.5e-4,
            buffer_size=10000,
            gamma=0.99,
            tau=1.0,
            num_envs: int = 1,
            n_minibatches: int = 4,
            target_network_frequency=500,
            batch_size=128,
            start_e=1,
            end_e=0.05,
            exploration_fraction=0.5,
            learning_starts=10000,
            train_frequency=10,
            device: str = "cpu",
            tensorboard_log: str = None,
    ):
        super().__init__(env, num_envs, num_steps, n_minibatches, tensorboard_log)
        self.num_envs = 1
        self.num_steps = num_steps
        self.seed = seed
        self.torch_deterministic = torch_deterministic
        self.env = env
        self.learning_rate = learning_rate
        self.n_minibatches = n_minibatches
        self.buffer_size = buffer_size
        self.gamma = gamma
        self.tau = tau
        self.target_network_frequency = target_network_frequency
        self.batch_size = batch_size
        self.start_e = start_e
        self.end_e = end_e
        self.exploration_fraction = exploration_fraction
        self.learning_starts = learning_starts
        self.train_frequency = train_frequency
        self.device = device
        self.tensorboard_log = tensorboard_log

        random.seed(self.seed)
        np.random.seed(self.seed)
        torch.manual_seed(self.seed)

        # TODO: modify it to multibinary
        # assert isinstance(self.env.action_space, gym.spaces.Discrete), "only discrete action space is supported"

        # Initialize primary and target DQNDeepSetAgent
        self.q_network = DQNDeepSetAgent(self.env).to(self.device)
        self.target_network = deepcopy(self.q_network)  # Create a deep copy for the target network
        self.optimizer = optim.Adam(self.q_network.parameters(), lr=self.learning_rate)

        # Initialize masks
        #self.masks = torch.zeros((self.num_envs, self.env.action_space.n), dtype=torch.bool).to(self.device)
        #self.masks = torch.tensor(self.env.action_masks(), dtype=torch.bool).to(self.device)
        self.masks = torch.zeros((self.num_steps, self.num_envs, self.env.action_space.n), dtype=torch.bool).to(
            self.device)
        # Initialize actions
        self.actions = torch.zeros((self.num_envs, 1), dtype=torch.int64).to(self.device)

        # Initialize replay buffer
        self.rb = ReplayBuffer(
            self.buffer_size,
            self.env.observation_space,
            self.env.action_space,
            self.device,
            self.num_envs,
            handle_timeout_termination=False,
        )

    def learn(self, total_timesteps: int = 15000):
        start_time = time.time()
        obs = self.env.reset()
        next_masks = torch.tensor(np.array(self.env.env_method("action_masks")), dtype=torch.bool).to(self.device)
        episode_rewards = []

        for global_step in range(total_timesteps):
            epsilon = linear_schedule(self.start_e, self.end_e, self.exploration_fraction * total_timesteps,
                                      global_step)
            self.masks = next_masks
            if random.random() < epsilon:
                actions = []
                for env_mask in self.masks:
                    valid_actions = np.where(env_mask)[0]
                    if valid_actions.size > 0:  # Controlla se ci sono azioni valide
                        action = np.random.choice(valid_actions)
                    else:
                        action = 0
                    actions.append(action)
                self.actions = torch.tensor(actions).to(self.device)
            else:
                q_values = self.q_network(torch.Tensor(obs).to(self.device))

                # Masking Q-values of invalid actions
                HUGE_NEGATIVE = -1e8
                action_masks_tensor = torch.tensor(self.masks, dtype=torch.bool).to(self.device)
                q_values = torch.where(action_masks_tensor, q_values, HUGE_NEGATIVE)

                self.actions = torch.argmax(q_values, dim=1)
            # Execute the game and log data
            
            actions_list = self.actions.cpu().numpy().tolist()
            next_obs, rewards, terminated, infos = self.env.step(actions_list)
            next_masks = torch.tensor(np.array(self.env.env_method("action_masks")), dtype=torch.bool).to(self.device)

            # Record rewards for plotting purposes
            for item in infos:
                if "episode" in item.keys():
                    episode_rewards.append(item['episode']['r'])
                    self.writer.add_scalar("charts/episodic_return", item["episode"]["r"], global_step)
                    self.writer.add_scalar("charts/episodic_length", item["episode"]["l"], global_step)
                    self.writer.add_scalar("rollout/ep_rew_mean", safe_mean(episode_rewards), global_step)
                    print(f"global_step: {global_step}, episodic_return={item['episode']['r']},  "
                          f"episode_rew_mean={safe_mean(episode_rewards)}")
                    break
            # Handle episode termination by resetting the environment
            if terminated:
                self.env.reset()

            # Save data to replay buffer; handle `final_observation`
            real_next_obs = next_obs.copy()

            # Since we have an environment with a fixed episode length, we don't much need to handle the truncated cases
            '''
            for idx, d in enumerate(truncated):
                if d:
                    real_next_obs[idx] = infos["final_observation"][idx]
            

            
            print('actions reshaped: ', self.actions.cpu().numpy().reshape(-1, 1))
            print('actions shape: ', self.actions.cpu().numpy().shape)
            #self.masks.reshape((-1, +self.env.action_space.n))
            '''

            self.rb.add(obs, real_next_obs, self.actions.cpu().numpy()[0].reshape(-1, 1), rewards, terminated, infos)

            # return next_obs
            obs = next_obs

            # ALGO LOGIC: training
            if global_step > self.learning_starts:
                if global_step % self.train_frequency == 0:
                    data = self.rb.sample(self.batch_size)
                    with torch.no_grad():
                        target_max, _ = self.target_network(data.next_observations).max(dim=1)
                        td_target = data.rewards.flatten() + self.gamma * target_max * (1 - data.dones.flatten())
                    old_val = self.q_network(data.observations).gather(1, data.actions).squeeze()
                    loss = F.mse_loss(td_target, old_val)

                    '''
                    if global_step % 100 == 0:
                        writer.add_scalar("losses/td_loss", loss, global_step)
                        writer.add_scalar("losses/q_values", old_val.mean().item(), global_step)
                        print("SPS:", int(global_step / (time.time() - start_time)))
                        writer.add_scalar("charts/SPS", int(global_step / (time.time() - start_time)), global_step)
                    '''

                    # optimize the model
                    self.optimizer.zero_grad()
                    loss.backward()
                    self.optimizer.step()

                    # Update target network
                    if global_step % self.target_network_frequency == 0:
                        for target_param, q_param in zip(self.target_network.parameters(), self.q_network.parameters()):
                            target_param.data.copy_(self.tau * q_param.data + (1.0 - self.tau) * target_param.data)

            # print("FPS:", int(global_step / (time.time() - start_time)))
            self.writer.add_scalar("charts/learning_rate", self.optimizer.param_groups[0]["lr"],
                                               global_step)
            # self.writer.add_scalar("losses/value_loss", v_loss.item(), global_step)
            # self.writer.add_scalar("losses/policy_loss", pg_loss.item(), global_step)
            # self.writer.add_scalar("losses/entropy", entropy_loss.item(), global_step)
            # self.writer.add_scalar("losses/old_approx_kl", old_approx_kl.item(), global_step)
            # self.writer.add_scalar("losses/approx_kl", approx_kl.item(), global_step)
            # self.writer.add_scalar("losses/clipfrac", np.mean(clipfracs), global_step)
            # self.writer.add_scalar("losses/explained_variance", explained_var, global_step)
            # print("FPS:", int(global_step / (time.time() - start_time)))
            self.writer.add_scalar("charts/FPS", int(global_step / (time.time() - start_time)), global_step)

    def predict(self, obs: npt.NDArray, masks: Optional[npt.NDArray] = None) -> npt.NDArray:
        with torch.no_grad():
            action = self.q_network.get_action(
                torch.as_tensor(obs, dtype=torch.float32), torch.as_tensor(masks, dtype=torch.bool), deterministic=True
            ).numpy()
        return action

    def save(self, path: str) -> None:
        torch.save(self.q_network.state_dict(), path)

    def load(self, path: str) -> None:
        self.q_network.load_state_dict(torch.load(path))

    '''
    def predict(self, obs: npt.NDArray, masks: Optional[npt.NDArray] = None) -> npt.NDArray:
        with torch.no_grad():
            # Assuming you have a get_action method in your DQN agent that handles action selection.
            action = self.agent.get_action(
                torch.as_tensor(obs, dtype=torch.float32), masks, deterministic=True
            ).numpy()
        return action

    '''


'''
class ReplayBuffer:
    # ... (original ReplayBuffer code)
    
    # Main DQN training loop
    def train_dqn(args, envs):
        q_network = DQNDeepSetAgent(envs).to(device)
        optimizer = optim.Adam(q_network.parameters(), lr=args.learning_rate)
        target_network = DQNDeepSetAgent(envs).to(device)
        target_network.load_state_dict(q_network.state_dict())

        rb = ReplayBuffer(
            args.buffer_size,
            envs.single_observation_space,
            envs.single_action_space,
            device,
            handle_timeout_termination=False,
        )
        start_time = time.time()
        
        obs, _ = envs.reset(seed=args.seed)
        for global_step in range(args.total_timesteps):
            epsilon = linear_schedule(args.start_e, args.end_e, args.exploration_fraction * args.total_timesteps, global_step)
            if random.random() < epsilon:
                actions = np.array([envs.single_action_space.sample() for _ in range(envs.num_envs)])
            else:
                q_values = q_network((torch.Tensor(obs).to(device), valid_actions))
                actions = torch.argmax(q_values, dim=1).cpu().numpy()

        # Rest of the DQN loop remains unchanged...
        
        return q_network

# Assuming the required arguments are provided in args
# trained_q_network = train_dqn(args, envs)

'''
