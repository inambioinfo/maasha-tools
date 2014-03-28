#!/usr/bin/env ruby

require 'pp'
require_relative 'feach'

CPUS       = 2
CHUNK_SIZE = 1024 * 20_000   # 20 Mb chunks

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
  def each
    enum = each_chunk(CHUNK_SIZE, '>')
    enum.feach(processes: 3) { |chunk| parse(chunk) { |entry| yield entry } }
  end

  def each_works
    while chunk = get_chunk(CHUNK_SIZE, '>')
      parse(chunk) { |entry| yield entry }
    end
  end

  private

  def parse(chunk)
    seq_name = nil
    seq      = ""
    lines    = chunk.split($/)

    lines.each do |line|
      line.chomp!

      if line[0] == '>'
        if seq_name and not seq.empty?
          yield Seq.new(seq_name, seq)
   
          seq_name = nil
          seq      = ""
        end
   
        seq_name = line[1 .. -1]
      else
        seq << line
      end
    end
   
    if seq_name and not seq.empty?
      yield Seq.new(seq_name, seq)
    end
  end
end

Fasta.open("/Users/maasha/test10.fna") do |ios|
  ios.each { |entry| puts entry.to_fasta }  # Do something with each entry
end
