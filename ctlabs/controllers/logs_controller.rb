# -----------------------------------------------------------------------------
# File        : ctlabs/controllers/logs_controller.rb
# Description : Controller for Log viewing and management
# License     : MIT License
# -----------------------------------------------------------------------------

class LogsController < BaseController
  get '/logs' do
    if params[:id]
      @log_id = params[:id]
      @log_file = resolve_log_path(@log_id)
      halt 403, "Invalid or expired log ID" unless @log_file
      halt 404, "Log file not found" unless File.file?(@log_file)
      
      basename = File.basename(@log_file, '.log')
      parts = basename.split('_')
      @lab_name = parts[2..-2].join('_').gsub(/\.yml$/, '.yml') rescue 'Unknown'
      @action = parts.last == 'up' ? 'up' : 'down'
      
      erb :live_log
    else
      @running_lab = Lab.current_name
      @log_files = @running_lab ? LabLog.all_for_lab(@running_lab) : LabLog.all_logs
      erb :logs_index
    end
  end

  get '/logs/current' do
    if Lab.running?
      log_path = LabLog.latest_for_running_lab
      if log_path
        log_id = register_log(log_path)
        redirect "/logs?id=#{log_id}"
      end
    end
    redirect '/logs'
  end

  get '/logs/download' do
    log_id = params[:id]
    log_file = resolve_log_path(log_id)
    
    halt 403, "Invalid or expired log ID" unless log_file
    halt 404, "Log file not found" unless File.file?(log_file)

    send_file log_file, filename: File.basename(log_file), type: 'text/plain'
  end

  get '/logs/content' do
    log_id = params[:id]
    log_file = resolve_log_path(log_id)

    unless log_file
      status 403
      return "<span style='color:#ef4444;'>❌ Error 403: Invalid or expired log ID</span>"
    end

    unless File.file?(log_file)
      status 404
      return "<span style='color:#ef4444;'>❌ Error 404: The log file does not exist.</span>"
    end

    offset = params[:offset].to_i
    file_size = File.size(log_file)
    
    # Optimization: On initial request (offset 0), if file is large (>256KB),
    # only fetch the tail to prevent browser/server memory pressure.
    is_initial_request = (offset == 0 && params[:offset]) || !params[:offset]
    if is_initial_request && file_size > 1024 * 256 && params[:format] == 'json'
      offset = file_size - 1024 * 256
    end

    # If offset is larger than file size (e.g. file rotated or cleared), reset to 0
    offset = 0 if offset > file_size

    content = ""
    new_offset = offset
    File.open(log_file, 'r') do |f|
      f.seek(offset)
      content = f.read
      new_offset = f.pos
    end

    if params[:format] == 'json'
      content_type :json
      {
        content:   ansi_to_html(content),
        offset:    new_offset,
        size:      file_size,
        truncated: is_initial_request && offset > 0
      }.to_json
    else
      content_type 'text/html; charset=utf-8'
      ansi_to_html(content)
    end
  end

  get '/logs/system' do
    system_log = '/var/log/ctlabs.log'
    if File.file?(system_log)
      log_id = register_log(system_log)
      redirect "/logs?id=#{log_id}"
    else
      halt 404, "System log not found"
    end
  end

  post '/logs/delete' do
    log_id = params[:id]
    log_file = resolve_log_path(log_id)

    halt 403, "Invalid or expired log ID" unless log_file
    halt 404, "Log file not found" unless File.file?(log_file)

    File.delete(log_file)
    session[:log_map].delete(log_id)
    redirect '/logs'
  end

  post '/logs/delete-all' do
    log_files = Dir.glob("#{LabLog::LOG_DIR}/ctlabs_*.log") + Dir.glob("#{LabLog::LOG_DIR}/build_*.log")
    log_files.each { |f| File.delete(f) if File.file?(f) }
    redirect '/logs'
  end
end
