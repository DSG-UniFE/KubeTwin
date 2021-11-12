# frozen_string_literal: true

require 'minitest_helper'

require_relative './reference_configuration'


describe KUBETWIN::DataCenter do
  it 'should create a valid public Cloud data center' do
    args = { maximum_vm_capacity: lambda {|vms| true } }
    KUBETWIN::DataCenter.new(id: :dc_name, name: "Some DC", type: :public, location_id: 1, **args)
  end

  it 'should create a valid private Cloud data center' do
    args = { maximum_vm_capacity: lambda {|vms| true } }
    KUBETWIN::DataCenter.new(id: :dc_name, name: "Some DC", type: :private, location_id: 1, **args)
  end
end

