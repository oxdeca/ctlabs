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

# --- NEW: Context File Browser Tree ---
get '/images/context/tree' do
  content_type :json
  df_path, _ = resolve_image_paths(params[:image])
  halt 404, { error: "Image path not found" }.to_json unless df_path

  begin
    img_dir = File.dirname(df_path)
    files = []
    if Dir.exist?(img_dir)
      Dir.glob(File.join(img_dir, "**", "*")).each do |file|
        next if File.directory?(file)
        # Exclude Dockerfile (it has a fixed tab) and hidden noisy folders
        next if file.include?('/.git/') || file.end_with?('/Dockerfile') || file.end_with?('/build.sh')
        
        files << file.sub(img_dir + '/', '')
      end
    end
    files.sort.to_json
  rescue => e
    status 400
    { error: e.message }.to_json
  end
end

# --- NEW: Fetch Specific Context File ---
get '/images/context/file' do
  content_type :json
  df_path, _ = resolve_image_paths(params[:image])
  halt 404, { error: "Image path not found" }.to_json unless df_path
  
  filepath = params[:path].to_s.strip
  halt 400, { error: "Invalid path" }.to_json if filepath.empty? || filepath.include?('..') || filepath.start_with?('/')

  begin
    img_dir = File.dirname(df_path)
    full_path = File.join(img_dir, filepath)
    
    # Return file if it exists, otherwise return blank string for a new file
    content = File.file?(full_path) ? File.read(full_path) : "# New file: #{filepath}\n"
    { content: content }.to_json
  rescue => e
    status 400
    { error: e.message }.to_json
  end
end

# --- NEW: Delete Specific Context File ---
post '/images/context/delete' do
  content_type :json
  df_path, _ = resolve_image_paths(params[:image])
  halt 404, { error: "Image path not found" }.to_json unless df_path
  
  filepath = params[:filepath].to_s.strip
  halt 400, { error: "Invalid path" }.to_json if filepath.empty? || filepath.include?('..') || filepath.start_with?('/')
  
  begin
    img_dir = File.dirname(df_path)
    full_path = File.join(img_dir, filepath)
    
    File.delete(full_path) if File.exist?(full_path)
    { success: true }.to_json
  rescue => e
    status 400
    { error: e.message }.to_json
  end
end

# --- UPDATED: Save Dockerfile & Context Files ---
post '/images/save' do
  content_type :json
  df_path, build_sh = resolve_image_paths(params[:image])
  halt 404, { error: "Dockerfile path not found" }.to_json unless df_path

  begin
    img_dir = File.dirname(df_path)
    
    # 1. Save Core Dockerfile
    File.write(df_path, params[:dockerfile]) if params[:dockerfile]
    
    # 2. Save dynamic context files
    context_files = JSON.parse(params[:context_files] || '{}')
    context_files.each do |filepath, content|
      next if filepath.include?('..') || filepath.start_with?('/') 
      full_path = File.join(img_dir, filepath)
      FileUtils.mkdir_p(File.dirname(full_path))
      File.write(full_path, content)
      
      # Auto-chmod shell and python scripts so they can execute during build
      FileUtils.chmod("+x", full_path) if filepath.end_with?('.sh') || filepath.end_with?('.py')
    end

    # 3. Patch the version tag in build.sh
    patch_image_version(build_sh, params[:version])

    { message: "Context files and Version saved" }.to_json
  rescue => e
    status 400
    { error: e.message }.to_json
  end
end

# --- UPDATED: Build Process ---
post '/images/build' do
  content_type :json
  df_path, build_sh = resolve_image_paths(params[:image])
  
  halt 404, { error: "Dockerfile path not found" }.to_json unless df_path
  halt 400, { error: "build.sh not found in directory" }.to_json unless File.exist?(build_sh)

  begin
    img_dir = File.dirname(df_path)
    
    # 1. Save Core Dockerfile
    File.write(df_path, params[:dockerfile]) if params[:dockerfile] && !params[:dockerfile].to_s.strip.empty?
    
    # 2. Save dynamic context files
    context_files = JSON.parse(params[:context_files] || '{}')
    context_files.each do |filepath, content|
      next if filepath.include?('..') || filepath.start_with?('/') 
      full_path = File.join(img_dir, filepath)
      FileUtils.mkdir_p(File.dirname(full_path))
      File.write(full_path, content)
      FileUtils.chmod("+x", full_path) if filepath.end_with?('.sh') || filepath.end_with?('.py')
    end

    # 3. Patch version tag
    patch_image_version(build_sh, params[:version])

    # 4. Trigger Build Process
    log_dir = defined?(::LOG_DIR) ? ::LOG_DIR : '/var/log/ctlabs'
    FileUtils.mkdir_p(log_dir)
    
    safe_img_name = params[:image].split(':').first.gsub('/', '_').gsub(/[^0-9a-zA-Z_]/, '')
    log_file = File.join(log_dir, "build_#{safe_img_name}_#{Time.now.to_i}.log")
    FileUtils.touch(log_file)
    
    spawn("cd #{img_dir} && bash build.sh > #{log_file} 2>&1")
    { message: "Build triggered", log_path: log_file }.to_json
    
  rescue => e
    status 400
    { error: e.message }.to_json
  end
