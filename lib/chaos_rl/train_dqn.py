from stable_baselines3 import DQN, PPO
from env import ChaosEnv
from datetime import datetime

import time

LOG_PATH = f"./results/dqn_{time.time()}/"

env = ChaosEnv(config=[LOG_PATH])  
num_steps = 50000
model = DQN('MlpPolicy', env, verbose=1, tensorboard_log=LOG_PATH)  
model.learn(total_timesteps=num_steps)  # Model training
model.save("models/DQN__totalSteps_" + str(num_steps) + str(datetime.today().strftime('%Y%m%d%H%M%S')))
'''
# Testing
obs = env.reset()
for i in range(100):
    action, _states = model.predict(obs, deterministic=True)
    obs, reward, done, info = env.step(action)
    if done:
      obs = env.reset()
'''
