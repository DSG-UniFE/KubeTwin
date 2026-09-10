# frozen_string_literal: true

require 'kube_twin/configuration'
require 'kube_twin/timespan'

START_TIME      = Time.utc(1978, 'Aug', 12, 14, 30, 0).to_f
DURATION        = KUBETWIN::Timespan.minute(1).to_f
WARMUP_DURATION = KUBETWIN::Timespan.seconds(10).to_f
SIMULATION_CHARACTERIZATION = <<END
  # start time, duration, and warmup time for simulations
  start_time Time.utc(1978, 'Aug', 12, 14, 30, 0)
  duration KUBETWIN::Timespan.minute(1)
  warmup_duration KUBETWIN::Timespan.seconds(10)
END


# characterization of clusters
# (renamed from the old data_centers model: KUBETWIN::Cluster now requires
# type/tier/node_number/node_resources_cpu/node_resources_memory -- see any
# examples/*.conf's `clusters` block for the current shape. Kept the same
# location_ids (0..4) that LATENCY_MODELS_CHARACTERIZATION and
# CUSTOMER_CHARACTERIZATION below already reference.)
CLUSTERS_CHARACTERIZATION = <<END
clusters \
  1 => {
    location_id: 0,
    name: "Cluster 1",
    type: :mec,
    tier: 'local',
    node_number: 25,
    node_resources_cpu: 100,
    node_resources_memory: 100,
  },
  2 => {
    location_id: 1,
    name: "Cluster 2",
    type: :mec,
    tier: 'local',
    node_number: 25,
    node_resources_cpu: 100,
    node_resources_memory: 100,
  },
  3 => {
    location_id: 2,
    name: "Cluster 3",
    type: :mec,
    tier: 'local',
    node_number: 25,
    node_resources_cpu: 100,
    node_resources_memory: 100,
  },
  4 => {
    location_id: 3,
    name: "Cluster 4",
    type: :mec,
    tier: 'local',
    node_number: 25,
    node_resources_cpu: 100,
    node_resources_memory: 100,
  },
  5 => {
    location_id: 4,
    name: "Cluster 5",
    type: :cloud,
    tier: 'central',
    node_number: 200,
    node_resources_cpu: 500,
    node_resources_memory: 500,
  }
END


LATENCY_MODELS_CHARACTERIZATION = <<END
latency_models \
  [
    # location 0
    [
      {
        distribution: :gaussian,
        args: {
          mean: 0.009,
          sd:   0.001,
        },
      },
      {
        distribution: :gaussian,
        args: {
          mean: 0.009,
          sd:   0.001,
        },
      },
      {
        distribution: :gaussian,
        args: {
          mean: 0.009,
          sd:   0.001,
        },
      },
      {
        distribution: :gaussian,
        args: {
          mean: 0.009,
          sd:   0.001,
        },
      },
      {
        distribution: :gaussian,
        args: {
          mean: 0.009,
          sd:   0.001,
        },
      },
      {
        distribution: :gaussian,
        args: {
          mean: 0.009,
          sd:   0.001,
        },
      },
      {
        distribution: :gaussian,
        args: {
          mean: 0.009,
          sd:   0.001,
        },
      },
      {
        distribution: :gaussian,
        args: {
          mean: 0.009,
          sd:   0.001,
        },
      },
    ],
    # location 1
    [
      {
        distribution: :gaussian,
        args: {
          mean: 0.009,
          sd:   0.001,
        },
      },
      {
        distribution: :gaussian,
        args: {
          mean: 0.009,
          sd:   0.001,
        },
      },
      {
        distribution: :gaussian,
        args: {
          mean: 0.009,
          sd:   0.001,
        },
      },
      {
        distribution: :gaussian,
        args: {
          mean: 0.009,
          sd:   0.001,
        },
      },
      {
        distribution: :gaussian,
        args: {
          mean: 0.009,
          sd:   0.001,
        },
      },
      {
        distribution: :gaussian,
        args: {
          mean: 0.009,
          sd:   0.001,
        },
      },
      {
        distribution: :gaussian,
        args: {
          mean: 0.009,
          sd:   0.001,
        },
      },
    ],
    # location 2
    [
      {
        distribution: :gaussian,
        args: {
          mean: 0.009,
          sd:   0.001,
        },
      },
      {
        distribution: :gaussian,
        args: {
          mean: 0.009,
          sd:   0.001,
        },
      },
      {
        distribution: :gaussian,
        args: {
          mean: 0.009,
          sd:   0.001,
        },
      },
      {
        distribution: :gaussian,
        args: {
          mean: 0.009,
          sd:   0.001,
        },
      },
      {
        distribution: :gaussian,
        args: {
          mean: 0.009,
          sd:   0.001,
        },
      },
      {
        distribution: :gaussian,
        args: {
          mean: 0.009,
          sd:   0.001,
        },
      },
    ],
    # location 3
    [
      {
        distribution: :gaussian,
        args: {
          mean: 0.009,
          sd:   0.001,
        },
      },
      {
        distribution: :gaussian,
        args: {
          mean: 0.009,
          sd:   0.001,
        },
      },
      {
        distribution: :gaussian,
        args: {
          mean: 0.009,
          sd:   0.001,
        },
      },
      {
        distribution: :gaussian,
        args: {
          mean: 0.009,
          sd:   0.001,
        },
      },
      {
        distribution: :gaussian,
        args: {
          mean: 0.009,
          sd:   0.001,
        },
      },
    ],
    # location 4
    [
      {
        distribution: :gaussian,
        args: {
          mean: 0.009,
          sd:   0.001,
        },
      },
      {
        distribution: :gaussian,
        args: {
          mean: 0.009,
          sd:   0.001,
        },
      },
      {
        distribution: :gaussian,
        args: {
          mean: 0.009,
          sd:   0.001,
        },
      },
      {
        distribution: :gaussian,
        args: {
          mean: 0.009,
          sd:   0.001,
        },
      },
    ],
    # location 5
    [
      {
        distribution: :gaussian,
        args: {
          mean: 0.009,
          sd:   0.001,
        },
      },
      {
        distribution: :gaussian,
        args: {
          mean: 0.009,
          sd:   0.001,
        },
      },
      {
        distribution: :gaussian,
        args: {
          mean: 0.009,
          sd:   0.001,
        },
      },
    ],
    # location 6
    [
      {
        distribution: :gaussian,
        args: {
          mean: 0.009,
          sd:   0.001,
        },
      },
      {
        distribution: :gaussian,
        args: {
          mean: 0.009,
          sd:   0.001,
        },
      },
    ],
    # location 7
    [
      {
        distribution: :gaussian,
        args: {
          mean: 0.009,
          sd:   0.001,
        },
      },
    ],
  ]
