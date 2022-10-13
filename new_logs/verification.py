import numpy as np
import pandas as pd
import matplotlib.pyplot as plt
import time

nsamples = 5000
rate = 20 # rps
samples = np.random.exponential(1 / 20, size=nsamples)

'''
temp_file = '.example.csv'
f = open(temp_file, 'w')
f.write('rid,st\n')

i = 0
while i < nsamples:
    f.write(str(i)+','+str(time.time())+'\n')
    time.sleep(samples[i])
    i += 1

f.close()
'''
fcsv = pd.read_csv('.example.csv')
fcsv['st_int'] = fcsv['st'].astype('int')

fcsv['st_int'].value_counts().plot()
plt.show()






