from stable_baselines3 import PPO
from env import ChaosEnv
import time 

seed = 2
env = ChaosEnv(config={})  

model = PPO('MlpPolicy', env, verbose=1, tensorboard_log="./t_log")  
model.learn(total_timesteps=10000, tb_log_name=f"{time.time()}_run")  # Model training
model.save("chaos_scheduler_ppo")


# Testing
obs = env.reset()
for i in range(100):
    action, _states = model.predict(obs, deterministic=True)
    obs, reward, done, info = env.step(action)
    if done:
      obs = env.reset()
