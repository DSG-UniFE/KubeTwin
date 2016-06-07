# A Simulator for IT Service in Federated Clouds (SISFC)

SISFC is a simulator designed to reenact the behaviour of IT services in
federated Cloud environments.


## Installation

You can install the SISFC simulator through RubyGems:

    gem install sisfc

While SISFC should work on MRI and Rubinius without problems, we highly
recommend you to run it on top of JRuby. Since JRuby is our reference
development platform, you will be very likely to have a smoother installation
and usage experience when deploying SISFC on top of JRuby.


## Usage

To run the simulator, simply digit:

    sisfc simulator.conf vm_allocation.conf

where simulator.conf and vm\_allocation.conf are your simulation environment
and vm allocation configuration files respectively.

The examples directory contains a set of example configuration files, including
an [R](http://www.r-project.org) script that models a stochastic request
generation process. To use that script, you will need R with the VGAM and
truncnorm packages installed.

Note that the SISFC was not designed to be run directly by users, but instead
to be integrated within automated tools that implement a continuous
optimization framework (for instance, built on top of our [mhl metaheuristics
library](https://github.com/mtortonesi/ruby-mhl)).


## References

The SISFC simulator was used in the following research papers:

1.  L. Foschini, M. Tortonesi, "Adaptive and Business-driven Service Placement
    in Federated Cloud Computing Environments", in Proceedings of the 8th
    IFIP/IEEE International Workshop on Business-driven IT Management (BDIM 2013),
    27 May 2013, Ghent, Belgium.

2.  G. Grabarnik, L. Shwartz, M. Tortonesi, "Business-Driven Optimization of
    Component Placement for Complex Services in Federated Clouds", in
    Proceedings of the 14th IEEE/IFIP Network Operations and Management Symposium
    (NOMS 2014) - Mini-conference track, 5-9 May 2014, Krakow, Poland.

3.  M. Tortonesi, L. Foschini, "Business-driven Service Placement for Highly
    Dynamic and Distributed Cloud Systems", IEEE Transactions on Cloud
    Computing, 2016 (in print).

Please, consider citing some of these papers if you find this simulator useful
for your research.


## Acknowledgements

The research work that led to the development of SISFC was supported in part by
the [DICET - INMOTO - ORganization of Cultural HEritage for Smart
Tourism and Real-time Accessibility (OR.C.HE.S.T.R.A.)](http://www.ponrec.it/open-data/progetti/scheda-progetto?ProgettoID=5835)
project, funded by the Italian Ministry of University and Research on Axis II
of the National operative programme (PON) for Research and Competitiveness
2007-13 within the call 'Smart Cities and Communities and Social Innovation'
(D.D. n.84/Ric., 2 March 2012).
