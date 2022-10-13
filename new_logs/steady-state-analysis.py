import pandas as pd
import numpy as np
import seaborn as sns; sns.set()
import matplotlib.pyplot as plt
import sys

if len(sys.argv) < 2:
    print("fig.py <ms1_file> <ms2_file>")
    sys.exit(1)

ms1 = pd.read_csv(sys.argv[1], header=None)
ms2 = pd.read_csv(sys.argv[2], header=None)

plt.plot(ms1[0])
plt.plot(ms1[0].rolling(window=50).mean())
plt.xlabel("Req No.")
plt.ylabel("Processing time (s)")
plt.title("MS1")
#plt.show()
plt.savefig("ms1_pt.pdf")

plt.clf()
plt.plot(ms2[0][1:])
plt.plot(ms2[0].rolling(window=50).mean())
plt.xlabel("Req No.")
plt.ylabel("Processing time (s)")
plt.title("MS2")
#plt.show()
plt.savefig("ms2_pt.pdf")


plt.clf()
plt.plot(ms1[0], label="MS1")
plt.plot(ms1[0].rolling(window=50).mean(), label="MS1-SMA")
plt.plot(ms2[0][1:], label="MS2")
plt.plot(ms2[0].rolling(window=50).mean(), label="MS2-SMA")
plt.xlabel("Req No.")
plt.ylabel("Processing time (s)")
plt.title("MS2")
plt.legend()
#plt.show()
plt.savefig("ms1+ms2-pt.pdf")


