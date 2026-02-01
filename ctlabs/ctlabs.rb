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
require 'fileutils'
require 'socket'

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
  opts.banner = "Usage: #{File.basename($0)} [options]"

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
  opts.on("-t", "--print", "Print inspect output") do
    options[:print] = true
  end
  opts.on("-p", "--play [CMD]", "Run playbook") do |cmd|
    options[:play] = cmd.nil? ? true : cmd
  end
  opts.on("-l", "--list", "List all available labs") do
    options[:list] = true
  end
  opts.on("-LLEVEL", "--log-level=LEVEL", "Set the log level") do |level|
    options[:dlevel] = level || 'warn'
  end
  opts.on("-s", "--status", "Show status of currently running lab") do
    options[:status] = true
  end
end.parse!

LABS_DIR = File.expand_path('../labs', __dir__)
LOG_DIR  = '/var/log/ctlabs'

# Handle --status first
if options[:status]
  if Lab.running?
    running_lab = Lab.current_name
    puts "✅ Lab is running: #{running_lab}"
    
    # Optional: show full path
    labs_dir = File.expand_path('../labs', __dir__)
    full_path = File.join(labs_dir, running_lab)
    puts "   Config file: #{full_path}"
    
    # Optional: show last log file
    log_dir = "/var/log/ctlabs"
    if Dir.exist?(log_dir)
      logs = Dir.glob("#{log_dir}/ctlabs_*_#{running_lab.gsub(/\//, '_')}_*.log")
      if logs.any?
        latest_log = logs.sort.last
        puts "   Log file: #{latest_log}"
      end
    end
  else
    puts "❌ No lab is currently running."
  end
  exit 0
end

def generate_log_filename(lab_name, action)
  timestamp = Time.now.to_i
  safe_lab  = lab_name.gsub(/\//, '_').gsub(/[^a-zA-Z0-9_.\-]/, '')
  "#{LOG_DIR}/ctlabs_#{timestamp}_#{safe_lab}_#{action}.log"
end

if options[:up]
  if !options[:config]
    puts "❌ Error: -c/--conf is required with --up"
    exit 1
  end
  if Lab.running?
    puts "❌ Error: A lab is already running: #{Lab.current_name}. Stop it first."
    exit 1
  end

  config_path = options[:config]
  labs_dir = File.expand_path('../labs', __dir__)
  full_path = File.join(labs_dir, config_path)

  # Validate lab exists
  unless File.file?(full_path)
    puts "❌ Error: Config file not found: #{full_path}"
    exit 1
  end

  #log = LabLog.new(out: $stdout, level: options[:dlevel] || 'info')
  log = LabLog.for_lab(lab_name: config_path, action: 'up')
  puts "Starting lab: #{config_path}"
  puts "Log file: #{log.path}"

  l1 = Lab.new(cfg: full_path, relative_path: config_path, log: log)
  l1.visualize
  l1.inventory
  l1.up

  log.info "✓ Lab started successfully"

  if options[:play]
    l1.run_playbook(options[:play])
  end

  log.close
  puts "✓ Lab started. View logs at: #{log.path}"
end

if( options[:play] )
  l1.run_playbook(options[:play])
end

if options[:down]
  if !Lab.running?
    puts "❌ Error: No lab is running. Use --status to check."
    exit 1
  end

  running_lab = Lab.current_name
  labs_dir    = File.expand_path('../labs', __dir__)
  full_path   = File.join(labs_dir, running_lab)

  #log = LabLog.new(out: $stdout, level: options[:dlevel] || 'info')
  log = LabLog.for_lab(lab_name: running_lab, action: 'down')

  puts "Stopping running lab: #{running_lab}"
  puts "Log file: #{log.path}"

  l1 = Lab.new(cfg: full_path, relative_path: running_lab, log: log)
  l1.down

  log.info "✓ Lab stopped successfully"
  log.close
  
  puts "✓ Lab stopped. View logs at: #{log.path}"
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

if options[:list]
  labs = Dir.glob(File.join(LABS_DIR, "**", "*.yml"))
            .map { |f| f.sub(LABS_DIR + '/', '') }
            .sort
  if labs.empty?
    puts "No labs found in #{LABS_DIR}"
  else
    puts "Available labs:"
    labs.each { |lab| puts "  #{lab}" }
  end
  exit 0
end
