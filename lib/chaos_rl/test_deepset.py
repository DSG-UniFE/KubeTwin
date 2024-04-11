import numpy as np
from stable_baselines3.common.vec_env import DummyVecEnv, SubprocVecEnv, VecMonitor
from env_deepset import ChaosEnvDeepSet
from envs.ppo_deepset import PPO_DeepSets
import time
import argparse

SEED = 2


SEED = 2
LOG_PATH = f"./results/ppo_deepset_test_{time.time()}/"
NUM_ENVS = 1

def parse_parameters():
    """
    Parse some parameters from the command line
    :return: (argparse.Namespace) the parsed arguments
    """
    parser = argparse.ArgumentParser(description="Test DeepSets")
    parser.add_argument("--model", type=str, default=None, help="Model to use (ppo or dqn)")
    parser.add_argument("--num_episodes", type=int, default=50, help="Number of episodes to test the model for")
    args = parser.parse_args()
    return args

if __name__ == "__main__":

    args = parse_parameters()
    num_episodes = args.num_episodes
    model_path = args.model
    if model_path is None:
        raise ValueError("Please provide a model path to test your model!")    

    for c in range(num_episodes):
        env = DummyVecEnv([lambda ne=ne: ChaosEnvDeepSet(config={"env_id": ne, "log": LOG_PATH}) for ne in range(NUM_ENVS)])
        agent = PPO_DeepSets(env, num_steps=100, n_minibatches=8, ent_coef=0.001, num_envs=NUM_ENVS, tensorboard_log=LOG_PATH)
        #agent = DQN_DeepSets(env=env, num_steps=100, n_minibatches=8, seed=SEED, tensorboard_log=LOG_PATH)
        agent.load(model_path)
        # Test the agent for 100 episodes
        obs = env.reset()
        action_mask = np.array(env.env_method("action_masks"))
        done = False
        while not done:
            action = agent.predict(obs, action_mask)
            obs, reward, dones, info = env.step(action)
            action_mask = np.array(env.env_method("action_masks"))
            print("Dones: ", dones)
            done = dones[0]
