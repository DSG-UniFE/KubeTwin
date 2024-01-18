from stable_baselines3.common.vec_env import SubprocVecEnv, VecMonitor, VecNormalize
from env_deepset import ChaosEnvDeepSet
from envs.dqn_deepset import DQN_DeepSets
from envs.ppo_deepset import PPO_DeepSets

import time

SEED = 2
LOG_PATH = f"./results/dqn_deepset_{time.time()}/"

if __name__ == "__main__":
    env = ChaosEnvDeepSet(config={})  
    
    
   #agent = PPO_DeepSets(envs, num_steps=100, n_minibatches=8, ent_coef=0.001, tensorboard_log=None, seed=SEED)
    agent = DQN_DeepSets(env=env, num_steps=100, n_minibatches=8, seed=SEED, tensorboard_log=LOG_PATH)

    agent.learn(50000)
    agent.save(f"./agents/dqn_deepset_{SEED}_plot.py")
