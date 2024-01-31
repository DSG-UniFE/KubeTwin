import gym
import numpy as np
import random
from env import ChaosEnv
from stable_baselines3 import DQN, PPO
from torch.utils.tensorboard import SummaryWriter

num_tests = 1

for i in range(num_tests):
    # Carica il tuo ambiente e modello salvato
    model = PPO.load("/home/filippo/code/KubeTwin/lib/chaos_rl/chaos_scheduler_ppo.zip")
    #model = DQN.load("models/DQN__totalSteps_1500020240129112302.zip")

    # Numero di run di test e numero di step per ogni test
    num_episodes = 50
    num_steps = 100

    # Esegui le run di test
    for test in range(num_episodes):
        env = ChaosEnv(config={})
        obs = env.reset()
        total_reward = 0
        while True:
            #action, _ = model.predict(obs, deterministic=False)
            action, _ = model.predict(obs, deterministic=False)
            obs, reward, done, info = env.step(action)
            total_reward += reward
            if done:
                break
        # Logga il reward totale su Tensorboard
        #writer.add_scalar("Test/Total Reward", total_reward, test)


