# -----------------------------------------------------------------------------
# File        : ctlabs/controllers/images_controller.rb
# Description : Controller for Image management
# License     : MIT License
# -----------------------------------------------------------------------------

class ImagesController < BaseController
  get '/images/dockerfile' do
    content_type :json
    df_path, build_sh = ImageService.resolve_image_paths(params[:image])
    
    if df_path && File.exist?(df_path)
      { dockerfile: File.read(df_path), version: ImageService.extract_version(build_sh) }.to_json
    else
      status 404
      { error: "Dockerfile not found for #{params[:image]}" }.to_json
    end
  end

  get '/images/context/tree' do
    content_type :json
    df_path, _ = ImageService.resolve_image_paths(params[:image])
    halt 404, { error: "Image path not found" }.to_json unless df_path

    begin
      ImageService.context_tree(df_path).to_json
    rescue => e
      status 400
      { error: e.message }.to_json
    end
  end

  get '/images/context/file' do
    content_type :json
    df_path, _ = ImageService.resolve_image_paths(params[:image])
    halt 404, { error: "Image path not found" }.to_json unless df_path
    
    filepath = params[:path].to_s.strip
    halt 400, { error: "Invalid path" }.to_json if filepath.empty? || filepath.include?('..') || filepath.start_with?('/')

    begin
      content = ImageService.read_context_file(df_path, filepath)
      { content: content }.to_json
    rescue => e
      status 400
      { error: e.message }.to_json
    end
  end

  post '/images/context/delete' do
    content_type :json
    df_path, _ = ImageService.resolve_image_paths(params[:image])
    halt 404, { error: "Image path not found" }.to_json unless df_path
    
    filepath = params[:filepath].to_s.strip
    halt 400, { error: "Invalid path" }.to_json if filepath.empty? || filepath.include?('..') || filepath.start_with?('/')
    
    begin
      ImageService.delete_context_file(df_path, filepath)
      { success: true }.to_json
    rescue => e
      status 400
      { error: e.message }.to_json
    end
  end

  post '/images/save' do
    content_type :json
    df_path, build_sh = ImageService.resolve_image_paths(params[:image])
    halt 404, { error: "Dockerfile path not found" }.to_json unless df_path

    begin
      File.write(df_path, params[:dockerfile]) if params[:dockerfile]
      
      context_files = JSON.parse(params[:context_files] || '{}')
      ImageService.write_context_files(df_path, context_files)

      ImageService.patch_version(build_sh, params[:version])

      { message: "Context files and Version saved" }.to_json
    rescue => e
      status 400
      { error: e.message }.to_json
    end
  end

  post '/images/build' do
    content_type :json
    df_path, build_sh = ImageService.resolve_image_paths(params[:image])
    
    halt 404, { error: "Dockerfile path not found" }.to_json unless df_path
    halt 400, { error: "build.sh not found in directory" }.to_json unless File.exist?(build_sh)

    begin
      img_dir = File.dirname(df_path)
      File.write(df_path, params[:dockerfile]) if params[:dockerfile] && !params[:dockerfile].to_s.strip.empty?
      
      context_files = JSON.parse(params[:context_files] || '{}')
      ImageService.write_context_files(df_path, context_files)

      ImageService.patch_version(build_sh, params[:version])

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
      ImageService.create_skeleton(params[:image_path])
      { message: "Created successfully" }.to_json
    rescue => e
      status 400
      { error: e.message }.to_json
    end
  end

  post '/images/delete' do
    content_type :json
    clean_path = params[:image].to_s.gsub(/[^a-zA-Z0-9_\-\/]/, '')
    full_dir = File.join(ImageService::IMAGES_DIR, clean_path)

    if File.directory?(full_dir)
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
      ImageService.unload_local_image(params[:image])
      { message: "Image unloaded successfully" }.to_json
    rescue => e
      status 404
      { error: e.message }.to_json
    end
  end
end
