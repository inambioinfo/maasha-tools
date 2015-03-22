#!/usr/bin/env ruby

require 'benchmark'
require 'pp'
require 'tempfile'
require 'parallel'
require_relative 'parallel'

class IO
  # Method that reads the next "chunk" of data from the I/O stream.
  # Chunks are terminated by _sep_. A seperator of nil return
  # chunks of _size_, otherwise a chunk is shaved from the right end
  # to the last occurence of _sep_ and the I/O stream is equally
  # rewinded. If _sep_ is given and no complete entry appears within
  # one chunk, the chunk is expanded. Thus a chunk will contain at
  # least one or more complete entries all beginning with _sep_.
  def get_chunk(size = 1024, sep = $/)
    chunk = ""

    while c = self.sysread(size)
      chunk << c

      if sep
        if pos = chunk.rindex(sep) and pos > 0
          offset = pos - chunk.size
          chunk  = chunk[0 ... pos]

          self.sysseek(offset, IO::SEEK_CUR)

          block_given? ? (yield chunk) : (return chunk)

          chunk = ""
        end
      else
        block_given? ? (yield chunk) : (return chunk)

        chunk = ""
      end
    end
  rescue EOFError
    block_given? ? (yield chunk) : (return chunk) unless chunk.empty?
  end

  def each_chunk(size = 1024, sep = $/)
    Enumerator.new do |yielder|
      while chunk = get_chunk(size, sep)
       if block_given?
         yield chunk
       else
         yielder << chunk
       end
      end
    end
  end
end

class Seq
  def initialize(seq_name, seq)
    @seq_name = seq_name
    @seq      = seq
  end

  def to_fasta
    '>' + @seq_name + $/ + @seq
  end
end

class Fasta < File
  # Using parallel gem
  # ~ 6.2 seconds
  # Parallel.each(cache, in_processes: CPUS) { parse(c) { |entry| yield entry } }  <- NOT SYNCHRONIZED
  # On order to synchronize output we have to use #map as below.
  def each_parallel
    cache = []

    while chunk = get_chunk(CHUNK_SIZE, '>')
      cache << chunk

      if cache.size == CPUS
        Parallel.map(cache, in_processes: CPUS) { |c| parse(c) }.each { |entries| entries.each { |entry| yield entry } }
        cache = []
      end
    end

    Parallel.map(cache, in_processes: CPUS) { |c| parse(c) }.each { |entries| entries.each { |entry| yield entry } }
  end

  # Using my own fork pool
  # ~ 19.8 seconds
  def each_forkpool
    enum = each_chunk(CHUNK_SIZE, '>').parallel(processes: CPUS) { |chunk| parse(chunk) }
    enum.each { |entries| entries.each { |entry| yield entry } }
  end

  # Simple serial method
  # ~ 7.8 seconds
  def each_serial
    while chunk = get_chunk(CHUNK_SIZE, '>')
      parse(chunk) { |entry| yield entry }
    end
  end

  private

  def parse(chunk)
    seq_name = nil
    seq      = ""
    lines    = chunk.split($/)
    entries  = []

    lines.each do |line|
      line.chomp!

      if line[0] == '>'
        if seq_name and not seq.empty?
          entry = Seq.new(seq_name, seq)

          block_given? ? (yield entry) : (entries << entry)
   
          seq_name = nil
          seq      = ""
        end
   
        seq_name = line[1 .. -1]
      else
        seq << line
      end
    end
   
    if seq_name and not seq.empty?
      entry = Seq.new(seq_name, seq)

      block_given? ? (yield entry) : (entries << entry)
    end

    entries
  end
end

# Create some mock data

temp_file = Tempfile.new('test.fna')

File.open(temp_file, 'w') do |ios|
  3_000_000.times do |i|
    ios << ">ILLUMINA-#{i}E_0004:2:1:1040:5263#TTAGGC/1\nTTCGGCATCGGCGGCGACGTTGGCGGCGGGGCCGGGCGGGTCGANNNCAT\n"
  end
end

# Mock data created

$stderr.puts "starting"

CPUS       = 20
CHUNK_SIZE = 1024 * 20_000   # 20 Mb chunks

each_parallel = Proc.new do
  Fasta.open(temp_file) do |ios|
    ios.each_parallel { |entry| entry.to_fasta }  # Do something with each entry
  end
end

each_forkpool = Proc.new do
  Fasta.open(temp_file) do |ios|
    ios.each_forkpool { |entry| entry.to_fasta }  # Do something with each entry
  end
end

each_serial = Proc.new do
  Fasta.open(temp_file) do |ios|
    ios.each_serial { |entry| entry.to_fasta }  # Do something with each entry
  end
end

Benchmark.bm() do |x|
  x.report("Parallel") { each_parallel.call }
  x.report("Forkpool") { each_forkpool.call }
  x.report("Serial")   { each_serial.call }
end

File.delete temp_file
