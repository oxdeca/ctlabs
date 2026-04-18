# -----------------------------------------------------------------------------
# File        : ctlabs/services/image_service.rb
# Description : Service for Image management operations
# License     : MIT License
# -----------------------------------------------------------------------------

require 'fileutils'

class ImageService
  IMAGES_DIR = File.expand_path('../../../images', __FILE__)

  def self.resolve_image_paths(image_name)
    image = image_name.to_s.split(':').first
    search_path = image.split('/').last(2).join('/')
    dockerfile_path = Dir.glob(File.join(IMAGES_DIR, "**", search_path, "Dockerfile")).first
    build_sh = dockerfile_path ? File.join(File.dirname(dockerfile_path), "build.sh") : nil
    
    [dockerfile_path, build_sh]
  end

  def self.extract_version(build_sh)
    return "latest" unless build_sh && File.exist?(build_sh)
    
    content = File.read(build_sh)
    if match = content.match(/IMG_VERS\s*=\s*"?([^"\s\n]+)"?/)
      match[1]
    elsif match = content.match(/VERSION\s*=\s*"?([^"\s\n]+)"?/)
      match[1]
    elsif match = content.match(/TAG\s*=\s*"?([^"\s\n]+)"?/)
      match[1]
    elsif match = content.match(/-t\s+[^\s:]+:([a-zA-Z0-9_.-]+)/)
      extracted = match[1]
      extracted == 'latest' ? 'latest' : extracted
    else
      "latest"
    end
  end

  def self.patch_version(build_sh, new_ver)
    return false unless new_ver && !new_ver.strip.empty? && build_sh && File.exist?(build_sh)
    
    content = File.read(build_sh)
    new_ver = new_ver.strip
    updated = false
    
    if content.match?(/IMG_VERS\s*=\s*"?([^"\s\n]+)"?/)
      content.gsub!(/(IMG_VERS\s*=\s*"?)[^"\s\n]+("?)/, "\\1#{new_ver}\\2")
      updated = true
    elsif content.match?(/VERSION\s*=\s*"?([^"\s\n]+)"?/)
      content.gsub!(/(VERSION\s*=\s*"?)[^"\s\n]+("?)/, "\\1#{new_ver}\\2")
      updated = true
    elsif content.match?(/TAG\s*=\s*"?([^"\s\n]+)"?/)
      content.gsub!(/(TAG\s*=\s*"?)[^"\s\n]+("?)/, "\\1#{new_ver}\\2")
      updated = true
    elsif content.match?(/-t\s+[^\s:]+:([a-zA-Z0-9_.-]+)/)
      content.gsub!(/(-t\s+[^\s:]+:)[a-zA-Z0-9_.-]+/, "\\1#{new_ver}")
      updated = true
    end
    
    File.write(build_sh, content) if updated
    updated
  end

  def self.create_skeleton(image_path)
    path = image_path.to_s.gsub(/[^a-zA-Z0-9_\-\/]/, '')
    full_dir = File.join(IMAGES_DIR, path)
    
    raise "Directory already exists" if File.directory?(full_dir)

    FileUtils.mkdir_p(full_dir)
    File.write(File.join(full_dir, "Dockerfile"), "FROM ubuntu:latest\n# Add your instructions here\n")
    
    build_sh = File.join(full_dir, "build.sh")
    File.write(build_sh, "#!/bin/bash\n# Replace with podman/docker build command\necho 'Build script for #{path}'\n")
    FileUtils.chmod(0755, build_sh)
  end

  def self.unload_local_image(image_path)
    clean_path = image_path.to_s.gsub(/[^a-zA-Z0-9_\-\/]/, '')
    full_dir = File.join(IMAGES_DIR, clean_path)

    raise "Image directory not found" unless File.directory?(full_dir)

    parts = clean_path.split('/')
    img_name = parts.size > 1 ? "ctlabs/#{parts[1..-1].join('/')}" : "ctlabs/#{clean_path}"

    build_sh = File.join(full_dir, "build.sh")
    if File.exist?(build_sh) && match = File.read(build_sh).match(/IMG_NAME\s*=\s*"?([^"\s\n]+)"?/)
      img_name = match[1]
    end

    tags = `podman images --format '{{.Repository}}:{{.Tag}}' #{img_name} 2>/dev/null`.split("\n").map(&:strip)
    tags += `docker images --format '{{.Repository}}:{{.Tag}}' #{img_name} 2>/dev/null`.split("\n").map(&:strip)
    
    tags.uniq.each do |tag|
      next if tag.empty? || tag == "<none>:<none>"
      `podman rmi #{tag} 2>/dev/null`
      `docker rmi #{tag} 2>/dev/null`
    end
    
    `podman rmi #{img_name}:latest 2>/dev/null`
    `docker rmi #{img_name}:latest 2>/dev/null`
  end

  def self.context_tree(df_path)
    img_dir = File.dirname(df_path)
    files = []
    if Dir.exist?(img_dir)
      Dir.glob(File.join(img_dir, "**", "*")).each do |file|
        next if File.directory?(file)
        next if file.include?('/.git/') || file.end_with?('/Dockerfile') || file.end_with?('/build.sh')
        files << file.sub(img_dir + '/', '')
      end
    end
    files.sort
  end

  def self.read_context_file(df_path, filepath)
    img_dir = File.dirname(df_path)
    full_path = File.join(img_dir, filepath)
    File.file?(full_path) ? File.read(full_path) : "# New file: #{filepath}\n"
  end

  def self.write_context_files(df_path, files_hash)
    img_dir = File.dirname(df_path)
    files_hash.each do |filepath, content|
      next if filepath.include?('..') || filepath.start_with?('/') 
      full_path = File.join(img_dir, filepath)
      FileUtils.mkdir_p(File.dirname(full_path))
      File.write(full_path, content)
      FileUtils.chmod("+x", full_path) if filepath.end_with?('.sh') || filepath.end_with?('.py')
    end
  end

  def self.delete_context_file(df_path, filepath)
    img_dir = File.dirname(df_path)
    full_path = File.join(img_dir, filepath)
    File.delete(full_path) if File.exist?(full_path)
  end
end
