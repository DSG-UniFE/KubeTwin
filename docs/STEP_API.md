# Driving KubeTwin step by step

A plain KubeTwin run (`bin/kube_twin`, `KSimulation#evaluate_allocation`)
simulates a configuration from start to end and returns one number. The
**step API** (`KUBETWIN::Twin`) turns the same simulator into an environment
that a controller — an autoscaler, a scheduler, a reinforcement learning
agent — drives in decision intervals: it observes the system, acts on it,
and lets simulated time advance, as often as it likes.

```ruby
require "kube_twin"

configuration = KUBETWIN::Configuration.load_from_file("examples/example-hpa.conf")
twin = KUBETWIN::Twin.new(configuration, decision_interval: 30.0, slos: {1 => 250.0})
twin.reset                                    # build the world and run the warm-up

until twin.done?
  observation = twin.observe                  # what happened in the last interval
  actions = my_controller.decide(observation)
  twin.step(actions)                          # apply them, then advance 30 simulated s
  warn twin.last_rejected.inspect if twin.last_rejected.any?
end

twin.result                                   # what evaluate_allocation would return
```

Time is measured in simulated seconds from the end of the warm-up. Running a
configuration to the end in steps **without actions** gives exactly the
results of `evaluate_allocation`, so the two modes can be compared directly.

## The interface

| Method | What it does |
|---|---|
| `Twin.new(configuration, decision_interval: 30.0, slos: {}, ...)` | Wraps a configuration; see the options below. Nothing is simulated yet. |
| `#reset` | Builds a fresh world from the configuration, places the initial pods, runs the warm-up and returns `#now` (0.0). Raises `Twin::UnfeasibleAllocation` if the initial pods can't all be placed. |
| `#step(actions = [], duration: decision_interval)` | Applies the actions in order, then advances `duration` simulated seconds (a positive multiple of the decision interval). Returns `#now`. |
| `#observe` | A summary of the last step (see below). |
| `#last_rejected` | The actions the last step could not apply, as `[action, reason]` pairs. |
| `#feasible?(action)` | Whether an action could be applied now. |
| `#replicas(service, cluster)` | How many pods of a service run (or are starting) in a cluster. |
| `#routing(service)` | The cluster weights the service's requests are routed with, or nil for the configured load balancing. |
| `#fork` | An independent copy in the current state (see below). |
| `#now`, `#done?`, `#result` | Simulated time; whether every event has been processed; the final score, once done. |

## Actions

Actions are plain values, applied at the start of a step. An action that
can't be applied is skipped and reported in `#last_rejected`, with the
reason; nothing else changes.

| Action | Effect | Rejection reasons |
|---|---|---|
| `Twin::ScaleReplicas.new(service:, cluster:, replicas:)` | Run that many pods of the service in the cluster: new pods are placed by the scheduler, surplus ones removed. | `:unknown_service`, `:unknown_cluster`, `:invalid_replicas`, `:no_replicas_left` (the service would have no pods anywhere), `:insufficient_resources`, `:managed_by_federation` |
| `Twin::Route.new(service:, weights:)` | Route the service's requests among clusters in proportion to `weights` (`{cluster => weight}`; clusters left out get none), then to one of that cluster's pods at random. `{}` restores the configured load balancing. | `:unknown_service`, `:unknown_cluster`, `:invalid_weights` |
| `Twin::DivideReplicas.new(service:, total:, weights:)` | Run `total` replicas of the service, divided among clusters by `weights`, and keep them so through cluster failures (a federation policy, after Karmada's). | `:unknown_service`, `:unknown_cluster`, `:invalid_replicas`, `:invalid_weights` |

Services and clusters are named as in the configuration (cluster names
may be symbols or numbers, e.g. `:one` or `1`, as the configuration has
them).

**Autoscalers keep running.** Horizontal pod autoscalers declared in the
configuration (`horizontal_pod_autoscalers`) stay active alongside the
controller and can change a service's replicas between its decisions. For
a controller in full charge of scaling, use a configuration without them.
New pods are placed by KubeTwin's scheduler, and with a `startup_time`
they serve only once started.

## Observations

`#observe` returns a Hash describing the last step, with rates and
statistics over that interval only:

- `locations`: one per cluster, with its `kind` (`:cloud` or `:edge`) and
  features `up` (the share of its nodes up), `cpu_capacity`,
  `cpu_requested`, `memory_capacity`, `memory_requested`, `cpu_utilization`;
- `links`: one per pair of distinct clusters, with `latency_mean` and
  `latency_p95` of the messages that crossed it (a link no message crossed
  repeats its last values);
- `placements`: one per (service, cluster) pair, with `replicas_ready`,
  `replicas_starting`, `queue_length_mean`, `arrival_rate` and
  `service_time_mean`;
- `workflows`: one per workflow type, with `arrival_rate`, `completed`,
  `dropped`, `response_mean`, `response_p50`, `response_p95` and
  `slo_violation_rate`
  (the share of responses above the workflow's objective in `slos:`, in
  ms; 0 without one);
- `global`: the `time` and the `cost` of the interval.

The sets of entities don't change during a run. Response and service times
are in milliseconds, rates per second. A few features are reported as
constants because KubeTwin doesn't model them (a link's `up`, `loss_rate`
and bandwidth, a location's `energy`); a network model can fill them in.

## Forking: what-if rollouts

`#fork` returns an independent copy of the twin in its current state,
random streams included. Given the same actions, the copy steps through
exactly the same future as the original (observations, rejections, result),
and nothing done to one affects the other. Use it to try actions out — e.g.
to evaluate candidate decisions, or to roll a planner forward — without
disturbing the original. The configuration's MDN models, which are only
read, are shared rather than copied.

## Options

All of these are optional and default to KubeTwin's classic behaviour.

### Cold starts

A microservice type's `startup_time` (seconds, or a distribution such as
`{distribution: :lognorm, args: {...}}`, drawn from its own random stream)
is how long a new pod takes before it serves
requests; until then it counts as `replicas_starting`. Without it, new pods
serve at once.

