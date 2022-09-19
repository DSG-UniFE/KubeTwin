import requests
import numpy as np
import sys
import time
import pandas as pd
from multiprocessing import Pool

def send_requests(uri, i, num_reqs, rps, filename):

    rv = np.random.exponential(1 / rps, size=num_reqs)
    j = 0
    results = ''
    while j < num_reqs: 
        start_req_time = time.time()
        req = requests.get(uri)
        if req.status_code == 200:
            req_time = time.time() - start_req_time
            results += f'{start_req_time},{req_time},{i}\n'
            sleep_time = rv[i] - req_time
            #print(f'About to sleep for {sleep_time}')
            time.sleep(sleep_time)
        j += 1
    f = open(filename, 'a')
    f.write(results)
    f.close()


if __name__ == '__main__':

    if len(sys.argv) < 4:
        sys.stderr('{} <target_rps> <#requests> <#c> <uri>'.format(sys.argv[0]))
        exit(1)
    try: 
        rps = float(sys.argv[1])
    except ValueError:
        sys.stderr("<target_rps> must be a numeric value")

    try:
        nreqs = int(sys.argv[2])
    except ValueError:
        sys.stderr("<#requests> must be a numeric value")
    
    try:
        c = int(sys.argv[3])
    except ValueError:
        sys.stderr("<#c> must be a numeric value")

    uri = sys.argv[4]

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

    pool = Pool(processes=c)
    # requests per process
    rpp = nreqs // c

    print(f'Target rps: {rps} Request per process: {rpp}')

    i = 0

    while i < c:
        pool.apply_async(send_requests, [uri, i, rpp, rps, res_name,])
        i += 1
    # here, we want to verify how many rps we sent
    # even if they are still in progress
    elapsed_time = time.time() - start

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