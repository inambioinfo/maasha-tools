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

  test 'SampleSheet#investigator_name without SampleSheet.csv fails' do
    ss = MiSeq::SampleSheet.new('')
    assert_raise(MiSeq::SampleSheetError) { ss.investigator_name }
  end

  test 'SampleSheet#investigator_name without Investigator line fails' do
    File.open(@file_samples, 'w') { |ios| ios.write('') }
    ss = MiSeq::SampleSheet.new(@file_samples)
    assert_raise(MiSeq::SampleSheetError) { ss.investigator_name }
  end

  test 'SampleSheet#investigator_name without Investigator field fails' do
    File.open(@file_samples, 'w') { |ios| ios.write('Investigator Name') }
    ss = MiSeq::SampleSheet.new(@file_samples)
    assert_raise(MiSeq::SampleSheetError) { ss.investigator_name }
  end

  test 'SampleSheet#investigator_name with Investigator name returns OK' do
    line = 'Investigator Name, Martin Hansen'
    File.open(@file_samples, 'w') { |ios| ios.write(line) }
    ss = MiSeq::SampleSheet.new(@file_samples)
    assert_equal('Martin_Hansen', ss.investigator_name)
  end

  test 'SampleSheet#experiment_name without SampleSheet.csv fails' do
    ss = MiSeq::SampleSheet.new('')
    assert_raise(MiSeq::SampleSheetError) { ss.experiment_name }
  end

  test 'SampleSheet#experiment_name without Experiment line fails' do
    File.open(@file_samples, 'w') { |ios| ios.write('') }
    ss = MiSeq::SampleSheet.new(@file_samples)
    assert_raise(MiSeq::SampleSheetError) { ss.experiment_name }
  end

  test 'SampleSheet#experiment_name without Experiment field fails' do
    File.open(@file_samples, 'w') { |ios| ios.write('Experiment Name') }
    ss = MiSeq::SampleSheet.new(@file_samples)
    assert_raise(MiSeq::SampleSheetError) { ss.experiment_name }
  end

  test 'SampleSheet#experiment_name with Experiment name returns OK' do
    line = 'Experiment Name, Big Bang'
    File.open(@file_samples, 'w') { |ios| ios.write(line) }
    ss = MiSeq::SampleSheet.new(@file_samples)
    assert_equal('Big_Bang', ss.experiment_name)
  end

  test 'DataDir#date with bad format fails' do
    dd = MiSeq::DataDir.new('/MiSeq/2013-04-50')
    assert_raise(MiSeq::DataDirError) { dd.date }
  end

  test 'DataDir#date returns OK' do
    dd = MiSeq::DataDir.new('/MiSeq/131223_')
    assert_equal('2013-12-23', dd.date)
  end

  test 'DataDir#rename with existing dir fails' do
    dd       = MiSeq::DataDir.new('/MiSeq/131223_')
    new_name = File.join(@dir, 'new')
    Dir.mkdir(new_name)
    assert_raise(MiSeq::DataDirError) { dd.rename(new_name) }
  end

  test 'DataDir#rename works OK' do
    old_name = File.join(@dir, '131223_')
    new_name = File.join(@dir, 'new')
    dd       = MiSeq::DataDir.new(old_name)
    Dir.mkdir(old_name)
    dd.rename(new_name)
    assert_true(File.directory? dd.dir)
  end

  # test 'Data#' do
  #   assert_equal(1, 2)
  # end
end
