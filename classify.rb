#!/usr/bin/env ruby

require 'pp'
require 'biopieces'
require 'narray'
require 'set'
require 'benchmark'
require 'tokyocabinet'

include TokyoCabinet

class TaxNode
  attr_accessor :oligos
  attr_reader :parent, :level, :name, :children, :id

  def initialize(parent, level, name, oligos, id)
    @parent = parent
    @level  = level
    @name   = name
    @oligos = oligos
    @id     = id

    @children = {}
  end

  def parent_id
    @parent.id if @parent
  end

  def children_ids
    ids = []

    @children.each_value { |child| ids << child.id }

    ids
  end

  def [](key)
    @children[key]
  end

  def []=(key, value)
    @children[key] = value
  end
end

Node = Struct.new(:id, :level, :name, :parent, :children, :count) do
  def to_marshal
    Marshal.dump(self)
  end
end

KMER   = 8
id     = 0
tree   = TaxNode.new(nil, 'R', nil, nil, id)
id     += 1
node   = tree
oligos = NArray.byte(4 ** KMER)

BioPieces::Fasta.open("/Users/maasha/scratch/SILVA/fixed.fasta") do |ios|
  ios.first(1000).each_with_index do |entry, i|
    kmers = entry.to_kmers(kmer_size: KMER)
    oligos.fill! 0
    oligos[NArray.to_na(kmers)] = 1
    
    seq_id, tax_string = entry.seq_name.split(' ')

    tax_levels = tax_string.split(';')

    tax_levels.each do |tax_level|
      level, name = tax_level.split('#')

      case level
      when 'K' then level = :kingdom
      when 'P' then level = :phylum
      when 'C' then level = :class
      when 'O' then level = :order
      when 'F' then level = :family
      when 'G' then level = :genus
      when 'S' then level = :species
      end

      if name
        if node[name]
          oligos |= node[name].oligos
          node[name].oligos = oligos
        else
          node[name] = TaxNode.new(node, level, name, oligos, id)
          id += 1
        end

        node = node[name]
      end
    end

    node = tree

    puts "Processed entries: #{i}" if (i % 1000) == 0
  end
end

hdb_node2oligos = HDB::new
hdb_oligo2nodes = HDB::new
hdb_taxonomy    = HDB::new

if !hdb_node2oligos.open("node2oligos.tch", HDB::OWRITER | HDB::OCREAT)
  ecode = hdb_node2oligos.ecode
  STDERR.printf("open error: %s\n", hdb_node2oligos.errmsg(ecode))
end

if !hdb_oligo2nodes.open("oligo2nodes.tch", HDB::OWRITER | HDB::OCREAT)
  ecode = hdb_oligo2nodes.ecode
  STDERR.printf("open error: %s\n", hdb_oligo2nodes.errmsg(ecode))
end

if !hdb_taxonomy.open("taxonomy.tch", HDB::OWRITER | HDB::OCREAT)
  ecode = hdb_taxonomy.ecode
  STDERR.printf("open error: %s\n", hdb_taxonomy.errmsg(ecode))
end

kmer_hash = Hash.new { |h1, k1| h1[k1] = Hash.new { |h2, k2| h2[k2] = Set.new } }

def hash_oligos(node, kmer_hash, hdb_node2oligos, hdb_taxonomy)
  kmers = node.oligos.to_a.each_with_index.reject {|e,_| e.zero? }.map(&:last)
  hdb_node2oligos[node.id] = kmers.pack("I*")
  hdb_taxonomy[node.id]  = Node.new(node.id, node.level, node.name, node.parent_id, node.children_ids, kmers.size).to_marshal

  kmers.map { |kmer| kmer_hash[node.level][kmer].add(node.id) }

  node.children.each_value { |child| hash_oligos(child, kmer_hash, hdb_node2oligos, hdb_taxonomy) }
end

hash_oligos(tree, kmer_hash, hdb_node2oligos, hdb_taxonomy)

#pp kmer_hash
exit

kmer_hash[:species].each { |kmer, nodes| hdb_oligo2nodes[kmer] = nodes.to_a.sort.pack("I*") }

#puts Benchmark.measure { 1500.times { hdb_node2oligos[rand(149)].unpack("I*") } }
#puts Benchmark.measure { 20000.times { Marshal.load(hdb_taxonomy[rand(149)]) } }
#puts Benchmark.measure { 20000.times { hdb_oligo2nodes[64990].unpack("I*") } }

puts hdb_oligo2nodes[64990].unpack("I*")

#pp tree

if !hdb_node2oligos.close
  ecode = hdb_node2oligos.ecode
  STDERR.printf("close error: %s\n", hdb_node2oligos.errmsg(ecode))
end

if !hdb_oligo2nodes.close
  ecode = hdb_oligo2nodes.ecode
  STDERR.printf("close error: %s\n", hdb_oligo2nodes.errmsg(ecode))
end

if !hdb_taxonomy.close
  ecode = hdb_taxonomy.ecode
  STDERR.printf("close error: %s\n", hdb_taxonomy.errmsg(ecode))
end

#pp tree

# # Searching index
# 
# result = Hash.new(0)
# 
# BioPieces::Fasta.open("/Users/maasha/scratch/SILVA/fixed.fasta") do |ios|
#   ios.first(10).each_with_index do |entry, i|
#     kmers = entry.to_kmers(kmer_size: KMER)
# 
#     kmers.each do |kmer|
#       nodes = index[:species][kmer]
# 
#       nodes.map { result[node] += 1 }
#     end
#   end
# end


__END__

puts "Total count #{bac_count + arc_count}"
puts "Bac count #{bac_count}"
puts "Arc count #{arc_count}"

puts "Total uniq kmers #{((bac + arc) > 0).count_true}"
puts "Bac uniq kmers #{(bac > 0).count_true}"
puts "Arc uniq kmers #{(arc > 0).count_true}"

shared = (bac > 0) & (arc > 0)

puts "Shared uniq kmers #{(shared > 0).count_true}"
puts "Bac specific uniq kmers #{(((bac > 0) ^ shared) > 0).count_true}"
puts "Arc specific uniq kmers #{(((arc > 0) ^ shared) > 0).count_true}"


Full
Total count 483415
Bac count 464618
Arc count 18797
Total uniq kmers 65536
Bac uniq kmers 65536
Arc uniq kmers 65492
Shared uniq kmers 65492
Bac specific uniq kmers 44
Arc specific uniq kmers 0

Slice
Total count 483415
Bac count 464618
Arc count 18797
Total uniq kmers 65536
Bac uniq kmers 65536
Arc uniq kmers 59519
Shared uniq kmers 59519
Bac specific uniq kmers 6017
Arc specific uniq kmers 0


__END__


bac = NArray.int(4 ** KMER)
arc = NArray.int(4 ** KMER)

BioPieces::Fasta.open("/Users/maasha/scratch/SILVA/fixed.fasta") do |ios|
  ios.first(10_000).each_with_index do |entry, i|
    na = NArray.to_na(entry.to_kmers(kmer_size: KMER))

    if entry.seq_name =~ /K#Bacteria;/
      bac[na] += 1
    elsif entry.seq_name =~ /K#Archaea;/
      arc[na] += 1
    end

    puts "Processed entries: #{i}" if (i % 1000) == 0
  end
end


__END__

