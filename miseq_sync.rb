#!/usr/bin/env ruby

# Script that locates all subdirectories starting with a number in the src
# specified below. Each of these subdirs are renamed based on information
# located in the SampleSheet.csv file within. Next each directory is packed with
# tar and synchcronized to a remote location.

require 'pp'
require 'english'
require 'fileutils'

SRC = '/Users/maasha/scratch/miseq_data/'
DST = '/Users/maasha/scratch/miseq_data_remote/'

# Namespace for MiSeq classes.
module MiSeq
  # Class for parsing the GenerateFASTQRunStatistics.xml file to determine if a
  # MiSeq run has completed.
  class RunStatistics
    # Constructor for RunStatistics.
    #
    # @oaram file [String] Path to file.
    #
    # @return [RunStatistics] Class instance.
    def initialize(file)
      @file = file
    end

    # Locates the CompletionTime tag in GenerateFASTQRunStatistics.xml and
    # returns true if found else false.
    def complete?
      parse_run_statistics.select { |line| line =~ /CompletionTime/ }.any?
    end

    private

    # Parse RunStatistics file and return a list of lines.
    #
    # @return [Array] List of Samplesheet lines.
    def parse_run_statistics
      File.read(@file).split($INPUT_RECORD_SEPARATOR)
    end
  end

  # Class for parsing information from MiSeq Samplesheets.
  class SampleSheet
    # Constructor for SampleSheet.
    #
    # @oaram file [String] Path to Samplesheet file.
    #
    # @return [SampleSheet] Class instance.
    def initialize(file)
      @file = file
    end

    # Extract the Investigator Name from the SampleSheet lines.
    # Any whitespace in the Investigator Name is replaced by underscores.
    #
    # @raise [RuntimeError] On failing Experiment Name line.
    # @raise [RuntimeError] On failing Experiment Name field.
    #
    # @return [String] Investigator name.
    def investigator_name
      lines = parse_samplesheet

      matching_lines = lines.select { |line| line =~ /^Investigator Name/ }

      fail 'No Investigator Name in file' if matching_lines.empty?

      fields = matching_lines.first.split(',')

      fail 'No Investigator Name in file' if fields.empty?

      fields[1].gsub(' ', '_')
    end

    # Extract the Experiment Name from the SampleSheet lines.
    # Any whitespace in the Experiment Name is replaced by underscores.
    #
    # @raise [RuntimeError] On failing Experiment Name line.
    # @raise [RuntimeError] On failing Experiment Name field.
    #
    # @return [String] Experiment name.
    def experiment_name
      lines = parse_samplesheet

      matching_lines = lines.select { |line| line =~ /^Experiment Name/ }

      fail 'No Experiment Name in file' if matching_lines.empty?

      fields = matching_lines.first.split(',')

      fail 'No Experiment Name in file' if fields.empty?

      fields[1].gsub(' ', '_')
    end

    private

    # Parse Samplesheet file and return a list of lines.
    #
    # @return [Array] List of Samplesheet lines.
    def parse_samplesheet
      File.read(@file).split($INPUT_RECORD_SEPARATOR)
    end
  end

  # Class for manipulating a MiSeq data directory.
  class DataDir
    # Constructor for DataDir class.
    #
    # @param dir [String] Path to MiSeq data dir.
    #
    # @return [DataDir] Class instance.
    def initialize(dir)
      @dir = dir
    end

    # Extract data from a given dir path and return this in ISO 8601 format
    # (YYYY-MM-DD).
    #
    # @raise [RuntimeError] On failed extraction.
    #
    # @return [String] ISO 8601 date.
    def date
      fields = File.basename(@dir).split('_')

      fail 'Date field not found' if fields.empty?

      year  = fields.first[0..1].to_i + 2000
      month = fields.first[2..3]
      day   = fields.first[4..5]

      "#{year}-#{month}-#{day}"
    end

    # Rename DataDir.
    #
    # @param new_name [String] New directory name.
    #
    # @raise [RuntimeError] If directory already exist.
    def rename(new_name)
      fail "Dir already exits: #{new_name}" if File.directory? new_name

      File.rename(@dir, new_name)

      @dir = new_name
    end
  end

  # Class for synchronizing MiSeq data.
  class Data
    # Synchcronize MiSeq data between a specified src dir and dst URL.
    # Prior to synchronization, the subdirectories are given sane names and are
    # packed with tar.
    #
    # @param src [String] Source directory.
    # @param dst [String] Destination URL.
    def self.sync(src, dst)
      data = new(src, dst)
      data.rename
      data.tar
      # data.remove
      data.sync
    end

    # Constructor for Data class.
    #
    # @param src [String] Source directory.
    # @param dst [String] Destination URL.
    #
    # @return [Data] Class instance.
    def initialize(src, dst)
      @src       = src
      @dst       = dst
      @new_names = []
    end

    # Rename all MiSeq data dirs based on sane date format and information from
    # SampleSheets.
    #
    # @raise [RuntimeError] on missing SampleSheet.
    def rename
      dirs.each do |dir|
        file = File.join(dir, 'SampleSheet.csv')

        fail "No SampleSheet located in dir: #{dir}" unless File.exist? file

        dd = MiSeq::DataDir.new(dir)
        ss = MiSeq::SampleSheet.new(file)

        new_name = compile_new_name(dir, dd.date, ss.investigator_name,
                                    ss.experiment_name)

        dd.rename(new_name)

        @new_names << new_name
      end
    end

    # Back all reanamed dirs with tar.
    #
    # @raise [RuntimeError] if tar file exist.
    # @raise [RuntimeError] if tar fails.
    def tar
      @new_names.each do |dir|
        fail "Tar file exist: #{dir}.tar" if File.exist? "#{dir}.tar"

        cmd = "tar -cf #{dir}.tar #{dir}"

        system(cmd)

        fail "Command failed: #{cmd}" unless $CHILD_STATUS.success?
      end
    end

    # # Remove original subdirectories.
    # def remove
    #   @new_names.each do |dir|
    #     # FileUtils.rm_rf dir
    #   end
    # end

    def sync
      log = "#{@src}/rsync.log"
      src = "#{@src}/*.tar"
      cmd = "rsync -Haq #{src} #{@dst} --log-file #{log} --exclude=delete_me"

      system(cmd)

      fail "Command failed: #{cmd}" unless $CHILD_STATUS.success?
    end

    private

    # Find MiSeq data dirs in base dir.
    #
    # @return [Array] List of dirs.
    def dirs
      Dir["#{@src}/*"].select { |dir| File.basename(dir) =~ /^\d{6}_/ }
    end

    # Compile a new directory name.
    #
    # @param dir [String] Old directory name.
    # @param date [String] Date.
    # @param investigator_name [String] Investigator name.
    # @param experiment_name [String] Experiment name.
    #
    # @return [String] New directory name.
    def compile_new_name(dir, date, investigor_name, experiment_name)
      path = File.dirname dir

      new_name = [date, investigor_name, experiment_name].join('_')

      File.join(path, new_name)
    end
  end
end

MiSeq::Data.sync(SRC, DST)