END


CUSTOMER_CHARACTERIZATION = <<END
customers \
  1 => { location_id: 5 },
  # first customer (id: 1) is in location with id=5 (?)
  2 => { location_id: 6 },
  # second customer (id: 2) is in location with id=6 (?)
  3 =>{ location_id: 7 },
  # third customer (id: 3) is in location with id=7 (?)
  4 => { location_id: 8 }
  # fourth customer (id: 4) is in location with id=8 (?)
END


# characterization of microservice types
# (renamed from the old service_component_types/allowed_vm_types model:
# KubeTwin characterizes each microservice by its per-cluster-type service
# time and its fixed CPU/memory resource requirements, not by a list of
# allowed VM sizes -- see any examples/*.conf for the current shape)
MICROSERVICE_TYPES_CHARACTERIZATION = <<END
microservice_types \
  'Web Server' => {
    service_time_distribution: {
      mec:   { distribution: :gaussian,
               args: { mean: 0.009, # 1 request processed every 9ms
                       sd:   0.001 } },
      cloud: { distribution: :gaussian,
               args: { mean: 0.007, # 1 request processed every 7ms
                       sd:   0.001 } },
    },
    resources_requirements_cpu:    50,
    resources_requirements_memory: 50,
  },
  'App Server' => {
    service_time_distribution: {
      mec:   { distribution: :gaussian,
               args: { mean: 0.015, # 1 request processed every 15ms
                       sd:   0.005 } },
      cloud: { distribution: :gaussian,
               args: { mean: 0.012, # 1 request processed every 12ms
                       sd:   0.003 } },
    },
    resources_requirements_cpu:    70,
    resources_requirements_memory: 70,
  },
  'Financial Transaction Server' => {
    service_time_distribution: {
      mec:   { distribution: :gaussian,
               args: { mean: 0.015, # 1 request processed every 15ms
                       sd:   0.004 } },
      cloud: { distribution: :gaussian,
               args: { mean: 0.008, # 1 request processed every 8ms
                       sd:   0.003 } },
    },
    resources_requirements_cpu:    80,
    resources_requirements_memory: 80,
  }
END


