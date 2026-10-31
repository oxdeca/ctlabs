# -----------------------------------------------------------------------------
# File        : ctlabs/controllers/terminal_controller.rb
# Description : Controller for Web Terminal WebSocket and UI
# License     : MIT License
# -----------------------------------------------------------------------------

class TerminalController < BaseController
  get '/terminal/:node_name' do
    if request.env['HTTP_UPGRADE']&.downcase == 'websocket'
      request.env['rack.hijack'].call
      io = request.env['rack.hijack_io']

      ssl_mutex = Mutex.new
      wrapper = WSSocketWrapper.new(request.env, io, ssl_mutex)
      driver = WebSocket::Driver.rack(wrapper)
      
      node_name = params[:node_name]
      env_token = params[:token]
      cmd = TerminalService.resolve_terminal_command(node_name, session, env_token: env_token)
      
      TerminalService.handle_websocket(driver, cmd, io, ssl_mutex, node_name, 
                                       initial_cols: params[:cols], 
                                       initial_rows: params[:rows],
                                       env_token: env_token)

      return [-1, {}, []]
    else
      @node_name = params[:node_name]
      @is_controller = TerminalService.is_controller?(@node_name)
      erb :terminal, layout: false
    end
  end

  get '/terminal/:node_name/sessions' do
    content_type :json
    { count: TerminalService.session_count(params[:node_name]) }.to_json
  end

  post '/terminal/:node_name/terminate_oldest' do
    content_type :json
    success = TerminalService.terminate_oldest(params[:node_name])
    { success: success }.to_json
  end

  post '/terminal/:node_name/env_files' do
    content_type :json
    node_name = params[:node_name]
    unless TerminalService.is_controller?(node_name)
      halt 403, { ok: false, error: 'Env files are only supported on controller terminals' }.to_json
    end

    begin
      payload = JSON.parse(request.body.read)
      files = payload['files'] || []
      token, summary = TerminalService.stage_env_files(node_name, files)
      { ok: true, token: token, files: summary }.to_json
    rescue ArgumentError => e
      status 400
      { ok: false, error: e.message }.to_json
    rescue => e
      status 500
      { ok: false, error: e.message }.to_json
    end
  end

  get '/terminal/:node_name/target_info' do
    content_type :json
    node_name = params[:node_name]
    target = TerminalService.resolve_node_target(node_name)
    if target
      {
        ok: true,
        node: node_name,
        type: target[:type],
        default_dir: target[:default_dir] || '/root',
        user: target[:user]
      }.to_json
    else
      status 404
      { ok: false, error: "Node #{node_name} not found" }.to_json
    end
  end

  get '/terminal/:node_name/check_file' do
    content_type :json
    node_name = params[:node_name]
    path = params[:path].to_s.strip
    if path.empty?
      status 400
      return { ok: false, exists: false, error: 'Path parameter is required' }.to_json
    end

    info = TerminalService.check_node_file(node_name, path)
    info.to_json
  end

  get '/terminal/:node_name/list_files' do
    content_type :json
    node_name = params[:node_name]
    dir = params[:dir].to_s.strip
    dir = nil if dir.empty?

    result = TerminalService.list_node_files(node_name, dir)
    result.to_json
  end

  post '/terminal/:node_name/upload' do
    content_type :json
    node_name = params[:node_name]
    dest_dir = params[:dest_dir].to_s.strip
    dest_dir = nil if dest_dir.empty?

    files_param = params[:files]
    file_param = params[:file]

    items_to_upload = []

    if files_param
      file_list = files_param.is_a?(Array) ? files_param : [files_param]
      paths_list = params[:paths] ? (params[:paths].is_a?(Array) ? params[:paths] : [params[:paths]]) : []

      file_list.each_with_index do |f, idx|
        next unless f && f[:tempfile]
        rel_path = paths_list[idx].to_s.strip
        rel_path = f[:filename] if rel_path.empty?
        items_to_upload << { tempfile: f[:tempfile], path: rel_path }
      end
    elsif file_param && file_param[:tempfile]
      custom_filename = params[:filename].to_s.strip
      custom_filename = nil if custom_filename.empty?
      rel_path = custom_filename || file_param[:filename]
      items_to_upload << { tempfile: file_param[:tempfile], path: rel_path }
    end

    empty_dirs = params[:dirs] ? (params[:dirs].is_a?(Array) ? params[:dirs] : [params[:dirs]]) : []

    if items_to_upload.empty? && empty_dirs.empty?
      status 400
      return { ok: false, error: 'No files or folders uploaded' }.to_json
    end

    begin
      # If single legacy upload with no empty dirs and not using files[]
      if items_to_upload.size == 1 && empty_dirs.empty? && !files_param
        item = items_to_upload.first
        res = TerminalService.upload_file(
          node_name,
          item[:tempfile],
          item[:path],
          dest_dir: dest_dir
        )
        return res.merge(count: 1, total_size: res[:size]).to_json
      end

      # Multi-file or folder upload
      result = TerminalService.upload_files(
        node_name,
        items_to_upload,
        dest_dir: dest_dir,
        empty_dirs: empty_dirs
      )

      # Backwards-compatible convenience fields for single file uploads
      if result[:files]&.size == 1
        result[:filename] = result[:files].first[:filename]
        result[:path] = result[:files].first[:path]
        result[:size] = result[:files].first[:size]
      end

      status(result[:ok] ? 200 : 207)
      result.to_json
    rescue => e
      status 500
      { ok: false, error: e.message }.to_json
    end
  end

  get '/terminal/:node_name/download' do
    node_name = params[:node_name]
    path = params[:path].to_s.strip
    if path.empty?
      status 400
      content_type :json
      return { ok: false, error: 'Path parameter is required' }.to_json
    end

    info = TerminalService.check_node_file(node_name, path)
    unless info[:exists]
      status 404
      content_type :json
      return { ok: false, error: "File or directory not found: #{path}" }.to_json
    end

    filename = info[:name] || File.basename(info[:path])
    is_dir = (info[:type] == :dir)

    if is_dir
      filename = "#{filename}.tar.gz" unless filename.end_with?('.tar.gz')
      content_type 'application/gzip'
    else
      content_type 'application/octet-stream'
      headers['Content-Length'] = info[:size].to_s if info[:size]
    end

    headers['Content-Disposition'] = "attachment; filename=\"#{filename}\""

    stream do |out|
      TerminalService.stream_file(node_name, info[:path], is_dir: is_dir) do |chunk|
        out << chunk
      end
    end
  end
end