### CPU sharing

A microservice type's `cores` makes the requests in service on a pod share
that many cores (processor sharing): each runs at full speed while there
are no more of them than cores, and at `cores / n` otherwise. Without it,
every request in service runs at full speed, however many there are.

### Failures

`failures:` adds failure processes (times in seconds):

```ruby
failures: {
  pods:     {mtbf: 3600, restart_time: 5},       # each pod crashes and restarts in place
  nodes:    {mtbf: 7200, mttr: 120},              # each node fails for a while
  clusters: {mtbf: 86_400, mttr: 300},            # as nodes, for a whole cluster
  outages:  [{cluster: "rome", at: 600, duration: 120}],  # scheduled failures
  seed: 42
}
```

Pods on a failed node leave their services until it recovers, then restart
(taking their type's `startup_time`); nothing new is placed on a failed
node. Requests finding no ready pod wait and retry.

### Federation

`federation:` manages services across clusters with propagation policies,
after Karmada's:

```ruby
federation: {
  policies: {"reviews" => {mode: :divided, replicas: 6, clusters: ["rome", "milan"], weights: {"rome" => 2, "milan" => 1}}},
  failover_toleration: 30   # seconds a cluster may be down before its replicas move elsewhere
}
```

`:divided` splits `replicas` among the clusters by weight (with optional
`min_clusters` and `max_clusters`); `:duplicated` runs `replicas` in each.
When a cluster has been down longer than the toleration, its replicas are
moved to the others, and they move back as soon as it recovers. With a federation configuration, `replicas_mapping:`
gives the cluster of each initial pod. Services under a policy are scaled
with `DivideReplicas`, not `ScaleReplicas`.

### Network

`network:` replaces KubeTwin's latency models with any network model, an
object with

```ruby
transfer(source, destination, bytes:, time:)  # -> an object with #delay and #delivered
```

where source and destination are location ids and `time` is in seconds
since the simulation's start (or something that builds one per `#reset`).
Every message between components crosses it. Lost messages are resent the
way TCP would, after a timeout that doubles on each loss
(`retransmission: {timeout:, max_attempts:}`, by default 0.2 s and 8
attempts); a message still lost
after the last attempt is counted as undelivered and handed over anyway.
The default network (`LegacyNetwork`) wraps the configured latency models
and delivers every message.

### External workloads

`workload:` adds requests beside the configured generators: any object
with `#arrivals(from:, to:)` returning arrivals with `#time`, `#location`,
`#workflow` and `#bytes`. Each arrival becomes a request of its workflow
from its location, its response going back there. This lets an external
model (e.g. devices offloading work at the edge) drive the load.

## Reproducibility

Every source of randomness — request generation, service times, failure
processes, the scheduler's own choices — draws from its own seeded stream,
so a run with the same configuration, options and actions is reproducible,
and a fork replays its parent's future exactly.
