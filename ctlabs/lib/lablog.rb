
# -----------------------------------------------------------------------------
# File        : ctlabs/lib/lablog.rb
# Description : logger
# License     : MIT License
# -----------------------------------------------------------------------------

require 'logger'

class LabLog
  def initialize(args = {})
    @level = args[:level] || 'warn'
    @file  = args[:file]  || "/var/log/ctlabs.log"
    @out   = args[:out]   || $stdout  # CLI uses $stdout; web passes file handle

    @logger_file = Logger.new(@file)
    @output_io   = @out               # for user-facing messages
  end

  # For debug/internal logs (goes only to file)
  def debug(msg)
    @logger_file.debug(msg) if @level == 'debug'
  end

  # For user-facing output (goes to @out AND file)
  def info(msg)
    @output_io.puts(msg)        # ← no timestamp for user-facing
    @output_io.flush
    @logger_file.info("[#{Time.now}] #{msg}")  # ← timestamp only in file
  end

#  def info(msg)
#    line = "[#{Time.now.strftime('%H:%M:%S')}] #{msg}"
#    @output_io.puts(line)
#    @output_io.flush
#    @logger_file.info(msg)
#  end

  # Optional: alias for compatibility
  def write(msg, level = 'info')
    case level
    when 'info'  then info(msg)
    when 'debug' then debug(msg)
    else
      @output_io.puts(msg)
      @logger_file.send(level, msg) rescue nil
    end
  end
end
