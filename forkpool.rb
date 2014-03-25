#!/usr/bin/env ruby
 
require 'pp'

DEBUG = 1
 
# Class to setup a fork pool with a specified _count_ of workers to process in
# parallel incomming jobs; potentially many more jobs than _count_. The results
# are returned in order they are given to the workers.
#
# ForkPool.new(count) |workers| do
#   heavy_tasks.each do |task|
#       result = workers.process task
#     end
#   end
# end
class ForkPool
  # Method to construct a new ForkPool object given a _count_ of workers to be
  # spawned.
  def initialize(count)
    $stderr.puts "Parent pid: #{Process.pid}"

    @parent  = true
    @workers = spawn_workers(count)
    @tickets = Array.new(count, false)

    yield self
  end
 
  # Method to process a _block_ in a parallel process and return the results.
  # @tickets contain information about idle workers; we find one and deletate
  # the processing to this worker.
  def process(&block)
    @tickets.each_with_index do |ticket, index|
      if ! ticket
        worker = @workers[index]
        @tickets[index] = true

        $stderr.puts "Worker #{index} with pid: #{worker.pid} put to work" if DEBUG

        worker.process(&block)
        @tickets[index] = false
 
        return Marshal.load(worker.ipc_read)
      end
    end
  end
 
  private
 
  # Method to spawn a given _count_ of workers that are returned on an array.
  # Each worker have an IO pipe for Inter Process Communication (IPC) of
  # results from the worker to the parent.
  def spawn_workers(count)
    workers = []
 
    (0 ... count).each do
      ipc_read, ipc_write = IO.pipe
 
      pid = Process.fork do
        @parent = false
      end

      $stderr.puts "Spawning worker with pid: #{pid} from parent process: #{Process.pid}" if DEBUG
 
      workers << Worker.new(ipc_read, ipc_write, pid) if @parent
    end
 
    workers
  end
 
  # Class with methods to construct and manipulate Worker objects.
  class Worker
    attr_reader :ipc_read, :ipc_write, :pid
 
    def initialize(ipc_read, ipc_write, pid)
      @ipc_read  = ipc_read
      @ipc_write = ipc_write
      @pid       = pid
    end
 
    # Method to process a given block and dump to the result IPC pipe.
    def process(&block)
      result = block.call

      $stderr.puts "Worker with pid: #{@pid} at work! Working process is #{Process.pid}" if DEBUG
 
      Marshal.dump(result, @ipc_write)
    end
  end
end
 
# Example processing 100 heavy jobs using 4 processes:
 
def fib(n) n < 2 ? n : fib(n-1)+fib(n-2); end # Lousy Fibonacci calculator <- heavy job
 
ForkPool.new(14) do |workers|
  (0 .. 100).each do |i|
    $stderr.puts "Sending job #{i} for processing" if DEBUG

    result = workers.process { "Job: #{i} - Calculating fib(35) = " + fib(35).to_s }
 
    pp result
  end
end
