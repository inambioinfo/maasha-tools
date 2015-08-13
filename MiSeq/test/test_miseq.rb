#!/usr/bin/env ruby
$LOAD_PATH.unshift File.join(File.dirname(__FILE__), '..')

require 'test/helper'


test "CSV.read_array returns correctly" do
  assert_equal(expected, result)
end
