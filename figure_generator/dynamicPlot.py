from matplotlib import pyplot as plt
import pandas as pd
import sys

plt.style.use('seaborn')

if len(sys.argv) != 2:
    print('{} <csv_file>'.format(sys.argv[0]))
    exit(1)


data = pd.read_csv(sys.argv[1])


data_by_component = {k: g.drop('Component', axis=1) for k, g in  data.groupby('Component')}
time = data_by_component['Video Transcoding']['Time']

fig1, ax1 = plt.subplots(figsize=(10,4))

ax1.plot(time, data_by_component['Video Transcoding']['Pods'], color='#F91907', alpha = 0.8, label='Video Transcoding')
ax1.plot(time, data_by_component['Visual Rendering']['Pods'], color = '#12AC10', alpha = 0.8, label='Visual Rendering')
ax1.plot(time, data_by_component['State Management']['Pods'], color = '#B00E97', alpha = 0.8, label='State Management')
ax1.set_ylabel('Pods')
ax1.set_xlabel('Simulation Time (s)')
ax1.legend()


fig1.savefig('fig_6.png')
plt.show()

fig1, ax2 = plt.subplots(figsize=(10,4))

ax2.plot(time, data_by_component['Video Transcoding']['TTP'].rolling(window=5).mean(), color='#F91907', alpha = 0.8, label='Video Transcoding')
ax2.plot(time, data_by_component['Visual Rendering']['TTP'].rolling(window=5).mean(), color = '#12AC10', alpha = 0.8, label='Visual Rendering')
ax2.plot(time, data_by_component['State Management']['TTP'].rolling(window=5).mean(), color = '#B00E97', alpha = 0.8, label='State Management')

ax2.set_xlabel('Simulation Time (s)')
ax2.set_ylabel('TTP (s)')
ax2.legend()

fig1.savefig('fig_5.png')
plt.show()

#fig1.savefig('dynamic2.png')
#plt.show()


