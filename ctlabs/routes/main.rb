# -----------------------------------------------------------------------------
# File        : ctlabs/routes/main.rb
# License     : MIT License
# -----------------------------------------------------------------------------

# ------------------------------------------------------------------------------
# ROUTES
# ------------------------------------------------------------------------------
get "/" do
  #ERB.new(home).result(binding)
  #erb :home
  redirect('/labs')
end

get '/upload' do
  erb :upload
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
  @running_lab = Lab.running? ? Lab.current_name : nil
  
  if @running_lab
    runtime_path = "#{LOCK_DIR}/#{@running_lab.gsub('/', '_')}.yml"
    @active_yaml = File.file?(runtime_path) ? File.read(runtime_path) : nil
  end
  erb :config
end
