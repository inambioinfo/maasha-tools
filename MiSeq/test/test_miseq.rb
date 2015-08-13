$LOAD_PATH.unshift File.join(File.dirname(__FILE__), '..')

require 'test/helper'
require 'lib/miseq'

# Test class for MiSeq.
class TestMiSeq < Test::Unit::TestCase
  def setup
    @dir          = Dir.mktmpdir('miseq')
    @file_stats   = File.join(@dir, 'GenerateFASTQRunStatistics.xml')
    @file_samples = File.join(@dir, 'Samplesheet.csv')
  end

  def teardown
    FileUtils.rm_rf @dir
  end

  test 'RunStatistics#complete? with non existing file' do
    assert_false(MiSeq::RunStatistics.complete?(''))
  end

  test 'RunStatistics#complete? without CompletionTime tag' do
    File.open(@file_stats, 'w') { |ios| ios.write('') }
    assert_false(MiSeq::RunStatistics.complete?(@file_stats))
  end

  test 'RunStatistics#complete? with CompletionTime tag' do
    File.open(@file_stats, 'w') { |ios| ios.write('  <CompletionTime>') }
    assert_true(MiSeq::RunStatistics.complete?(@file_stats))
  end

  # test 'SampleSheet#' do
  #   assert_equal(1, 2)
  # end
  #
  # test 'DataDir#' do
  #   assert_equal(1, 2)
  # end
  #
  # test 'Data#' do
  #   assert_equal(1, 2)
  # end
end
