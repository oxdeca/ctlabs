# -----------------------------------------------------------------------------
# File        : ctlabs/routes/logs.rb
# License     : MIT License
# -----------------------------------------------------------------------------

get '/logs' do
  if params[:file]
    # View specific log
    @log_file = URI.decode_www_form_component(params[:file])
    halt 403 unless @log_file.start_with?(LabLog::LOG_DIR) && @log_file.end_with?('.log')
    halt 404 unless File.file?(@log_file)
    
    # Extract from filename (minimal parsing for display only)
    basename = File.basename(@log_file, '.log')
    parts = basename.split('_')
    @lab_name = parts[2..-2].join('_').gsub(/\.yml$/, '.yml') rescue 'Unknown'
    @action = parts.last == 'up' ? 'up' : 'down'
    
    erb :live_log
  else
    # Show log index
    @running_lab = Lab.running? ? Lab.current_name : nil
    
    # ✅ DELEGATE TO LABLOG
    @log_files = if @running_lab
      LabLog.all_for_lab(@running_lab)
    else
      LabLog.all_logs
    end
    
    erb :logs_index
  end
end

get '/logs/current' do
  if Lab.running?
    log_path = LabLog.latest_for_running_lab  # ✅ No pattern matching!
    redirect "/logs?file=#{URI.encode_www_form_component(log_path)}" if log_path
  end
  redirect '/logs'
end

get '/logs/content' do
  content_type 'text/html; charset=utf-8'
  log_file = URI.decode_www_form_component(params[:file])
  
  # Forgiving path check
  log_dir = defined?(LOG_DIR) ? LOG_DIR : '/var/log/ctlabs'
  basename = File.basename(log_file)
  is_valid_prefix = basename.start_with?('ctlabs_') || basename.start_with?('build_')
  
  # If it fails the security check, print it to the UI!
  unless log_file.start_with?(log_dir) && is_valid_prefix && log_file.end_with?('.log')
    status 403
    return "<span style='color:#ef4444;'>❌ Error 403: Log viewer blocked access to: #{log_file}.</span>"
  end

  # If the file hasn't been written to disk yet, print it to the UI!
  unless File.file?(log_file)
    status 404
    return "<span style='color:#ef4444;'>❌ Error 404: The log file does not exist. (Did the build script fail to execute?)</span>"
  end

  raw_text = File.read(log_file)
  ansi_to_html(raw_text)
end

get '/logs/system' do
  system_log = '/var/log/ctlabs.log'
  if File.file?(system_log)
    @log_file = system_log
    @lab_name = 'System Log (CLI operations)'
    @action = 'system'
    erb :live_log
  else
    halt 404, "System log not found"
  end
end

# Delete a single log file
post '/logs/delete' do
  log_file = URI.decode_www_form_component(params[:file])
  # Security: only allow logs from our directory with correct pattern
  # Security: allow standard lab logs AND image build logs
  basename = File.basename(log_file)
  is_valid_pattern = basename.match?(/\Actlabs_\d+_.+_\w+\.log\z/) || basename.match?(/\Abuild_.+_\d+\.log\z/)

  halt 403 unless log_file.start_with?(LOG_DIR) && File.basename(log_file).match?(/\Actlabs_\d+_.+_\w+\.log\z/) && log_file.end_with?('.log')
  halt 404 unless File.file?(log_file)

  File.delete(log_file)
  redirect '/logs'
end

# Delete all log files
post '/logs/delete-all' do
  log_files = Dir.glob("#{LOG_DIR}/ctlabs_*.log") + Dir.glob("#{LOG_DIR}/build_*.log")
  log_files.each { |f| File.delete(f) if File.file?(f) }
  redirect '/logs'
end
