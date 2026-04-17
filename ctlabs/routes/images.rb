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
