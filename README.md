# KubeTwin

KubeTwin is a SISFC fork, a simulator to reenact the behaviour of IT services in Federated Clouds. 
KubeTwin aims to extends the SISFC project to provide a Kubernetes simulator.

We are still on development stage.


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

Before the usage, it's neccessary to install the pip package needed to run the evaluate script. The Python version necessary is 3.10.

To do so, run the following command:
    
    pip install -r requirements.txt

## Usage

To run the simulator with bundler simply digit:

    bundle exec bin/kube_twin examples/use_case.conf 

where example/use_case.conf is an example of a simulation environment configuration.

## Examples

The examples directory contains a set of example configuration files, including
an [R](http://www.r-project.org) script that models a stochastic request
generation process. To use that script, you will need R with the VGAM and
truncnorm packages installed.

## MQTT clients to comunicate with the parser server
In this repo there are two MQTT clients to comunicate with the parser server. The first one is based on the ruby gem `mqtt` and the second one is based on the python library `paho-mqtt`. The project is divided in two parts: the MQTT subcriber client and the MQTT publisher client. The subcriber is responsible to listen to the `parsing/to-kt` topic, process the received data (to optimize) and publish the result bask to the Flask server through the publisher client on the topic `parsing/from-kt`. Read the README.md in the [lib/mqtt-clients](./lib/mqtt-clients/README.md) directory for more information.

## License

This software is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).


