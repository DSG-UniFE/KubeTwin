# KubeTwin

KubeTwin is a research-born software platform for creating Digital Twins of Kubernetes applications.

## Installation

As KubeTwin was developed in Ruby, you will first need a working Ruby interpreter.
Once you have Ruby installed, you can install KubeTwin by cloning this repository and installing the required gems.

Specifically, we recommend to use a Ruby version (> 3.x) and to use bundler for managing all the dependencies:

```bash
    gem install bundler

    bundle config set path vendor/bundle

    bundle install
```

Before the usage, it's neccessary to install the pip package needed to run the evaluate script. The Python version necessary is 3.10.

To do so, run the following command:
    
    pip install -r requirements.txt

### Installing torch-rb (LibTorch)

KubeTwin uses the [torch-rb](https://github.com/ankane/torch-rb) gem (see `lib/kube_twin/mdn.rb`) to run the MDN service-time prediction models from Ruby. Unlike most gems, `torch-rb` needs a local copy of LibTorch (the PyTorch C++ library) to compile its native extension against, so `bundle install` will fail with `LibTorch not found` unless you set this up first:

1. Download the LibTorch (C++) distribution matching the gem's PyTorch version (currently 2.13.0) and your platform/architecture from the [PyTorch "Get Started" page](https://pytorch.org/get-started/locally/) (choose Package: LibTorch, Compute Platform: CPU, and the C++/Java, cxx11 ABI build for your OS).
2. Unzip it. This creates a `libtorch/` directory containing `include/` and `lib/`; place it wherever you like (e.g. in the project root).
3. On Apple Silicon Macs, also install the OpenMP runtime that LibTorch links against:

       brew install libomp

4. Tell Bundler where to find LibTorch before installing gems, using the **absolute path** to the folder from step 2:

       bundle config build.torch-rb --with-torch-dir=/absolute/path/to/libtorch

   (If you instead extract `libtorch/` under `/usr/local`, `/opt/homebrew`, or `/home/linuxbrew/.linuxbrew`, `torch-rb` will find it automatically and you can skip this step.)
5. Run `bundle install` as described above. Bundler will remember the `build.torch-rb` setting in `.bundle/config` (which is machine-specific and not committed to the repo).

## Usage

To run the KubeTwin on a simple scenario bundler simply digit:

    bundle exec bin/kube_twin examples/use_case.conf 

where example/use_case.conf is an example of a simulation environment configuration.

## Examples

The examples directory contains a set of example configuration files. We highly recommend to take a look.

## Publications

We suggest the following Publications:

- Borsatti, Davide, Cerroni, Walter, Foschini, Luca, Grabarnik, Genady Ya., Manca, Lorenzo, Poltronieri, Filippo, Scotece, Domenico, Shwartz, Larisa, Stefanelli, Cesare, Tortonesi, Mauro, Zaccarini, Mattia (2024). KubeTwin: A Digital Twin Framework for Kubernetes Deployments at Scale. IEEE TRANSACTIONS ON NETWORK AND SERVICE MANAGEMENT, vol. 21, p. 3889-3903, ISSN: 1932-4537, doi: 10.1109/tnsm.2024.3405175

- Manca, Lorenzo, Borsatti, Davide, Poltronieri, Filippo, Zaccarini, Mattia, Scotece, Domenico, Davoli, Gianluca, Foschini, Luca, Grabarnik, Genady Ya., Shwartz, Larisa, Stefanelli, Cesare, Tortonesi, Mauro, Cerroni, Walter (2023). Characterization of Microservice Response Time in Kubernetes: A Mixture Density Network Approach. In: 2023 19th International Conference on Network and Service Management (CNSM) : Network and Service Management in the Era of Generative AI and Digital Twins. p. 1-9, IEEE, ISBN: 9783903176591, Niagara Falls, Canada, 30/10/2023-02/11/2023, doi: 10.23919/cnsm59352.2023.10327842

## MQTT clients to comunicate with the parser server
In this repo there are two MQTT clients to comunicate with the parser server. The first one is based on the ruby gem `mqtt` and the second one is based on the python library `paho-mqtt`. The project is divided in two parts: the MQTT subcriber client and the MQTT publisher client. The subcriber is responsible to listen to the `parsing/to-kt` topic, process the received data (to optimize) and publish the result bask to the Flask server through the publisher client on the topic `parsing/from-kt`. Read the README.md in the [lib/mqtt-clients](./lib/mqtt-clients/README.md) directory for more information.

## License

This software is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
