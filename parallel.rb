#!/usr/bin/env ruby

module Enumerable
  FEACH_DEBUG = false

  # Iterates over an enumerable in parallel given a number of processes and a
  # block to call. The parallel iteration is done by a pool of workers created
  # using fork. An enumerator with synchronized output is returned and can be
  # iterated over. Calling parallel with :processes => 0 disables forking for
  # debugging purposes.
  #
  # @example - process 10 elements using 4 processes:
  #
  # (0 ... 10).parallel(processes: 4) { |i| sleep 3; i }.each { |e| puts e }
  def parallel(options = {}, &block)
    $stderr.puts "Parent pid: #{Process.pid}" if FEACH_DEBUG

    procs = options[:processes] || 0

    Enumerator.new do |yielder|
      if procs > 0
        workers = spawn_workers(procs, &block)
        threads = []
        cache   = []

        self.each_with_index do |elem, index|
          threads << Thread.new do
            $stderr.puts "elem: #{elem}    index: #{index}" if FEACH_DEBUG
            i        = index % procs
            cache[i] = workers[i].process(elem)
          end

          if threads.size == procs
            threads.each { |thread| thread.join }
            cache.each { |result| yielder << result }
            threads = []
            cache   = []
          end
        end

        threads.each { |thread| thread.join }
        cache.each   { |result| yielder << result }
        workers.each { |worker| worker.terminate }
      else
        self.each do |elem|
          yielder << block.call(elem)
        end
      end
    end
  end

  def spawn_workers(procs, &block)
    workers = []

    procs.times do 
      child_read, parent_write = IO.pipe
      parent_read, child_write = IO.pipe

      pid = Process.fork do
        begin
          parent_write.close
          parent_read.close
          call(child_read, child_write, &block)
        ensure
          child_read.close
          child_write.close
        end
      end

      child_read.close
      child_write.close

      $stderr.puts "Spawning worker with pid: #{pid}" if FEACH_DEBUG

      workers << Worker.new(parent_read, parent_write, pid)
    end

    workers
  end

  def call(child_read, child_write, &block)
    while not child_read.eof?
      elem = IPC.load(child_read)
      $stderr.puts "      call with Process.pid: #{Process.pid}" if FEACH_DEBUG
      result = block.call(elem)
      IPC.dump(result, child_write)
    end
  end

  class IPC
    def self.load(io)
      size       = io.read(4)
      raise EOFError unless size
      size       = size.unpack("I").first
      marshalled = io.read(size)
      Marshal.load(marshalled)
    end

    def self.dump(obj, io)
      marshalled = Marshal.dump(obj)
      io.write([marshalled.size].pack("I"))
      io.write(marshalled)
    end
  end

  class Worker
    attr_reader :parent_read, :parent_write, :pid

    def initialize(parent_read, parent_write, pid)
      @parent_read  = parent_read
      @parent_write = parent_write
      @pid          = pid
    end

    def process(elem)
      IPC.dump(elem, @parent_write)
      $stderr.puts "   process with worker pid: #{@pid} and parent pid: #{Process.pid}" if FEACH_DEBUG
      IPC.load(@parent_read)
    end

    def terminate
      $stderr.puts "Terminating worker with pid: #{@pid}" if FEACH_DEBUG
      Process.wait(@pid, Process::WNOHANG)
      @parent_read.close
      @parent_write.close
    end
  end
end

#def fib(n) n < 2 ? n : fib(n-1)+fib(n-2); end # Lousy Fibonacci calculator <- heavy job
#(0 ... 10).parallel(processes: 4) { |i| "#{i}: #{fib(33)}" }.each { |e| puts e }

(0 ... 10).parallel(processes: 4) { |i| sleep 3; i }.each { |e| puts e }
