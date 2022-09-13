import requests
import numpy as np
import sys
import time
import pandas as pd
from multiprocessing import Pool

def send_requests(uri, i, filename):
    start_req_time = time.time()
    req = requests.get(uri)
    if req.status_code == 200:
        req_time = time.time() - start_req_time
        # print(f'Took #{req_time}')
        results = f'{start_req_time},{req_time},{i}\n'
        f = open(filename, 'a')
        f.write(results)
        f.close()


if __name__ == '__main__':

    if len(sys.argv) < 4:
        sys.stderr('{} <target_rps> <#requests> <uri>'.format(sys.argv[0]))
        exit(1)
    try: 
        rps = float(sys.argv[1])
    except ValueError:
        sys.stderr("<target_rps> must be a numeric value")
    
    try:
        nreqs = int(sys.argv[2])
    except ValueError:
        sys.stderr("<#requests> must be a numeric value")

    uri = sys.argv[3]

    print(uri)

    # i = 0
    start = time.time()
    # log also request to get quantile info

    res_file = open(f'req_logs_{start}.csv', 'w')
    res_file.write('st,ttr,rid\n')
    # close results file
    res_name = res_file.name
    res_file.close()

    # create Pool
    # It looks like we have to call close before join()
    # check if we can reuse the pool without closing it

    pool = Pool(processes=int(rps))
    print(f'Target rps: {rps}')

    i = 0
    rv = np.random.exponential(1 / rps, size=nreqs)
    while i < nreqs:
        pool.apply_async(send_requests, [uri, i, res_name])
        time.sleep(rv[i])
        i += 1
        
    # here, we want to verify how many rps we sent
    # even if they are still in progress
    elapsed_time = time.time() - start
    done_rps = nreqs / elapsed_time
    
    print(f'Sent RPS: {done_rps}')

    # wait for requests to be over
    pool.close()
    pool.join()
    
    elapsed_time = time.time() - start
    print(f'Took {elapsed_time}')
    

    ds = pd.read_csv(res_name)
    ds.ttr *= 1E3
    print(f"Requests {len(ds['ttr'])} mean: {ds['ttr'].mean()} ms std: {ds['ttr'].std()} ms")
    print(f"Median: {ds['ttr'].median()} ms")
    print("Percentage of requests within ms")
    for q in [.5, .66, .75, .80, .90, .95, .98, .99, 1.0]:
        ttr_percentile = ds['ttr'].quantile(q)
        print(f'{q * 100}% {round(ttr_percentile)}')
'''
    ds.sort_values(by=['st'])
    plt.plot(ds['st'], ds['ttr'])
    plt.show()
'''