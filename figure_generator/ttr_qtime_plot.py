from matplotlib import pyplot as plt
import numpy as np
import math

plt.style.use("seaborn")

replicas = ['25','50', '75', '100', '125', '150']

meanQtW1 = [24.6222, 0.0862, 0.0176, 0.0076, 0.0041, 0.0018]
meanQtW2 = [20.7644, 0.0810, 0.0173, 0.0083, 0.0037, 0.0039]

stdQtW1 = [math.sqrt(17250591.5209/140621), math.sqrt(1002.0323/140620),
                   math.sqrt(100.2008/140622), math.sqrt(39.3162/140627),
                   math.sqrt(19.2029/140621), math.sqrt(8.9330/140618)]
stdQtW2 = [math.sqrt(7422756.8456/75797), math.sqrt(577.8434/75794),
                    math.sqrt(50.5923/75797), math.sqrt(20.8598/75799),
                    math.sqrt(9.4501/75797), math.sqrt(8.7024/75794)]

meanTtrW1 = [24.7986, 0.2609, 0.1916, 0.1812, 0.1787, 0.1765]
meanTtrW2 = [20.9109, 0.2256, 0.1632, 0.1540, 0.1521, 0.1531]

stdTtrW1 = [math.sqrt(17250661.2082/140621), math.sqrt(1164.3869/140620),
                     math.sqrt(266.2881/140622), math.sqrt(211.9433/140627),
                     math.sqrt(188.4745/140621), math.sqrt(174.8005/140618)]
stdTtrW2 = [math.sqrt(7422756.8456/75797), math.sqrt(524.3447/75794),
                      math.sqrt(105.7487/75797), math.sqrt(76.0375/75799),
                      math.sqrt(67.7938/75797), math.sqrt(67.6369/75794)]

x = np.arange(len(replicas))
width = 0.25

fig1, (ax1, ax2) = plt.subplots(2,1)
fig2, (ax4,ax3) = plt.subplots(2,1)

ax1.bar(x-width/2, meanQtW1, yerr=stdQtW1, width = width, alpha=0.8, color = '#335BFB', label='WF01')
ax1.bar(x+width/2, meanQtW2, yerr=stdQtW2, width=width, alpha=0.8, color = '#ff8c1a', label='WF02')
ax2.bar(x-width/2, meanTtrW1, yerr=stdTtrW1, width = width, alpha=0.8, color = '#335BFB', label='WF01')
ax2.bar(x+width/2, meanTtrW2, yerr=stdTtrW2, width=width, alpha=0.8, color = '#ff8c1a', label='WF02')
ax3.bar(x-width/2, meanQtW1, yerr=stdQtW1, log = True, width = width, alpha=0.8, color = '#335BFB', label='WF01')
ax3.bar(x+width/2, meanQtW2, yerr=stdQtW2, width=width, alpha=0.8, color = '#ff8c1a', label='WF02')
ax4.bar(x-width/2, meanTtrW1, yerr=stdTtrW1, log = True, width = width, alpha=0.8, color = '#335BFB', label='WF01')
ax4.bar(x+width/2, meanTtrW2, yerr=stdTtrW2, width=width, alpha=0.8, color = '#ff8c1a', label='WF02')


ax1.set_ylabel('QTime (s)')
ax2.set_ylabel('TTR (s)')
ax2.set_xlabel('Replicas')
ax3.set_ylabel('QTime (s)')
ax4.set_ylabel('TTR (s)')
ax4.set_xlabel('Replicas')

ax1.set_xticks(x, replicas, rotation=90, horizontalalignment="center")
ax2.set_xticks(x, replicas, rotation=90, horizontalalignment="center")
ax3.set_xticks(x, replicas, rotation=90, horizontalalignment="center")
ax4.set_xticks(x, replicas, rotation=90, horizontalalignment="center")

ax1.legend()
ax2.legend()
ax3.legend()
ax4.legend()

fig1.tight_layout()
fig2.tight_layout()

fig2.savefig("TtrQtime.png")
plt.show()
