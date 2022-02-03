import pandas as pd
import matplotlib.pyplot as plt
import sys

if len(sys.argv) < 2:
    print("fig.py <csv_file>")
    sys.exit(1)

df = pd.read_csv(sys.argv[1])

fig, ax = plt.subplots(figsize=(10,4))
for key, grp in df.groupby(['Component']):
    ax.plot(grp['Time'], grp['TTP'], label=key)

ax.legend()
plt.xlabel('time (s)')
plt.ylabel('TTP (s)')
plt.show()
fig.savefig('fig1.pdf')

fig, ax = plt.subplots(figsize=(10,4))
for key, grp in df.groupby(['Component']):
    ax.plot(grp['Time'],grp['Pods'],label=key)

ax.legend()
plt.xlabel('time (s)')
plt.ylabel('# Pods')
plt.show()
fig.savefig('fig2.pdf')



