# -----------------------------------------------------------------------------
# File        : ctlabs/helpers/image_helper.rb
# License     : MIT License
# -----------------------------------------------------------------------------

module ImageHelper
  require 'fileutils'

  # Finds the Dockerfile and build.sh path based on the image string
  def resolve_image_paths(image_name)
    image = image_name.to_s.split(':').first
    search_path = image.split('/').last(2).join('/')
    dockerfile_path = Dir.glob(File.join("..", "images", "**", search_path, "Dockerfile")).first
    build_sh = dockerfile_path ? File.join(File.dirname(dockerfile_path), "build.sh") : nil
    
    [dockerfile_path, build_sh]
  end

  # Scans build.sh for the version/tag variables
  def extract_image_version(build_sh)
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

  # Updates the version/tag in build.sh
  def patch_image_version(build_sh, new_ver)
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

  # Creates a fresh image directory skeleton
  def create_image_skeleton(image_path)
    path = image_path.to_s.gsub(/[^a-zA-Z0-9_\-\/]/, '')
    full_dir = File.join("..", "images", path)
    
    raise "Directory already exists" if File.directory?(full_dir)

    FileUtils.mkdir_p(full_dir)
    File.write(File.join(full_dir, "Dockerfile"), "FROM ubuntu:latest\n# Add your instructions here\n")
    
    build_sh = File.join(full_dir, "build.sh")
    File.write(build_sh, "#!/bin/bash\n# Replace with podman/docker build command\necho 'Build script for #{path}'\n")
    FileUtils.chmod(0755, build_sh)
  end

  # Unloads all tags for a local image from the container registry
  def unload_local_image(image_path)
    clean_path = image_path.to_s.gsub(/[^a-zA-Z0-9_\-\/]/, '')
    full_dir = File.join("..", "images", clean_path)

    raise "Image directory not found" unless File.directory?(full_dir) && full_dir.include?("../images/")

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
end
