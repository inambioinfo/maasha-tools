#!/usr/bin/env ruby

require 'biopieces'
require 'optparse'

ARGV << "-h" if ARGV.empty?

options = {}

OptionParser.new do |opts|
  opts.banner = "Usage: #{File.basename(__FILE__)} [options] <FASTQ file>"

  opts.on("-h", "--help", "Display this screen" ) do
    $stderr.puts opts
    exit
  end

  opts.on("-n", "--number <int>", Integer, "Number of read pairs to subsample") do |o|
    options[:number] = o
  end

  opts.on("-o", "--output <file>", String, "Name of output file") do |o|
    options[:output] = o
  end

  opts.on("-v", "--verbose", "Verbose output") do |o|
    options[:verbose] = o
  end
end.parse!

raise OptionParser::MissingArgument, "No number specified."                          unless options[:number]
raise OptionParser::InvalidArgument, "Number must be >= 2 - not #{options[:number]}" unless options[:number] >= 2
raise OptionParser::InvalidArgument, "Number must be even - not #{options[:number]}" unless options[:number].even?

file = ARGV.dup.first

$stderr.puts "Processing file: #{file}" if options[:verbose]
`wc -l #{file}` =~ /^\s+(\d+)/
lines   = $1.to_i
records = lines / 4

raise "Requested number of random records > number of records: #{options[:number]} > #{records}" if options[:number] > records

vector = (0 .. records).to_a.shuffle.select { |i| i.even? }.first(options[:number] / 2).sort
max    = vector.max
random = {}
vector.map {|i| random[i] = true }

i        = 0
selected = 0

BioPieces::Fastq.open(options[:output], 'w') do |output|
  BioPieces::Fastq.open(file) do |input|
    input.each_slice(2) do |entry1, entry2|
      if random[i]
        output.puts entry1.to_fastq
        output.puts entry2.to_fastq

        selected += 2
      end

      i += 2

      $stderr.puts "Processed: #{i}   selected: #{selected}" if (i % 10_000) == 0 and options[:verbose]

      break if i > max
    end
  end
end

$stderr.puts "Processed: #{i}   selected: #{selected}" if options[:verbose]

