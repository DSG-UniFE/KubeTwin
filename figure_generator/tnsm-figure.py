import pandas as pd
import numpy as np
import matplotlib.pyplot as plt
import sys
import itertools
markers = itertools.cycle(('+', '.', 'o', '*')) 
colors = itertools.cycle(('r', 'g'))

plt.style.use('ggplot')


if len(sys.argv) < 2:
    print("fig.py <csv_file>")
    sys.exit(1)

df_complete = pd.read_csv(sys.argv[1]) 
#df = df_complete[df_complete['Time'] < (df_complete['Time'][0] + 135)]
df = df_complete[df_complete['TTP'] > 0]

grouped = df.groupby('Component')['TTP']


time = df['Time']
ms1_service_time = 0.010 * 1.5
ms2_service_time = 0.020 * 1.5
ms1d = np.repeat(ms1_service_time, len(time))
ms2d = np.repeat(ms2_service_time, len(time))

fig, ax = plt.subplots(figsize=(10,4))

for key, grp in df.groupby(['Component']):
    # calculate SMA for TTP
    grp['TTP-SMA'] = grp['TTP'].rolling(window=5).mean()
    ax.plot(grp['Time'], grp['TTP-SMA'], marker=next(markers), color=next(colors), label=key[0])

ax.plot(time, ms1d, label='MS1-desired', alpha=0.8)
ax.plot(time, ms2d, label='MS2-desired', alpha=0.8)

plt.xlabel('Time (s)')
plt.ylabel('Time To Process (TTP) (s)')
plt.legend(facecolor="white")
#plt.grid()

plt.tight_layout()
plt.show()
fig.savefig('ttp-tnsm.pdf')


markers = itertools.cycle(('+', '.', 'o', '*')) 
colors = itertools.cycle(('r', 'g'))

df = df_complete

fig, ax = plt.subplots(figsize=(10,4))
for key, grp in df.groupby(['Component']):
    ax.plot(grp['Time'],grp['Pods'],label=key[0], marker=next(markers), color=next(colors))



ax.legend()
plt.xlabel('Time (s)')
plt.ylabel('# Pods')
plt.legend(facecolor="white")
#plt.grid()
plt.tight_layout()
plt.show()
fig.savefig('pods-tnsm.pdf')

df = pd.read_csv(sys.argv[2])

markers = itertools.cycle(('+', '.', 'o', '*')) 
colors = itertools.cycle(('r', 'g'))

fig, ax = plt.subplots(figsize=(10,4))
ax.plot(df['Time'],df['CRequests'])

plt.xlabel('Time (s)')
plt.ylabel('Requests per Second (RPS)')
#plt.legend(facecolor="white")
plt.tight_layout()
#plt.grid()
plt.show()
fig.savefig('requests-tnsm.pdf')




