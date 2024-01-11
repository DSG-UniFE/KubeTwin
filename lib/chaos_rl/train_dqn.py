from stable_baselines3 import DQN
from env import ChaosEnv

seed = 2
env = ChaosEnv(config={})  

model = DQN('MlpPolicy', env, verbose=1)  
model.learn(total_timesteps=10000)  # Model training

# Testing
obs = env.reset()
for i in range(100):
    action, _states = model.predict(obs, deterministic=True)
    obs, reward, done, info = env.step(action)
    if done:
      obs = env.reset()