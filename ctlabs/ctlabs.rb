#!/usr/bin/env ruby

# -----------------------------------------------------------------------------
# File        : ctlabs/ctlab.rb
# Description : ctlabs main script
# License     : MIT License
# -----------------------------------------------------------------------------

$DEBUG = false

#
#
# Depends on
#   - iproute2
#   - iptables
#   - docker/podman
#

require 'yaml'
require 'erb'

require './lib/lab'
require './lib/node'
require './lib/link'
require './lib/graph'
require './lib/lablog'

#
# MAIN
#
require 'optparse'

options = {}
OptionParser.new do |opts|
  ARGV.empty? ? opts.default_argv = ['-h'] :
  opts.banner = "Usage: ${0} [options]"

  opts.on("-cCFG", "--conf=CFG", "Configuration File") do |c|
    options[:config] = c
  end
  opts.on("-u", "--up", "Start the Environment") do
    options[:up] = true
  end
  opts.on("-d", "--down", "Stop the Environment") do
    if( options[:up].nil? )
      options[:down] = true
    end
  end
  opts.on("-g", "--graph", "Create a graphviz dot export file") do
    options[:graph] = true
  end
  opts.on("-i", "--ini", "Create an inventory ini-file") do
    options[:ini] = true
  end
  opts.on("-p", "--print", "Print inspect output") do
    options[:print] = true
  end
  opts.on("-lLEVEL", "--debug=LEVEL", "Set the debug level") do |l|
    options[:dlevel] = l || 'warn'
  end
end.parse!



l1 = Lab.new( options[:config], nil, dlevel=options[:dlevel] )
puts l1

if( options[:up] )
  l1.visualize
  l1.inventory
  l1.up
end
if( options[:down] )
  l1.down
end
if( options[:graph] )
  l1.visualize
end
if( options[:ini] )
  l1.inventory
end
if( options[:print] )
  p l1
end
