# KubeTwin

KubeTwin is a SISFC fork, a simulator to reenact the behaviour of IT services in Federated Clouds. 
KubeTwin aims to extends the SISFC project to provide a Kubernetes simulator.

We are on development stage. 


## Installation

As KubeTwin was developed in Ruby, you will first need a working Ruby interpreter.
Once you have Ruby installed, you can install SISFC through RubyGems:

While KubeTwin should work on MRI and Rubinius without problems, we highly
recommend you to run it on top of JRuby. Since JRuby is our reference
development platform, you will be very likely to have a smoother installation
and usage experience when deploying SISFC on top of JRuby.

To install and work with KubeTwin we kindly suggest to use bundler:

    gem install bundler

    bundle config set path vendor/bundle

    bundle install

## Usage

To run the simulator with bundler simply digit:

    bundle exec bin/sisfc simulator.conf vm_allocation.conf

where simulator.conf and vm\_allocation.conf are your simulation environment
and vm allocation configuration files respectively.

The examples directory contains a set of example configuration files, including
an [R](http://www.r-project.org) script that models a stochastic request
generation process. To use that script, you will need R with the VGAM and
truncnorm packages installed.

Note that the KubeTwin was not designed to be run directly by users, but instead
to be integrated within higher level frameworks that implement continuous
optimization (such as [BDMaaS+](https://github.com/DSG-UniFE/bdmaas-plus-core)).



