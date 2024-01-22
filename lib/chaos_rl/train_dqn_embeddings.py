from stable_baselines3 import DQN
from env_embeddings import ChaosEnv
from datetime import datetime

import time

LOG_PATH = f"./results/dqn_{time.time()}/"

env = ChaosEnv(config={})  

model = DQN('MlpPolicy', env, verbose=1, tensorboard_log=LOG_PATH)  
model.learn(total_timesteps=50000)  # Model training
model.save("models/DQN__totalSteps_" + str(50000) + str(datetime.today().strftime('%Y%m%d%H%M%S')))
# Testing
obs = env.reset()
for i in range(100):
    action, _states = model.predict(obs, deterministic=True)
    obs, reward, done, info = env.step(action)
    if done:
      obs = env.reset()
