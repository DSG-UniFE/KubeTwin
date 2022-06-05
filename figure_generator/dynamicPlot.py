from matplotlib import pyplot as plt
import pandas as pd
import numpy as np
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


fig1.savefig('fig_6.pdf')
plt.show()


# separate plot -- with multiple axis

fig1, ax1 = plt.subplots(figsize=(10,5), nrows=3, sharex=True, sharey=True)
ax1[0].plot(time, data_by_component['Video Transcoding']['Pods'], color='#F91907', alpha = 0.8, label='Video Transcoding')
ax1[0].set_title('Video Transcoding')

ax1[1].plot(time, data_by_component['Visual Rendering']['Pods'], color = '#12AC10', alpha = 0.8, label='Visual Rendering')
ax1[1].set_title('Visual Rendering')

ax1[2].plot(time, data_by_component['State Management']['Pods'], color = '#B00E97', alpha = 0.8, label='State Management')
ax1[2].set_title('State Mangement')

fig1.supxlabel('Simulation Time (s)')
fig1.supylabel('Pods')
fig1.savefig('fig_6_b.png')
#fig1.tight_layout()
plt.show()

fig1, ax2 = plt.subplots(figsize=(10,5), nrows=3, ncols=1, sharex=True, sharey=False)

ax2[0].plot(time, data_by_component['Video Transcoding']['TTP'].rolling(window=1).mean(), color='#F91907', alpha = 0.8, label='Measured')
vt_service_time = 0.030 * 1.5
vtd = np.repeat(vt_service_time, len(time))
ax2[0].plot(time, vtd, alpha = 0.8, label='Desired')
ax2[0].set_title('Video Transcoding')

ax2[1].plot(time, data_by_component['Visual Rendering']['TTP'].rolling(window=1).mean(), color = '#12AC10', alpha = 0.8, label='Measured')
vr_service_time = 0.025 * 1.5
vrd = np.repeat(vr_service_time, len(time))
ax2[1].plot(time, vrd, alpha = 0.8, label='Desired')
ax2[1].set_title('Visual Rendering')


ax2[2].plot(time, data_by_component['State Management']['TTP'].rolling(window=1).mean(), color = '#B00E97', alpha = 0.8, label='Measured')
sm_service_time = 0.020 * 1.5
smd = np.repeat(sm_service_time, len(time))
ax2[2].plot(time, smd, marker='x', alpha = 0.8, label='Desired')
ax2[2].set_title('State Management')


for x in ax2:
    #x.set_xlabel('Simulation Time (s)')
    x.legend()

fig1.supxlabel('Simulation Time (s)')
fig1.supylabel('TTP (s)')

#ax2.set_xlabel('Simulation Time (s)')
#ax2.set_ylabel('TTP (s)')
#ax2.legend()


fig1.savefig('fig_5.pdf')
plt.show()

#fig1.savefig('dynamic2.png')
#plt.show()


