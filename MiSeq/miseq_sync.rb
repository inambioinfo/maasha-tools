#!/usr/bin/env ruby

# Script that locates all subdirectories starting with a number in the src
# specified below. Each of these subdirs are renamed based on information
# located in the SampleSheet.csv file within. Next each directory is packed with
# tar and synchcronized to a remote location.

SRC = '/Users/maasha/scratch/miseq_data/'
DST = '/Users/maasha/scratch/miseq_data_remote/'

MiSeq::Data.sync(SRC, DST)
