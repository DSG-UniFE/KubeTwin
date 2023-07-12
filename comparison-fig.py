import pandas as pd
import numpy as np
import matplotlib.pyplot as plt
import sys
from sklearn.metrics import mean_squared_error

df = pd.read_csv(sys.argv[1])

mse = 0
for k,g in df.groupby('system'):
    plt.plot(g['rps'], g['mean'], label=k)

k8s = df[df['system'] == 'KubeTwin']
kt = df[df['system'] == 'K8S']

mse_mean = mean_squared_error(k8s['mean'][0:30], kt['mean'][0:30])
mse_99 = mean_squared_error(k8s['99th'][0:30], kt['99th'][0:30])
print(f'MSEs mean: {mse_mean} 99th: {mse_99}')


plt.legend()
plt.xlabel('RPS')
plt.ylabel('MTTR (s)')
plt.grid()
#plt.show()
plt.savefig('mttr-1-20-rps.pdf')

plt.clf()
for k,g in df.groupby('system'):
    plt.plot(g['rps'], g['99th'], label=k)

plt.legend()
plt.xlabel('RPS')
plt.ylabel('99-th (s)')
plt.grid()
plt.savefig('99th-1-20-rps.pdf')
#plt.show()

# all-in version
plt.clf()
import itertools
markers = itertools.cycle((',', '+', '.', 'o', '*')) 

for k,g in df.groupby('system'):
   plt.plot(g['rps'][0:30], g['mean'][0:30], label=k+'-mean', marker=next(markers))

for k,g in df.groupby('system'):
    plt.plot(g['rps'][0:30], g['99th'][0:30], label=k+'-99th', marker=next(markers))

plt.legend()
plt.xlabel('RPS')
plt.ylabel('TTR (s)')
plt.grid()
plt.savefig('comp-mttr-99-20-rps.pdf')
#plt.show()
