#!/usr/bin/env ruby

require 'biopieces'
require 'optparse'
require 'csv'

DEFAULT_SCORE_MIN  = 15
DEFAULT_SCORE_MEAN = 20
DEFAULT_MISMATCHES = 1

ARGV << "-h" if ARGV.empty?

options = {}

OptionParser.new do |opts|
  opts.banner = <<USAGE
  Demultiplex MiSeq run.
  
  Usage: #{File.basename(__FILE__)} [options] <FASTQ files>

USAGE

  opts.on("-h", "--help", "Display this screen" ) do
    $stderr.puts opts
    exit
  end

  opts.on("-m", "--mapping_file <file>", String, "Path to mapping file") do |o|
    options[:file_map] = o
  end

  opts.on("--mismatches <uint>", Integer, "Maximum mismatches allowed (default=1)") do |o|
    options[:mismatches] = o
  end

  opts.on("--scores_min <uint>", Integer, "Drop reads if a single position in the index have a quality score below scores_min (default=36)") do |o|
    options[:scores_min] = o
  end

  opts.on("--scores_mean <uint>", Integer, "Drop reads if the mean index quality score is below scores_mean (default=38)") do |o|
    options[:scores_mean] = o
  end

  opts.on("-v", "--verbose", "Verbose output") do |o|
    options[:verbose] = o
  end
end.parse!

options[:mismatches] ||= DEFAULT_MISMATCHES
options[:scores_min]  ||= DEFAULT_SCORE_MIN
options[:scores_mean] ||= DEFAULT_SCORE_MEAN

raise OptionParser::MissingArgument, "No mapping_file specified."                              unless options[:file_map]
raise OptionParser::InvalidArgument, "No such file: #{options[:file_map]}"                     unless File.file? options[:file_map]
raise OptionParser::InvalidArgument, "mismatches must be >= 0 - not #{options[:mismatches]}"   unless options[:mismatches] >= 0
raise OptionParser::InvalidArgument, "mismatches must be <= 3 - not #{options[:mismatches]}"   unless options[:mismatches] <= 3
raise OptionParser::InvalidArgument, "scores_min must be >= 0 - not #{options[:scores_min]}"     unless options[:scores_min]  >= 0
raise OptionParser::InvalidArgument, "scores_min must be <= 40 - not #{options[:scores_min]}"    unless options[:scores_min]  <= 40
raise OptionParser::InvalidArgument, "scores_mean must be >= 0 - not #{options[:scores_mean]}"   unless options[:scores_mean] >= 0
raise OptionParser::InvalidArgument, "scores_mean must be <= 40 - not #{options[:scores_mean]}"  unless options[:scores_mean] <= 40

fastq_files = ARGV.dup

raise ArgumentError, "Expected 4 input files - not #{fastq_files.size}" if fastq_files.size != 4

samples = CSV.read(options[:file_map], col_sep: "\t")

index_hash = {}
file_hash  = {}

samples.each do |sample|
  index_hash["#{sample[1]}#{sample[2]}".to_sym] = sample[0].to_sym
  file_forward = "#{sample[0]}_S0_L001_R1_001.fastq.gz"
  file_reverse = "#{sample[0]}_S0_L001_R2_001.fastq.gz"
  io_forward   = BioPieces::Fastq.open(file_forward, 'w', compress: :gzip)
  io_reverse   = BioPieces::Fastq.open(file_reverse, 'w', compress: :gzip)
  file_hash[sample[0].to_sym] = [io_forward, io_reverse]
end

file_forward = "Undertermined_R1.fastq.gz"
file_reverse = "Undertermined_R2.fastq.gz"
io_forward   = BioPieces::Fastq.open(file_forward, 'w', compress: :gzip)
io_reverse   = BioPieces::Fastq.open(file_reverse, 'w', compress: :gzip)
file_hash[:undetermined] = [io_forward, io_reverse]

index1_file = fastq_files.grep(/_I1_/).first
index2_file = fastq_files.grep(/_I2_/).first
read1_file  = fastq_files.grep(/_R1_/).first
read2_file  = fastq_files.grep(/_R2_/).first
 
stats = {
  count:           0,
  match_hash:      0,
  match_hamming:   0,
  undetermined:    0,
  index1_bad_mean: 0,
  index2_bad_mean: 0,
  index1_bad_min:  0,
  index2_bad_min:  0
}

def match_hamming(samples, mismatches, entry1, entry2)
  samples.each do |sample|
    if BioPieces::Hamming.distance(sample[1], entry1.seq) <= mismatches and
       BioPieces::Hamming.distance(sample[2], entry2.seq) <= mismatches
      return sample[0].to_sym
    end
  end

  nil
end

begin
  i1_io = BioPieces::Fastq.open(index1_file)
  i2_io = BioPieces::Fastq.open(index2_file)
  r1_io = BioPieces::Fastq.open(read1_file)
  r2_io = BioPieces::Fastq.open(read2_file)

  print "\e[H\e[2J" if options[:verbose] # Console code to clear screen

  while i1 = i1_io.get_entry and i2 = i2_io.get_entry and r1 = r1_io.get_entry and r2 = r2_io.get_entry
    if i1.scores_mean < options[:scores_mean]
      stats[:index1_bad_mean] += 1
      stats[:undetermined] += 1
      io_forward, io_reverse = file_hash[:undetermined]
    elsif i2.scores_mean < options[:scores_mean]
      stats[:index2_bad_mean] += 1
      stats[:undetermined] += 1
      io_forward, io_reverse = file_hash[:undetermined]
    elsif i1.scores_min < options[:scores_min]
      stats[:index1_bad_min] += 1
      stats[:undetermined] += 1
      io_forward, io_reverse = file_hash[:undetermined]
    elsif i2.scores_min < options[:scores_min]
      stats[:index2_bad_min] += 1
      stats[:undetermined] += 1
      io_forward, io_reverse = file_hash[:undetermined]
    elsif sample_id = index_hash["#{i1.seq}#{i2.seq}".to_sym]
      stats[:match_hash] += 1
      io_forward, io_reverse = file_hash[sample_id]
    elsif sample_id = match_hamming(samples, options[:mismatches], i1, i2)
      stats[:match_hamming] += 1
      io_forward, io_reverse = file_hash[sample_id]
    else
      stats[:undetermined] += 1
      io_forward, io_reverse = file_hash[:undetermined]
    end

    io_forward.puts r1.to_fastq
    io_reverse.puts r2.to_fastq

    stats[:count] += 1

    if options[:verbose] and (stats[:count] % 10_000) == 0
      print "\e[1;1H"    # Console code to move cursor to 1,1 coordinate.
      pp stats
    end
  end
ensure
  i1_io.close
  i2_io.close
  r1_io.close
  r2_io.close
end

pp stats if options[:verbose]

at_exit { file_hash.each_value { |value| value[0].close; value[1].close } }
