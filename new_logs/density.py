import numpy as np
import pandas as pd
import matplotlib.pyplot as plt
#import seaborn as sns; sns.set()
import sys

if len(sys.argv) < 3:
    print("Usage: python3 <log-file> <sim-file>")
    exit(1)

log_file = sys.argv[1]
sim_file = sys.argv[2]

k8s = pd.read_csv(log_file)
sim = pd.read_csv(sim_file)
df = pd.DataFrame({
    'K8S': k8s['ttr'],
    'KubeTwin': sim['ttr']})
df.plot.kde()
plt.rcParams.update({'font.size': 22})
plt.xlabel('TTR (s)')
plt.ylabel('Density')
plt.xlim(0, k8s['ttr'].max())
plt.style.use("ggplot")
plt.grid()
plt.legend(facecolor="white")

#plt.show()
#plt.title("RPS {}".format(file_name))
plt.savefig("dists_comparision_rev.pdf")


