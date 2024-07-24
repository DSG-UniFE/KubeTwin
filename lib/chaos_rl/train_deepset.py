from stable_baselines3.common.vec_env import SubprocVecEnv
from env_deepset import ChaosEnvDeepSet
from envs.ppo_deepset import PPO_DeepSets
from envs.dqn_deepset import DQN_DeepSets

import time

SEED = 2
LOG_PATH = f"./results/dqn_deepset_{time.time()}/"
NUM_ENVS = 1

if __name__ == "__main__":
    env = SubprocVecEnv(
        [
            lambda ne=ne: ChaosEnvDeepSet(config={"env_id": ne, "log": LOG_PATH})
            for ne in range(NUM_ENVS)
        ]
    )
    # state = env.reset()
    # print(state, f"shape: state.shape", state.shape[1])
    
    agent = PPO_DeepSets(
        env,
        num_steps=100,
        n_minibatches=8,
        ent_coef=0.001,
        num_envs=NUM_ENVS,
        tensorboard_log=LOG_PATH,
    )
    

    #agent = DQN_DeepSets(env=env, num_steps=100, n_minibatches=8, seed=SEED, tensorboard_log=LOG_PATH)
    agent.learn(15_000)
    agent.save(f"./agents/ppo_deepset_{time.time()}")
