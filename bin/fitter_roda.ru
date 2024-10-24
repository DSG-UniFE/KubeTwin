#!/usr/bin/env ruby

begin
  require 'kube_twin'
  require 'socket'
  require 'jsons'
  require 'logger'
  require 'pycall'
  require 'pycall/import'
  include PyCall::Import
  require 'csv'
rescue LoadError
  require 'rubygems'
  require 'kube_twin'
  require 'mhl'
end

def do_abort(message)
    abort <<-EOS.gsub(/^\s+\|/, '')
      |#{message}
      |
      |Usage:
      |    #{File.basename(__FILE__)} simulator_config_file testbed_file n
      |
    EOS
  end



class App < Roda

  pyfrom :scipy, import: :stats

  $n = 3

  $params = $n * 3 - 1 # weight mu sigma for each component
  SIM_FILE = "examples/sm-c1-1000-gv.conf"
  K8S_LOG = "req_logs_august.csv"
  MS1_LOG = "ms1-960-red.txt"
  MS2_LOG = "ms2-960-red.txt"
  # - 1 --> array indexes start from 0
  puts "n #{$n} params #{$params}"

  # pycall import
  PyCall.import_module("numpy")

  # here run the optimizer on the oracle
  # load simulation configuration
  time = Time.now.strftime('%Y%m%d%H%M%S')

  sim_conf = KUBETWIN::Configuration.load_from_file(SIM_FILE)
  msc = sim_conf.microservice_types

  # open the log only once
  k8s_log = CSV.parse(File.read(K8S_LOG), headers: true)
  k8s_ttr = k8s_log.by_col[1].map(&:to_f) # get the ttr column

  # ms1 ttr
  k8s_ms1 = CSV.parse(File.read(MS1_LOG), headers: true)
  ms1_ttr = k8s_ms1.by_col[0].map(&:to_f) # get the ttr column
  puts "MS1: #{ms1_ttr.length} #{ms1_ttr.max} #{ms1_ttr.min}"
  # ms2 ttr
  k8s_ms2 = CSV.parse(File.read(MS2_LOG), headers: true)
  ms2_ttr = k8s_ms2.by_col[0].map(&:to_f) # get the ttr column
  # ms2_ttr = ms2_ttr.select{|e| ! e.nil?}.collect {|e| e * 1E3}
  puts "MS2: #{ms2_ttr.length} #{ms2_ttr.max} #{ms2_ttr.min}"
  puts "TTR: #{k8s_ttr.length} #{k8s_ttr.max} #{k8s_ttr.min}"


  $microservice_types = sim_conf.microservice_types
  $n_ms = $microservice_types.length

  puts "Number of microservices #{$n_ms}"

  $seed = 12345

  def encode_service_time_conf(x, n_ms)

  # for each micro-servce
  config = {}

  #puts "x:#{x}"

  x.each_slice($params).to_a.each_with_index do |ms, msi|

    #puts "Microservice: #{msi}"
    #puts "Microservice: #{ms}"
    #msi_istart = msi
    #msi_iend = msi * $params - $n # n is the number of component for the GMM

    # [0.15, 15, 30, 0.35, 20, 22, 30, 15] # n = 3 components
    # weights = 0.15, 0.35 

    # get last weight parameter

    w_last = 1
    (0..($params - 3)).select {|pi| pi % 3 == 0}.each do |p| 
      w_last -= ms[p]
    end
    #puts "w_last #{w_last}"

    # w_last = 0 if w_last < 0 # reject negative probabilities  
    # or normalize the sum of tha absolute values to 1?
    return nil if w_last < 0

    #puts "ms gmm parameters: #{ms}"
    # clone the component allocation
    y = ms.clone
    y.insert($params - 2, w_last)
    # add w_last in its position
    #puts "y gmm parameters: #{y}"

    #puts $microservice_types
    microservice_name = $microservice_types.keys[msi]
    #puts "msn #{microservice_name}"
    config[microservice_name] = { distribution: :mixture, args: 
      ERV::GaussianMixtureHelper.RawParametersToMixtureArgsSeed(*y, $seed)
    }
    
     #puts config
  end
  config
