import pandas as pd
import numpy as np
import matplotlib.pyplot as plt
import sys

df = pd.read_csv(sys.argv[1])

for k,g in df.groupby('system'):
    plt.plot(g['rps'], g['mean'], label=k)

plt.legend()
plt.xlabel('RPS')
plt.ylabel('MTTR (s)')
#plt.show()
plt.savefig('mttr-1-20-rps.png')

plt.clf()
for k,g in df.groupby('system'):
    plt.plot(g['rps'], g['99th'], label=k)

plt.legend()
plt.xlabel('RPS')
plt.ylabel('99-th (s)')
plt.savefig('99th-1-20-rps.png')
#plt.show()