# workflow (or job) types descriptions
WORKFLOW_TYPES_CHARACTERIZATION = <<END
workflow_types \
  1 => {
    component_sequence: [
      { name: 'Web Server' },
      { name: 'App Server' },
      { name: 'Financial Transaction Server' },
    ],
    next_component_selection: :random,
  },
  2 => {
    component_sequence: [
      { name: 'Web Server' },
      { name: 'App Server' },
    ],
    # next_component_selection: :least_loaded,
    next_component_selection: :random,
  }
END


CONSTRAINT_CHARACTERIZATION = <<END
constraints \
  'Web Server' => [
    { data_center: 1, min: 0, max: 300 },
    { data_center: 2, min: 0, max: 300 },
    { data_center: 3, min: 0, max: 300 },
    { data_center: 4, min: 0, max: 300 },
    { data_center: 5, min: 0, max: 300 },
  ],
  'App Server' => [
    { data_center: 1, min: 0, max: 300 },
    { data_center: 2, min: 0, max: 300 },
    { data_center: 3, min: 0, max: 300 },
    { data_center: 4, min: 0, max: 300 },
    { data_center: 5, min: 0, max: 300 },
  ],
  'Financial Transaction Server' => [
    { data_center: 1, number: 1 },
    { data_center: 2, number: 0 },
    { data_center: 3, number: 0 },
    { data_center: 4, number: 0 },
    { data_center: 5, number: 0 },
  ]
END


REQUEST_GENERATION_CHARACTERIZATION = <<END
request_generation \
  command: "<pwd>/generator.R"
END


KPI_CUSTOMIZATION_CHARACTERIZATION = <<END
kpi_customization \
  longer_than: [ 2.0, 5.0 ] # count number of requests longer than 2 and 5 seconds respectively
END


# (renamed from the old vm_hourly_cost model: KUBETWIN::Evaluator now reads
# conf.evaluation[:cluster_hourly_cost], keyed by cluster id with
# fixed_cpu_hourly_cost/fixed_memory_hourly_cost -- see evaluation.rb)
EVALUATION_CHARACTERIZATION = <<END
evaluation \
  cluster_hourly_cost: [
    { cluster: 1, fixed_cpu_hourly_cost: 0.160, fixed_memory_hourly_cost: 0.080 },
    { cluster: 2, fixed_cpu_hourly_cost: 0.184, fixed_memory_hourly_cost: 0.092 },
    { cluster: 3, fixed_cpu_hourly_cost: 0.160, fixed_memory_hourly_cost: 0.080 },
    { cluster: 4, fixed_cpu_hourly_cost: 0.184, fixed_memory_hourly_cost: 0.092 },
    { cluster: 5, fixed_cpu_hourly_cost: 0.320, fixed_memory_hourly_cost: 0.160 },
  ],
  # 500$ penalties if MTTR takes more than 50 msecs
  penalties: lambda {|kpis,dc_kpis| { slo_violation_penalties: 500.0 } if kpis[:mttr] > 0.050 }
END

# this is the whole reference configuration
# (useful for spec'ing configuration.rb)
REFERENCE_CONFIGURATION =
  SIMULATION_CHARACTERIZATION +
  CLUSTERS_CHARACTERIZATION +
  LATENCY_MODELS_CHARACTERIZATION +
  CUSTOMER_CHARACTERIZATION +
  MICROSERVICE_TYPES_CHARACTERIZATION +
  WORKFLOW_TYPES_CHARACTERIZATION +
  CONSTRAINT_CHARACTERIZATION +
  REQUEST_GENERATION_CHARACTERIZATION +
  KPI_CUSTOMIZATION_CHARACTERIZATION +
  EVALUATION_CHARACTERIZATION


evaluator = Object.new
evaluator.extend KUBETWIN::Configurable
evaluator.instance_eval(REFERENCE_CONFIGURATION)

# these are preprocessed portions of the reference configuration
# (useful for spec'ing everything else)
CLUSTERS                = evaluator.clusters
MICROSERVICE_TYPES = evaluator.microservice_types
WORKFLOW_TYPES          = evaluator.workflow_types
EVALUATION              = evaluator.evaluation
LATENCY_MODELS          = evaluator.latency_models


def with_reference_config(opts={})
  begin
    # create temporary file with reference configuration
    tf = Tempfile.open('REFERENCE_CONFIGURATION')
    tf.write(REFERENCE_CONFIGURATION)
    tf.close

    # create a configuration object from the reference configuration file
    conf = KUBETWIN::Configuration.load_from_file(tf.path, validate: false)

    # apply any change from the opts parameter and validate the modified configuration
    opts.each do |k,v|
      conf.send(k, v)
    end
    conf.validate

    # pass the configuration object to the block
    yield conf
  ensure
    # delete temporary file
    tf.delete
  end
end
