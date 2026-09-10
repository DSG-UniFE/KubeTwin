# frozen_string_literal: true

require 'minitest_helper'

require_relative './reference_configuration'


describe KUBETWIN::Configuration do

  describe 'simulation-related parameters' do

    it 'should correctly load simulation start' do
      with_reference_config do |conf|
        _(conf.start_time).must_equal START_TIME
      end
    end

    it 'should correctly load simulation duration' do
      with_reference_config do |conf|
        _(conf.duration).must_equal DURATION
      end
    end

    it 'should correctly load simulation end time' do
      with_reference_config do |conf|
        _(conf.end_time).must_equal START_TIME + DURATION
      end
    end

    it 'should correctly load warmup phase duration' do
      with_reference_config do |conf|
        _(conf.warmup_duration).must_equal WARMUP_DURATION
      end
    end

  end


  describe 'microservice_types' do

    it 'should have 3 items' do
      with_reference_config do |conf|
        _(conf.microservice_types.size).must_equal 3
      end
    end

    it 'should define a Web Server' do
      with_reference_config do |conf|
        _(conf.microservice_types.keys).must_include('Web Server')
      end
    end

    it 'should define an App Server' do
      with_reference_config do |conf|
        _(conf.microservice_types.keys).must_include('App Server')
      end
    end

    it 'should define a Financial Transaction Server' do
      with_reference_config do |conf|
        _(conf.microservice_types.keys).must_include('Financial Transaction Server')
      end
    end

    describe 'the Web Server' do
      it 'should define service times for both mec and cloud clusters' do
        with_reference_config do |conf|
          item_conf = conf.microservice_types['Web Server']
          _(item_conf[:service_time_distribution].keys).must_include(:mec)
          _(item_conf[:service_time_distribution].keys).must_include(:cloud)
        end
      end
    end

    describe 'the App Server' do
      it 'should require more CPU and memory than the Web Server' do
        with_reference_config do |conf|
          web_conf = conf.microservice_types['Web Server']
          app_conf = conf.microservice_types['App Server']
          _(app_conf[:resources_requirements_cpu]).must_be :>, web_conf[:resources_requirements_cpu]
          _(app_conf[:resources_requirements_memory]).must_be :>, web_conf[:resources_requirements_memory]
        end
      end
    end

  end


  describe 'clusters' do
    it 'should have 5 items' do
      with_reference_config do |conf|
        _(conf.clusters.size).must_equal 5
      end
    end
  end

end
