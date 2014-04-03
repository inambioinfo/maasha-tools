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

  private

  # Creates a given number (_procs_) of Worker objects which are returned in an
  # array. The workers are created using fork, and each worker has a call
  # method to process the given _block_ as well as two pipes for communicate
  # between the worker and the parent process and visa versa.
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

  # Method that is called in worker processes (forked childs) and which reads
  # elements (_elem_) from one Inter Process Communcation (IPC) IO pipe and 
  # calls the given _block_ with the _elem_ as argument. The result is written
  # to another IPC pipe.
  def call(child_read, child_write, &block)
    while not child_read.eof?
      elem = IPC.load(child_read)
      $stderr.puts "      call with Process.pid: #{Process.pid}" if FEACH_DEBUG
      result = block.call(elem)
      IPC.dump(result, child_write)
    end
  end

  # Class for Inter Process Communication (IPC) between forked processes. IPC
  # is achieved by reading and writing Marshalled objects to IO.pipes.
  class IPC
    # Read, unmarshal and return an object from a given IO (_io_).
    def self.load(io)
      size       = io.read(4)
      raise EOFError unless size
      size       = size.unpack("I").first
      marshalled = io.read(size)
      Marshal.load(marshalled)
    end

    # Marshal a given object (_obj_) and write to a given IO (_io_).
    def self.dump(obj, io)
      marshalled = Marshal.dump(obj)
      io.write([marshalled.size].pack("I"))
      io.write(marshalled)

      nil  # Save GC
    end
  end

  # Worker object that can be used to access the underlying child process by
  # writing and reading to the Inter Communication Process IO pipes.
  class Worker
    attr_reader :parent_read, :parent_write, :pid

    # Instantiates a Worker object given two IPC pipes _parent_read_ and 
    # _parent_write as well as the process id (_pid_).
    def initialize(parent_read, parent_write, pid)
      @parent_read  = parent_read
      @parent_write = parent_write
      @pid          = pid
    end

    # Method to be called from the parent process to delegate work on the given
    # element (_elem_) to the child process of this Worker object and return the
    # result through IPC.
    def process(elem)
      IPC.dump(elem, @parent_write)
      $stderr.puts "   process with worker pid: #{@pid} and parent pid: #{Process.pid}" if FEACH_DEBUG
      IPC.load(@parent_read)
    end

    # Terminate Worker object by waiting for the child process to exit and
    # close IPC IO streams.
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
