from stable_baselines3 import DQN
from env_embeddings import ChaosEnv
from datetime import datetime

import time

LOG_PATH = f"./results/dqn_{time.time()}/"

env = ChaosEnv(config={})  

#model = DQN('MlpPolicy', env, verbose=1, tensorboard_log=LOG_PATH)  
#TODO Load the model
# Testing
obs = env.reset()
steps = 1000
total_reward = 0
for i in range(steps):
    #action, _states = model.predict(obs, deterministic=True)
    action = env.action_space.sample()
    obs, reward, done, info = env.step(action)
    total_reward  += reward
    if done:
      obs = env.reset()

print(f"Avg reward: {total_reward / steps} after {steps} steps")
