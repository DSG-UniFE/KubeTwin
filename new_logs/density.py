import numpy as np
import pandas as pd
import matplotlib.pyplot as plt
import seaborn as sns; sns.set()
import sys
import tikzplotlib

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
plt.xlabel('TTR')
plt.ylabel('Density')
plt.xlim(0, k8s['ttr'].max())
plt.style.use("ggplot")
plt.grid(True)
plt.legend()

plt.show()
#tikzplotlib.save("fig.tex")

#plt.title("RPS {}".format(file_name))
#plt.savefig("dists_comparision_wsd.pdf")


