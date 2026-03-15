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

# Add or Edit a Defined Image
post '/labs/*/image/edit' do
  lab_name = params[:splat].first
  lab_path = get_lab_file_path(lab_name)

  begin
    full_yaml = YAML.load_file(lab_path) || {}
    full_yaml['defaults'] ||= {}
    
    type = params[:type].to_s.strip
    kind = params[:kind].to_s.strip
    
    raise "Type and Kind are required." if type.empty? || kind.empty?

    full_yaml['defaults'][type] ||= {}
    img_cfg = full_yaml['defaults'][type][kind] || {}
    
    img_cfg['image'] = params[:image].strip unless params[:image].to_s.strip.empty?

    # Parse capabilities
    params[:caps].to_s.strip.empty? ? img_cfg.delete('caps') : img_cfg['caps'] = params[:caps].split(',').map(&:strip)
    
    # Parse environment variables
    if params[:env] && !params[:env].strip.empty?
      img_cfg['env'] = params[:env].split("\n").map(&:strip).reject(&:empty?)
    else
      img_cfg.delete('env')
    end

    # Process Extra Arbitrary Attributes (ports, privileged, etc.)
    # 1. Clean out old extra keys first
    core_keys = ['image', 'caps', 'env']
    img_cfg.keys.each { |k| img_cfg.delete(k) unless core_keys.include?(k) }
    
    # 2. Safely merge the new ones
    if params[:extra_attrs] && !params[:extra_attrs].strip.empty?
      parsed_extras = YAML.safe_load(params[:extra_attrs])
      img_cfg.merge!(parsed_extras) if parsed_extras.is_a?(Hash)
    end

    full_yaml['defaults'][type][kind] = img_cfg
    write_formatted_yaml(lab_path, full_yaml)

    content_type :json
    { success: true, message: "Image configuration saved." }.to_json
  rescue => e
    status 400
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