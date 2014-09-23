#!/usr/bin/env ruby

require 'biopieces'
require 'optparse'

DEFAULT_SCORE_MIN  = 36
DEFAULT_SCORE_MEAN = 38
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

  opts.on("--score_min <uint>", Integer, "Drop reads if a single position in the index have a quality score below score_min (default=36)") do |o|
    options[:score_min] = o
  end

  opts.on("--score_mean <uint>", Integer, "Drop reads if the mean index quality score is below score_mean (default=38)") do |o|
    options[:score_mean] = o
  end

  opts.on("-v", "--verbose", "Verbose output") do |o|
    options[:verbose] = o
  end
end.parse!

options[:mismatches] ||= DEFAULT_MISMATCHES
options[:score_min]  ||= DEFAULT_SCORE_MIN
options[:score_mean] ||= DEFAULT_SCORE_MEAN

raise OptionParser::MissingArgument, "No mapping_file specified."                              unless options[:file_map]
raise OptionParser::InvalidArgument, "No such file: #{options[:file_map]}"                     unless File.file? options[:file_map]
raise OptionParser::InvalidArgument, "mismatches must be >= 0 - not #{options[:mismatches]}"   unless options[:mismatches] >= 0
raise OptionParser::InvalidArgument, "mismatches must be <= 3 - not #{options[:mismatches]}"   unless options[:mismatches] <= 3
raise OptionParser::InvalidArgument, "score_min must be >= 0 - not #{options[:score_min]}"     unless options[:score_min]  >= 0
raise OptionParser::InvalidArgument, "score_min must be <= 40 - not #{options[:score_min]}"    unless options[:score_min]  <= 40
raise OptionParser::InvalidArgument, "score_mean must be >= 0 - not #{options[:score_mean]}"   unless options[:score_mean] >= 0
raise OptionParser::InvalidArgument, "score_mean must be <= 40 - not #{options[:score_mean]}"  unless options[:score_mean] <= 40

fastq_files = ARGV.dup

raise ArgumentError, "Expected 4 input files - not #{fastq_files.size}" if fastq_files.size != 4

index1_file = fastq_files.grep /_I1_/

pp index1_file
