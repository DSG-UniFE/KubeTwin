# KubeTwin

KubeTwin is a discrete-event simulator that models Kubernetes-style multi-cluster deployments: scheduling, horizontal pod autoscaling, inter-cluster network latency, and (optionally) machine-learning-predicted service times. Given a configuration describing a topology (clusters/nodes or a simplified Liqo-style federation), a workflow of microservices, and a traffic pattern, it runs a full simulated timeline of requests flowing through the deployment and reports aggregate performance and cost metrics.

KubeTwin is a research tool: a "digital twin" used to evaluate scheduling and autoscaling strategies, and to explore multi-objective placement optimization (via the `KOptimizer*`/NSGA-II code under `lib/kube_twin/`), without needing real infrastructure. See [Publications](#publications) below for the papers this implements and evaluates.

`master` is the actively developed branch and the one to clone from; it carries all of KubeTwin's current functionality, including the multi-objective Optimuum optimizer and the MDN response-time surrogate.

## Installation

KubeTwin is written in Ruby. You'll need:

- **Ruby &ge; 3.3** (see `kube_twin.gemspec`; CI runs against 3.3 and the current latest stable release — `.github/workflows/ci.yml` is a working reference environment if you want to see a known-good setup end to end).
- **Python 3.10** for the evaluation scripts (`requirements.txt`).
- LibTorch, if you plan to use the MDN service-time models — see the dedicated section below. `bundle install` will fail without it, since `lib/kube_twin/ksimulation.rb` requires `torch-rb` unconditionally.

Clone the repository, then install the Ruby dependencies with Bundler:

```bash
gem install bundler
bundle config set path vendor/bundle
bundle install
```

And the Python dependencies, ideally inside a virtual environment:

```bash
pip install -r requirements.txt
```

### Installing torch-rb (LibTorch)

KubeTwin uses the [torch-rb](https://github.com/ankane/torch-rb) gem (see `lib/kube_twin/mdn.rb`) to run the MDN service-time prediction models from Ruby. Unlike most gems, `torch-rb` needs a local copy of LibTorch (the PyTorch C++ library) to compile its native extension against, so `bundle install` will fail with `LibTorch not found` unless you set this up first:

1. Download the LibTorch (C++) distribution matching the gem's PyTorch version &mdash; currently 2.14.x, per [torch-rb's own compatibility table](https://github.com/ankane/torch-rb#libtorch-compatibility) for the 0.26.x series this project pins &mdash; and your platform/architecture from the [PyTorch "Get Started" page](https://pytorch.org/get-started/locally/) (choose Package: LibTorch, Compute Platform: CPU, C++/Java). Recent LibTorch releases no longer offer a separate "pre-cxx11 ABI" build to choose against, so there's just the one Linux/CPU option.
2. Unzip it. This creates a `libtorch/` directory containing `include/` and `lib/`; place it wherever you like (e.g. in the project root).
3. On Apple Silicon Macs, also install the OpenMP runtime that LibTorch links against:

       brew install libomp

4. Tell Bundler where to find LibTorch before installing gems, using the **absolute path** to the folder from step 2:

       bundle config build.torch-rb --with-torch-dir=/absolute/path/to/libtorch

   (If you instead extract `libtorch/` under `/usr/local`, `/opt/homebrew`, or `/home/linuxbrew/.linuxbrew`, `torch-rb` will find it automatically and you can skip this step.)
5. Run `bundle install` as described above. Bundler will remember the `build.torch-rb` setting in `.bundle/config` (machine-specific, not committed to the repo).

## Quick start

Run a simulation against one of the bundled example configurations:

```bash
bundle exec bin/kube_twin examples/parallel-working-test.conf
```

This example models a single cluster running a small [BookInfo](https://istio.io/latest/docs/examples/bookinfo/)-style deployment (`productpage`, `reviews`, `ratings`, `details`), including one workflow whose `reviews`/`details` steps run in parallel — see `docs/CONFIGURATION.md`'s section on `component_sequence` for how that's expressed. It's fully self-contained: synthetic traffic, no external CSV or R script, no MDN weights file, so it's a good first thing to run after installing.

A run starts by printing a replica snapshot (how many pods of each microservice exist at t=0), runs quietly while the simulated clock advances (unless the config sets `stats_print_interval`, in which case you'll see periodic stats too), then prints an evaluation block ending in:

```
Weighted sum: <a number>
```

and finally, from `bin/kube_twin` itself:

```
Result:
<the same number>
```

That number is a weighted-sum objective &mdash; combining mean response time, a replica-spreading penalty, latency-threshold penalties, and an availability penalty (see `docs/CONFIGURATION.md`'s `evaluation`/`policies` sections for what feeds into it). The same run also writes `final_allocation.txt` and `final_allocation.json` into your current directory, describing the pod-to-node allocation that produced that score; both are overwritten on every run.

`bin/kube_twin` also accepts a pre-computed allocation to replay instead of using the config's own initial placement:

```bash
bundle exec bin/kube_twin examples/your.conf allocation.json [solution_id]
```

which is how you evaluate a specific solution out of an optimizer's output (see `lib/kube_twin/allocation_replay.rb` and the `bin/optimizer*` scripts).

## Writing your own configuration

A `.conf` file is a small Ruby DSL, not a data format &mdash; it's evaluated against a `Configuration` object, so it can use local variables, `require`, loops, anything plain Ruby can do. It declares your topology (either a simplified `federation` JSON blob, or lower-level `clusters` + `latency_models`), the microservices in your deployment and how they call each other (`workflow_types`), how traffic arrives (`request_gen` for synthetic load, or `request_generation` to replay a CSV), and optional pieces like autoscalers and SLO policies.

**[docs/CONFIGURATION.md](docs/CONFIGURATION.md) is the full reference** &mdash; every directive that's actually read by the simulator, verified against the code rather than just inferred from examples, plus a minimal skeleton and a list of worked example files to read alongside it.

## Examples

`examples/` contains three dozen configuration files spanning the project's history. Not every file here is still relevant to current work: we are in the process of cleaning up this folder and improve the quality of the examples. For the moment, we suggest you to focus on example-hpa.conf (multi-cluster, HPA configured, no MDN, Gaussian-sampled service times) and bookinfo-3c-xr.conf (the MDN config behind the OPTIMUUM extension). Please treat the rest of the content of the `examples/` folder as an archive to search rather than something where every file is expected to run cleanly.

## Publications

We suggest the following publications:

- Borsatti, Davide, Cerroni, Walter, Foschini, Luca, Grabarnik, Genady Ya., Manca, Lorenzo, Poltronieri, Filippo, Scotece, Domenico, Shwartz, Larisa, Stefanelli, Cesare, Tortonesi, Mauro, Zaccarini, Mattia (2024). KubeTwin: A Digital Twin Framework for Kubernetes Deployments at Scale. IEEE TRANSACTIONS ON NETWORK AND SERVICE MANAGEMENT, vol. 21, p. 3889-3903, ISSN: 1932-4537, doi: 10.1109/tnsm.2024.3405175

- Manca, Lorenzo, Borsatti, Davide, Poltronieri, Filippo, Zaccarini, Mattia, Scotece, Domenico, Davoli, Gianluca, Foschini, Luca, Grabarnik, Genady Ya., Shwartz, Larisa, Stefanelli, Cesare, Tortonesi, Mauro, Cerroni, Walter (2023). Characterization of Microservice Response Time in Kubernetes: A Mixture Density Network Approach. In: 2023 19th International Conference on Network and Service Management (CNSM): Network and Service Management in the Era of Generative AI and Digital Twins. p. 1-9, IEEE, ISBN: 9783903176591, Niagara Falls, Canada, 30/10/2023-02/11/2023, doi: 10.23919/cnsm59352.2023.10327842

## MQTT clients to communicate with the parser server

This repo includes two MQTT clients for talking to the parser server: one built on the Ruby `mqtt` gem, one on Python's `paho-mqtt`. Each project is split into a subscriber and a publisher client. The subscriber listens on the `parsing/to-kt` topic, processes the received data (to optimize), and publishes the result back through the publisher client on `parsing/from-kt`. See [lib/mqtt-clients/README.md](./lib/mqtt-clients/README.md) for details.

## License

This software is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
