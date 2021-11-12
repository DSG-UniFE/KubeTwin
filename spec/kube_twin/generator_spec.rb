# frozen_string_literal: true

require 'minitest_helper'

require 'tempfile'
require 'kube_twin/generator'

require_relative './reference_configuration'


describe KUBETWIN::RequestGenerator do

  GENERATION_TIMES  = [ Time.now, Time.now + 1.second, Time.now + 2.seconds ].map(&:to_f)
  WORKFLOW_TYPE_IDS = GENERATION_TIMES.map { rand(10) }
  CUSTOMER_IDS      = GENERATION_TIMES.map { rand(5) }
  REQUEST_GENERATION_DATA=<<-END
    Generation Time,Workflow Type ID,Customer ID
    #{GENERATION_TIMES[0]},#{WORKFLOW_TYPE_IDS[0]},#{CUSTOMER_IDS[0]}
    #{GENERATION_TIMES[1]},#{WORKFLOW_TYPE_IDS[1]},#{CUSTOMER_IDS[1]}
    #{GENERATION_TIMES[2]},#{WORKFLOW_TYPE_IDS[2]},#{CUSTOMER_IDS[2]}
  END

  it 'should read from CSV file' do
    begin
      # create temporary file with request generation information
      tf = Tempfile.new('generator_test')
      tf.write(REQUEST_GENERATION_DATA)
      tf.close

      with_reference_config(request_generation: { filename: tf.path }) do |conf|
        rg = KUBETWIN::RequestGenerator.new(conf.request_generation)
        r = rg.generate
        _(r[:rid]).must_equal 1
        _(r[:generation_time]).must_equal GENERATION_TIMES[0]
        _(r[:workflow_type_id]).must_equal WORKFLOW_TYPE_IDS[0]
        _(r[:customer_id]).must_equal CUSTOMER_IDS[0]
      end

    ensure
      # delete temporary file
      tf.delete
    end
  end

  it 'should read from command' do
    begin
      # create temporary file with request generation information
      tf = Tempfile.new('generator_test')
      tf.write(REQUEST_GENERATION_DATA)
      tf.close

      with_reference_config(request_generation: { command: "cat #{tf.path}" }) do |conf|
        rg = SISFC::RequestGenerator.new(conf.request_generation)
        r = rg.generate
        _(r[:rid]).must_equal 1
        _(r[:generation_time]).must_equal GENERATION_TIMES[0]
        _(r[:workflow_type_id]).must_equal WORKFLOW_TYPE_IDS[0]
        _(r[:customer_id]).must_equal CUSTOMER_IDS[0]
      end
    ensure
      # delete temporary file
      tf.delete
    end
  end

end
