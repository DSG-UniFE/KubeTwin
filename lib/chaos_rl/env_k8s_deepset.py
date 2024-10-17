import gymnasium as gym
import random
from gymnasium import spaces
import numpy as np
import socket
import json
import wandb
import subprocess
import time
import torch
import logging
import os
from tensorboardX import SummaryWriter


MAX_NUM_PODS = 20
MAX_NUM_NODES = 3
NUM_FEATURES = 7

logging.basicConfig(level=logging.DEBUG)


class ChaosEnvDeepSet(gym.Env):
    """
    Environment for Chaos Engineering on KubeTwin
    """

    def __init__(self, config):
        super(ChaosEnvDeepSet, self).__init__()
        self.config = config
        if self.config:
            self.env_id = self.config["env_id"]
        else:
            self.env_id = 1
        LOG_PATH = f"./results/ppo_ds_{time.time()}/"
        self.observation_space = spaces.Box(
            low=0, high=100.0, shape=(MAX_NUM_NODES, NUM_FEATURES), dtype=np.float32
        )  # 4 as pod features, 6 as node features
        logging.debug(LOG_PATH)
        self.episode_over = False
        self.action_space = spaces.Discrete(MAX_NUM_NODES)
        self.available_actions = np.arange(MAX_NUM_NODES)
        self.writer = SummaryWriter(LOG_PATH)
        self.total_step = 0
        self.pod_received = 0
        self.pod_reallocated = 0
        self.conn = None
        self._create_server()
        #self._create_reward_server()

    def _create_server(self, path="/tmp/telka.sock", env_id=1):
        """
        Connect to UNIX socket server
        """
        self.sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        server_address = path
        # Just remove the path to socket if it already exists
        try:
            os.remove(server_address)
        except FileNotFoundError as e:
            pass
        # Then listen for connections 
        self.sock.bind(server_address)
        self.sock.listen(1)
        logging.debug(f"RL: Waiting for connection on {server_address}")

    def _create_reward_server(self, path="/tmp/rtelka.sock", env_id=1):
        """
        Connect to UNIX socket server
        """
        self.rsock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        server_address = path
        # Just remove the path to socket if it already exists
        try: 
            os.remove(server_address)
        except FileNotFoundError as e:
            pass
        # Then listen for connections 
        self.rsock.bind(server_address)
        self.rsock.listen(1)
        logging.info(f"RL: Waiting for connection on {server_address}")

    def dict_to_array(self, state_dict):
        return np.array(state_dict["state"], dtype=np.float32)

    def read_state(self):
        # logging.debug("RL: Waiting for data from socket...")
        self.conn, client_address = self.sock.accept()
        json_data = self.conn.recv(2048).decode("utf-8")
        logging.debug(f"RL: Received data from socket: {json_data}")
        data = json.loads(json_data)
        self.state = self.dict_to_array({"state": data})
        logging.debug(f"RL: State shape: {self.state.shape}")
        # Send an acknowledgment to the client 
        #conn.sendall("OK\n".encode("utf-8"))
        #conn.close()
        return self.state

    def action_masks(self):
        # State example [[0,0,0,0,-1,-1,150],[1,983,775363072,0,-1,-1,150],[2,990,803002880,0,-1,-1,150]]
        masks = np.zeros(MAX_NUM_NODES, dtype=np.float32)
        for action in self.available_actions:
            if 0 <= action < len(masks):
                # CPU limit in action_masking if pod cpu requirements are greater than node cpu available
                if self.state[action][-1] > self.state[action][1]:
                    masks[action] = 0
                else:
                    masks[action] = 1
            else:
                logging.debug(f"Azione non valida: {action}")
        return masks


    def reallocate_pod(self, node_id, pod_id):
        info = {"node_id": int(node_id), "pod_id": int(pod_id)}
        # logging.debug(f"Sending info to simulator for the pod reallocation: {info}")
        info_json = json.dumps(info)

        try:
            self.sock.sendall(info_json.encode("utf-8"))
        except socket.error as e:
            logging.error(
                "Error in sending data to simulator for the pod reallocation through UNIX socket: {e}"
            )
            exit(1)

    def _check_done(self):
        if self.steps >= self.max_steps:
            return True
        return False

    def step(self, action):
        if self.steps != 0: state = self.read_state()
        state = self.state
        # Send the action to the client 
        self.conn.sendall(str(action).encode("utf-8"))
        #self.conn.close()
        #self.rconn = self.rsock.accept()
        # Read the reward from connection
        reward = self.conn.recv(1024).decode("utf-8")
        reward = int(reward)
        # Then close the connection
        self.conn.close()
        #self.rconn.close()
        #conn.sendall("OK\n".encode("utf-8"))
        self.steps += 1
        self.total_step += 1
        #state = self.read_state()
        logging.debug(f"RL: Step: {self.steps}, action: {action} in state: {state}, reward: {reward}")

        if state is None:
            self.episode_over = True
            logging.info("Episode ended {} {}".format(state))
            return self.state, reward, self.episode_over, False, {}

        self.state = state
        self.pod_received += 1

        logging.info(f"Step: {self.steps}, action: {action}")

        """

        if action not in self.available_actions:
            # logging.debug(f"Action {action} not in action space")
            # threat this as a NULL action and penalize the agent

            self.sock.sendall("WRONG_ACTION".encode("utf-8"))
            reward_json = self._read_until_newline()
            reward = json.loads(reward_json)
            # logging.debug(f"Reward Wrong Action: {reward}")
            self.total_reward += reward
            self.sock.sendall("OK\n".encode("utf-8"))

        else:
            if evicted_pods:
                pod_id = evicted_pods["pod_id"]
                # logging.debug(f"Current Pod to reallocate: {pod_id}")
                # logging.debug(f"Testing action: {action}")
                # logging.debug(f"Selected node: {action}")
                self.reallocate_pod(action, pod_id)
                reward_json = self._read_until_newline()
                reward = json.loads(reward_json)
                # logging.debug(f"Pod Reward: {reward}")
                if reward > 0:
                    self.pod_reallocated += 1
                self.total_reward += reward
                logging.info("Total Reward: {}".format(self.total_reward))
                self.sock.sendall("OK\n".encode("utf-8"))
            else:
                logging.info("No pods to reallocate")

        # logging.debug(f"Returning reward: {self.total_reward}")
        # logging.debug(f"Returning done: {self.episode_over}")
        """

        self.writer.add_scalar("Step_Reward", reward, self.total_step)
        """
        False stands for truncated here
        """
        return self.state, reward, self.episode_over, False, {}

    def calculate_reward(self, action):
        """
        Calculate reward for the given action
        - Se individuato nodo sotto pressione con le risorse rimaste, reward inferiore rispetto a nodi con risorse disponibili maggiori o penalità per aver messo sotto
          pressione nodo quando ne avevo altri più liberi
        - Possibile reward aggiuntivo per nodi di tipo Edge piuttosto che Cloud
        """
        pass

    def reset(self, seed=None, **options):
        """
        Reset the environment
        """
        logging.debug("RL: Resetting environment")
        self.action_space = spaces.Discrete(MAX_NUM_NODES) 
        self.state = self.read_state()
        # Calling read initial state to initialize the self.state
        # logging.warning(f"RL: Read initial state, shape: {self.state.shape}")
        # logging.warning(f"RL: Read initial state, {self.state}")
        self.steps = 0
        self.max_steps = 100
        self.total_reward = 0
        self.episode_over = False
        self.pod_received = 0
        self.pod_reallocated = 0
        # logging.debug("RL: Environment reset", f"{self.state.shape}")

        return self.state, {}

    def seed(self, seed=None):
        """
        Generate a random seed
        """
        seed = random.randint(0, 100)
        return [seed]

    def render(self, mode="human"):
        """
        Render the environment
        """
        pass

    def close(self):
        """
        Close the environment
        """
        pass

