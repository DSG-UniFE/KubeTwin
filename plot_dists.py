import numpy as np
import pandas as pd
import matplotlib.pyplot as plt
import sys

if len(sys.argv) < 4:
    print("Usage: python3 <log-file> <sim-file>")
    exit(1)
log_file = sys.argv[1]
sim_file = sys.argv[2]
file_name = sys.argv[3]

k8s = pd.read_csv(log_file)
sim = pd.read_csv(sim_file)
df = pd.DataFrame({
    'k8s': k8s['ttr'],
    'sim': sim['ttr']})
df.plot.kde()
plt.title("RPS {}".format(file_name))
plt.savefig("dists_comparision_{}.pdf".format(file_name))
