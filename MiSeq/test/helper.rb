require 'pp'
require 'tempfile'
require 'fileutils'
require 'test/unit'

# Appending Test::Unit::TestCase class.
class Test::Unit::TestCase
  # Monkey patch of TestCase to define test method.
  #
  # @param desc [String] Test description.
  # @param impl [Proc]   Code block.
  def self.test(desc, &impl)
    define_method("test #{desc}", &impl)
  end
end
