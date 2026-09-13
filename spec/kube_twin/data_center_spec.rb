# frozen_string_literal: true

require 'minitest_helper'

describe KUBETWIN::DataCenter do

  it 'must be either private or public' do
    _{ KUBETWIN::DataCenter.new(id: 1, location_id: 1, name: "SomeDC", type: :unsupported) }.must_raise ArgumentError
  end

end
