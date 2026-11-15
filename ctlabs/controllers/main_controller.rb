# -----------------------------------------------------------------------------
# File        : ctlabs/controllers/main_controller.rb
# Description : Main controller for CT Labs
# License     : MIT License
# -----------------------------------------------------------------------------

class MainController < BaseController
  get "/" do
    redirect('/labs')
  end

  get '/upload' do
    erb :upload
  end

  post '/upload' do
    uploaded_file = params[:file]
    halt 400, "No file uploaded" unless uploaded_file

    filename = uploaded_file[:tempfile].path
    halt 400, "Empty file" if File.zero?(filename)

    upload_dir = defined?(::UPLOAD_DIR) ? ::LOCK_DIR : '/srv/ctlabs-server/uploads'
    FileUtils.cp(filename, File.join(upload_dir, uploaded_file[:filename]))
    redirect '/upload'
  end

  get '/con' do
    @title       = "Connection Maps"
    @icon        = "fa-link"
    @file_prefix = "con"
    erb :map_viewer
  end

  get '/topo' do
    @title       = "Topology Maps"
    @icon        = "fa-project-diagram"
    @file_prefix = "topo"
    erb :map_viewer
  end

  get '/maps/dot/:type' do
    content_type :json
    type = params[:type].to_s.strip.downcase
    dot = Lab.render_diagram_dot(type, lab_name: params[:lab_name])
    if dot
      lab_name = params[:lab_name].to_s.strip
      lab_name = Lab.current_name if lab_name.empty?
      clean_lab = lab_name.to_s.split('/').last.to_s.sub(/\.ya?ml\z/i, '')
      clean_lab = 'lab' if clean_lab.empty?
      suggested_name = "study.#{clean_lab}.#{type}.01"

      { ok: true, type: type, dot: dot, name: suggested_name, lab: clean_lab }.to_json
    else
      status 404
      { ok: false, error: "Diagram '#{type}' not available or could not be generated." }.to_json
    end
  end

  get '/maps/export_info' do
    content_type :json
    lab_name = Lab.current_name.to_s
    clean_lab = lab_name.split('/').last.to_s.sub(/\.ya?ml\z/i, '')
    clean_lab = 'lab' if clean_lab.empty?

    active_wk = session[:walkthrough].to_s.strip
    walkthroughs = RecordingService.respond_to?(:load_walkthroughs) ? RecordingService.load_walkthroughs : {}
    active_wk = walkthroughs.keys.first.to_s if active_wk.empty? && !walkthroughs.empty?

    sets = walkthroughs.map do |slug, data|
      set_name = data.is_a?(Hash) ? (data['name'] || slug) : (data.to_s.empty? ? slug : data)
      steps = RecordingService.respond_to?(:list_for_walkthrough) ? RecordingService.list_for_walkthrough(slug) : []
      unint = RecordingService.respond_to?(:list_unintegrated_for_walkthrough) ? RecordingService.list_unintegrated_for_walkthrough(slug) : []
      notes = (steps + unint).select { |s| s[:type] == :markdown }.uniq { |n| n[:id] }.map do |n|
        { id: n[:id], title: n[:title] }
      end
      last_rec = session["last_recording_#{slug}"].to_s
      { slug: slug, name: set_name, notes: notes, active_note: last_rec }
    end

    {
      ok: true,
      lab: clean_lab,
      active_walkthrough: active_wk,
      walkthrough_sets: sets,
      types: {
        topo: 'Topology — Data Network',
        mgmt_topo: 'Topology — Management Network',
        con: 'Connections — Data Network',
        mgmt_con: 'Connections — Management Network'
      }
    }.to_json
  end

  post '/maps/export_to_graphviz' do
    content_type :json
    type = params[:type].to_s.strip.downcase
    dot = Lab.render_diagram_dot(type, lab_name: params[:lab_name])
    unless dot
      status 404
      return { ok: false, error: "Source diagram '#{type}' not found or could not be generated." }.to_json
    end

    raw_name = params[:name].to_s.strip
    if raw_name.empty?
      lab_name = params[:lab_name].to_s.strip
      lab_name = Lab.current_name if lab_name.empty?
      clean_lab = lab_name.to_s.split('/').last.to_s.sub(/\.ya?ml\z/i, '')
      clean_lab = 'lab' if clean_lab.empty?
      raw_name = "study.#{clean_lab}.#{type}.01"
    end

    clean_name = raw_name.sub(/\.(svg|png|dot|jpe?g|webp)\z/i, '').gsub(/[^a-zA-Z0-9_.-]+/, '_').strip[0, 60]
    clean_name = 'diagram' if clean_name.empty?

    wk = params[:walkthrough].to_s.strip
    wk = session[:walkthrough].to_s.strip if wk.empty?
    if wk.empty?
      walkthroughs = RecordingService.respond_to?(:load_walkthroughs) ? RecordingService.load_walkthroughs : {}
      wk = walkthroughs.keys.first.to_s
    end

    # Prepend 80-column header comment if not already present
    header_block = "# ------------------------------------------------------------------------------\n# File: #{clean_name}\n# ------------------------------------------------------------------------------\n"
    source = dot.start_with?('# ------') ? dot : (header_block + dot)

    result = GraphvizService.render(source, format: 'svg', engine: 'dot', walkthrough: wk)
    unless result[:ok]
      status 422
      return { ok: false, error: result[:error] }.to_json
    end

    saved = RecordingService.save_diagram(
      result[:data], clean_name,
      walkthrough: wk, source: source, format: 'svg', base: clean_name
    )

    # Handle optional insertion into a Markdown document
    note_id = params[:note_id].to_s.strip
    target_note_id = nil
    img_filename = saved['filename'] || "#{clean_name}.svg"

    if note_id == '__new__'
      note_title = params[:new_note_title].to_s.strip
      note_title = clean_name if note_title.empty?
      snippet = "![#{clean_name}](/recordings/images/#{img_filename})"
      note_content = "# #{note_title}\n\n#{snippet}\n"
      target_note_id = RecordingService.create_markdown_step(wk, title: note_title, content: note_content)
    elsif !note_id.empty? && RecordingService.valid_id?(note_id)
      current_content = RecordingService.read_content(note_id) || ''
      snippet = "![#{clean_name}](/recordings/images/#{img_filename})"
      unless current_content.include?(img_filename) || current_content.include?("#{clean_name}.svg")
        updated_content = current_content.rstrip
        updated_content = updated_content.empty? ? snippet : "#{updated_content}\n\n#{snippet}\n"
        RecordingService.update_content(note_id, updated_content)
      end
      target_note_id = note_id
    end

    session[:walkthrough] = wk
    session["last_recording_#{wk}"] = target_note_id if target_note_id

    redirect_url = if target_note_id
                     "/demo?walkthrough=#{Rack::Utils.escape_path(wk)}&recording=#{Rack::Utils.escape_path(target_note_id)}&graphviz=#{Rack::Utils.escape_path(saved['base'])}"
                   else
                     "/demo?walkthrough=#{Rack::Utils.escape_path(wk)}&graphviz=#{Rack::Utils.escape_path(saved['base'])}"
                   end

    {
      ok: true,
      filename: saved['filename'],
      base: saved['base'],
      walkthrough: wk,
      note_id: target_note_id,
      redirect: redirect_url
    }.to_json
  rescue StandardError => e
    status 500
    { ok: false, error: e.message }.to_json
  end

  get '/inventory' do
    erb :inventory
  end

  get '/config' do
    @running_lab = Lab.current_name
    if @running_lab
      runtime_path = Lab.get_file_path(@running_lab)
      @active_yaml = File.file?(runtime_path) ? File.read(runtime_path) : nil
    end
    erb :config
  end

