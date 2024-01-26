import gym
import numpy as np
from env import ChaosEnv
from stable_baselines3 import DQN
from torch.utils.tensorboard import SummaryWriter

# Carica il tuo ambiente e modello salvato
env = ChaosEnv(config={})
model = DQN.load("models/DQN__totalSteps_5000020240125120858.zip")

# Crea un writer di Tensorboard
#writer = SummaryWriter(log_dir='results/testing')

# Numero di run di test e numero di step per ogni test
num_tests = 50
num_steps = 100

# Esegui le run di test
for test in range(num_tests):
    obs = env.reset()
    total_reward = 0
    for step in range(num_steps):
        action, _states = model.predict(obs, deterministic=True)
        obs, reward, done, info = env.step(action)
        total_reward += reward
        if done:
            break
    # Logga il reward totale su Tensorboard
    #writer.add_scalar("Test/Total Reward", total_reward, test)


