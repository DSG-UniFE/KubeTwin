import requests
import numpy as np
import sys
import time
import pandas as pd

if len(sys.argv) < 4:
    sys.stderr.write('{} <target_rps> <#requests> <uri>'.format(sys.argv[1]))
    exit(1)

try: 
    rps = float(sys.argv[1])
except ValueError:
    sys.stderr.write("<target_rps> must be a numeric value")

try: 
    nreqs = int(sys.argv[2])
except ValueError:
    sys.stderr.write("<#requests> must be a numeric value")

uri = sys.argv[3]

rv = np.random.exponential(1 / rps, size=nreqs)

i = 0
start = time.time()

# log also request to get quantile info
res_file = open(f'req_logs_{start}.csv', 'w')
res_file.write('rid,ttr\n')
while i < nreqs:
    start_req_time = time.time()
    req = requests.get(uri)
    req_time = time.time() - start_req_time
    res_file.write(f'{i},{req_time}\n')
    if req_time < rv[i]:
        sleep_time = rv[i] - req_time
        #print(f'About to sleep for {sleep_time}')
        time.sleep(sleep_time)
    i +=1

print(f'Took {time.time() - start} seconds')
res_name = res_file.name
res_file.close()

ds = pd.read_csv(res_name)
ds.ttr *= 1E3
print(f"Requests {len(ds['ttr'])} mean: {ds['ttr'].mean()} ms std: {ds['ttr'].std()} ms")
print(f"Median: {ds['ttr'].median()} ms")
print("Percentage of requests within ms")
for q in [.5, .66, .75, .80, .90, .95, .98, .99, 1.0]:
    ttr_percentile = ds['ttr'].quantile(q)
    print(f'{q * 100}% {round(ttr_percentile)}')

