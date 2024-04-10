from stable_baselines3.common.vec_env import SubprocVecEnv, VecMonitor, VecNormalize, DummyVecEnv
from env_deepset import ChaosEnvDeepSet
from envs.dqn_deepset import DQN_DeepSets
from envs.ppo_deepset import PPO_DeepSets

import time

SEED = 2
LOG_PATH = f"./results/ppo_deepset_{time.time()}/"

if __name__ == "__main__":

    env = DummyVecEnv([lambda: ChaosEnvDeepSet(config={}) ])
    #state = env.reset()
    #print(state, f"shape: state.shape", state.shape[1])
    
    agent = PPO_DeepSets(env, num_steps=100, n_minibatches=8, ent_coef=0.001, num_envs=1, tensorboard_log=LOG_PATH)
    #agent = DQN_DeepSets(env=env, num_steps=100, n_minibatches=8, seed=SEED, tensorboard_log=LOG_PATH)

    agent.learn(50_000)
    agent.save(f"./agents/ppo_deepset_{SEED}_plot.py")
