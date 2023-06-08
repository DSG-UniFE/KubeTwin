import pandas as pd
import numpy as np
import matplotlib.pyplot as plt
import sys
import itertools
markers = itertools.cycle(('+', '.', 'o', '*')) 
colors = itertools.cycle(('r', 'g'))

if len(sys.argv) < 2:
    print("fig.py <csv_file>")
    sys.exit(1)

df = pd.read_csv(sys.argv[1]) 
df = df[df['Time'] < (df['Time'][0] + 150)]

grouped = df.groupby('Component')['TTP']

fig, ax = plt.subplots(2, 1, figsize=(18,10), squeeze= False)
plt.subplots_adjust(left=0.125, bottom=0.1, right=0.9, top=0.9, wspace=0.2, hspace=0.4)
i = 0 #index used in subplots generation

for key, grp in df.groupby(['Component']):
    # calculate SMA for TTP
    grp['TTP-SMA'] = grp['TTP'].rolling(window=5).mean()
    ax[i,0].plot(grp['Time'], grp['TTP-SMA'], marker=next(markers), color=next(colors))
    i += 1

fig.text(0.5, 0.04, 'Time (s)', ha='center', fontsize='large')
fig.text(0.04, 0.5, 'Time To Process (TTP) (s)', va='center', rotation='vertical', fontsize='large')

ax[0,0].set_title('MS1')
ax[1,0].set_title('MS2')

lines, labels = fig.axes[-1].get_legend_handles_labels()
fig.legend(lines, labels, loc = 'upper left', fontsize='large')
#plt.legend(facecolor="white")
plt.grid()

plt.show()

fig.savefig('ttp-tnsm.pdf')

markers = itertools.cycle(('+', '.', 'o', '*')) 
colors = itertools.cycle(('r', 'g'))

fig, ax = plt.subplots(figsize=(10,4))
for key, grp in df.groupby(['Component']):
    ax.plot(grp['Time'],grp['Pods'],label=key, marker=next(markers), color=next(colors))

ax.legend()
plt.xlabel('Time (s)')
plt.ylabel('# Pods')
plt.legend(facecolor="white")
plt.grid()
plt.show()
fig.savefig('pods-tnsm.pdf')



