$LOAD_PATH.unshift File.join(File.dirname(__FILE__), '..')

require 'test/helper'
require 'lib/miseq'

# rubocop:disable ClassLength

# Test class for MiSeq.
class TestMiSeq < Test::Unit::TestCase
  def setup
    @dir_src      = Dir.mktmpdir('miseq_src')
    @dir_dst      = Dir.mktmpdir('miseq_dst')
    @file_stats   = File.join(@dir_src, 'GenerateFASTQRunStatistics.xml')
    @file_samples = File.join(@dir_src, 'Samplesheet.csv')

    setup_dir_src_ok
    setup_dir_src_unfinished
  end

  def setup_dir_src_ok
    @dir_src_ok = Dir.mktmpdir('miseq_src_ok')

    3.times do |i|
      data_dir     = File.join(@dir_src_ok, ('130400'.to_i + i).to_s + '_test')
      file_stats   = File.join(data_dir, 'GenerateFASTQRunStatistics.xml')
      file_samples = File.join(data_dir, 'SampleSheet.csv')

      Dir.mkdir(data_dir)

      File.open(file_stats, 'w') { |ios| ios.puts "  <CompletionTime>#{i}" }

      File.open(file_samples, 'w') do |ios|
        ios.puts "Investigator Name, Martin Hansen #{i}"
        ios.puts "Experiment Name, Big Bang #{i}"
      end
    end
  end

  def setup_dir_src_unfinished
    @dir_src_unfinished = Dir.mktmpdir('miseq_src_unfinished')

    3.times do |i|
      data_dir     = File.join(@dir_src_unfinished,
                               ('130400'.to_i + i).to_s + '_test')
      file_stats   = File.join(data_dir, 'GenerateFASTQRunStatistics.xml')
      file_samples = File.join(data_dir, 'SampleSheet.csv')

      Dir.mkdir(data_dir)

      if i != 2
        File.open(file_stats, 'w') { |ios| ios.puts "  <CompletionTime>#{i}" }
      end

      File.open(file_samples, 'w') do |ios|
        ios.puts "Investigator Name, Martin Hansen #{i}"
        ios.puts "Experiment Name, Big Bang #{i}"
      end
    end
  end

  def teardown
    FileUtils.rm_rf @dir_src
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
    new_name = File.join(@dir_src, 'new')
    Dir.mkdir(new_name)
    assert_raise(MiSeq::DataDirError) { dd.rename(new_name) }
  end

  test 'DataDir#rename works OK' do
    old_name = File.join(@dir_src, '131223_')
    new_name = File.join(@dir_src, 'new')
    dd       = MiSeq::DataDir.new(old_name)
    Dir.mkdir(old_name)
    dd.rename(new_name)
    assert_true(File.directory? dd.dir)
  end

  test 'Data#sync works OK' do
    MiSeq::Data.sync(@dir_src_ok, @dir_dst)

    file1 = '2013-04-00_Martin_Hansen_0_Big_Bang_0.tar'
    file2 = '2013-04-01_Martin_Hansen_1_Big_Bang_1.tar'
    file3 = '2013-04-02_Martin_Hansen_2_Big_Bang_2.tar'

    assert_true(File.exist? File.join(@dir_dst, file1))
    assert_true(File.exist? File.join(@dir_dst, file2))
    assert_true(File.exist? File.join(@dir_dst, file3))
  end

  test 'Data#sync with existing dirs works OK' do
    MiSeq::Data.sync(@dir_src_ok, @dir_dst)
    MiSeq::Data.sync(@dir_src_ok, @dir_dst)

    file1 = '2013-04-00_Martin_Hansen_0_Big_Bang_0.tar'
    file2 = '2013-04-01_Martin_Hansen_1_Big_Bang_1.tar'
    file3 = '2013-04-02_Martin_Hansen_2_Big_Bang_2.tar'

    assert_true(File.exist? File.join(@dir_dst, file1))
    assert_true(File.exist? File.join(@dir_dst, file2))
    assert_true(File.exist? File.join(@dir_dst, file3))
  end

  test 'Data#sync with unfinished data dir works OK' do
    MiSeq::Data.sync(@dir_src_unfinished, @dir_dst)

    file1 = '2013-04-00_Martin_Hansen_0_Big_Bang_0.tar'
    file2 = '2013-04-01_Martin_Hansen_1_Big_Bang_1.tar'
    file3 = '2013-04-02_Martin_Hansen_2_Big_Bang_2.tar'

    assert_true(File.exist? File.join(@dir_dst, file1))
    assert_true(File.exist? File.join(@dir_dst, file2))
    assert_false(File.exist? File.join(@dir_dst, file3))
  end
end
