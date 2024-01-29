import gym
import numpy as np
from env import ChaosEnv
from stable_baselines3 import DQN, PPO
from torch.utils.tensorboard import SummaryWriter
import numpy as np

num_tests = 1

''''
Random test to compare our solution with rl-ones
'''
for i in range(num_tests):
    # Carica il tuo ambiente e modello salvato
    # Numero di run di test e numero di step per ogni test
    num_episodes = 50
    num_steps = 100

    '''
    {
        "node_id": @node_id,
        "resources_cpu_available": available_resources_cpu,
        "resources_memory_available": available_resources_memory,
        "cluster_id": @cluster_id,
        "pods": @pods,
        "pod_id_list": @pod_id_list,
      }
    '''
    # Esegui le run di test
    for test in range(num_episodes):
        env = ChaosEnv(config={})
        first = True
        obs = env.reset()
        total_reward = 0
        while True:
            if first:
                action = 0
                first = False
            else:
                '''Analyse the state'''
                # exclude the first three elements of the state
                nodes_info = obs[3:]
                # here the action is to select the node from the ones alive
                # that has the highest amount of CPU and RAM resources available
                selected_node = None
                max_cpu = 0
                max_ram = 0
                for node_id in range(0, len(nodes_info), 3):
                    if nodes_info[node_id + 1] > max_cpu:
                        max_cpu = nodes_info[node_id + 1]
                        max_ram = nodes_info[node_id + 2]
                        selected_node = nodes_info[node_id]
                print(f"Selected node: {selected_node}, CPU: {max_cpu}, RAM: {max_ram}")
                action = selected_node
            print(f"Action: {action}")
            obs, reward, done, info = env.step(action)
            total_reward += reward
            if done:
                break
        # Logga il reward totale su Tensorboard
        #writer.add_scalar("Test/Total Reward", total_reward, test)


