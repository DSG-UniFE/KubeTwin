from pickletools import markobject
import requests
import numpy as np
import sys
import time
import pandas as pd
from multiprocessing import Pool
from matplotlib import pyplot as plt

def send_requests(nr, rps, uri, process_name):
    #   print(nr, process_name)
    i = 0
    results = ""
    rv = np.random.exponential(1 / rps, size=nr)
    while i < nr:
        start_req_time = time.time_ns()
        req = requests.get(uri)
        if req.status_code == 200:
            req_time = time.time() - (start_req_time / 1E9  )
            # print(f'Took #{req_time}')
            results += (f'{start_req_time},{req_time},{i},{process_name}\n')
            #if req_time < rv[i]:
            #    sleep_time = rv[i] - req_time
                #print(f'About to sleep for {sleep_time}')
            #    time.sleep(sleep_time)
        i +=1
    return results


if __name__ == '__main__':

    if len(sys.argv) < 5:
        sys.stderr('{} <target_rps> <#double_rps> <concurrency_level> <#requests> <uri>'.format(sys.argv[0]))
        exit(1)

    try: 
        rps = float(sys.argv[1])
    except ValueError:
        sys.stderr("<target_rps> must be a numeric value")
    
    try: 
        n_double_rps = int(sys.argv[2])
    except ValueError:
        sys.stderr("<n_double_rps> must be a numeric value")

    try: 
        c_level = int(sys.argv[3])
    except ValueError:
        sys.stderr("<concurrency_level> must be a numeric value")

    try: 
        nreqs = int(sys.argv[4])
    except ValueError:
        sys.stderr("<#requests> must be a numeric value")

    uri = sys.argv[5]

    # i = 0
    start = time.time()
    # log also request to get quantile info

    res_file = open(f'req_logs_{start}.csv', 'w')
    res_file.write('st,ttr,rid,process_name\n')

    for st in range(1, n_double_rps + 1):
        # create Pool
        # It looks like we have to call close before join()
        # check if we can reuse the pool without closing it
        pool = Pool(processes=c_level)
        # how many requests for each shape?
        # n_reqs / n_double_rps an eqaul amount of requests for each frequency
        reqs_per_process = (nreqs // n_double_rps) //c_level
        target_rps = rps * st
        print(f'Target rps: {target_rps}')

        results = []
        for i in range(c_level):
            results.append(pool.apply_async(send_requests, [reqs_per_process, target_rps,uri,i]))
        pool.close()
        pool.join()
        
        for ri in results:
            res_file.write(ri.get())

    pool.close()


    print(f'Took {time.time() - start} seconds')



    # close results file
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
'''
    ds.sort_values(by=['st'])
    plt.plot(ds['st'], ds['ttr'])
    plt.show()
'''