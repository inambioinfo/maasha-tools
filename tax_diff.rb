#!/usr/bin/env ruby

require 'pp'

# K#Bacteria(100);P#Bacteroidetes(100);C#Bacteroidia(100);O#Bacteroidales(100);F#Prevotellaceae(100);G#Prevotella(100)

unless ARGV.size == 2
  puts "Usage: tax_diff.rb <file1> <file2>"
  exit
end

file1, file2 = *ARGV

File.open(file1) do |io1|
  File.open(file2) do |io2|
    until io1.eof? || io2.eof?
      line1 = io1.gets
      line2 = io2.gets

      next if line1[0] == '#' || line2[0] == '#'

      line1.chomp!
      line2.chomp!

      fields1 = line1.split("\t")
      fields2 = line2.split("\t")

      fail "ID's don't match: #{fields1[0]} != #{fields2[0]}" if fields1[0] != fields2[0]

      tax1 = fields1.last.split(";")
      tax2 = fields2.last.split(";")

      min = [tax1.size, tax2.size].min

      shared = []
      i = 0

      while i < min && tax1[i].gsub(/\(\d+\)/, '') == tax2[i].gsub(/\(\d+\)/, '')
        shared << tax1[i]
        i += 1
      end

      puts [fields1[0], shared.join(';'), tax1[i..-1].join(';'), tax2[i..-1].join(';')].join("\t")
    end
  end
end
