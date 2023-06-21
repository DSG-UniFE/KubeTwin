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

df = pd.read_csv(sys.argv[1]) 


#fig, ax = plt.subplots(1, 1, figsize=(18,10), squeeze= False)
rps = []
avg_ttr = []
ttr_99 = []
sla = []
plt.figure(figsize=(10, 5))

#plt.figure(figsize=(18, 12))
#plt.rc('font', size=20)          # controls default text sizes
'''
plt.rc('axes', titlesize=SMALL_SIZE)     # fontsize of the axes title
plt.rc('axes', labelsize=MEDIUM_SIZE)    # fontsize of the x and y labels
plt.rc('xtick', labelsize=SMALL_SIZE)    # fontsize of the tick labels
plt.rc('ytick', labelsize=SMALL_SIZE)    # fontsize of the tick labels
plt.rc('legend', fontsize=SMALL_SIZE)    # legend fontsize
plt.rc('figure', titlesize=BIGGER_SIZE)  # fontsize of the figure title
'''

for v in df['rps']:
    if int(v) > 3:
        rps.append(int(v))
        avg_ttr.append(df['mean'][int(v) - 1])
        ttr_99.append(df['99th'][int(v) - 1])
        sla.append(0.060)

plt.bar(np.array(rps) - 0.2, avg_ttr, width=0.4, label ='Mean TTR')
plt.bar(np.array(rps) + 0.2, ttr_99, width=0.4, label = '99th TTR')

# add also a tolerance line here
# just a sla indicator
rps = rps + [20.5]
sla = sla + [0.06] 
plt.plot(rps , sla, linewidth=3.5, color='g', label='Target TTR')   

#plt.xlim([3, 15])
plt.xticks([5, 10, 15, 20])
plt.xlabel('RPS')
plt.ylabel('Time To Resolution (TTR)')




#plt.subplots_adjust(left=0.125, bottom=0.1, right=0.9, top=0.9, wspace=0.2, hspace=0.4)

plt.legend()
#plt.legend(facecolor="white")
#plt.grid()
plt.tight_layout()
plt.show()

plt.savefig('tnsm-static-deployment.pdf')



