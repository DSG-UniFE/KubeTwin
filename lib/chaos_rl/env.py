import gym
from gym import spaces
import numpy as np
import socket
import json
import wandb

class ChaosEnv(gym.Env):

    """
    Environment for Chaos Engineering on KubeTwin
    """

    def __init__(self, config):
        super(ChaosEnv, self).__init__()
        self.config = config
        #Agente deve avere a disposizione informazioni nodi sani e pod in stato Evicted da allocare --> tra tutti i nodi sani azione, qual'è il migliore per allocare il pod?
        #self.action_space = spaces.Discrete(...) #TODO: Define action space, number of nodes in clusters? 
        self.observation_space = spaces.Box(low=0, high=1, shape=(1,), dtype=np.float32) #TODO: Define observation space, maybe a matrix composed by node metrics?
        self.state = None
        self.steps = 0
        self.max_steps = 100

        self.sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        server_address = '/tmp/chaos_sim.sock'

        try:
            self.sock.connect(server_address)
        except socket.error:
            print("Error in connecting to UNIX socket")
            exit(1)


    def read_state(self):
        print("Waiting for data from socket...")
        evicted_pods_json = self._read_until_newline()
        nodes_alive_json = self._read_until_newline()
        evicted_pods = json.loads(evicted_pods_json)
        nodes_alive = json.loads(nodes_alive_json)
        return f"Read from Socket: Evicted Pods --> {dict(evicted_pods)}, Nodes Still Alive --> {dict(nodes_alive)}"

    ######TODO: Implement this function to read from socket until newline #########
    def _read_until_newline(self): 
        data = []
        while True:
            chunk = self.sock.recv(1).decode('utf-8')
            if chunk == "\n":
                break
            data.append(chunk)
        return ''.join(data)

    def step(self, action):
        #self.steps += 1
        #if action == 0:
        #    self.state = 0
        #elif action == 1:
        #    self.state = 1
        #else:
        #    raise ValueError("Invalid action")
        #if self.steps >= self.max_steps:
        #   done = True
        #else:
        #    done = False
        #return self.state, 0, done, {}
        pass
    
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

if __name__ == "__main__":
    config = {}
    env = ChaosEnv(config)
    result = env.read_state()
    print(result)