
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
from tensorboardX import SummaryWriter


MAX_NUM_PODS = 20
MAX_NUM_NODES = 90
NUM_FEATURES = 7

logging.basicConfig(level=logging.INFO)


class ChaosEnvDeepSet(gym.Env):
    """
    Environment for Chaos Engineering on KubeTwin
    """

    def __init__(self, config):
        super(ChaosEnvDeepSet, self).__init__()
        self.config = config
        if self.config:
            self.env_id = self.config["env_id"]
            # LOG_PATH = self.config["log"]
        else:
            self.env_id = 1
        LOG_PATH = f"./results/ppo_ds_{time.time()}/"
        self.observation_space = spaces.Box(
            low=0, high=100.0, shape=(MAX_NUM_NODES, NUM_FEATURES), dtype=np.float32
        )  # 4 as pod features, 6 as node features
        logging.debug(self.observation_space.shape, self.env_id)
        logging.debug(LOG_PATH)
        self.episode_over = False
        self.action_space = spaces.Discrete(MAX_NUM_NODES)
        self.available_actions = np.arange(MAX_NUM_NODES)
        self.writer = SummaryWriter(LOG_PATH)
        self.total_step = 0
        self.pod_received = 0
        self.pod_reallocated = 0

    def _connect_to_socket(self, env_id=1):
        """
        Connect to UNIX socket (simulator)
        """
        self.sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        server_address = f"/tmp/chaos_telka_{str(env_id)}.sock"
        max_attempts = 15
        i = 0
        time.sleep(0.5)
        while i < max_attempts:
            try:
                i += 1
                self.sock.connect(server_address)
            except socket.error:
                logging.error(
                    "Error in connecting to UNIX socket, retrying in 0.5 seconds...",
                    server_address,
                )
                time.sleep(0.5)
            else:
                break
        if i == max_attempts:
            logging.error("Error in connecting to UNIX socket, max attempts reached")
            raise Exception("Error in connecting to UNIX socket, max attempts reached")

    def dict_to_array(self, state_dict):
        features = []
        pod = state_dict["evicted_pods"]
        # Create a dummy pod if no pod is evicted is given... this allows us to described the initial state
        if pod is None:
            pod = {"pod_id": -1, "original_node": -1, "requirements": {"cpu": -1}}
        logging.debug(f"Pod: {pod}")
        for node in state_dict["nodes_alive"].values():
            features.append(
                [
                    node["node_id"],
                    node["resources_cpu_available"],
                    node["resources_memory_available"],
                    node["operational_status"],
                    pod["pod_id"],
                    pod["original_node"],
                    pod["requirements"]["cpu"],
                ]
            )

        # logging.debug(f"Features Length: {len(features)}")

        return np.array(features, dtype=np.float32)

    def read_initial_state(self):
        logging.info("RL: Waiting for the initial state from socket...")
        nodes_alive_json = self._read_until_newline()
        # sending ack to socket
        self.sock.send("OK\n".encode("utf-8"))
        nodes_alive = json.loads(nodes_alive_json)
        self.state = self.dict_to_array(
            {"evicted_pods": None, "nodes_alive": nodes_alive}
        )

    def read_state(self):
        # logging.debug("RL: Waiting for data from socket...")
        evicted_pod_json = self._read_until_newline()
        if evicted_pod_json is None:
            return None, None
        if evicted_pod_json.startswith("END"):
            reward = evicted_pod_json.split(";")[3]
            ratio = evicted_pod_json.split(";")[1]
            med_ttr = evicted_pod_json.split(";")[2]

            self.writer.add_scalar("Testing_Ratio", float(ratio), self.total_step)
            self.writer.add_scalar("Testing_Med_TTR", float(med_ttr), self.total_step)
            self.writer.add_scalar(
                "Testing_Pods_Received", self.pod_received, self.total_step
            )
            self.writer.add_scalar(
                "Testing_Pods_Reallocated", self.pod_reallocated, self.total_step
            )
            # self.writer.add_scalar('Testing Pods Reallocated Ratio', self.pod_reallocated/self.pod_received, self.total_step)
            return None, reward
        self.sock.send("OK\n".encode("utf-8"))
        nodes_alive_json = self._read_until_newline()
        evicted_pod = json.loads(evicted_pod_json)
        nodes_alive = json.loads(nodes_alive_json)
        self.state = self.dict_to_array(
            {"evicted_pods": evicted_pod, "nodes_alive": nodes_alive}
        )
        # logging.debug(f"RL: State read from socket: {self.state} {self.state.shape}")
        return self.state, evicted_pod

    def action_masks(self):
        masks = np.zeros(MAX_NUM_NODES, dtype=np.float32)
        for action in self.available_actions:
            if 0 <= action < len(masks):
                masks[action] = 1
            else:
                logging.debug(f"Azione non valida: {action}")
        return masks

    # Function to read from socket until newline --> separate Evicted Pods and Nodes Alive
    def _read_until_newline(self):
        data = []
        while True:
            try:
                self.sock.settimeout(5)
                chunk = self.sock.recv(1).decode("utf-8")
            except (socket.error, TimeoutError) as e:
                logging.error(f"Error in reading data from UNIX socket: {e}")
                # self.sock.close()
                # self.reset()
                return None
            if chunk == "\n":
                break
            data.append(chunk)
        return "".join(data)

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
        self.steps += 1
        self.total_step += 1
        state, evicted_pods = self.read_state()

        if state is None and evicted_pods is None:
            self.episode_over = True
            logging.info("Episode ended {} {}", state, evicted_pods)
            reward = 0
            self.writer.add_scalar("Step_Reward".format(reward, self.total_step))
            self.writer.add_scalar(
                "Episodic_return", self.total_reward, self.total_step
            )
            self.sock.close()
            return self.state, reward, self.episode_over, False, {}

        if state is None:
            self.episode_over = True
            logging.info("Episode ended {} {}".format(state, evicted_pods))
            reward = float(evicted_pods)
            self.total_reward += reward
            self.writer.add_scalar("Step_Reward", reward, self.total_step)
            self.writer.add_scalar(
                "Episodic_return", self.total_reward, self.total_step
            )
            self.sock.close()
            return self.state, reward, self.episode_over, False, {}

        self.state = state

        if evicted_pods:
            self.pod_received += 1

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
        start_simulator(self.env_id)
        self._connect_to_socket(self.env_id)
        self.action_space = spaces.Discrete(MAX_NUM_NODES)
        # self.state = None
        # Calling read initial state to initialize the self.state
        self.read_initial_state()
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


def start_simulator(env_id=1, config_file="examples/example-hpa.conf"):
    """
    Start the ruby simulator as a separate subprocess
    We need to change the working directory to ../.. because the simulator must be called with bundler
    bundle exec bin/kube_twin example/example_hpa.conf
    """
    logging.debug(f"About to start the simulator: {env_id}")
    subprocess.Popen(
        ["bundle", "exec", "bin/kube_twin", config_file, str(env_id)], cwd="../.."
    )
    logging.debug("Simulator started")


"""   
if __name__ == "__main__":
    config = {}
    # Start Simulator
    # Just an episode example
    env = ChaosEnv(config)
    env.reset()
    while True:
        result = env.read_state()
        if result is None:
            logging.debug("Episode ended")
            break
        
        new_state, reward, episode_over, info = env.step() 

        logging.debug(f"Reward: {reward}")
        #logging.debug(f"Done: {done}")
        logging.debug(f"Info: {info}")
"""
