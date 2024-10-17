import gym
import random
from gym import spaces
import numpy as np
import socket
import json
import wandb
import subprocess
import time
from transformers import BertTokenizer, BertModel
import torch

from tensorboardX import SummaryWriter

MAX_NUM_PODS = 20
MAX_NUM_NODES = 100

class ChaosEnv(gym.Env):

    """
    Environment for Chaos Engineering on KubeTwin
    """

    def __init__(self, config):
        super(ChaosEnv, self).__init__()
        self.config = config 
        self.observation_space = spaces.Box(low=-np.inf, high=np.inf, shape=(768, ), dtype=np.float32) #4 as pod features, 6 as node features
        self.episode_over = False
        self.action_space = spaces.Discrete(MAX_NUM_NODES)
        self.available_actions = np.arange(MAX_NUM_NODES)
        self.writer = SummaryWriter(f'results/dqn_{int(time.time())}')
        # load the transformers
        self.tokenizer = BertTokenizer.from_pretrained('bert-base-uncased')
        self.model = BertModel.from_pretrained('bert-base-uncased')
        self.total_step = 0

    def _connect_to_socket(self):
        """
        Connect to UNIX socket (simulator)
        """    
        self.sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        server_address = '/tmp/chaos_sim.sock'
        time.sleep(0.25)
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
            #features.append(pod["node_affinity"])
            features.append(pod["requirements"]["cpu"])

        for node in state_dict["nodes_alive"].values():
            features.append(node["node_id"])
            features.append(node["resources_cpu_available"])
            features.append(node["resources_memory_available"])
        print(f"Features Length: {len(features)}")

        if len(features) < self.observation_space.shape[0]:
            features.extend([0] * (self.observation_space.shape[0] - len(features)))

        return np.array(features, dtype=np.float32)
    
    def dict_to_embedding(self, input_dict, tokenizer, model):
        # Convert a dictionary into a stringdic_string
        dic_string = str(input_dict)
    
        # Tokenize the dic_string
        inputs = tokenizer(dic_string, return_tensors="pt", truncation=True, max_length=512)
        
        with torch.no_grad():
            outputs = model(**inputs)

        # Get the embedding of the [CLS] tokenizer
        embedding = outputs.last_hidden_state[:, 0, :] 

        return embedding

    def read_state(self):
        print("RL: Waiting for data from socket...")
        evicted_pod_json = self._read_until_newline()
        if evicted_pod_json is None:
            return None, None
        if evicted_pod_json.startswith("END"):
            reward = evicted_pod_json.split(';')[1]
            return None, reward
        nodes_alive_json = self._read_until_newline()
        if nodes_alive_json is None:
            return None, None
        evicted_pod = json.loads(evicted_pod_json)
        nodes_alive = json.loads(nodes_alive_json)
        self.state = self.dict_to_embedding({"evicted_pods": evicted_pod, "nodes_alive": nodes_alive}, self.tokenizer, self.model)
        print(f"Self.state lenght: {self.state.shape}")
        self.define_action_space(nodes_alive)
        #print(f"RL: State read from socket: {self.state}")
        return self.state, evicted_pod


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
            try:
                chunk = self.sock.recv(1).decode('utf-8')
            except socket.error as e:
                print("Error in reading data from UNIX socket: {e}")
                self.sock.close()
                return None
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
        self.total_step += 1
        state, evicted_pods = self.read_state()

        if state is None and evicted_pods is None:
            self.episode_over = True
            print("Episode ended")
            reward = 0
            self.writer.add_scalar('Step Reward', reward, self.total_step)
            self.writer.add_scalar('Episodic return', self.total_reward, self.total_step)
            self.sock.close()
            return self.state, reward, self.episode_over, {}
        
        if state is None:
            self.episode_over = True
            print("Episode ended")
            reward = float(evicted_pods)
            self.total_reward += reward
            self.writer.add_scalar('Step Reward', reward, self.total_step)
            self.writer.add_scalar('Episodic return', self.total_reward, self.total_step)
            self.sock.close()
            return self.state, reward, self.episode_over, {}
        self.state = state
        
        if action not in self.available_actions:
            print(f"Action {action} not in action space")
            # threat this as a NULL action and penalize the agent

            self.sock.sendall("WRONG_ACTION".encode('utf-8'))
            reward_json = self._read_until_newline()

            reward = json.loads(reward_json)
            print(f"Reward Wrong Action: {reward}")
            self.total_reward += reward

        else:
            if evicted_pods:
                pod_id = evicted_pods["pod_id"]
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
            
        #self.sock.sendall("END_PODS".encode('utf-8'))
        #print(f"Returning state: {self.state}")
        print(f"Returning reward: {self.total_reward}")
        print(f"Returning done: {self.episode_over}")

        self.writer.add_scalar('Step Reward', reward, self.total_step)
        return self.state, reward, self.episode_over, {}  

    
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
        self.state = self.dict_to_embedding({'list': [0,0,0,0]}, self.tokenizer, self.model)
        #self.action_space = None 
        #self.state = None
        self.steps = 0
        self.max_steps = 100
        self.total_reward = 0
        self.episode_over = False

        return self.state



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
