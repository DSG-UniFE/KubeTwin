from stable_baselines3.common.vec_env import SubprocVecEnv, VecMonitor, VecNormalize
from env_deepset import ChaosEnvDeepSet
from envs.dqn_deepset import DQN_DeepSets
from envs.ppo_deepset import PPO_DeepSets

SEED = 2
MONITOR_PATH = f"./results/dqn_deepset_{SEED}_plot.monitor.csv"

if __name__ == "__main__":
    env = ChaosEnvDeepSet(config={})  
    
    #env.reset() # is already called when the agent calls learn()
    
    # Filippo: why do you need this?
    #_, _, _, info = env.step(0)
    #info_keywords = tuple(info.keys())
    
   #agent = PPO_DeepSets(envs, num_steps=100, n_minibatches=8, ent_coef=0.001, tensorboard_log=None, seed=SEED)
    agent = DQN_DeepSets(env=env, num_steps=100, n_minibatches=8, seed=SEED)

    agent.learn(1500000)
    agent.save(f"./agents/dqn_deepset_{SEED}_plot.py")
