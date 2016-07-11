require 'sisfc/configuration'

START_TIME      = Time.utc(1978, 'Aug', 12, 14, 30, 0).to_f
DURATION        = 1.minute.to_f
WARMUP_DURATION = 10.seconds.to_f
SIMULATION_CHARACTERIZATION = <<END
  # start time, duration, and warmup time for simulations
  start_time Time.utc(1978, 'Aug', 12, 14, 30, 0)
  duration 1.minute
  warmup_duration 10.seconds
END


# characterization of data centers
DATA_CENTERS_CHARACTERIZATION = <<END
data_centers \
  1 => {
    maximum_vm_capacity: {
      tiny:   300,
      small:  300,
      medium: 300,
      large:  300,
      huge:   300,
    },
    location_id: 0,
  },
  2 => {
    maximum_vm_capacity: {
      tiny:   300,
      small:  300,
      medium: 300,
      large:  300,
      huge:   300,
    },
    location_id: 1,
  },
  3 => {
    maximum_vm_capacity: {
      tiny:   300,
      small:  300,
      medium: 300,
      large:  300,
      huge:   300,
    },
    location_id: 2,
  },
  4 => {
    maximum_vm_capacity: {
      tiny:   300,
      small:  300,
      medium: 300,
      large:  300,
      huge:   300,
    },
    location_id: 3,
  },
  5 => {
    maximum_vm_capacity: {
      tiny:   300,
      small:  300,
      medium: 300,
      large:  300,
      huge:   300,
    },
    location_id: 4,
  }
END


LATENCY_MODELS_CHARACTERIZATION = <<END
latency_models \
  [
    # location 0
    [
      # remember to add nil in position 0
      { distribution: :gaussian,
        mu:           0.009,
        sigma:        0.001 },
      { distribution: :gaussian,
        mu:           0.009,
        sigma:        0.001 },
      { distribution: :gaussian,
        mu:           0.009,
        sigma:        0.001 },
      { distribution: :gaussian,
        mu:           0.009,
        sigma:        0.001 },
      { distribution: :gaussian,
        mu:           0.009,
        sigma:        0.001 },
      { distribution: :gaussian,
        mu:           0.009,
        sigma:        0.001 },
      { distribution: :gaussian,
        mu:           0.009,
        sigma:        0.001 },
      { distribution: :gaussian,
        mu:           0.009,
        sigma:        0.001 },
    ],
  ]
END


CUSTOMER_CHARACTERIZATION = <<END
customers \
  [
    # first customer (id: 0) is in location with id=5 (?)
    { location_id: 5 },
    # second customer (id: 1) is in location with id=6 (?)
    { location_id: 6 },
    # third customer (id: 2) is in location with id=7 (?)
    { location_id: 7 },
    # fourth customer (id: 3) is in location with id=8 (?)
    { location_id: 8 },
  ]
END


# characterization of component types
SERVICE_COMPONENT_TYPES_CHARACTERIZATION = <<END
service_component_types \
  'Web Server' => {
    allowed_vm_types: [ :medium, :large ],
    service_time_distribution: {
      medium: { distribution: :gaussian,
                mu:           0.009, # 1 request processed every 9ms
                sigma:        0.001 },
      large:  { distribution: :gaussian,
                mu:           0.007, # 1 request processed every 7ms
                sigma:        0.001 } },
    estimated_workload: 50,
  },
  'App Server' => {
    allowed_vm_types: [ :medium, :large, :huge ],
    service_time_distribution: {
      medium: { distribution: :gaussian,
                mu:           0.015, # 1 request processed every 15ms
                sigma:        0.005 },
      large:  { distribution: :gaussian,
                mu:           0.012, # 1 request processed every 12ms
                sigma:        0.003 },
      huge:   { distribution: :gaussian,
                mu:           0.009, # 1 request processed every 7ms
                sigma:        0.002 } },
    estimated_workload: 70,
  },
  'Financial Transaction Server' => {
    allowed_vm_types: [ :large, :huge ],
    service_time_distribution: {
      large:  { distribution: :gaussian,
                mu:           0.015, # 1 request processed every 15ms
                sigma:        0.004 },
      huge:   { distribution: :gaussian,
                mu:           0.008, # 1 request processed every 8ms
                sigma:        0.003 } },
    estimated_workload: 80,
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


EVALUATION_CHARACTERIZATION = <<END
evaluation \
  vm_hourly_cost: [
    { data_center: 1, vm_type: :medium, cost: 0.160 },
    { data_center: 1, vm_type: :large,  cost: 0.320 },
    { data_center: 2, vm_type: :medium, cost: 0.184 },
    { data_center: 2, vm_type: :large,  cost: 0.368 }
  ],
  # 500$ penalties if MTTR takes more than 50 msecs
  penalties: lambda {|kpis,dc_kpis| 500.0 if kpis[:mttr] > 0.050 }
END

# this is the whole reference configuration
# (useful for spec'ing configuration.rb)
REFERENCE_CONFIGURATION =
  SIMULATION_CHARACTERIZATION +
  DATA_CENTERS_CHARACTERIZATION +
  LATENCY_MODELS_CHARACTERIZATION +
  CUSTOMER_CHARACTERIZATION +
  SERVICE_COMPONENT_TYPES_CHARACTERIZATION +
  WORKFLOW_TYPES_CHARACTERIZATION +
  CONSTRAINT_CHARACTERIZATION +
  REQUEST_GENERATION_CHARACTERIZATION +
  KPI_CUSTOMIZATION_CHARACTERIZATION +
  EVALUATION_CHARACTERIZATION


evaluator = Object.new
evaluator.extend SISFC::Configurable
evaluator.instance_eval(REFERENCE_CONFIGURATION)

# these are preprocessed portions of the reference configuration
# (useful for spec'ing everything else)
DATA_CENTERS            = evaluator.data_centers
SERVICE_COMPONENT_TYPES = evaluator.service_component_types
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
    conf = SISFC::Configuration.load_from_file(tf.path)

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
