from matplotlib import pyplot as plt
 
plt.style.use('seaborn')
 
#datacenters = [1, 2, 3, 4, 5, 6, 7]
tiers = [1, 2, 3, 4]
#sampleValues = [15, 13, 27, 12, 20, 100, 113]
#sortedValues = [75, 77, 68, 68, 12, 0, 0]

'''
localDcSample = [9, 0, 0, 0]
euCentralSample = [0, 16, 0, 0]
euWest3Sample = [0, 17, 0, 0]
euWest2Sample = [0, 0, 21, 0]
euNorthSample = [0, 0, 27, 0]
caCentralSample = [0, 0, 0, 100]
usEastSample = [0, 0, 0, 110]
localDcSorted = [75, 0, 0, 0]
euCentralSorted = [0, 77, 0, 0]
euWest3Sorted = [0, 68, 0, 0]
euWest2Sorted = [0, 0, 68, 0]
euNorthSorted = [0, 0, 12, 0]
caCentralSorted = [0, 0, 0, 0]
usEastSorted = [0, 0, 0, 0]
'''

localDc_50 = [75, 0, 0, 0]
euCentral_50 = [0, 0, 0, 0]
euWest3_50 = [0, 75, 0, 0]
euWest2_50 = [0, 0, 0, 0]
euNorth_50 = [0, 0, 0, 0]
caCentral_50 = [0, 0, 0, 0]
usEast_50 = [0, 0, 0, 0]

localDc_150 = [75, 0, 0, 0]
euCentral_150 = [0, 150, 0, 0]
euWest3_150 = [0, 150, 0, 0]
euWest2_150 = [0, 0, 75, 0]
euNorth_150 = [0, 0, 0, 0]
caCentral_150 = [0, 0, 0, 0]
usEast_150 = [0, 0, 0, 0]

#labels = ["eu-south-1", "eu-central-1", "eu-west-3", "eu-west-2", "eu-north-1", "ca-central-1", "us-east-1"]

labels = ["Local DC", "Tier 1", "Tier 2", "Remote DC"]
fig, axs = plt.subplots(nrows=1,ncols=2, figsize=(10, 5), sharex=True, sharey=True)
 
'''
p11 = axs[0].bar(tiers, localDcSample, label='eu-south-1')
p12 = axs[0].bar(tiers, euCentralSample, bottom=localDcSample, label='eu-central-1')
p13 = axs[0].bar(tiers, euWest3Sample, bottom=euCentralSample, label='eu-west-3')
p14 = axs[0].bar(tiers, euWest2Sample, bottom=euWest3Sample, label='eu-west-2')
p15 = axs[0].bar(tiers, euNorthSample, bottom=euWest2Sample, label='eu-north-1')
p16 = axs[0].bar(tiers, caCentralSample, bottom=euNorthSample, label='ca-central-1')
p17 = axs[0].bar(tiers, usEastSample, bottom=caCentralSample, color='orange', label='us-east-1')
'''

p21 = axs[0].bar(tiers, localDc_50, label='Local DC')
p22 = axs[0].bar(tiers, euCentral_50, bottom=localDc_50, label='eu-central-1')
p23 = axs[0].bar(tiers, euWest3_50, bottom=euCentral_50, label='eu-west-3')
p24 = axs[0].bar(tiers, euWest2_50, bottom=euWest3_50, label='eu-west-2')
p25 = axs[0].bar(tiers, euNorth_50, bottom=euWest2_50, label='eu-north-1')
p26 = axs[0].bar(tiers, caCentral_50, bottom=euNorth_50, label='ca-central-1')
p27 = axs[0].bar(tiers, usEast_50, bottom=caCentral_50, color='orange', label='us-east-1')
 
p21 = axs[1].bar(tiers, localDc_150)
p22 = axs[1].bar(tiers, euCentral_150, bottom=localDc_150)
p23 = axs[1].bar(tiers, euWest3_150, bottom=euCentral_150)
p24 = axs[1].bar(tiers, euWest2_150, bottom=euWest3_150)
p25 = axs[1].bar(tiers, euNorth_150, bottom=euWest2_150)
p26 = axs[1].bar(tiers, caCentral_150, bottom=euNorth_150)
p27 = axs[1].bar(tiers, usEast_150, bottom=caCentral_150, color='orange')

#axs[0].bar(datacenters, sampleValues, align='center', label='Pods Allocated')
#axs[1].bar(datacenters, sortedValues, align='center', label='Pods Allocated')
 
axs[0].set_title('50 Replicas Deployment')
axs[1].set_title('150 Replicas Deployment')
fig.tight_layout()

#fig.text(0.5, 0.001, 'Datacenters', ha='center', fontsize='large')
#fig.text(0.04, 0.5, 'Pods Allocated', rotation='vertical', va='center', fontsize='large')
 
plt.xticks(tiers, labels)

fig.legend(fontsize='medium', loc='center right')
 
plt.show()
fig.savefig("distribution_plot.pdf")
