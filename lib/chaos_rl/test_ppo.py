import gym
import numpy as np
from env import ChaosEnv
from stable_baselines3 import DQN, PPO
from torch.utils.tensorboard import SummaryWriter

num_tests = 20

for i in range(num_tests):
    # Carica il tuo ambiente e modello salvato
    env = ChaosEnv(config={})
    model = PPO.load("models/PPO__totalSteps_5000020240126183537.zip")

    # Numero di run di test e numero di step per ogni test
    num_episodes = 50
    num_steps = 100

    # Esegui le run di test
    for test in range(num_episodes):
        obs = env.reset()
        total_reward = 0
        for step in range(num_steps):
            action, _ = model.predict(obs, deterministic=False)
            obs, reward, done, info = env.step(action)
            total_reward += reward
            if done:
                break
        # Logga il reward totale su Tensorboard
        #writer.add_scalar("Test/Total Reward", total_reward, test)


