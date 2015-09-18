#!/usr/bin/env ruby

require 'pp'

# K#Bacteria(100);P#Bacteroidetes(100);C#Bacteroidia(100);O#Bacteroidales(100);F#Prevotellaceae(100);G#Prevotella(100)

# Usage: tax_nr.rb < tax.txt > tax_nr.txt

class Node
  attr_reader :level, :orig, :parent, :children

  def initialize(level, name, orig, parent)
    @level    = level
    @name     = name
    @orig     = orig
    @parent   = parent
    @children = {}
  end

  def empty?
    @children.empty?
  end

  def [](key)
    @children[key]
  end

  def []=(key, val)
    @children[key] = val
  end

  def to_s
    names = []

    node = self

    until node.nil?
      names << "#{node.level}##{node.orig}"
      node = node.parent
    end

    names[0..-2].reverse.join(';')
  end

  def each
    nodes = traverse([], self)

    nodes.each { |node| yield node if node.empty? }
  end

  def traverse(nodes, node)
    node.children.each_value { |child| traverse(nodes, child) }
    nodes << node
  end
end

tree = Node.new('R', 'root', 'root', nil)

STDIN.each_line do |line|
  node = tree

  line.chomp.split(';').each do |field|
    level, orig = field.split('#')

    name = orig.gsub(/\([^)]+\)/, '')

    unless node[name]
      node[name] = Node.new(level, name, orig, node)
    end

    node = node[name]
  end
end

tree.each do |node|
  puts node
end
