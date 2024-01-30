from stable_baselines3 import PPO
from env import ChaosEnv
import time 

LOG_PATH = f"./results/ppo_{time.time()}/"
seed = 2
env = ChaosEnv(config=[LOG_PATH])  

model = PPO('MlpPolicy', env, verbose=1, tensorboard_log=LOG_PATH)  
model.learn(total_timesteps=50000)  # Model training
model.save("chaos_scheduler_ppo")


# Testing
obs = env.reset()
for i in range(100):
    action, _states = model.predict(obs, deterministic=True)
    obs, reward, done, info = env.step(action)
    if done:
      obs = env.reset()