#  get '/demo' do
#    @recordings = RecordingService.list
#    erb :demo
#  end

  get '/demo' do
    requested_repo = params[:repo].to_s.strip
    if !requested_repo.empty? && RecordingService.respond_to?(:switch_repository)
      if RecordingService.switch_repository(requested_repo)
        session.delete(:walkthrough)
      end
    end

    @repositories = RecordingService.respond_to?(:repositories_summary) ? RecordingService.repositories_summary : []
    @active_repo = RecordingService.respond_to?(:active_repo) ? RecordingService.active_repo : 'default'
    @active_repo_name = RecordingService.respond_to?(:active_repo_name) ? RecordingService.active_repo_name : 'Local Workspace'

    @walkthroughs = RecordingService.load_walkthroughs
    requested = params[:walkthrough].to_s
    # Coming back via the nav link (no ?walkthrough=) should reopen the set the
    # user was last working in, not silently fall back to the default set.
    requested = session[:walkthrough].to_s if requested.empty?
    @active_walkthrough = if @walkthroughs.key?(requested)
                            requested
                          else
                            @walkthroughs.keys.first.to_s
                          end
    session[:walkthrough] = @active_walkthrough
    @walkthrough_name = RecordingService.walkthrough_name(@active_walkthrough)
    @recordings = RecordingService.list_for_walkthrough(@active_walkthrough)
    @other_recordings = RecordingService.list_unintegrated_for_walkthrough(@active_walkthrough)
    selected = params[:recording].to_s
    selected = session["last_recording_#{@active_walkthrough}"].to_s if selected.empty?
    @selected_recording = RecordingService.valid_id?(selected) ? selected : ''
    session["last_recording_#{@active_walkthrough}"] = @selected_recording unless @selected_recording.empty?

    @running_nodes = []
    begin
      current_lab = Lab.current if defined?(Lab) && Lab.respond_to?(:current)
      @running_nodes += current_lab.nodes.select(&:running?).map(&:name) if current_lab && current_lab.respond_to?(:nodes)
      @running_nodes += Controller.running_node_names if defined?(Controller) && Controller.respond_to?(:running_node_names)
      @running_nodes.uniq!
    rescue => _e
      # Safe fallback
    end

    erb :demo
  end

  get '/markdown' do
    erb :markdown
  end

  get '/flashcards' do
    @read_only = Lab.running?
    erb :flashcards
  end

  post '/flashcards/data' do
    content_type :json
    if Lab.running?
       status 403
       return { success: false, error: 'Read-Only Mode: Cannot save while Lab is running.' }.to_json
    end
    
    begin
      data = JSON.parse(request.body.read)
      public_file = '/srv/ctlabs-server/public/flashcards.json'
      if !data['set'] || !data['set']['cards'] || data['set']['cards'].empty?
        halt 400, { success: false, error: 'Cannot save empty flashcard set' }.to_json
      end
      File.write(public_file, JSON.pretty_generate(data))
      { success: true }.to_json
    rescue => e
      status 400
      { success: false, error: e.message }.to_json
    end
  end
end
