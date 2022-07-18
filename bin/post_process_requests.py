import pandas as pd
import sys
import matplotlib.pyplot as plt

if len(sys.argv) < 2:
    sys.stderr('Include the request log file')
    exit(1)

ds = pd.read_csv(sys.argv[1])
ds.ttr *= 1E3
print(f"Requests {len(ds['ttr'])} mean: {ds['ttr'].mean()} ms std: {ds['ttr'].std()} ms")
print(f"Median: {ds['ttr'].median()} ms")
'''
  50%     37
  66%     39
  75%     40
  80%     41
  90%     45	
  95%     48
  98%     52
  99%     56
'''
print("Percentage of requests within ms")
for q in [.5, .66, .75, .80, .90, .95, .98, .99, 1.0]:
    ttr_percentile = ds['ttr'].quantile(q)
    print(f'{q * 100}% {round(ttr_percentile)}')

