import pandas as pd
import numpy as np
import matplotlib.pyplot as plt
import sys
import itertools
markers = itertools.cycle(('+', '.', 'o', '*')) 
colors = itertools.cycle(('r', 'g'))

plt.style.use('ggplot')

#plt.rcParams.update({'font.size': 18})

if len(sys.argv) < 2:
    print("fig.py <csv_file>")
    sys.exit(1)

df = pd.read_csv(sys.argv[1]) 
#df = df_complete[df_complete['Time'] < (df_complete['Time'][0] + 135)]
#df = df_complete[df_complete['TTP'] > 0]
#df = df_complete

grouped = df.groupby('Component')['TTP']


time = df['Time']
ms1_service_time = 0.010 * 1.5
ms2_service_time = 0.020 * 1.5
ms1d = np.repeat(ms1_service_time, len(time))
ms2d = np.repeat(ms2_service_time, len(time))

plt.rc('legend', fontsize=12)    # legend fontsize
plt.rc('axes', labelsize=15)    # fontsize of the x and y labels
plt.rc('xtick', labelsize=15)    # fontsize of the tick labels
plt.rc('ytick', labelsize=15)    # fontsize of the tick labels

fig, ax = plt.subplots(figsize=(10,5))

grouped = df.groupby('Component')
df['Index'] = grouped.cumcount().reset_index(drop=True)

for key, grp in df.groupby(['Component']):
    # calculate SMA for TTP
    grp['TTP-SMA'] = grp['TTP'].rolling(window=5).mean()
    ax.plot(grp['Index'], grp['TTP-SMA'], marker=next(markers), color=next(colors), label=key[0])

ax.plot(df['Index'], ms1d, label='MS1-desired', alpha=0.8)
ax.plot(df['Index'], ms2d, label='MS2-desired', alpha=0.8)

plt.xlabel('Time (s)')
plt.ylabel('Time To Process (TTP) (s)')
plt.legend(facecolor="white")


# plt.grid()


plt.tight_layout()
plt.show()
fig.savefig('ttp-tnsm.pdf')


markers = itertools.cycle(('+', '.', 'o', '*')) 
colors = itertools.cycle(('r', 'g'))


fig, ax = plt.subplots(figsize=(10,5))


for key, grp in df.groupby(['Component']):
    ax.plot(grp['Index'],grp['Pods'],label=key[0], marker=next(markers), color=next(colors))



ax.legend()
plt.xlabel('Time (s)')
plt.ylabel('# Pods')
plt.legend(facecolor="white")
#plt.grid()
plt.tight_layout()
plt.show()
fig.savefig('pods-tnsm.pdf')

df = pd.read_csv(sys.argv[2])

df['Index'] = df.reset_index(drop=True).index

markers = itertools.cycle(('+', '.', 'o', '*')) 
colors = itertools.cycle(('r', 'g'))

fig, ax = plt.subplots(figsize=(10,5))
ax.plot(df['Index'],df['CRequests'], color='#1f77b4')

plt.xlabel('Time (s)')
plt.ylabel('Requests per Second (RPS)')
#plt.legend(facecolor="white")
plt.tight_layout()
#plt.grid()
plt.show()
fig.savefig('requests-tnsm.pdf')




