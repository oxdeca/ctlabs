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

  get '/demo' do
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
