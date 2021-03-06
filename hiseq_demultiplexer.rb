#!/usr/bin/env ruby

require 'biopieces'
require 'optparse'
require 'csv'
require 'google_hash'

USAGE = <<USAGE
  This program demultiplexes Illumina Paired data given a samples file and four
  FASTQ files containing forward and reverse index data and forward and reverse
  read data.
  
  The samples file consists of three tab-separated columns: sample_id, forward
  index, reverse inded).

  Demultiplexing will generate file pairs according to the sample information
  in the samples file and input file suffix, one pair per sample, and these
  will be output to the output directory. Also a file pair with undetermined 
  reads are created where the index sequence is appended to the sequence name.
  
  It is possible to allow up to three mismatches per index. Also, read pairs are
  filtered if either of the indexes have a mean quality score below a given
  threshold or any single position in the index have a quality score below a 
  given theshold.

  Finally, a log file `Demultiplex.log` is output containing the stats of the
  demultiplexing process along with a list of the samples ids and unique index1
  and index2 sequences.

  Usage: #{File.basename(__FILE__)} [options] <FASTQ files>

  Example: #{File.basename(__FILE__)} -m samples.tsv Data*.fastq.gz

  Options:
USAGE

class Demultiplexer
  def self.run(fastq_files, options)
    d = self.new(fastq_files, options)
    d.demultiplex
  end

  def initialize(fastq_files = [], options = {})
    @fastq_files  = fastq_files
    @options      = options
    @index1_file  = nil
    @index2_file  = nil
    @read1_file   = nil
    @read2_file   = nil
    @suffix1      = nil
    @suffix2      = nil
    @samples      = nil
    @undetermined = nil
    @stats        = nil
    @file_hash    = nil
    @index_hash   = nil
  end

  def suffix_extract(file)
    if file =~ /.+(_L\d{3}_R[1234]_\d{3}).+$/
      suffix = $1
    else
      raise RuntimeError, "Unable to parse file suffix from: #{file}"
    end

    case @options[:compress]
    when /gzip/
      suffix << ".fastq.gz"
    when /bzip2/
      suffix << ".fastq.bz2"
    else
      suffix << ".fastq"
    end

    suffix
  end

  def samples_parse
    @samples = []

    CSV.read(@options[:samples_file], col_sep: "\t").each do |id, index1, index2|
      if @options[:revcomp_index1]
        index1 = BioPieces::Seq.new(seq: index1, type: :dna).reverse.complement.seq
      end

      if @options[:revcomp_index2]
        index2 = BioPieces::Seq.new(seq: index2, type: :dna).reverse.complement.seq
      end

      @samples << Sample.new(id, index1, index2)
    end

    errors       = []
    lookup_index = {}
    lookup_id    = {}

    @samples.each do |sample|
      if id2 = lookup_index["#{sample.index1}#{sample.index2}"]
        errors << ["Samples with same index combination", sample.id, id2].join("\t")
      else
        lookup_index["#{sample.index1}#{sample.index2}"] = sample.id
      end

      if lookup_id[sample.id]
        errors << ["Non-unique sample id", sample.id].join("\t")
      end

      lookup_id[sample.id] = true
    end

    unless errors.empty?
      pp errors
      raise "errors found in sample file."
    end

    @samples
  end

  def files_open
    file_hash  = {}

    @samples.each_with_index do |sample, i|
      file_forward = "#{sample.id}#{@suffix1}"
      file_reverse = "#{sample.id}#{@suffix2}"
      io_forward   = BioPieces::Fastq.open(File.join(@options[:output_dir], file_forward), 'w', compress: @options[:compress])
      io_reverse   = BioPieces::Fastq.open(File.join(@options[:output_dir], file_reverse), 'w', compress: @options[:compress])
      file_hash[i] = [io_forward, io_reverse]
    end

    @undetermined = @samples.size + 1

    file_forward             = "Undetermined#{@suffix1}"
    file_reverse             = "Undetermined#{@suffix2}"
    io_forward               = BioPieces::Fastq.open(File.join(@options[:output_dir], file_forward), 'w', compress: @options[:compress])
    io_reverse               = BioPieces::Fastq.open(File.join(@options[:output_dir], file_reverse), 'w', compress: @options[:compress])
    file_hash[@undetermined] = [io_forward, io_reverse]

    at_exit { file_hash.each_value { |value| value[0].close; value[1].close } }

    file_hash
  end

  def index_create
    index_hash = (@options[:mismatches_max] <= 1) ? GoogleHashSparseLongToInt.new : GoogleHashDenseLongToInt.new

    @samples.each_with_index do |sample, i|
      index_list1 = [sample.index1]
      index_list2 = [sample.index2]

      index_list1 = permutate(index_list1, permutations: @options[:mismatches_max])
      index_list2 = permutate(index_list2, permutations: @options[:mismatches_max])

      raise "Permutated list sizes differ: #{index_list1.size} != #{index_list2.size}" if index_list1.size != index_list2.size

      index_list1.product(index_list2).each do |index1, index2|
        key = hash_index("#{index1}#{index2}")

        if j = index_hash[key]
          raise "Index combo of #{index1} and #{index2} already exists for sample id: #{@samples[j].id} and #{sample.id}"
        else
          index_hash[key] = i
        end
      end
    end

    index_hash
  end

  def permutate(list, options = {})
    permutations = options[:permutations] || 2
    alphabet     = options[:alphabet]     || "ATCG"

    permutations.times do
      hash = list.inject({}) { |memo, obj| memo[obj.to_sym] = true; memo }

      list.each do |word|
        (0 ... word.size).each do |pos|
          alphabet.each_char do |char|
            new_word = "#{word[0 ... pos]}#{char}#{word[pos + 1 .. -1]}"

            hash[new_word.to_sym] = true
          end
        end
      end

      list = hash.keys.map { |k| k.to_s }
    end

    list
  end

  def hash_index(index)
    index.tr("ATCG", "0123").to_i
  end

  def demultiplex
    @read1_file  = @fastq_files.grep(/_R1_/).first
    @read2_file  = @fastq_files.grep(/_R4_/).first
    @index1_file = @fastq_files.grep(/_R2_/).first
    @index2_file = @fastq_files.grep(/_R3_/).first
    @suffix1     = suffix_extract(@read1_file)
    @suffix2     = suffix_extract(@read2_file)
    @samples     = samples_parse
    @file_hash   = files_open
    @index_hash  = index_create

    @stats = {
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
      i1_io = BioPieces::Fastq.open(@index1_file)
      i2_io = BioPieces::Fastq.open(@index2_file)
      r1_io = BioPieces::Fastq.open(@read1_file)
      r2_io = BioPieces::Fastq.open(@read2_file)

      print "\e[H\e[2J" if @options[:verbose] # Console code to clear screen

      while i1 = i1_io.get_entry and i2 = i2_io.get_entry and r1 = r1_io.get_entry and r2 = r2_io.get_entry
        found = false

        if sample_id = @index_hash[hash_index("#{i1.seq}#{i2.seq}")]
          @stats[:match] += 2
          found = true
          io_forward, io_reverse = @file_hash[sample_id]
        elsif i1.scores_mean < @options[:scores_mean]
          @stats[:index1_bad_mean] += 2
        elsif i2.scores_mean < @options[:scores_mean]
          @stats[:index2_bad_mean] += 2
        elsif i1.scores_min < @options[:scores_min]
          @stats[:index1_bad_min] += 2
        elsif i2.scores_min < @options[:scores_min]
          @stats[:index2_bad_min] += 2
        end

        unless found
          r1.seq_name = "#{r1.seq_name} #{i1.seq}" 
          r2.seq_name = "#{r2.seq_name} #{i2.seq}" 
          io_forward, io_reverse = @file_hash[@undetermined]
          @stats[:undetermined] += 2
        end

        io_forward.puts r1.to_fastq
        io_reverse.puts r2.to_fastq

        @stats[:count] += 2

        if @options[:verbose] and (@stats[:count] % 1_000) == 0
          print "\e[1;1H"    # Console code to move cursor to 1,1 coordinate.
          @stats[:undetermined_percent] = (100 * @stats[:undetermined] / @stats[:count].to_f).round(1)
          @stats[:time]  = (Time.mktime(0) + (Time.now - time_start)).strftime("%H:%M:%S")
          pp @stats
        end

        # break if @stats[:count] == 100_000
      end
    ensure
      i1_io.close
      i2_io.close
      r1_io.close
      r2_io.close
    end

    pp @stats if @options[:verbose]

    save_log
  end

  def save_log
    @stats[:sample_id] = @samples.map { |sample| sample.id }
    @stats[:index1]    = @samples.inject({}) { |memo, obj| memo[obj.index1] = true; memo}.keys.sort
    @stats[:index2]    = @samples.inject({}) { |memo, obj| memo[obj.index2] = true; memo}.keys.sort

    File.open(File.join(@options[:output_dir], "Demultiplex.log"), 'w') do |ios|
      PP.pp(@stats, ios)
    end
  end

  Sample = Struct.new :id, :index1, :index2 do
  end
end

DEFAULT_SCORE_MIN  = 16
DEFAULT_SCORE_MEAN = 16
DEFAULT_MISMATCHES = 1

ARGV << "-h" if ARGV.empty?

options = {}

OptionParser.new do |opts|
  opts.banner = USAGE

  opts.on("-h", "--help", "Display this screen" ) do
    $stderr.puts opts
    exit
  end

  opts.on("-s", "--samples_file <file>", String, "Path to samples file") do |o|
    options[:samples_file] = o
  end

  opts.on("-m", "--mismatches_max <uint>", Integer, "Maximum mismatches_max allowed (default=#{DEFAULT_MISMATCHES})") do |o|
    options[:mismatches_max] = o
  end

  opts.on("--revcomp_index1", "Reverse complement index1") do |o|
    options[:revcomp_index1] = o
  end

  opts.on("--revcomp_index2", "Reverse complement index2") do |o|
    options[:revcomp_index2] = o
  end

  opts.on("--scores_min <uint>", Integer, "Drop reads if a single position in the index have a quality score below scores_min (default=#{DEFAULT_SCORE_MIN})") do |o|
    options[:scores_min] = o
  end

  opts.on("--scores_mean <uint>", Integer, "Drop reads if the mean index quality score is below scores_mean (default=#{DEFAULT_SCORE_MEAN})") do |o|
    options[:scores_mean] = o
  end

  opts.on("-o", "--output_dir <dir>", String, "Output directory") do |o|
    options[:output_dir] = o
  end

  opts.on("-c", "--compress <gzip|bzip2>", String, "Compress output using gzip or bzip2 (default=<no compression>)") do |o|
    options[:compress] = o.to_sym
  end

  opts.on("-v", "--verbose", "Verbose output") do |o|
    options[:verbose] = o
  end
end.parse!

options[:mismatches_max] ||= DEFAULT_MISMATCHES
options[:scores_min]     ||= DEFAULT_SCORE_MIN
options[:scores_mean]    ||= DEFAULT_SCORE_MEAN
options[:output_dir]     ||= Dir.pwd

Dir.mkdir options[:output_dir] unless File.directory? options[:output_dir]

raise OptionParser::MissingArgument, "No samples_file specified."                                    unless options[:samples_file]
raise OptionParser::InvalidArgument, "No such file: #{options[:samples_file]}"                       unless File.file? options[:samples_file]
raise OptionParser::InvalidArgument, "mismatches_max must be >= 0 - not #{options[:mismatches_max]}" unless options[:mismatches_max] >= 0
raise OptionParser::InvalidArgument, "mismatches_max must be <= 3 - not #{options[:mismatches_max]}" unless options[:mismatches_max] <= 3
raise OptionParser::InvalidArgument, "scores_min must be >= 0 - not #{options[:scores_min]}"         unless options[:scores_min]     >= 0
raise OptionParser::InvalidArgument, "scores_min must be <= 40 - not #{options[:scores_min]}"        unless options[:scores_min]     <= 40
raise OptionParser::InvalidArgument, "scores_mean must be >= 0 - not #{options[:scores_mean]}"       unless options[:scores_mean]    >= 0
raise OptionParser::InvalidArgument, "scores_mean must be <= 40 - not #{options[:scores_mean]}"      unless options[:scores_mean]    <= 40

if options[:compress]
  unless options[:compress] =~ /^gzip|bzip2$/
    raise OptionParser::InvalidArgument, "Bad argument to --compress: #{options[:compress]}"
  end
end

fastq_files = ARGV.dup

raise ArgumentError, "Expected 4 input files - not #{fastq_files.size}" if fastq_files.size != 4

Demultiplexer.run(fastq_files, options)
