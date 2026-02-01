# lib/lablog.rb
require 'logger'
require 'fileutils'

class LabLog
  LOG_DIR = '/var/log/ctlabs'.freeze

  # Factory: real log file for lab operations
  def self.for_lab(lab_name:, action:)
    FileUtils.mkdir_p(LOG_DIR)
    
    timestamp = Time.now.to_i
    safe_lab  = lab_name.gsub(%r{[^a-zA-Z0-9_.\-/]}, '_').gsub('/', '_')
    path      = "#{LOG_DIR}/ctlabs_#{timestamp}_#{safe_lab}_#{action}.log"
    
    # Write header
    File.open(path, 'w') do |f|
      f.puts "=" * 80
      f.puts "CTLabs Lab #{action.capitalize} Log"
      f.puts "Lab: #{lab_name}"
      f.puts "Started: #{Time.now.strftime('%Y-%m-%d %H:%M:%S %Z')}"
      f.puts "=" * 80
      f.puts
    end
    
    new(path: path, lab_name: lab_name, action: action)
  end

  # Factory: silent logger for read-only operations (no file creation)
  def self.null
    new(path: '/dev/null', silent: true)
  end

  # Discovery methods (MVC-compliant)
  def self.latest_for_running_lab
    return nil unless Lab.running?
    lab_name = Lab.current_name
    return nil unless lab_name
    
    safe_lab = lab_name.gsub(%r{[^a-zA-Z0-9_.\-/]}, '_').gsub('/', '_')
    Dir.glob("#{LOG_DIR}/ctlabs_*_#{safe_lab}_*.log")
      .sort_by { |f| File.mtime(f) }
      .reverse
      .first
  end

  def self.all_for_lab(lab_name)
    safe_lab = lab_name.gsub(%r{[^a-zA-Z0-9_.\-/]}, '_').gsub('/', '_')
    Dir.glob("#{LOG_DIR}/ctlabs_*_#{safe_lab}_*.log")
      .sort_by { |f| File.mtime(f) }
      .reverse
  end

  def self.all_logs
    Dir.glob("#{LOG_DIR}/ctlabs_*.log")
      .sort_by { |f| File.mtime(f) }
      .reverse
  end

  # Instance initialization - ALWAYS requires path:
  def initialize(path:, lab_name: nil, action: nil, silent: false)
    @path     = path
    @lab_name = lab_name
    @action   = action
    @silent   = silent
    
    # Only configure real logger if not silent
    unless @silent
      FileUtils.mkdir_p(File.dirname(path))
      @logger = Logger.new(path, 10, 1024 * 1024)
      @logger.level = Logger::INFO
      @logger.datetime_format = '%Y-%m-%d %H:%M:%S'
      @logger.formatter = proc do |severity, datetime, _progname, msg|
        "[#{datetime}] #{severity[0]}: #{msg}\n"
      end
    end
  end

  # PUBLIC API - CORRECT ARITY (critical fix!)
  def info(msg)
    return if @silent  # Silent mode: no output
    
    $stdout.puts(msg)
    $stdout.flush
    @logger&.info(msg)
  end

  def debug(msg)
    return if @silent
    @logger&.debug(msg)
  end

  def write(msg, level = 'info')
    return if @silent
    
    case level.to_s.downcase
    when 'info'  then info(msg)
    when 'debug' then debug(msg)
    else
      $stdout.puts(msg)
      @logger&.send(level.to_s.downcase, msg) rescue nil
    end
  end

  attr_reader :path, :lab_name, :action

  def close
    @logger&.close
  end
end
