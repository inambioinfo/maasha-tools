#!/usr/bin/env ruby

require 'pp'

DEBUG = false
CPUS  = 2

module Enumerable
  # Fork each (feach) creates a fork pool with a specified number of processes
  # (_procs_) to iterate over the Enumerable object processing the specified
  # block. Calling feach with 0 _procs_ disables forking for debugging purposes.
  #
  # @example - process 10 elements using 4 processes:
  #
  # (0 ... 10).feach(4) { |i| puts i; sleep 1 }
  def feach(procs, &block)
    $stderr.puts "Parent pid: #{Process.pid}" if DEBUG

    if procs > 0
      workers = spawn_workers(procs, &block)
      threads = []

      self.each_with_index do |elem, index|
        $stderr.puts "elem: #{elem}    index: #{index}" if DEBUG

        threads << Thread.new do 
          worker = workers[index % procs]
          worker.process(elem)
        end
      end

      threads.each { |thread| thread.join }
      workers.each { |worker| worker.terminate }
    else
      self.each do |elem|
        block.call(elem)
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

      $stderr.puts "Spawning worker with pid: #{pid}" if DEBUG

      workers << Worker.new(parent_read, parent_write, pid)
    end

    workers
  end

  def call(child_read, child_write, &block)
    while not child_read.eof?
      elem = Marshal.load(child_read)
      $stderr.puts "      call with Process.pid: #{Process.pid}" if DEBUG
      result = block.call(elem)
      Marshal.dump(result, child_write)
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
      Marshal.dump(elem, @parent_write)
      $stderr.puts "   process with worker pid: #{@pid} and parent pid: #{Process.pid}" if DEBUG
      Marshal.load(@parent_read)
    end

    def terminate
      $stderr.puts "Terminating worker with pid: #{@pid}" if DEBUG
      @parent_read.close
      @parent_write.close
      Process.wait(@pid, Process::WNOHANG)
    end
  end
end

def fib(n) n < 2 ? n : fib(n-1)+fib(n-2); end # Lousy Fibonacci calculator <- heavy job

(0 ... 20).feach(CPUS) { |i| puts "#{i}: #{fib(Random.rand(20..35))}" }
