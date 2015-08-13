$LOAD_PATH.unshift File.join(File.dirname(__FILE__), '..')

require 'test/helper'

class TestCSV < Test::Unit::TestCase
  test 'my favorite test' do
    assert_equal(1, 2)
  end
end
