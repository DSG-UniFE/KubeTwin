# Changelog

All notable changes to KubeTwin are documented in this file. The format is
based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the
project follows [Semantic Versioning](https://semver.org/) (before 1.0, minor
versions may change behaviour).

## [0.2.0] - 2026-11-22

KubeTwin can now be driven step by step, as an environment for controllers
such as autoscalers, schedulers and reinforcement learning agents. See
[docs/STEP_API.md](docs/STEP_API.md).

### Added

- `KUBETWIN::Twin`: runs a simulation in decision intervals (`reset`, `step`,
  `observe`, `done?`, `result`). Running a configuration to the end in steps
  without actions gives exactly the results of `evaluate_allocation`.
- Actions: `ScaleReplicas` (pods of a service in a cluster), `Route` (route a
  service's requests among clusters by weight) and `DivideReplicas` (divide a
  service's replicas among clusters by weight), with the reasons for any
  action that can't be applied (`last_rejected`, `feasible?`).
- Per-step observations of clusters, links between clusters, placements
  (service × cluster) and workflows, including SLO violation rates.
- `Twin#fork`: an independent copy of a running twin that replays the same
  future, for what-if rollouts.
- Cold starts: a microservice type's `startup_time` delays new pods.
- Failures: pod crashes, node and cluster failures with repairs, and
  scheduled outages (`failures:` option); requests wait and retry when no pod
  is ready.
- CPU sharing: a microservice type's `cores` makes concurrent requests share
  a pod's cores (processor sharing).
- A pluggable network model for every message between components
  (`network:` option), with TCP-like retransmissions; the configured latency
  models remain the default (`LegacyNetwork`).
- A Karmada-style federation controller: propagation policies (divided or
  duplicated replicas), `DivideReplicas`, and failover after a toleration
  (`federation:` option); `ReplicaDivision` holds the division arithmetic.
- External workload sources (`workload:` option) that add requests from
  outside the configured generators.
- Initial pod placement by cluster for federation configurations
  (`replicas_mapping:`), and mean workflow response times in observations.
- Characterization tests for the maintained examples.
- Documentation: [docs/STEP_API.md](docs/STEP_API.md), the step API section
  of the README and ARCHITECTURE.md, and the `startup_time` and `cores` keys
  in [docs/CONFIGURATION.md](docs/CONFIGURATION.md).

### Changed

- **Seeded runs give different numbers than before.** Every source of
  randomness now draws from its own seeded stream (each pod, each MDN
  distribution, the simulation's own choices), so runs are reproducible and
  forks replay exactly, but a seeded configuration no longer reproduces the
  exact figures of earlier versions.
- `evaluate_allocation` is split into setup, event handlers and wind-down;
  its results are unchanged.
- Far fewer allocations per event (3–7× fewer overall), which makes runs
  faster.
- torch-rb is pinned to 0.27 in the Gemfile, which needs LibTorch 2.15 (see
  the README's installation notes).

## Earlier versions

Until this release, `KUBETWIN::VERSION` read 0.0.1 throughout KubeTwin's
development: whole-run simulation of Kubernetes-based microservice
deployments (`evaluate_allocation`), horizontal pod autoscaling, MDN-driven
service times, and PSO-, NSGA-II- and surrogate-based allocation
optimizers. The repository's `v0.0.1` and `v0.1.0` tags (2014) predate
KubeTwin: they mark releases of SISFC, the simulator it grew out of. Papers
that used KubeTwin are tagged by name (e.g. `paper/tnsm2023`).

[0.2.0]: https://github.com/DSG-UniFE/KubeTwin/releases/tag/v0.2.0
