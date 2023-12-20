import gym
import random
from gym import spaces
import numpy as np
import socket
import json
import wandb
import subprocess
import time

MAX_NUM_PODS = 100
MAX_NUM_NODES = 100

class ChaosEnv(gym.Env):

    """
    Environment for Chaos Engineering on KubeTwin
    """

    def __init__(self, config):
        super(ChaosEnv, self).__init__()
        self.config = config 
        self.observation_space = spaces.Dict({
            "evicted_pods": spaces.Dict({
                "pod_id": spaces.Discrete(100),  
                "original_node": spaces.Discrete(100),
                "node_affinity": spaces.Discrete(10), 
                "requirements": spaces.Dict({
                    "cpu": spaces.Box(low=0, high=np.inf, shape=(1,), dtype=np.float32),
                    "memory": spaces.Box(low=0, high=np.inf, shape=(1,), dtype=np.float32),
                }),
            }),
            "nodes_alive": spaces.Dict({
                "node_id": spaces.Discrete(100),
                "resources_cpu_available": spaces.Box(low=0, high=np.inf, shape=(1,), dtype=np.float32),
                "resources_memory_available": spaces.Box(low=0, high=np.inf, shape=(1,), dtype=np.float32),
            }),
        }) #TODO: Define observation space, maybe a matrix composed by node metrics?
        self.observation_space = spaces.Box(low=-np.inf, high=np.inf, shape=(275, ), dtype=np.float32) #4 as pod features, 6 as node features

        self.episode_over = False
        self.action_space = spaces.Discrete(MAX_NUM_NODES)
        self.available_actions = None


    def _connect_to_socket(self):
        """
        Connect to UNIX socket (simulator)
        """    
        self.sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        server_address = '/tmp/chaos_sim.sock'
        max_attempts = 15
        i = 0
        while i < max_attempts:
            try:
                i += 1
                self.sock.connect(server_address)
            except socket.error:
                print("Error in connecting to UNIX socket, retrying in 0.5 seconds...")
                time.sleep(0.5)
            else:
                break
        if i == max_attempts:
            print("Error in connecting to UNIX socket, max attempts reached")
            raise Exception("Error in connecting to UNIX socket, max attempts reached")                

    def dict_to_array(self, state_dict):
        features = []
        for pod in state_dict["evicted_pods"].values():
            features.append(pod["pod_id"])
            features.append(pod["original_node"])
            features.append(pod["node_affinity"])
            features.append(pod["requirements"]["cpu"])

        for node in state_dict["nodes_alive"].values():
            features.append(node["node_id"])
            features.append(node["resources_cpu_available"])
            features.append(node["resources_memory_available"])

        return np.array(features, dtype=np.float32)


    def read_state(self):
        print("Waiting for data from socket...")
        evicted_pods_json = self._read_until_newline()
        if evicted_pods_json == "END":
            return None, None
        nodes_alive_json = self._read_until_newline()
        evicted_pods = json.loads(evicted_pods_json)
        nodes_alive = json.loads(nodes_alive_json)
        self.state = self.dict_to_array({"evicted_pods": evicted_pods, "nodes_alive": nodes_alive})
        self.define_action_space(nodes_alive)
        print(f"State read from socket: {self.state}")
        return self.state, evicted_pods


    #Define action space based on the number of nodes in the cluster
    def define_action_space(self, nodes_alive):
        if nodes_alive:
            self.available_actions = list(int(i) for i in nodes_alive.keys())
            print(f"Available actions: {self.available_actions}")
        else:
            print("No live nodes available to define action space.")
            self.available_actions = []

    #Function to read from socket until newline --> separate Evicted Pods and Nodes Alive
    def _read_until_newline(self): 
        data = []
        while True:
            chunk = self.sock.recv(1).decode('utf-8')
            if chunk == "\n":
                break
            data.append(chunk)
        return ''.join(data)
    
    def reallocate_pod(self, node_id, pod_id):
        info = {"node_id": int(node_id), "pod_id": int(pod_id)}
        print(f"Sending info to simulator for the pod reallocation: {info}")
        info_json = json.dumps(info)

        try:
            self.sock.sendall(info_json.encode('utf-8'))
        except socket.error as e:
            print("Error in sending data to simulator for the pod reallocation through UNIX socket: {e}")
            exit(1)

    def _check_done(self):
        if self.steps >= self.max_steps:
            return True
        return False
    

    def step(self, action):
        self.steps += 1

        state, evicted_pods = self.read_state()
        if state is None:
            self.episode_over = True
            print("Episode ended")
            self.sock.close()
            return self.state, self.total_reward, self.episode_over, {}
        self.state = state
        
        if action not in self.available_actions:
            print(f"Action {action} not in action space")
            reward = -1
            self.total_reward += reward
            self.episode_over = True
            return self.state, self.total_reward, self.episode_over, {"error": "Action not in action space"}
        else:
        #TODO: Function to select node from action space
            if evicted_pods:
                for pod_id, pod_data in evicted_pods.items():
                    print(f"Current Pod to reallocate: {pod_id}")
                    #action = random.choice(self.action_space)
                    print(f"Testing action: {action}")
                    print(f"Selected node: {action}")
                    self.reallocate_pod(action, pod_id)
                    reward_json = self._read_until_newline()
                    reward = json.loads(reward_json)
                    print(f"Pod Reward: {reward}")
                    self.total_reward += reward
                    print(f"Total Reward: {self.total_reward}")
            
            self.sock.sendall("END_PODS".encode('utf-8'))
            #print("Reallocation of pods ended --> Episode ended")
            print(f"Returning state: {self.state}")
            print(f"Returning reward: {self.total_reward}")
            print(f"Returning done: {self.episode_over}")
            return self.state, self.total_reward, self.episode_over, {}  

    
    def calculate_reward(self, action):
        """
        Calculate reward for the given action
        - Se individuato nodo sotto pressione con le risorse rimaste, reward inferiore rispetto a nodi con risorse disponibili maggiori o penalità per aver messo sotto
          pressione nodo quando ne avevo altri più liberi
        - Possibile reward aggiuntivo per nodi di tipo Edge piuttosto che Cloud
        """
        pass

    def reset(self):
        """
        Reset the environment
        """
        start_simulator()
        self._connect_to_socket()
        self.state = {}
        self.action_space = None 
        self.state = None
        self.steps = 0
        self.max_steps = 100
        self.total_reward = 0
        self.episode_over = False



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


def start_simulator(config_file="examples/example-hpa.conf"):
    """
    Start the ruby simulator as a separate subprocess
    We need to change the working directory to ../.. because the simulator must be called with bundler
    bundle exec bin/kube_twin example/example_hpa.conf
    """
    subprocess.Popen(["bundle", "exec", "bin/kube_twin", config_file], cwd="../..")
    print("Simulator started")

'''   
if __name__ == "__main__":
    config = {}
    # Start Simulator
    # Just an episode example
    env = ChaosEnv(config)
    env.reset()
    while True:
        result = env.read_state()
        if result is None:
            print("Episode ended")
            break
        
        new_state, reward, episode_over, info = env.step() 

        print(f"Reward: {reward}")
        #print(f"Done: {done}")
        print(f"Info: {info}")
'''