# -----------------------------------------------------------------------------
# File        : ctlabs/routes/images.rb
# License     : MIT License
# -----------------------------------------------------------------------------

get '/images/dockerfile' do
  content_type :json
  df_path, build_sh = resolve_image_paths(params[:image])
  
  if df_path && File.exist?(df_path)
    { dockerfile: File.read(df_path), version: extract_image_version(build_sh) }.to_json
  else
    status 404
    { error: "Dockerfile not found for #{params[:image]}" }.to_json
  end
end

post '/images/save' do
  content_type :json
  df_path, build_sh = resolve_image_paths(params[:image])
  halt 404, { error: "Dockerfile path not found" }.to_json unless df_path

  File.write(df_path, params[:dockerfile]) if params[:dockerfile]
  patch_image_version(build_sh, params[:version])

  { message: "Dockerfile and Version saved" }.to_json
end

post '/images/build' do
  content_type :json
  df_path, build_sh = resolve_image_paths(params[:image])
  
  halt 404, { error: "Dockerfile path not found" }.to_json unless df_path
  halt 400, { error: "build.sh not found in directory" }.to_json unless File.exist?(build_sh)

  File.write(df_path, params[:dockerfile]) if params[:dockerfile] && !params[:dockerfile].to_s.strip.empty?
  patch_image_version(build_sh, params[:version])

  log_dir = defined?(::LOG_DIR) ? ::LOG_DIR : '/var/log/ctlabs'
  FileUtils.mkdir_p(log_dir)
  
  safe_img_name = params[:image].split(':').first.gsub('/', '_').gsub(/[^0-9a-zA-Z_]/, '')
  log_file = File.join(log_dir, "build_#{safe_img_name}_#{Time.now.to_i}.log")
  FileUtils.touch(log_file)
  
  spawn("cd #{File.dirname(build_sh)} && bash build.sh > #{log_file} 2>&1")
  { message: "Build triggered", log_path: log_file }.to_json
end

post '/images/pull' do
  content_type :json
  image = params[:image_name].to_s.gsub(/[^a-zA-Z0-9_\-\/:\.]/, '')
  halt 400, { error: "Invalid image name provided" }.to_json if image.empty?
  
  success = system("podman pull #{image} > /dev/null 2>&1") || system("docker pull #{image} > /dev/null 2>&1")
  
  if success
    { message: "Image pulled successfully" }.to_json
  else
    status 500
    { error: "Failed to pull image '#{image}'. Ensure the name is correct and the registry is reachable." }.to_json
  end
end

post '/images/remove_imported' do
  content_type :json
  image = params[:image].to_s.gsub(/[^a-zA-Z0-9_\-\/:\.]/, '')
  halt 400, { error: "Invalid image tag provided" }.to_json if image.empty?
  
  system("podman rmi #{image} > /dev/null 2>&1")
  system("docker rmi #{image} > /dev/null 2>&1")
  { message: "External image removed successfully" }.to_json
end

post '/images/create' do
  content_type :json
  begin
    create_image_skeleton(params[:image_path])
    { message: "Created successfully" }.to_json
  rescue => e
    status 400
    { error: e.message }.to_json
  end
end

post '/images/delete' do
  content_type :json
  clean_path = params[:image].to_s.gsub(/[^a-zA-Z0-9_\-\/]/, '')
  full_dir = File.join("..", "images", clean_path)

  if File.directory?(full_dir) && full_dir.include?("../images/")
    FileUtils.rm_rf(full_dir)
    { message: "Deleted successfully" }.to_json
  else
    status 404
    { error: "Image directory not found" }.to_json
  end
end

post '/images/unload' do
  content_type :json
  begin
    unload_local_image(params[:image])
    { message: "Image unloaded successfully" }.to_json
  rescue => e
    status 404
    { error: e.message }.to_json
  end
end

# -----------------------------------

post '/labs/*/image/edit' do
  lab_name = params[:splat].first
  lab_path = get_lab_file_path(lab_name)

  begin
    full_yaml = YAML.load_file(lab_path)
    
    # 1. Initialize the new 'images' block if it doesn't exist
    full_yaml['defaults'] ||= {}
    
    type = params[:type].to_s.strip
    kind = params[:kind].to_s.strip
    
    halt 400, { error: "Type and Kind are required" }.to_json if type.empty? || kind.empty?

    # 2. Build the profile data
    profile = {}
    profile['image'] = params[:image].strip unless params[:image].to_s.strip.empty?
    
    caps = params[:caps].to_s.split(',').map(&:strip).reject(&:empty?)
    profile['caps'] = caps unless caps.empty?
    
    env = params[:env].to_s.split(/\r?\n/).map(&:strip).reject(&:empty?)
    profile['env'] = env unless env.empty?
    
    if params[:extras] && !params[:extras].strip.empty?
      begin
        # Merge extra YAML attributes directly into the profile
        profile.merge!(YAML.safe_load(params[:extras]))
      rescue => e
        raise "Invalid YAML in Extras: #{e.message}"
      end
    end

    # 3. Save into the new clean structure!
    full_yaml['defaults'][type] ||= {}
    full_yaml['defaults'][type][kind] = profile

    write_formatted_yaml(lab_path, full_yaml)

    content_type :json
    { success: true }.to_json
  rescue Exception => e
    status 400
    content_type :json
    { success: false, error: e.message }.to_json
  end
end

# Delete an Image
post '/labs/*/image/:type/:kind/delete' do
  lab_name = params[:splat].first
  lab_path = get_lab_file_path(lab_name)
  begin
    yaml = YAML.load_file(lab_path)
    yaml['defaults'][params[:type]].delete(params[:kind]) rescue nil
    yaml['defaults'].delete(params[:type]) if yaml['defaults'][params[:type]]&.empty?
    write_formatted_yaml(lab_path, yaml)
    { success: true, message: "Image deleted." }.to_json
  rescue => e
    status 400
    { success: false, error: e.message }.to_json
  end
end
