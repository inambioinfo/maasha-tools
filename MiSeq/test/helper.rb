require 'pp'
require 'tempfile'
require 'fileutils'
require 'test/unit'

class Test::Unit::TestCase
  def self.test(desc, &impl)
    define_method("test #{desc}", &impl)
  end
end
