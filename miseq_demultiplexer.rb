#!/usr/bin/env ruby

require 'biopieces'
require 'optparse'
require 'csv'
require 'google_hash'

DEFAULT_SCORE_MIN  = 15
DEFAULT_SCORE_MEAN = 16
DEFAULT_MISMATCHES = 1

def hash_index(index)
  index.tr("ATCG", "0123").to_i
end

def permutate(list, options = {})
  permutations = options[:permutations] || 2
  alphabet     = options[:alphabet]     || "ATCG"

  permutations.times do
    hash = list.inject({}) { |memo, obj| memo[obj.to_sym] = true; memo }

    list.each do |word|
      (0 ... word.size).each do |pos|
        alphabet.each_char do |char|
          new_word = word[0 ... pos] + char + word[ pos + 1 .. -1]

          hash[new_word.to_sym] = true
        end
      end
    end

    list = hash.keys.map { |k| k.to_s }
  end

  list
end

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

  opts.on("-m", "--samples_file <file>", String, "Path to mapping file") do |o|
    options[:samples_file] = o
  end

  opts.on("--mismatches_max <uint>", Integer, "Maximum mismatches_max allowed (default=1)") do |o|
    options[:mismatches_max] = o
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

options[:mismatches_max] ||= DEFAULT_MISMATCHES
options[:scores_min]     ||= DEFAULT_SCORE_MIN
options[:scores_mean]    ||= DEFAULT_SCORE_MEAN

raise OptionParser::MissingArgument, "No samples_file specified."                                      unless options[:samples_file]
raise OptionParser::InvalidArgument, "No such file: #{options[:samples_file]}"                         unless File.file? options[:samples_file]
raise OptionParser::InvalidArgument, "mismatches_max must be >= 0 - not #{options[:mismatches_max]}"   unless options[:mismatches_max] >= 0
raise OptionParser::InvalidArgument, "mismatches_max must be <= 3 - not #{options[:mismatches_max]}"   unless options[:mismatches_max] <= 3
raise OptionParser::InvalidArgument, "scores_min must be >= 0 - not #{options[:scores_min]}"           unless options[:scores_min]     >= 0
raise OptionParser::InvalidArgument, "scores_min must be <= 40 - not #{options[:scores_min]}"          unless options[:scores_min]     <= 40
raise OptionParser::InvalidArgument, "scores_mean must be >= 0 - not #{options[:scores_mean]}"         unless options[:scores_mean]    >= 0
raise OptionParser::InvalidArgument, "scores_mean must be <= 40 - not #{options[:scores_mean]}"        unless options[:scores_mean]    <= 40

fastq_files = ARGV.dup

raise ArgumentError, "Expected 4 input files - not #{fastq_files.size}" if fastq_files.size != 4

index1_file = fastq_files.grep(/_I1_/).first
index2_file = fastq_files.grep(/_I2_/).first
read1_file  = fastq_files.grep(/_R1_/).first
read2_file  = fastq_files.grep(/_R2_/).first

if read1_file =~ /.+(_S\d_L\d{3}_R1_\d{3}\.fastq(?:\.gz)?)$/
  suffix1 = $1
else
  raise RuntimeError, "Unable to parse file suffix"
end

if read2_file =~ /.+(_S\d_L\d{3}_R2_\d{3}\.fastq(?:\.gz)?)$/
  suffix2 = $1
else
  raise RuntimeError, "Unable to parse file suffix"
end

samples = CSV.read(options[:samples_file], col_sep: "\t")

if options[:mismatches_max] <= 1
  index_hash = GoogleHashSparseLongToInt.new
else
  index_hash = GoogleHashDenseLongToInt.new
end

file_hash  = {}

samples.each_with_index do |sample, i|
  index_list1 = [sample[1]]
  index_list2 = [sample[2]]

  index_list1 = permutate(index_list1, permutations: options[:mismatches_max])
  index_list2 = permutate(index_list2, permutations: options[:mismatches_max])

  raise "Permutated list sizes differ: #{index_list1.size} != #{index_list2.size}" if index_list1.size != index_list2.size

  index_list1.product(index_list2).each do |index1, index2|
    index_hash[hash_index("#{index1}#{index2}")] = i
  end

  file_forward = "#{sample[0]}#{suffix1}"
  file_reverse = "#{sample[0]}#{suffix2}"
  io_forward   = BioPieces::Fastq.open(file_forward, 'w')#, compress: :gzip)
  io_reverse   = BioPieces::Fastq.open(file_reverse, 'w')#, compress: :gzip)
  file_hash[i] = [io_forward, io_reverse]
end

undetermined = samples.size + 1

file_forward = "Undertermined#{suffix1}"
file_reverse = "Undertermined#{suffix2}"
io_forward   = BioPieces::Fastq.open(file_forward, 'w')#, compress: :gzip)
io_reverse   = BioPieces::Fastq.open(file_reverse, 'w')#, compress: :gzip)
file_hash[undetermined] = [io_forward, io_reverse]
 
stats = {
  count:           0,
  match:           0,
  undetermined:    0,
  index1_bad_mean: 0,
  index2_bad_mean: 0,
  index1_bad_min:  0,
  index2_bad_min:  0
}

time_start = Time.now

begin
  i1_io = BioPieces::Fastq.open(index1_file)
  i2_io = BioPieces::Fastq.open(index2_file)
  r1_io = BioPieces::Fastq.open(read1_file)
  r2_io = BioPieces::Fastq.open(read2_file)

  print "\e[H\e[2J" if options[:verbose] # Console code to clear screen

  while i1 = i1_io.get_entry and i2 = i2_io.get_entry and r1 = r1_io.get_entry and r2 = r2_io.get_entry
    if i1.scores_mean < options[:scores_mean]
      stats[:index1_bad_mean] += 2
      stats[:undetermined] += 2
      io_forward, io_reverse = file_hash[undetermined]
    elsif i2.scores_mean < options[:scores_mean]
      stats[:index2_bad_mean] += 2
      stats[:undetermined] += 2
      io_forward, io_reverse = file_hash[undetermined]
    elsif i1.scores_min < options[:scores_min]
      stats[:index1_bad_min] += 2
      stats[:undetermined] += 2
      io_forward, io_reverse = file_hash[undetermined]
    elsif i2.scores_min < options[:scores_min]
      stats[:index2_bad_min] += 2
      stats[:undetermined] += 2
      io_forward, io_reverse = file_hash[undetermined]
    elsif sample_id = index_hash[hash_index("#{i1.seq}#{i2.seq}")]
      stats[:match] += 2
      io_forward, io_reverse = file_hash[sample_id]
    else
      stats[:undetermined] += 2
      io_forward, io_reverse = file_hash[undetermined]
    end

    io_forward.puts r1.to_fastq
    io_reverse.puts r2.to_fastq

    stats[:count] += 2

    if options[:verbose] and (stats[:count] % 1_000) == 0
      print "\e[1;1H"    # Console code to move cursor to 1,1 coordinate.
      stats[:time] = (Time.mktime(0) + (Time.now - time_start)).strftime("%H:%M:%S")
      pp stats
    end

    break if stats[:count] == 1_000_000
  end
ensure
  i1_io.close
  i2_io.close
  r1_io.close
  r2_io.close
end

pp stats if options[:verbose]

at_exit { file_hash.each_value { |value| value[0].close; value[1].close } }
