import gym
from gym import spaces
import numpy as np
import socket
import json
import wandb
import subprocess

class ChaosEnv(gym.Env):

    """
    Environment for Chaos Engineering on KubeTwin
    """

    def __init__(self, config):
        super(ChaosEnv, self).__init__()
        self.config = config 
        self.observation_space = spaces.Box(low=0, high=1, shape=(1,), dtype=np.float32) #TODO: Define observation space, maybe a matrix composed by node metrics?
        self.action_space = None 
        self.state = None
        self.steps = 0
        self.max_steps = 100
        self._connect_to_socket()


    def _connect_to_socket(self):
        
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

    #Function to read state from socket
    def read_state(self):
        print("Waiting for data from socket...")
        evicted_pods_json = self._read_until_newline()
        if evicted_pods_json == "END":
            return None
        nodes_alive_json = self._read_until_newline()
        evicted_pods = json.loads(evicted_pods_json)
        nodes_alive = json.loads(nodes_alive_json)
        self.state = {"evicted_pods": evicted_pods, "nodes_alive": nodes_alive}
        print("Data received from socket: ", self.state)
        self.define_action_space()
        return self.state
    
    #Define action space based on the number of nodes in the cluster
    def define_action_space(self):
        if self.state and "nodes_alive" in self.state:
            self.action_space = list(self.state["nodes_alive"].keys())

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
        info = {"node_id": node_id, "pod_id": pod_id}
        info_json = json.dumps(info)

        try:
            self.sock.sendall(info_json.encode('utf-8'))
        except socket.error as e:
            print("Error in sending data to simulator for the pod reallocation through UNIX socket: {e}")
            exit(1)
    

    def step(self, action):
        self.steps += 1

        #TODO: Function to select node from action space
        selected_node_id = action

        if self.state["evicted_pods"]:
            pod_to_reallocate = next(iter(self.state["evicted_pods"].values()))
            print(f"Pod to reallocate: {pod_to_reallocate}")
            self.reallocate_pod(selected_node_id, pod_to_reallocate["pod_id"])
            reward_json = self._read_until_newline()
            reward = json.loads(reward_json)
            print(f"Reward: {reward}")


        #TODO: Check if the environment is done
        #done = self._check_done()
        
        info = {}
        return self.state, reward, info #done, info

    
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
        #self.steps = 0
        #self.state = 0
        #return self.state
        #TODO: Reset the environment
        #self._connect_to_socket()
        pass

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
    
if __name__ == "__main__":
    config = {}
    # Start Simulator
    start_simulator()
    import time
    env = ChaosEnv(config)
    while True:
        result = env.read_state()
        if result is None:
            print("Episode ended")
            break
        action = 30
        print(f"Testing action: {action}")

        new_state, reward, info = env.step(action) #done, info = env.step(action)

        print(f"New State: {new_state}")
        print(f"Reward: {reward}")
        #print(f"Done: {done}")
        print(f"Info: {info}")
