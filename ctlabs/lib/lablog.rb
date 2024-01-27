
# -----------------------------------------------------------------------------
# File        : ctlabs/lib/lablog.rb
# Description : logger
# License     : MIT License
# -----------------------------------------------------------------------------

require 'logger'

class LabLog
  attr_writer :level

  def initialize(args={})
    @level  = args[:level] || 'warn'
    @file   = args[:file]  || "/var/log/#{File.basename($PROGRAM_NAME, '.rb')}.log"
    @out    = args[:out]   || $stdout
    @log1   = Logger.new(@out,  progname: File.basename($PROGRAM_NAME, '.rb') )
    @log2   = Logger.new(@file, progname: File.basename($PROGRAM_NAME, '.rb') )
  end

  def write(msg, level=@level)
    case @level
      when 'info'
        @log1.info(msg)
        @log2.info(msg)
      when 'debug'
        @log2.debug(msg)
    end
  end
end