end

# --- UNCHANGED ROUTES ---

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

# ===================================================
# HELPER: Check if a profile is used by any node
# ===================================================
def profile_in_use?(yaml, target_type, target_profile)
  vm = yaml['topology']&.first || {}
  
  # Gather all nodes across all planes (or flat nodes array)
  nodes_to_scan = vm['planes'] ? vm['planes'].values.map { |p| p['nodes'] } : [vm['nodes']]
  
  nodes_to_scan.compact.each do |node_group|
    node_group.values.each do |n|
      node_type = n['type'] || 'host'
      node_prof = n['profile'] || n['kind'] || 'linux'
      
      # If we find a match, it is in use!
      if node_type.to_s == target_type.to_s && node_prof.to_s == target_profile.to_s
        return true
      end
    end
  end
  false
end

# ===================================================
# EDIT PROFILE (Schema Aware)
# ===================================================
post '/labs/*/image/edit' do
  lab_name = params[:splat].first
  lab_path = get_lab_file_path(lab_name)

  begin
    full_yaml = YAML.load_file(lab_path) || {}

    type = params[:type].to_s.strip
    kind = params[:kind].to_s.strip

    halt 400, { error: "Type and Kind are required" }.to_json if type.empty? || kind.empty?

    # Detect if lab is using v2 'profiles' or v1 'defaults'
    profile_key = full_yaml.key?('profiles') ? 'profiles' : 'defaults'
    
    full_yaml[profile_key] ||= {}
    full_yaml[profile_key][type] ||= {}
    full_yaml[profile_key][type][kind] ||= {}

    profile = full_yaml[profile_key][type][kind]
    
    # Update properties
    params[:image].to_s.strip.empty? ? profile.delete('image') : profile['image'] = params[:image].strip

    caps = params[:caps].to_s.split(',').map(&:strip).reject(&:empty?)
    caps.empty? ? profile.delete('caps') : profile['caps'] = caps

    env = params[:env].to_s.split(/\r?\n/).map(&:strip).reject(&:empty?)
    env.empty? ? profile.delete('env') : profile['env'] = env

    if params[:extras] && !params[:extras].strip.empty?
      begin
        profile.merge!(YAML.safe_load(params[:extras]))
      rescue => e
        raise "Invalid YAML in Extras: #{e.message}"
      end
    end

    write_formatted_yaml(lab_path, full_yaml)

    content_type :json
    { success: true, message: "Profile updated successfully." }.to_json
  rescue Exception => e
    status 400
    content_type :json
    { success: false, error: e.message }.to_json
  end
end

# ===================================================
# DELETE PROFILE (Protected)
# ===================================================
post '/labs/*/image/:type/:kind/delete' do
  lab_name = params[:splat].first
  lab_path = get_lab_file_path(lab_name)
  
  begin
    yaml = YAML.load_file(lab_path)
    
    # 1. Protection Check!
    if profile_in_use?(yaml, params[:type], params[:kind])
      halt 400, { error: "Cannot delete '#{params[:kind]}'. It is currently being used by a node in this lab!" }.to_json
    end

    # 2. Safe Deletion
    profile_key = yaml.key?('profiles') ? 'profiles' : 'defaults'
    
    if yaml[profile_key] && yaml[profile_key][params[:type]]
      yaml[profile_key][params[:type]].delete(params[:kind])
      yaml[profile_key].delete(params[:type]) if yaml[profile_key][params[:type]].empty?
      write_formatted_yaml(lab_path, yaml)
    end
    
    content_type :json
    { success: true, message: "Image profile deleted." }.to_json
  rescue => e
    status 400
    content_type :json
    { success: false, error: e.message }.to_json
  end
end