end

def fitting_function(component_allocation)

    res = 0

    # load simulation configuration
    conf = KUBETWIN::Configuration.load_from_file(ARGV[0])
    msc = sim_conf.microservice_types
    processing_time = encode_service_time_conf(component_allocation, msc.keys.length)
    
    if processing_time.nil?
      res = 1E+195
    else

      processing_time.each do |ms_name, ms_time_dist|
        # puts msc
        msc[ms_name][:service_time_distribution][:mec] = ms_time_dist
        # create a simulator and launch it
      end

      #puts msc

      sim = KUBETWIN::KSimulation.new(configuration: conf,
                                  evaluator: KUBETWIN::Evaluator.new(conf))
      benchmark, bms1, bms2 = sim.evaluate_allocation(nil, nil, msc)

      # evaluate bench here

      sim_log = CSV.parse(File.read(benchmark), headers: true)
      sim_ttr = sim_log.by_col[1].map(&:to_f)

      ms1_log = CSV.parse(File.read(bms1), headers: true)
      sim_ms1_ttr = ms1_log.by_col[1].map(&:to_f)

      ms2_log = CSV.parse(File.read(bms2), headers: true)
      sim_ms2_ttr = ms2_log.by_col[1].map(&:to_f)

      if sim_ttr.length < (k8s_ttr.length / 2) ||  sim_ttr.length > (k8s_ttr.length * 3 / 2.to_f)
        res = 1E+195
        # puts "#{sim_ttr.length}"
      else
        ks_e2e = stats.kstest(sim_ttr, k8s_ttr)

        #ks_ms1 = stats.kstest(sim_ms1_ttr, ms1_ttr)
        #ks_ms2 = stats.kstest(sim_ms2_ttr, ms2_ttr)
        

        tt_ms1 = stats.ttest_ind(ms1_ttr, sim_ms1_ttr)
        tt_ms2 = stats.ttest_ind(ms2_ttr, sim_ms2_ttr)
  
        # add a penalty if ms1 and ms2 do not pass the validation test
        # here the t-test was chosen because the metrics are not accurate
        # so we do not want to apply a K-S validation
  
        penalty = 0
        penalty += 1E3 if tt_ms1.pvalue.to_f < 0.05 # ms1
        penalty += 1E3 if tt_ms2.pvalue.to_f < 0.05 # ms2
        #penalty += 1E3 if ks_ms1.pvalue.to_f < 0.05 # ms1
        #penalty += 1E3 if ks_ms2.pvalue.to_f < 0.05 # ms2

        # penalty += 50 if ks_e2e.pvalue.to_f < 0.05

        res = ks_e2e.statistic.to_f + penalty
  
        #res = 0.33 * ks_e2e.statistic.to_f + 0.33 * ks_ms1.statistic.to_f + 0.33 * ks_ms2.statistic.to_f
        
        puts "sim: #{ks_e2e}, ms1: #{tt_ms1}, ms2: #{tt_ms1}, reqs: #{sim_ttr.length}, res: #{res}" if penalty == 0
        #puts "sim: #{ks_e2e}, ms1: #{ks_ms1}, ms2: #{ks_ms1}, reqs: #{sim_ttr.length}, res: #{res}" if penalty == 0
      end
      File.delete(benchmark)
      File.delete(bms1)
      File.delete(bms2)
    end
    # puts "#{res}"
    -res
end

server = TCPServer.new 5678

while session = server.accept

  conf = session.read
  puts(conf)
  ca = JSON.parse(conf)
  configuration = ca['configuration']

  #puts allocation
  res = fitting_function(configuration)
  response['Content-Type'] = 'application/json'
  response.write({ 'res' => res}.to_json)
  response.finish

  session.puts "#{Time.now}"
  session.close
end