# -----------------------------------------------------------------------------
# File        : ctlabs/services/recording_service.rb
# Description : Asciicast (v2) storage for terminal walkthrough recordings
# License     : MIT License
# -----------------------------------------------------------------------------
#
# A recording is a plain asciicast v2 file: one JSON header line followed by
# newline-delimited events `[time, "o", data]` (output) and `[time, "r",
# "COLSxROWS"]` (resize). That is exactly what the vendored asciinema player
# reads, and the files remain portable to `asciinema play` / `asciinema cat`
# outside the web UI.
#
# Recordings live OUTSIDE the public/ tree and are served by
# RecordingsController, so they are behind the same basic-auth as every other
# page and the file name can never escape the directory.

require 'json'
require 'time'
require 'securerandom'
require 'fileutils'
require 'base64'
require_relative 'recording_git_service'

class RecordingService
  BASE_DIR        = '/srv/ctlabs-server/recordings'
  DIR             = BASE_DIR
  IMAGES_DIR      = File.join(BASE_DIR, 'images')
  REPOS_BASE_DIR  = '/srv/ctlabs-server/walkthrough-repos'
  REPOS_MANIFEST  = File.join(REPOS_BASE_DIR, '_repos.json')
  REPO_SLUG_RE    = /\A[a-zA-Z0-9_-]{1,120}\z/
  EXT             = '.cast'
  MD_EXT          = '.md'
  VIDEO_EXTS      = ['.webm', '.mp4'].freeze
  VIDEO_EXT       = '.webm'
  IMAGE_EXTS      = ['.png', '.jpg', '.jpeg', '.gif', '.svg', '.webp', '.jxl'].freeze
  DIAGRAM_EXTS    = ['.svg', '.png'].freeze
  DOT_EXT         = '.dot'
  IMAGE_REF_RE    = %r{(?<![\w.-])images/([a-zA-Z0-9_.-]+)}
  MANIFEST        = '_walkthrough.json'
  LEGACY_MANIFEST = '_walkthroughs.json'
  ID_RE           = /\A[a-zA-Z0-9_.-]{1,120}\z/
  NODE_MAX        = 40
  NAME_MAX        = 80
  TAIL_BYTES      = 8192

  @repo_mutex = Mutex.new

  # --- Repository Container Management (Multiple Sets per Repository) --------

  def self.valid_repo_slug?(slug)
    s = slug.to_s.strip
    !s.empty? && !s.include?('..') && !!(s =~ REPO_SLUG_RE)
  end

  def self.repo_slug_for(name)
    s = name.to_s.strip.downcase.gsub(/[^a-z0-9_-]+/, '_').gsub(/\A_+|_+\z/, '')[0, 80]
    s.empty? ? "repo_#{SecureRandom.hex(3)}" : s
  end

  def self.repo_dir(repo_slug = nil)
    target = repo_slug.to_s.strip
    target = active_repo if target.empty?
    return BASE_DIR if target == 'default' || !valid_repo_slug?(target)

    File.join(REPOS_BASE_DIR, target)
  end

  def self.dir
    repo_dir(active_repo)
  end

  def self.images_dir
    File.join(dir, 'images')
  end

  def self.load_repositories
    FileUtils.mkdir_p(BASE_DIR) unless Dir.exist?(BASE_DIR)
    FileUtils.mkdir_p(REPOS_BASE_DIR) unless Dir.exist?(REPOS_BASE_DIR)

    parsed = if File.file?(REPOS_MANIFEST)
               begin
                 JSON.parse(File.read(REPOS_MANIFEST))
               rescue StandardError
                 nil
               end
             end
    parsed = {} unless parsed.is_a?(Hash)

    repos = parsed['repos'].is_a?(Hash) ? parsed['repos'].dup : {}
    repos['default'] ||= {
      'name'       => 'Local Workspace',
      'created_at' => (File.mtime(BASE_DIR).to_f rescue Time.now.to_f)
    }

    # Auto-discover any repository directory under REPOS_BASE_DIR
    begin
      Dir.children(REPOS_BASE_DIR).sort.each do |entry|
        next if entry.start_with?('.', '_')
        next unless valid_repo_slug?(entry)
        p = File.join(REPOS_BASE_DIR, entry)
        next unless File.directory?(p)

        repos[entry] ||= {
          'name'       => entry.tr('_-', ' '),
          'created_at' => (File.mtime(p).to_f rescue Time.now.to_f)
        }
      end
    rescue StandardError
    end

    # Remove stale entries whose directories no longer exist
    repos.keys.each do |rslug|
      next if rslug == 'default'
      repos.delete(rslug) unless File.directory?(File.join(REPOS_BASE_DIR, rslug))
    end

    active = parsed['active'].to_s.strip
    active = 'default' if active.empty? || !repos.key?(active)

    state = { 'active' => active, 'repos' => repos }
    if parsed['active'] != active || parsed['repos'] != repos
      save_repositories(state)
    end
    state
  end

  def self.save_repositories(state)
    FileUtils.mkdir_p(REPOS_BASE_DIR) unless Dir.exist?(REPOS_BASE_DIR)
    File.write(REPOS_MANIFEST, JSON.pretty_generate(state))
    File.chmod(0600, REPOS_MANIFEST) rescue nil
  rescue StandardError
    nil
  end

  def self.active_repo
    load_repositories['active']
  rescue StandardError
    'default'
  end

  def self.active_repo_name
    state = load_repositories
    active = state['active']
    entry = state.dig('repos', active) || {}
    name = entry['name'].to_s.strip
    name.empty? ? active : name
  rescue StandardError
    'Local Workspace'
  end

  def self.repository_set_count(repo_slug)
    rdir = repo_dir(repo_slug)
    return 0 unless File.directory?(rdir)

    Dir.children(rdir).count do |entry|
      p = File.join(rdir, entry)
      File.directory?(p) && !entry.start_with?('.', '_') && entry != 'images'
    end
  rescue StandardError
    0
  end

  def self.repositories_summary
    state = load_repositories
    active = state['active']
    state['repos'].map do |rslug, info|
      rdir = repo_dir(rslug)
      remote_url = nil
      branch = nil
      if defined?(WalkthroughGitService) && File.directory?(File.join(rdir, '.git'))
        remote_url = WalkthroughGitService.redact_url(WalkthroughGitService.remote_url_for_dir(rdir)) rescue nil
        branch = WalkthroughGitService.current_branch_for_dir(rdir) rescue nil
      end
      {
        'slug'       => rslug,
        'name'       => (info['name'].to_s.strip.empty? ? rslug : info['name'].to_s.strip),
        'active'     => (rslug == active),
        'set_count'  => repository_set_count(rslug),
        'remote'     => remote_url,
        'branch'     => branch,
        'created_at' => info['created_at']
      }
    end
  end

  def self.switch_repository(repo_slug)
    clean = repo_slug.to_s.strip
    return false if clean.empty?

    state = load_repositories
    return false unless state['repos'].key?(clean)

    state['active'] = clean
    save_repositories(state)
    ensure_dir
    RecordingGitService.ensure_repo! if defined?(RecordingGitService)
    load_walkthroughs
    true
  end

  def self.register_repository(repo_slug, name: nil, switch: true)
    clean_slug = (repo_slug.to_s.strip == 'default') ? 'default' : repo_slug_for(repo_slug)
    rdir = repo_dir(clean_slug)
    FileUtils.mkdir_p(rdir)

    state = load_repositories
    display_name = name.to_s.strip[0, NAME_MAX]
    display_name = (clean_slug == 'default' ? 'Local Workspace' : clean_slug) if display_name.empty?

    existing = state['repos'][clean_slug] || {}
    state['repos'][clean_slug] = existing.merge(
      'name'       => display_name,
      'created_at' => (existing['created_at'] || Time.now.to_f)
    )
    state['active'] = clean_slug if switch
    save_repositories(state)
    clean_slug
  end

  def self.create_repository(name, slug: nil, switch: true)
    clean_name = name.to_s.strip[0, NAME_MAX]
    clean_name = 'New Repository' if clean_name.empty?
    base_slug  = slug.to_s.strip.empty? ? repo_slug_for(clean_name) : repo_slug_for(slug)
    base_slug  = "repo_#{base_slug}" if base_slug == 'default'

    state = load_repositories
    candidate = base_slug
    idx = 2
    while state['repos'].key?(candidate) || File.exist?(repo_dir(candidate))
      candidate = "#{base_slug}_#{idx}"
      idx += 1
    end

    register_repository(candidate, name: clean_name, switch: switch)
    if switch
      RecordingGitService.ensure_repo! if defined?(RecordingGitService)
      load_walkthroughs
      RecordingGitService.commit("Initialize repository '#{clean_name}' (#{candidate})") rescue nil
    end
    candidate
  end

  def self.rename_repository(repo_slug, new_name)
    clean_slug = repo_slug.to_s.strip
    clean_slug = active_repo if clean_slug.empty?
    state = load_repositories
    return nil unless state['repos'].key?(clean_slug)

    clean_name = new_name.to_s.strip[0, NAME_MAX]
    state['repos'][clean_slug]['name'] = clean_name unless clean_name.empty?
    save_repositories(state)
    [clean_slug, state['repos'][clean_slug]['name']]
  end

  def self.delete_repository(repo_slug)
    clean_slug = repo_slug.to_s.strip
    return false if clean_slug.empty? || clean_slug == 'default'

    state = load_repositories
    return false unless state['repos'].key?(clean_slug)

    rdir = repo_dir(clean_slug)
    FileUtils.rm_rf(rdir) if File.directory?(rdir) && rdir.start_with?(REPOS_BASE_DIR + '/')
    keys_dir = File.join(REPOS_BASE_DIR, '.keys')
    Dir.glob(File.join(keys_dir, "#{clean_slug}*")).each { |f| FileUtils.rm_f(f) } if Dir.exist?(keys_dir)

    state['repos'].delete(clean_slug)
    state['active'] = 'default' if state['active'] == clean_slug
    save_repositories(state)
    true
  end

  def self.ensure_dir
    d = dir
    FileUtils.mkdir_p(d) unless Dir.exist?(d)
    d
  rescue SystemCallError
    dir
  end

  def self.walkthrough_dir(slug)
    d = ensure_dir
    clean = slug_for(slug.to_s)
    File.join(d, clean)
  end

  def self.ensure_images_dir(slug = nil)
    ensure_dir
    target = slug ? File.join(walkthrough_dir(slug), 'images') : images_dir
    FileUtils.mkdir_p(target) unless Dir.exist?(target)
    target
  rescue SystemCallError
    target
  end

  def self.images_dir_for(walkthrough)
    if walkthrough && !walkthrough.to_s.empty?
      ensure_images_dir(walkthrough)
    else
      wks = load_walkthroughs rescue {}
      first_slug = wks.keys.first
      first_slug ? ensure_images_dir(first_slug) : ensure_images_dir
    end
  end

  def self.save_image(tempfile_or_path, original_filename, walkthrough: nil)
    ext = File.extname(original_filename.to_s).downcase
    ext = '.png' unless IMAGE_EXTS.include?(ext)

    clean_base = File.basename(original_filename.to_s, ext).gsub(/[^a-zA-Z0-9_-]+/, '_')[0, 30]
    clean_base = 'img' if clean_base.empty?
    timestamp  = Time.now.strftime('%Y%m%d-%H%M%S')
    token      = SecureRandom.hex(3)
    filename   = "#{clean_base}_#{timestamp}_#{token}#{ext}"

    target_dir = images_dir_for(walkthrough)

    FileUtils.mkdir_p(target_dir)
    target = File.join(target_dir, filename)

    if ext == '.svg'
      raw_bytes = if tempfile_or_path.respond_to?(:path)
                    File.binread(tempfile_or_path.path)
                  elsif tempfile_or_path.respond_to?(:read)
                    tempfile_or_path.rewind if tempfile_or_path.respond_to?(:rewind)
                    tempfile_or_path.read
                  else
                    File.binread(tempfile_or_path.to_s)
                  end

      if raw_bytes.start_with?("\x89PNG".b)
        w, h = raw_bytes[16, 8].unpack('NN') rescue [800, 600]
        w = 800 if !w || w.zero?
        h = 600 if !h || h.zero?
        b64 = Base64.strict_encode64(raw_bytes)
        svg_content = <<~SVG
          <?xml version="1.0" encoding="UTF-8" standalone="no"?>
          <svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="#{w}" height="#{h}" viewBox="0 0 #{w} #{h}">
            <image width="#{w}" height="#{h}" xlink:href="data:image/png;base64,#{b64}"/>
          </svg>
        SVG
        File.binwrite(target, svg_content)
      else
        if tempfile_or_path.respond_to?(:path)
          FileUtils.cp(tempfile_or_path.path, target)
        else
          FileUtils.cp(tempfile_or_path.to_s, target)
        end
      end
    else
      if tempfile_or_path.respond_to?(:path)
        FileUtils.cp(tempfile_or_path.path, target)
      else
        FileUtils.cp(tempfile_or_path.to_s, target)
      end
    end
    File.chmod(0644, target) rescue nil

    # Keep a copy in global images_dir only when not scoped to a walkthrough
    if walkthrough.to_s.strip.empty?
      begin
        ensure_images_dir
        legacy_target = File.join(images_dir, filename)
        FileUtils.cp(target, legacy_target) unless target == legacy_target
      rescue StandardError
      end
    end

    RecordingGitService.commit("Save image '#{filename}'#{walkthrough ? " in '#{walkthrough}'" : ''}", files: [target], slug: walkthrough) rescue nil

    filename
  end

  def self.save_annotated_image(tempfile_or_path, original_filename, walkthrough: nil, mode: 'overwrite')
    clean = File.basename(original_filename.to_s)
    return nil if clean.empty? || clean.include?('..')

    ext = File.extname(clean).downcase
    ext = '.png' unless IMAGE_EXTS.include?(ext)

    target_dir = images_dir_for(walkthrough)
    FileUtils.mkdir_p(target_dir)

    if mode == 'overwrite'
      target = image_path(clean, walkthrough: walkthrough) || File.join(target_dir, clean)
      out_filename = File.basename(target)
    else
      clean_base = File.basename(clean, ext).gsub(/[^a-zA-Z0-9_-]+/, '_')[0, 30]
      clean_base = 'img' if clean_base.empty?
      clean_base = clean_base.sub(/_annotated(_\d+)?\z/, '')
      timestamp  = Time.now.strftime('%Y%m%d-%H%M%S')
      out_filename = "#{clean_base}_annotated_#{timestamp}#{ext}"
      target = File.join(target_dir, out_filename)
    end

    if ext == '.svg'
      raw_bytes = if tempfile_or_path.respond_to?(:path)
                    File.binread(tempfile_or_path.path)
                  elsif tempfile_or_path.respond_to?(:read)
                    tempfile_or_path.rewind if tempfile_or_path.respond_to?(:rewind)
                    tempfile_or_path.read
                  else
                    File.binread(tempfile_or_path.to_s)
                  end

      if raw_bytes.start_with?("\x89PNG".b)
        w, h = raw_bytes[16, 8].unpack('NN') rescue [800, 600]
        w = 800 if !w || w.zero?
        h = 600 if !h || h.zero?
        b64 = Base64.strict_encode64(raw_bytes)
        svg_content = <<~SVG
          <?xml version="1.0" encoding="UTF-8" standalone="no"?>
          <svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="#{w}" height="#{h}" viewBox="0 0 #{w} #{h}">
            <image width="#{w}" height="#{h}" xlink:href="data:image/png;base64,#{b64}"/>
          </svg>
        SVG
        File.binwrite(target, svg_content)
      else
        if tempfile_or_path.respond_to?(:path)
          FileUtils.cp(tempfile_or_path.path, target)
        else
          FileUtils.cp(tempfile_or_path.to_s, target)
        end
      end
    else
      if tempfile_or_path.respond_to?(:path)
        FileUtils.cp(tempfile_or_path.path, target)
      else
        FileUtils.cp(tempfile_or_path.to_s, target)
      end
    end
    File.chmod(0644, target) rescue nil

    if walkthrough.to_s.strip.empty?
      begin
        ensure_images_dir
        legacy_target = File.join(images_dir, out_filename)
        FileUtils.cp(target, legacy_target) unless target == legacy_target
      rescue StandardError
      end
    end

    RecordingGitService.commit("Save annotated image '#{out_filename}'#{walkthrough ? " in '#{walkthrough}'" : ''}", files: [target], slug: walkthrough) rescue nil

    { filename: out_filename, mode: mode }
  end

  def self.diagram_base_valid?(base)
    clean = base.to_s.strip
    return false if clean.empty? || clean.include?('..') || clean.include?('/') || clean.include?('\\')
    return false if clean.start_with?('.') || clean.end_with?('.')
    return false unless clean.match?(/\A[a-zA-Z0-9_.-]{1,80}\z/)

    !%w[. ..].include?(clean)
  end

  def self.save_diagram(rendered, original_name, walkthrough: nil, source: nil, format: 'svg', base: nil)
    ext = ".#{format.to_s.downcase}"
    ext = '.svg' unless DIAGRAM_EXTS.include?(ext)

    clean_base = base.to_s.strip.sub(/\.(svg|png|dot|jpe?g|webp)\z/i, '')
    clean_base = '' unless diagram_base_valid?(clean_base)

    if clean_base.empty?
      clean_base = File.basename(original_name.to_s).sub(/\.(svg|png|dot|jpe?g|webp)\z/i, '').gsub(/[^a-zA-Z0-9_.-]+/, '_').strip[0, 60]
      clean_base = 'diagram' if clean_base.empty? || !diagram_base_valid?(clean_base)
    end

    filename   = "#{clean_base}#{ext}"
    target_dir = images_dir_for(walkthrough)
    FileUtils.mkdir_p(target_dir)
    target = File.join(target_dir, filename)

    data = rendered.respond_to?(:read) ? rendered.read : rendered.to_s
    File.binwrite(target, data)
    File.chmod(0644, target) rescue nil
    File.write(File.join(target_dir, "#{clean_base}#{DOT_EXT}"), source.to_s, mode: 'wb') unless source.nil?

    if walkthrough.to_s.strip.empty?
      begin
        ensure_images_dir
        [filename, "#{clean_base}#{DOT_EXT}"].each do |name|
          src = File.join(target_dir, name)
          dst = File.join(images_dir, name)
          FileUtils.cp(src, dst) if File.file?(src) && src != dst
        end
      rescue StandardError
      end
    end

    dot_target = File.join(target_dir, "#{clean_base}#{DOT_EXT}")
    commit_files = [target]
    commit_files << dot_target if File.file?(dot_target)
    RecordingGitService.commit("Save diagram '#{clean_base}'#{walkthrough ? " in '#{walkthrough}'" : ''}", files: commit_files, slug: walkthrough) rescue nil

    { 'filename' => filename, 'base' => clean_base }
  end

  def self.diagram_sources(slug)
    key, = walkthrough_entry(slug)
    dir = ensure_images_dir(key)

    Dir.glob(File.join(dir, "*#{DOT_EXT}")).filter_map do |path|
      next unless File.file?(path)

      base = File.basename(path, DOT_EXT)
      next unless diagram_base_valid?(base)

      svg = File.join(dir, "#{base}.svg")
      png = File.join(dir, "#{base}.png")
      image = if File.file?(svg)
                "#{base}.svg"
              elsif File.file?(png)
                "#{base}.png"
              end

      {
        'base'       => base,
        'filename'   => image,
        'url'        => image ? "/recordings/images/#{image}" : nil,
        'updated_at' => File.mtime(path).to_i
      }
    end.sort_by { |entry| -entry['updated_at'] }
  end

  def self.diagram_source(slug, base)
    return nil unless diagram_base_valid?(base)

    key, = walkthrough_entry(slug)
    path = File.join(ensure_images_dir(key), "#{base}#{DOT_EXT}")
    return nil unless File.file?(path)

    File.read(path, encoding: 'UTF-8')
  end

  def self.rename_diagram(slug, old_base, new_base)
    key, = walkthrough_entry(slug)
    old_clean = old_base.to_s.strip
    new_clean = new_base.to_s.strip
    return { ok: false, error: 'Invalid current diagram name' } unless diagram_base_valid?(old_clean)
    return { ok: false, error: 'Invalid new diagram name' } unless diagram_base_valid?(new_clean)
    return { ok: true, old_base: old_clean, new_base: new_clean } if old_clean == new_clean

    scoped_dir = ensure_images_dir(key)
    old_dot = File.join(scoped_dir, "#{old_clean}#{DOT_EXT}")
    new_dot = File.join(scoped_dir, "#{new_clean}#{DOT_EXT}")

    return { ok: false, error: "Diagram '#{new_clean}' already exists" } if File.exist?(new_dot)
    return { ok: false, error: "Source diagram '#{old_clean}' not found" } unless File.exist?(old_dot)

    # Rename .dot and images in scoped dir
    FileUtils.mv(old_dot, new_dot) if File.exist?(old_dot)
    old_svg = File.join(scoped_dir, "#{old_clean}.svg")
    new_svg = File.join(scoped_dir, "#{new_clean}.svg")
    FileUtils.mv(old_svg, new_svg) if File.exist?(old_svg)
    old_png = File.join(scoped_dir, "#{old_clean}.png")
    new_png = File.join(scoped_dir, "#{new_clean}.png")
    FileUtils.mv(old_png, new_png) if File.exist?(old_png)

    # Also rename in global images dir if present
    global_dir = ensure_images_dir
    g_new_dot = nil
    if scoped_dir != global_dir
      g_old_dot = File.join(global_dir, "#{old_clean}#{DOT_EXT}")
      g_new_dot = File.join(global_dir, "#{new_clean}#{DOT_EXT}")
      FileUtils.mv(g_old_dot, g_new_dot) if File.exist?(g_old_dot) && !File.exist?(g_new_dot)
      g_old_svg = File.join(global_dir, "#{old_clean}.svg")
      g_new_svg = File.join(global_dir, "#{new_clean}.svg")
      FileUtils.mv(g_old_svg, g_new_svg) if File.exist?(g_old_svg) && !File.exist?(g_new_svg)
      g_old_png = File.join(global_dir, "#{old_clean}.png")
      g_new_png = File.join(global_dir, "#{new_clean}.png")
      FileUtils.mv(g_old_png, g_new_png) if File.exist?(g_old_png) && !File.exist?(g_new_png)
    end

    # If the renamed .dot file starts with header "# File: <old_clean>", update it
    [new_dot, g_new_dot].compact.uniq.each do |dot_file|
      next unless File.file?(dot_file)
      content = begin
        File.read(dot_file, encoding: 'UTF-8')
      rescue StandardError
        nil
      end
      next unless content

      header_regex = /\A(#[ \t]*-{40,}[ \t]*\r?\n#[ \t]*File:[ \t]*)#{Regexp.escape(old_clean)}([ \t]*\r?\n#[ \t]*-{40,}[ \t]*\r?\n?)/
      if content.match?(header_regex)
        updated = content.sub(header_regex, "\\1#{new_clean}\\2")
        File.write(dot_file, updated, encoding: 'UTF-8')
      end
    end

    # Update references in all markdown notes of this walkthrough
    Dir.glob(File.join(walkthrough_dir(key), "*#{MD_EXT}")).each do |note_path|
      next unless File.file?(note_path)
      content = begin
        File.read(note_path, encoding: 'UTF-8')
      rescue StandardError
        nil
      end
      next unless content

      updated = content.gsub("#{old_clean}.svg", "#{new_clean}.svg")
                       .gsub("#{old_clean}.png", "#{new_clean}.png")
                       .gsub("#{old_clean}#{DOT_EXT}", "#{new_clean}#{DOT_EXT}")
      File.write(note_path, updated, encoding: 'UTF-8') if updated != content
    end

    RecordingGitService.commit("Rename diagram '#{old_clean}' to '#{new_clean}' in '#{key}'", slug: key) rescue nil

    { ok: true, old_base: old_clean, new_base: new_clean, filename: "#{new_clean}.svg" }
  end

  def self.image_path(filename, walkthrough: nil)
    clean = File.basename(filename.to_s)
    return nil if clean.empty? || clean.include?('..')

    # 1. Check scoped walkthrough's images/
    if walkthrough && !walkthrough.to_s.empty?
      target = File.join(walkthrough_dir(walkthrough), 'images', clean)
      return target if File.file?(target)
    end

    # 2. Check all walkthrough images directories, picking the newest if multiple sets have it
    candidates = Dir.glob(File.join(dir, '*', 'images', clean)).select { |p| File.file?(p) }
    if candidates.any?
      return candidates.max_by { |p| File.mtime(p).to_f rescue 0 }
    end

    # 3. Check legacy/global images directory
    legacy = File.join(ensure_images_dir, clean)
    return legacy if File.file?(legacy)

    # 4. Check root DIR directly
    direct = File.join(ensure_dir, clean)
    return direct if File.file?(direct)

    nil
  end

  # Maps image filename => [recording ids that reference it] for one set.
  # Only markdown steps/notes can reference pictures, so scan every .md file in
  # the set directory (including files not yet adopted into the manifest).
  def self.image_references(slug)
    refs = Hash.new { |h, k| h[k] = [] }
    Dir.glob(File.join(walkthrough_dir(slug), "*#{MD_EXT}")).each do |path|
      next unless File.file?(path)

      id = File.basename(path, MD_EXT)
      content = begin
        File.read(path, encoding: 'UTF-8')
      rescue StandardError
        ''
      end
      content.scan(IMAGE_REF_RE).flatten.uniq.each { |name| refs[name] << id }
    end
    refs
  end

  # Inventory of the pictures belonging to one walkthrough set. Each entry
  # reports whether it is used by any note, which steps use it, and whether a
  # referenced file is missing.
  def self.image_inventory(slug)
    key, entry, = walkthrough_entry(slug)
    scoped_dir = ensure_images_dir(key)
    global_dir = ensure_images_dir
    refs = image_references(key)

    titles = {}
    Dir.glob(File.join(walkthrough_dir(key), "*#{MD_EXT}")).each do |path|
      m = meta(path)
      titles[m[:id]] = m[:title] if m
    end

    step_positions = {}
    Array(entry['recording_ids']).each_with_index { |id, i| step_positions[id.to_s] = i + 1 }

    names = Dir.children(scoped_dir).select do |name|
      path = File.join(scoped_dir, name)
      File.file?(path) && IMAGE_EXTS.include?(File.extname(name).downcase)
    end
    refs.each_key { |name| names << name unless names.include?(name) }

    names.uniq.sort.map do |name|
      scoped_path = File.join(scoped_dir, name)
      global_path = File.join(global_dir, name)
      in_scoped = File.file?(scoped_path)
      in_global = File.file?(global_path)
      used_by = Array(refs[name]).uniq.map do |id|
        {
          'id'    => id,
          'title' => (titles[id] || id).to_s,
          'step'  => step_positions[id]
        }
      end

      sidecar_base = File.basename(name, File.extname(name))
      has_dot = File.file?(File.join(scoped_dir, "#{sidecar_base}#{DOT_EXT}")) ||
                File.file?(File.join(global_dir, "#{sidecar_base}#{DOT_EXT}"))

      {
        'filename'     => name,
        'size'         => in_scoped ? File.size(scoped_path) : (in_global ? File.size(global_path) : 0),
        'scoped'       => in_scoped,
        'global_only'  => !in_scoped && in_global,
        'missing'      => !in_scoped && !in_global,
        'used'         => used_by.any?,
        'used_by'      => used_by,
        'diagram'      => has_dot,
        'diagram_base' => (has_dot ? sidecar_base : nil)
      }
    end
  end

  # Removes an unused picture from a set's images/ directory. Refuses to delete
  # a picture that is still referenced by a note in this set, or one that
  # another set needs and cannot resolve through the global fallback.
  def self.delete_image(slug, filename)
    clean = filename.to_s
    return false if clean.empty? || clean != File.basename(clean) || clean.include?('..')
    return false unless IMAGE_EXTS.include?(File.extname(clean).downcase)

    key, = walkthrough_entry(slug)
    return false if image_references(key).key?(clean)

    path = File.join(ensure_images_dir(key), clean)
    return false unless File.file?(path)

    if other_sets_reference_image?(clean, except_slug: key) && !File.file?(File.join(ensure_images_dir, clean))
      return false
    end

    File.delete(path)

    sidecar_base   = File.basename(clean, File.extname(clean))
    scoped_sidecar = File.join(ensure_images_dir(key), "#{sidecar_base}#{DOT_EXT}")
    File.delete(scoped_sidecar) if File.file?(scoped_sidecar)

    unless other_sets_reference_image?(clean, except_slug: key)
      global_sidecar = File.join(images_dir, "#{sidecar_base}#{DOT_EXT}")
      File.delete(global_sidecar) if File.file?(global_sidecar)
    end

    RecordingGitService.commit("Delete image '#{clean}' from '#{key}'", files: [path, scoped_sidecar], slug: key) rescue nil

    true
  rescue SystemCallError
    false
  end

  def self.other_sets_reference_image?(filename, except_slug:)
    load_walkthroughs.keys.any? do |slug|
      next false if slug == except_slug

      image_references(slug).key?(filename)
    end
  end

  def self.delete_unused_images(slug)
    image_inventory(slug).count do |img|
      next false if img['used'] || img['missing'] || !img['scoped']

      delete_image(slug, img['filename'])
    end
  end

  # The public id is the basename without extension. It travels in URLs, so
  # never allow separators or a traversal sequence.
  def self.valid_id?(id)
    s = id.to_s
    !s.empty? && !s.include?('..') && !!(s =~ ID_RE)
  end

  def self.path_for(id, walkthrough: nil)
    return nil unless valid_id?(id)
    base = id.to_s

    candidate_dirs = []
    if walkthrough && !walkthrough.to_s.empty?
      candidate_dirs << walkthrough_dir(walkthrough)
    end

    cur_dir = dir
    all_set_dirs = begin
      Dir.children(cur_dir).filter_map do |d|
        p = File.join(cur_dir, d)
        p if File.directory?(p) && !d.start_with?('.', '_') && d != 'images'
      end
    rescue StandardError
      []
    end

    candidate_dirs.concat(all_set_dirs)
    candidate_dirs << cur_dir
    candidate_dirs.uniq!

    # Direct match if extension already provided
    if base.end_with?(EXT) || base.end_with?(MD_EXT) || VIDEO_EXTS.any? { |e| base.end_with?(e) } || IMAGE_EXTS.any? { |e| base.end_with?(e) }
      candidate_dirs.each do |cdir|
        p = File.join(cdir, base)
        return p if File.file?(p)
        p_img = File.join(cdir, 'images', base)
        return p_img if File.file?(p_img)
      end
      p_root_img = File.join(ensure_images_dir, base)
      return p_root_img if File.file?(p_root_img)
      return nil
    end

    # Check candidate dirs for .cast, .md, and video extensions
    candidate_dirs.each do |cdir|
      cast_p = File.join(cdir, "#{base}#{EXT}")
      return cast_p if File.file?(cast_p)

      md_p = File.join(cdir, "#{base}#{MD_EXT}")
      return md_p if File.file?(md_p)

      VIDEO_EXTS.each do |vext|
        v_p = File.join(cdir, "#{base}#{vext}")
        return v_p if File.file?(v_p)
      end
    end

    nil
  end

  def self.walkthrough_for(id_or_path)
    clean_id = File.basename(id_or_path.to_s, '.*')
    path = id_or_path.to_s.include?('/') ? id_or_path.to_s : path_for(id_or_path)
    if path && File.exist?(path)
      parent = File.dirname(path)
      cur_dir = dir
      if parent != cur_dir && parent.start_with?(cur_dir)
        slug = File.basename(parent)
        return slug unless slug == 'images'
      end
    end

    # Fallback: scan walkthrough manifests for recording or unintegrated id
    wks = load_walkthroughs rescue {}
    wks.each do |slug, entry|
      r_ids = Array(entry['recording_ids']).map(&:to_s)
      u_ids = Array(entry['unintegrated_ids']).map(&:to_s)
      return slug if r_ids.include?(clean_id) || u_ids.include?(clean_id)
    end

    nil
  end

  def self.node_slug(node)
    node.to_s.gsub(/[^a-zA-Z0-9_.-]+/, '_').gsub(/\A_+|_+\z/, '')[0, NODE_MAX].to_s
  end

  def self.new_id(node)
    "#{Time.now.strftime('%Y%m%d-%H%M%S')}_#{node_slug(node)}_#{SecureRandom.hex(3)}"
  end

  def self.new_markdown_id(label = 'note')
    "md_#{Time.now.strftime('%Y%m%d-%H%M%S')}_#{node_slug(label)}_#{SecureRandom.hex(3)}"
  end

  def self.new_video_id(label = 'screen')
    "vid_#{Time.now.strftime('%Y%m%d-%H%M%S')}_#{node_slug(label)}_#{SecureRandom.hex(3)}"
  end

  def self.all_disk_files(slug = nil)
    cur_dir = ensure_dir
    patterns = if slug
                 sdir = walkthrough_dir(slug)
                 [File.join(sdir, "*#{EXT}"), File.join(sdir, "*#{MD_EXT}")] +
                   VIDEO_EXTS.map { |ext| File.join(sdir, "*#{ext}") }
               else
                 [File.join(cur_dir, '*', "*#{EXT}"), File.join(cur_dir, '*', "*#{MD_EXT}"),
                  File.join(cur_dir, "*#{EXT}"), File.join(cur_dir, "*#{MD_EXT}")] +
                   VIDEO_EXTS.flat_map { |ext| [File.join(cur_dir, '*', "*#{ext}"), File.join(cur_dir, "*#{ext}")] }
               end
    patterns.flat_map { |pat| Dir.glob(pat) }
            .reject { |p| File.basename(p).start_with?('_') }
            .uniq
  end

  # Opens a recording, writes the asciicast v2 header and returns [id, io].
  # The caller owns the io and must close it when recording stops.
  def self.open(node:, cols: nil, rows: nil, title: nil, walkthrough: nil)
    ensure_dir
    id         = new_id(node)
    target_dir = if walkthrough && !walkthrough.to_s.empty?
                   walkthrough_dir(walkthrough)
                 else
                   wks = load_walkthroughs rescue {}
                   walkthrough_dir(wks.keys.first || 'walkthrough_1')
                 end
    FileUtils.mkdir_p(target_dir)
    path = File.join(target_dir, "#{id}#{EXT}")
    io   = File.open(path, 'wb')

    header = {
      'version'   => 2,
      'width'     => positive_int(cols, 120),
      'height'    => positive_int(rows, 40),
      'timestamp' => Time.now.to_i,
      'title'     => title.to_s.empty? ? node.to_s : title.to_s,
      'command'   => 'ctlabs web terminal',
      'env'       => { 'TERM' => 'xterm-256color', 'SHELL' => '/bin/bash' },
      # Non-standard, ignored by the player: lets the list page know the node
      # even if the file name is ever renamed by hand.
      'ctlabs'    => { 'node' => node.to_s, 'recorder' => 'ctlabs' }
    }
    io.write(JSON.generate(header) + "\n")
    io.flush
    [id, io]
  rescue StandardError
    io&.close rescue nil
    raise
  end

  def self.positive_int(value, fallback)
    n = value.to_i
    n.positive? ? n : fallback
  end

  # Newest first.
  def self.list
    ensure_dir
    all_disk_files
       .filter_map { |path| meta(path) }
       .sort_by { |m| [m[:created_at], m[:id]] }
       .reverse
  end

  def self.meta(path)
    return nil unless File.file?(path)

    if path.end_with?(MD_EXT)
      id   = File.basename(path, MD_EXT)
      size = File.size(path)
      meta_file = File.join(File.dirname(path), "#{id}.json")
      meta_file = File.join(dir, "#{id}.json") unless File.file?(meta_file)
      meta_data = {}
      if File.file?(meta_file)
        begin
          meta_data = JSON.parse(File.read(meta_file))
        rescue StandardError
          meta_data = {}
        end
      end
      meta_data = {} unless meta_data.is_a?(Hash)

      title = meta_data['title'].to_s.strip
      if title.empty?
        content = begin
          File.read(path, encoding: 'UTF-8')
        rescue StandardError
          ''
        end
        content.to_s.lines.each do |line|
          l = line.strip
          next if l.empty?
          title = l.sub(/^#+\s*/, '').strip
          break
        end
        title = 'Step Note' if title.empty?

        begin
          init_data = {
            'title'      => title,
            'type'       => 'markdown',
            'created_at' => File.mtime(path).to_i
          }
          target_meta = File.join(File.dirname(path), "#{id}.json")
          File.write(target_meta, JSON.pretty_generate(init_data))
        rescue StandardError
        end
      end

      created_at = meta_data['created_at'] ? Time.at(meta_data['created_at'].to_i) : File.mtime(path)

      return {
        id:         id,
        path:       path,
        node:       'Markdown',
        title:      title,
        type:       :markdown,
        created_at: created_at,
        duration:   0.0,
        size:       size
      }
    end

    if VIDEO_EXTS.any? { |e| path.end_with?(e) }
      ext  = File.extname(path)
      id   = File.basename(path, ext)
      size = File.size(path)
      meta_file = File.join(File.dirname(path), "#{id}.json")
      meta_file = File.join(dir, "#{id}.json") unless File.file?(meta_file)
      meta_data = {}
      if File.file?(meta_file)
        begin
          meta_data = JSON.parse(File.read(meta_file))
        rescue StandardError
          meta_data = {}
        end
      end
      meta_data = {} unless meta_data.is_a?(Hash)
      title = meta_data['title'].to_s.strip
      title = 'Browser Recording' if title.empty?
      duration = meta_data['duration'].to_f
      created_at = meta_data['created_at'] ? Time.at(meta_data['created_at'].to_i) : File.mtime(path)

      return {
        id:         id,
        path:       path,
        node:       'Screen',
        title:      title,
        type:       :video,
        created_at: created_at,
        duration:   duration,
        size:       size
      }
    end

    id   = File.basename(path, EXT)
    size = File.size(path)

    header = begin
      first = File.open(path, 'rb') { |f| f.gets }
      first ? JSON.parse(first) : {}
    rescue StandardError
      {}
    end
    header = {} unless header.is_a?(Hash)

    created_at = begin
      Time.at(Integer(header['timestamp']))
    rescue StandardError
      File.mtime(path)
    end

    {
      id:         id,
      path:       path,
      node:       header.dig('ctlabs', 'node') || node_from_id(id),
      title:      header['title'].to_s,
      type:       :cast,
      cols:       header['width'],
      rows:       header['height'],
      created_at: created_at,
      duration:   last_event_time(path, size),
      size:       size
    }
  end

  # Duration is the timestamp of the last event. Only the tail is read, so
  # listing a library of multi-megabyte casts stays cheap; a partially-read
  # first line simply fails to parse and is skipped.
  def self.last_event_time(path, size)
    return 0.0 if size.to_i <= 0

    tail = File.open(path, 'rb') do |f|
      f.seek([size - TAIL_BYTES, 0].max)
      f.read
    end

    tail.to_s.lines.reverse_each do |line|
      line = line.strip
      next if line.empty?
      begin
        event = JSON.parse(line)
      rescue StandardError
        next
      end
      return event[0].to_f if event.is_a?(Array) && event[0].is_a?(Numeric)
    end
    0.0
  rescue StandardError
    0.0
  end

  # `<date>-<time>_<node>_<random>` -> node.
  def self.node_from_id(id)
    parts = id.to_s.split('_')
    parts.length >= 3 ? parts[1] : id.to_s
  end

  # Reads the ctlabs.node hint from a cast header (if the file has one). The
  # client-side recorder did not always write it, so callers must still fall
  # back to the file name.
  def self.node_from_cast(data)
    first = data.to_s.lines.first
    return nil unless first

    header = JSON.parse(first)
    return nil unless header.is_a?(Hash)

    node = header.dig('ctlabs', 'node').to_s.strip
    node.empty? ? nil : node
  rescue StandardError
    nil
  end

  def self.delete(id)
    path = path_for(id)
    return false unless path
    fdir = File.dirname(path)
    File.delete(path) rescue nil

    # Clean up sidecar metadata if present
    base_id = File.basename(path, File.extname(path))
    sidecar = File.join(fdir, "#{base_id}.json")
    File.delete(sidecar) if File.file?(sidecar)
    root_sidecar = File.join(dir, "#{base_id}.json")
    File.delete(root_sidecar) if File.file?(root_sidecar)

    # Clean up references across all walkthrough sets
    wks = load_walkthroughs
    changed = false
    wks.each_value do |entry|
      current = Array(entry['recording_ids']).map(&:to_s)
      if current.include?(id.to_s)
        entry['recording_ids'] = current - [id.to_s]
        changed = true
      end
      unintegrated = (Array(entry['unintegrated_ids']) + Array(entry['excluded_ids'])).map(&:to_s)
      if unintegrated.include?(id.to_s)
        entry['unintegrated_ids'] = unintegrated - [id.to_s]
        entry.delete('excluded_ids')
        changed = true
      end
    end
    save_walkthroughs(wks) if changed
    RecordingGitService.commit("Delete step '#{id}'") rescue nil
    true
  rescue SystemCallError
    false
  end

  # --- View formatting -------------------------------------------------------

  def self.duration_label(seconds)
    total = seconds.to_f
    return '0s' if total <= 0
    return format('%.1fs', total) if total < 60

    minutes, secs = total.divmod(60)
    return format('%dm %02ds', minutes, secs) if minutes < 60

    hours, minutes = minutes.divmod(60)
    format('%dh %02dm', hours, minutes)
  end

  def self.size_label(bytes)
    b = bytes.to_i
    return '0 B' if b <= 0
    return "#{b} B" if b < 1024

    units = %w[KB MB GB TB]
    value = b.to_f / 1024
    unit  = 0
    while value >= 1024 && unit < units.length - 1
      value /= 1024
      unit  += 1
    end
    format('%.1f %s', value, units[unit])
  end


  # Updates the title in the JSON header of the .cast file or heading of .md file
  def self.update_meta(id, title:)
    path = path_for(id)
    return false unless path

    if path.end_with?(MD_EXT)
      id_clean = File.basename(path, MD_EXT)
      dir = File.dirname(path)
      meta_file = File.join(dir, "#{id_clean}.json")
      meta_data = {}
      if File.file?(meta_file)
        begin
          meta_data = JSON.parse(File.read(meta_file))
        rescue StandardError
          meta_data = {}
        end
      end
      meta_data = {} unless meta_data.is_a?(Hash)
      clean_title = title.to_s.strip
      clean_title = 'Step Note' if clean_title.empty?
      meta_data['title'] = clean_title
      meta_data['type'] ||= 'markdown'
      meta_data['created_at'] ||= File.mtime(path).to_i
      File.write(meta_file, JSON.pretty_generate(meta_data))
      RecordingGitService.commit("Update note '#{id}' title to '#{clean_title}'", files: [meta_file]) rescue nil
      return true
    end

    if VIDEO_EXTS.any? { |e| path.end_with?(e) }
      ext = File.extname(path)
      id_clean = File.basename(path, ext)
      dir = File.dirname(path)
      meta_file = File.join(dir, "#{id_clean}.json")
      meta_data = {}
      if File.file?(meta_file)
        begin
          meta_data = JSON.parse(File.read(meta_file))
        rescue StandardError
          meta_data = {}
        end
      end
      meta_data = {} unless meta_data.is_a?(Hash)
      clean_title = title.to_s.strip
      meta_data['title'] = clean_title.empty? ? 'Browser Recording' : clean_title
      meta_data['type'] ||= 'video'
      meta_data['created_at'] ||= File.mtime(path).to_i
      File.write(meta_file, JSON.pretty_generate(meta_data))
      return true
    end

    lines = File.readlines(path)
    return false if lines.empty?

    header = begin
      JSON.parse(lines[0])
    rescue StandardError
      nil
    end
    return false unless header.is_a?(Hash)

    header['title'] = title.to_s
    lines[0] = JSON.generate(header) + "\n"

    File.write(path, lines.join)
    RecordingGitService.commit("Update recording '#{id}' title to '#{title}'", files: [path]) rescue nil
    true
  rescue StandardError
    false
  end

  def self.create_markdown_step(slug, title: 'Step Note', content: nil)
    id = new_markdown_id('note')
    target_dir = walkthrough_dir(slug)
    FileUtils.mkdir_p(target_dir)
    path = File.join(target_dir, "#{id}#{MD_EXT}")
    clean_title = title.to_s.strip
    clean_title = 'Step Note' if clean_title.empty?
    initial_content = content || "# #{clean_title}\n\nAdd your step notes or instructions here.\n"
    File.write(path, initial_content, encoding: 'UTF-8')

    meta_file = File.join(target_dir, "#{id}.json")
    meta_data = {
      'title'      => clean_title,
      'type'       => 'markdown',
      'created_at' => File.mtime(path).to_i
    }
    File.write(meta_file, JSON.pretty_generate(meta_data))

    add_to_walkthrough(slug, [id])
    RecordingGitService.commit("Create note '#{clean_title}' (#{id}) in '#{slug}'", files: [path, meta_file, File.join(target_dir, MANIFEST)], slug: slug) rescue nil
    id
  end

  def self.read_content(id)
    path = path_for(id)
    return nil unless path && path.end_with?(MD_EXT)
    File.read(path, encoding: 'UTF-8')
  rescue StandardError
    nil
  end

  def self.update_content(id, content, commit: false, commit_message: nil)
    path = path_for(id)
    return false unless path && path.end_with?(MD_EXT)
    File.write(path, content.to_s, encoding: 'UTF-8')
    if commit
      msg = commit_message.to_s.strip
      msg = "Update note '#{id}'" if msg.empty?
      RecordingGitService.commit(msg, files: [path]) rescue nil
    end
    true
  rescue StandardError
    false
  end

  # Saves the drag-and-drop custom order array to an index file
  def self.reorder!(ordered_ids)
    cur_dir = ensure_dir
    order_file = File.join(cur_dir, '_order.json')
    File.write(order_file, JSON.generate(ordered_ids))
    true
  rescue StandardError
    false
  end

  # Lists recordings ordered by saved drag-and-drop sequence, falling back to newest first
  def self.list
    cur_dir = ensure_dir
    files = all_disk_files
    recs = files.filter_map { |path| meta(path) }

    order_file = File.join(cur_dir, '_order.json')
    if File.file?(order_file)
      begin
        ordered_ids = JSON.parse(File.read(order_file))
        if ordered_ids.is_a?(Array)
          recs.sort_by! do |r|
            idx = ordered_ids.index(r[:id])
            idx ? idx : 999999
          end
        end
      rescue StandardError
        recs.sort_by! { |m| [m[:created_at], m[:id]] }.reverse!
      end
    else
      recs.sort_by! { |m| [m[:created_at], m[:id]] }.reverse!
    end

    recs
  end


  # --- Walkthrough Collections Management ---
  #
  # Each walkthrough set lives in its own dedicated directory on disk:
  #   DIR/<walkthrough_slug>/
  #
  # Inside each directory:
  #   - `_walkthrough.json`: Manifest scoped to this set (name, step order, unintegrated ids).
  #   - Media files (.cast, .md, .webm, .mp4, and .json sidecars) belonging to this set.
  #   - `images/`: Directory for images attached to notes in this set.

  def self.walkthroughs_file
    File.join(ensure_dir, LEGACY_MANIFEST)
  end

  def self.migrate_to_folder_hierarchy!
    cur_dir = ensure_dir
    legacy_file = File.join(cur_dir, LEGACY_MANIFEST)
    return unless File.file?(legacy_file)

    data = begin
      JSON.parse(File.read(legacy_file))
    rescue StandardError
      nil
    end
    return unless data.is_a?(Hash) && !data.empty?

    data.each do |slug, entry|
      wk_dir = File.join(cur_dir, slug)
      wk_images_dir = File.join(wk_dir, 'images')
      FileUtils.mkdir_p(wk_images_dir)

      all_ids = (Array(entry['recording_ids']) + Array(entry['unintegrated_ids'])).map(&:to_s).uniq
      all_ids.each do |id|
        [EXT, MD_EXT, *VIDEO_EXTS].each do |ext|
          src = File.join(cur_dir, "#{id}#{ext}")
          if File.file?(src)
            dst = File.join(wk_dir, "#{id}#{ext}")
            FileUtils.mv(src, dst) unless src == dst

            # Move sidecar if exists
            sidecar_src = File.join(cur_dir, "#{id}.json")
            if File.file?(sidecar_src)
              FileUtils.mv(sidecar_src, File.join(wk_dir, "#{id}.json"))
            end

            # If markdown, scan for images and copy them into set's images/
            if ext == MD_EXT
              content = File.read(dst) rescue ''
              imgs = content.scan(%r{(?:(?:recordings?/+)+|/)?images/([a-zA-Z0-9_.-]+)}).flatten.uniq
              imgs.each do |img|
                img_src = File.join(cur_dir, 'images', img)
                if File.file?(img_src)
                  FileUtils.cp(img_src, File.join(wk_images_dir, img)) rescue nil
                end
              end
            end
            break
          end
        end
      end

      # Write per-set manifest
      manifest = {
        'name'             => entry['name'].to_s,
        'created_at'       => entry['created_at'] || Time.now.to_f,
        'recording_ids'    => Array(entry['recording_ids']).map(&:to_s),
        'unintegrated_ids' => Array(entry['unintegrated_ids']).map(&:to_s)
      }
      File.write(File.join(wk_dir, MANIFEST), JSON.pretty_generate(manifest))
    end

    # Move any remaining orphan files in root cur_dir into the first walkthrough set
    first_slug = data.keys.first
    if first_slug
      first_dir = File.join(cur_dir, first_slug)
      first_manifest = File.join(first_dir, MANIFEST)
      first_data = JSON.parse(File.read(first_manifest)) rescue nil

      if first_data
        orphan_files = (Dir.glob(File.join(cur_dir, "*#{EXT}")) +
                        Dir.glob(File.join(cur_dir, "*#{MD_EXT}")) +
                        VIDEO_EXTS.flat_map { |ext| Dir.glob(File.join(cur_dir, "*#{ext}")) })
                       .reject { |p| File.basename(p).start_with?('_') }

        orphan_ids = []
        orphan_files.each do |p|
          ext = File.extname(p)
          oid = File.basename(p, ext)
          dst = File.join(first_dir, "#{oid}#{ext}")
          FileUtils.mv(p, dst) rescue nil
          sidecar = File.join(cur_dir, "#{oid}.json")
          FileUtils.mv(sidecar, File.join(first_dir, "#{oid}.json")) if File.file?(sidecar)
          orphan_ids << oid
        end

        if orphan_ids.any?
          first_data['unintegrated_ids'] = (Array(first_data['unintegrated_ids']).map(&:to_s) + orphan_ids).uniq
          File.write(first_manifest, JSON.pretty_generate(first_data))
        end
      end
    end

    # Rename legacy index file to .migrated so migration only runs once
    FileUtils.mv(legacy_file, "#{legacy_file}.migrated") rescue nil
  end

  def self.load_walkthroughs
    cur_dir = ensure_dir
    migrate_to_folder_hierarchy! if File.file?(File.join(cur_dir, LEGACY_MANIFEST))

    data = {}
    # Scan subdirectories that contain _walkthrough.json
    slug_dirs = begin
      Dir.children(cur_dir).select do |entry|
        p = File.join(cur_dir, entry)
        File.directory?(p) && !entry.start_with?('.', '_') && entry != 'images'
      end.sort
    rescue StandardError
      []
    end

    slug_dirs.each do |slug|
      manifest_file = File.join(cur_dir, slug, MANIFEST)
      if File.file?(manifest_file)
        begin
          parsed = JSON.parse(File.read(manifest_file))
          if parsed.is_a?(Hash)
            data[slug] = {
              'name'             => parsed['name'].to_s,
              'created_at'       => parsed['created_at'] || File.mtime(manifest_file).to_f,
              'recording_ids'    => Array(parsed['recording_ids']).map(&:to_s),
              'unintegrated_ids' => Array(parsed['unintegrated_ids']).map(&:to_s)
            }
          end
        rescue StandardError
        end
      end

      # Directory without manifest: discover or initialize
      unless data.key?(slug)
        manifest_data = {
          'name'             => slug.tr('_-', ' ').capitalize,
          'created_at'       => File.mtime(File.join(cur_dir, slug)).to_f,
          'recording_ids'    => [],
          'unintegrated_ids' => []
        }
        data[slug] = manifest_data
        save_walkthrough(slug, manifest_data)
      end
    end

    # Auto-adopt any files sitting in DIR/<slug> that aren't listed in recording_ids or unintegrated_ids
    data.each do |slug, entry|
      disk_ids = all_disk_files(slug).map { |f| File.basename(f, File.extname(f)) }
      known = (Array(entry['recording_ids']) + Array(entry['unintegrated_ids'])).map(&:to_s)
      unclaimed = disk_ids - known
      if unclaimed.any?
        entry['unintegrated_ids'] = (Array(entry['unintegrated_ids']).map(&:to_s) + unclaimed).uniq
        save_walkthrough(slug, entry)
      end
    end

    # Fallback if no sets exist
    if data.empty?
      default_slug = 'walkthrough_1'
      data[default_slug] = {
        'name'             => 'Walkthrough 1',
        'created_at'       => Time.now.to_f,
        'recording_ids'    => [],
        'unintegrated_ids' => []
      }
      save_walkthrough(default_slug, data[default_slug])
    end

    data
  end

  def self.save_walkthrough(slug, entry)
    dir = walkthrough_dir(slug)
    FileUtils.mkdir_p(dir)
    manifest_file = File.join(dir, MANIFEST)
    cleaned = {
      'name'             => entry['name'].to_s,
      'created_at'       => entry['created_at'] || Time.now.to_f,
      'recording_ids'    => Array(entry['recording_ids']).map(&:to_s),
      'unintegrated_ids' => (Array(entry['unintegrated_ids']) + Array(entry['excluded_ids'])).map(&:to_s).uniq - Array(entry['recording_ids']).map(&:to_s)
    }
    File.write(manifest_file, JSON.pretty_generate(cleaned))
  end

  def self.save_walkthroughs(walkthroughs)
    walkthroughs.each do |slug, entry|
      save_walkthrough(slug, entry)
    end
  end

  def self.slug_for(name)
    slug = name.to_s.strip.downcase.gsub(/[^a-z0-9_-]+/, '_')
    slug.empty? ? "walkthrough_#{SecureRandom.hex(3)}" : slug
  end

  def self.walkthrough_entry(slug, walkthroughs = nil)
    wks   = walkthroughs || load_walkthroughs
    key   = if wks.key?(slug.to_s)
              slug.to_s
            elsif wks.any?
              wks.keys.first.to_s
            else
              'walkthrough_1'
            end
    entry = wks[key] ||= { 'name' => 'Walkthrough 1', 'recording_ids' => [], 'unintegrated_ids' => [] }
    [key, entry, wks]
  end

  def self.walkthrough_name(slug = 'default')
    _key, entry = walkthrough_entry(slug)
    entry['name'].to_s
  end

  def self.walkthrough_sealed?(_slug = 'default')
    false
  end

  def self.rename_walkthrough(slug, name)
    key, entry, wks = walkthrough_entry(slug)
    clean = name.to_s.strip[0, NAME_MAX]
    entry['name'] = clean unless clean.empty?
    save_walkthrough(key, entry)
    RecordingGitService.commit("Rename walkthrough '#{key}' to '#{entry['name']}'", files: [File.join(walkthrough_dir(key), MANIFEST)], slug: key) rescue nil
    [key, entry['name'].to_s]
  end

  def self.create_walkthrough(name, recording_ids: [], unintegrated_ids: [], unique: false, overwrite: false, slug: nil)
    wks   = load_walkthroughs
    clean = name.to_s.strip[0, NAME_MAX]
    clean = 'New Walkthrough' if clean.empty?
    base  = slug.to_s.strip.empty? ? slug_for(clean) : slug_for(slug)

    if wks.key?(base)
      if overwrite
        # Proceed with overwriting base walkthrough entry
      elsif unique
        base = "#{base}_#{SecureRandom.hex(3)}"
        base = "#{base}_#{SecureRandom.hex(3)}" while wks.key?(base)
      else
        return base
      end
    end

    recs   = Array(recording_ids).map(&:to_s).uniq
    unints = (Array(unintegrated_ids).map(&:to_s) - recs).uniq

    wk_dir = walkthrough_dir(base)
    FileUtils.mkdir_p(wk_dir)
    FileUtils.mkdir_p(File.join(wk_dir, 'images'))

    entry = {
      'name'             => clean,
      'recording_ids'    => recs,
      'unintegrated_ids' => unints,
      'created_at'       => (overwrite && wks[base] && wks[base]['created_at']) || Time.now.to_f
    }
    save_walkthrough(base, entry)
    wks[base] = entry
    RecordingGitService.commit("#{overwrite ? 'Update' : 'Create'} walkthrough '#{clean}' (#{base})", files: [File.join(wk_dir, MANIFEST)], slug: base) rescue nil
    base
  end

  # Appends ids to a set's steps without duplicating membership.
  # Moves files into target walkthrough directory if they live elsewhere.
  def self.add_to_walkthrough(slug, recording_ids)
    key, entry, wks = walkthrough_entry(slug)
    wanted  = Array(recording_ids).map(&:to_s)
    target_dir = walkthrough_dir(key)
    FileUtils.mkdir_p(target_dir)

    wanted.each do |id|
      current_path = path_for(id)
      if current_path && File.file?(current_path)
        current_dir = File.dirname(current_path)
        if current_dir != target_dir
          ext = File.extname(current_path)
          FileUtils.mv(current_path, File.join(target_dir, "#{id}#{ext}")) rescue nil
          sidecar = File.join(current_dir, "#{id}.json")
          if File.file?(sidecar)
            FileUtils.mv(sidecar, File.join(target_dir, "#{id}.json")) rescue nil
          end
        end
      end
    end

    wks.each do |k, other_entry|
      next if k == key
      other_entry['recording_ids'] = Array(other_entry['recording_ids']).map(&:to_s) - wanted
      other_entry['unintegrated_ids'] = (Array(other_entry['unintegrated_ids']) + Array(other_entry['excluded_ids'])).map(&:to_s) - wanted
      other_entry.delete('excluded_ids')
      save_walkthrough(k, other_entry)
    end

    current = Array(entry['recording_ids']).map(&:to_s)
    entry['recording_ids'] = current + (wanted - current)
    unint = (Array(entry['unintegrated_ids']) + Array(entry['excluded_ids'])).map(&:to_s)
    entry['unintegrated_ids'] = unint - wanted
    entry.delete('excluded_ids')
    save_walkthrough(key, entry)
    RecordingGitService.commit("Add steps to '#{key}'", slug: key) rescue nil
    key
  end

  def self.list_for_walkthrough(slug = 'default')
    wks = load_walkthroughs
    key, wk, = walkthrough_entry(slug, wks)
    allowed_ids = Array(wk['recording_ids']).map(&:to_s)

    all_recs = all_disk_files(key)
                  .filter_map { |path| meta(path) }
                  .sort_by { |m| [m[:created_at], m[:id]] }
                  .reverse
    recs_map = all_recs.map { |r| [r[:id], r] }.to_h

    allowed_ids.filter_map do |id|
      recs_map[id] || (path = path_for(id); path ? meta(path) : nil)
    end
  end

  # Returns recordings that belong to this walkthrough set but are not integrated as steps.
  def self.list_unintegrated_for_walkthrough(slug = 'default')
    wks = load_walkthroughs
    key, wk, = walkthrough_entry(slug, wks)
    step_ids = Array(wk['recording_ids']).map(&:to_s)
    unint_ids = (Array(wk['unintegrated_ids']) + Array(wk['excluded_ids'])).map(&:to_s).uniq - step_ids

    all_recs = all_disk_files(key)
                  .filter_map { |path| meta(path) }
                  .sort_by { |m| [m[:created_at], m[:id]] }
                  .reverse
    recs_map = all_recs.map { |r| [r[:id], r] }.to_h

    unint_ids.filter_map do |id|
      recs_map[id] || (path = path_for(id); path ? meta(path) : nil)
    end
  end

  class << self
    alias list_other_recordings list_unintegrated_for_walkthrough
  end

  # Returns a hash mapping recording_id => true for all recordings that are
  # members of ANY walkthrough set (steps or unintegrated).
  def self.all_set_member_ids(walkthroughs = nil)
    wks = walkthroughs || load_walkthroughs
    member_ids = {}
    wks.each_value do |entry|
      (Array(entry['recording_ids']) + Array(entry['unintegrated_ids']) + Array(entry['excluded_ids'])).each do |id|
        member_ids[id.to_s] = true
      end
    end
    member_ids
  end

  # Deletes a complete walkthrough set directory. If delete_recordings is true,
  # the directory and all contained files are permanently removed. If false,
  # the directory is archived as _archived_<slug>_<timestamp>.
  def self.delete_walkthrough(slug, delete_recordings: false)
    wks = load_walkthroughs
    slug_str = slug.to_s
    return false unless wks.key?(slug_str)

    wdir = walkthrough_dir(slug_str)
    if delete_recordings
      FileUtils.rm_rf(wdir) if File.directory?(wdir)
    else
      if File.directory?(wdir)
        archived_dir = File.join(dir, "_archived_#{slug_str}_#{Time.now.strftime('%Y%m%d_%H%M%S')}")
        FileUtils.mv(wdir, archived_dir) rescue nil
      end
    end

    if load_walkthroughs.empty?
      create_walkthrough('Walkthrough 1')
    end

    RecordingGitService.commit("Delete walkthrough '#{slug_str}'") rescue nil

    true
  end

  def self.update_walkthrough_order(slug, ordered_ids)
    key, entry, wks = walkthrough_entry(slug)
    ordered = Array(ordered_ids).map(&:to_s)

    wks.each do |k, other_entry|
      next if k == key
      other_entry['recording_ids'] = Array(other_entry['recording_ids']).map(&:to_s) - ordered
      other_entry['unintegrated_ids'] = (Array(other_entry['unintegrated_ids']) + Array(other_entry['excluded_ids'])).map(&:to_s) - ordered
      other_entry.delete('excluded_ids')
      save_walkthrough(k, other_entry)
    end

    current = Array(entry['recording_ids']).map(&:to_s)
    removed = current - ordered

    entry['recording_ids'] = ordered
    unint = (Array(entry['unintegrated_ids']) + Array(entry['excluded_ids'])).map(&:to_s)
    entry['unintegrated_ids'] = (unint + removed).uniq - ordered
    entry.delete('excluded_ids')

    save_walkthrough(key, entry)
    RecordingGitService.commit("Update step order in '#{key}'", files: [File.join(walkthrough_dir(key), MANIFEST)], slug: key) rescue nil
    key
  end

  def self.remove_from_walkthrough(slug, recording_id, order: nil)
    key, entry, wks = walkthrough_entry(slug)
    id = recording_id.to_s
    current = Array(entry['recording_ids']).map(&:to_s)
    remaining = order.nil? ? (current - [id]) : (Array(order).map(&:to_s) - [id])
    entry['recording_ids'] = remaining

    unint = (Array(entry['unintegrated_ids']) + Array(entry['excluded_ids'])).map(&:to_s)
    entry['unintegrated_ids'] = (unint + [id]).uniq - remaining
    entry.delete('excluded_ids')

    save_walkthrough(key, entry)
    RecordingGitService.commit("Remove step '#{id}' from '#{key}'", files: [File.join(walkthrough_dir(key), MANIFEST)], slug: key) rescue nil
    key
  end

  def self.recording_in_sealed_walkthrough?(_id)
    false
  end

  # Everything the ZIP export needs: the resolved set name/membership, in the
  # exact order the page shows them.
  def self.export_bundle(slug = 'default')
    key, entry = walkthrough_entry(slug)
    {
      slug:         key,
      name:         entry['name'].to_s,
      sealed:       false,
      recordings:   list_for_walkthrough(key),
      unintegrated: list_unintegrated_for_walkthrough(key),
      dir:          walkthrough_dir(key)
    }
  end

  # Formats numeric dimension to include standard 'px' unit for Pandoc attributes
  def self.format_docx_dimension(val)
    return nil if val.nil? || val.to_s.strip.empty?
    v = val.to_s.strip
    v =~ /\A\d+\z/ ? "#{v}px" : v
  end

  # Preprocesses Markdown content specifically for Pandoc DOCX export:
  # - Translates extended markdown image dimensions (e.g. =400, =400x300, =50%) to Pandoc attributes {width=... height=...}
  # - Translates Obsidian pipe syntax dimensions (e.g. ![alt|400](...), ![400](...)) to Pandoc attributes
  # - Normalizes curly attribute dimensions (e.g. {width=400}, {400x300})
  # - Converts HTML <img> tags with width/height/style to Markdown images with Pandoc attributes
  # - Resolves relative / scoped image paths to absolute filesystem paths on disk so Pandoc embeds them into DOCX
  def self.preprocess_markdown_for_docx(content, walkthrough: nil)
    # 1. Convert HTML <img> tags to Markdown images with attributes
    processed = content.to_s.gsub(/<img\s+([^>]+)>/i) do |match|
      attrs_str = $1
      src = attrs_str[/src=["']?([^"'\s>]+)["']?/i, 1]
      next match unless src

      alt = attrs_str[/alt=["']([^"']*)["']/i, 1] || ''
      w = attrs_str[/width=["']?(\d+(?:%|px)?)["']?/i, 1]
      h = attrs_str[/height=["']?(\d+(?:%|px)?)["']?/i, 1]

      if (style = attrs_str[/style=["']([^"']*)["']/i, 1])
        w ||= style[/width\s*:\s*(\d+(?:%|px|in|cm)?)/i, 1]
        h ||= style[/height\s*:\s*(\d+(?:%|px|in|cm)?)/i, 1]
      end

      attr_list = []
      attr_list << "width=#{format_docx_dimension(w)}" if w
      attr_list << "height=#{format_docx_dimension(h)}" if h
      attr_suffix = attr_list.empty? ? '' : "{#{attr_list.join(' ')}}"

      "![#{alt}](#{src})#{attr_suffix}"
    end

    # 2. Process Markdown images: ![alt](target){attrs}
    processed.gsub(/!\[(?<alt>[^\]]*)\]\((?<target>[^)]+)\)(?:\{(?<attrs>[^}]+)\})?/) do
      alt = $~[:alt] || ''
      target = $~[:target] || ''
      attrs = $~[:attrs]

      width = nil
      height = nil
      clean_alt = alt.strip

      # Check target for =WxH or =W (e.g. "path/to/img.png =400x300" or "path/to/img.png =400")
      if target =~ /\s+=(\d+(?:%|px)?)(?:\s*x\s*(\d+(?:%|px)?))?/i
        width = $1
        height = $2
        target = target.sub(/\s+=(\d+(?:%|px)?)(?:\s*x\s*(\d+(?:%|px)?))?/i, '').strip
      end

      # Check curly attrs if present
      other_attrs = []
      if attrs && !attrs.strip.empty?
        attrs_trimmed = attrs.strip
        if (dim_m = attrs_trimmed.match(/\A(\d+(?:%|px)?)\s*x\s*(\d+(?:%|px)?)\z/i))
          width ||= dim_m[1]
          height ||= dim_m[2]
        elsif (single_m = attrs_trimmed.match(/\A(\d+(?:%|px)?)\z/i))
          width ||= single_m[1]
        else
          # Key-value attrs: width=..., height=...
          if (w_m = attrs_trimmed.match(/width\s*[:=]\s*["']?(\d+(?:%|px|in|cm)?)["']?/i))
            width ||= w_m[1]
          end
          if (h_m = attrs_trimmed.match(/height\s*[:=]\s*["']?(\d+(?:%|px|in|cm)?)["']?/i))
            height ||= h_m[1]
          end
          # Retain other attributes (classes, IDs, etc.)
          cleaned = attrs_trimmed.gsub(/width\s*[:=]\s*["']?(\d+(?:%|px|in|cm)?)["']?/i, '')
                                 .gsub(/height\s*[:=]\s*["']?(\d+(?:%|px|in|cm)?)["']?/i, '')
                                 .strip
          other_attrs << cleaned unless cleaned.empty?
        end
      end

      # Check alt for Obsidian pipe syntax (e.g. "alt text|400x300", "alt text|400", "400x300", "400")
      if clean_alt =~ /\A(.*)\|(.*)\z/
        clean_alt = $1.strip
        dim_candidate = $2.strip
        if (dim_m = dim_candidate.match(/\A(\d+(?:%|px)?)\s*x\s*(\d+(?:%|px)?)\z/i))
          width ||= dim_m[1]
          height ||= dim_m[2]
        elsif dim_candidate =~ /\A\d+(?:%|px)?\z/i
          width ||= dim_candidate
        end
      elsif clean_alt =~ /\A(\d+(?:%|px)?)\s*x\s*(\d+(?:%|px)?)\z/i
        width ||= $1
        height ||= $2
        clean_alt = ''
      elsif clean_alt =~ /\A\d+(?:%|px)?\z/i
        width ||= clean_alt
        clean_alt = ''
      end

      # Extract URL and optional title from target
      url = target
      title_part = ''
      if target =~ /\A(\S+)\s+(["'].*)\z/
        url = $1
        title_part = " #{$2}"
      end

      # Resolve image path to real filesystem path if not already an existing file
      unless File.file?(url)
        if url =~ %r{(?:(?:\.?/)?(?:recordings?/+)+|(?:\./)?|/)images/([a-zA-Z0-9_.-]+)}
          img_name = $1
          real_path = image_path(img_name, walkthrough: walkthrough)
          url = real_path if real_path && File.file?(real_path)
        end
      end

      attr_list = []
      attr_list << "width=#{format_docx_dimension(width)}" if width
      attr_list << "height=#{format_docx_dimension(height)}" if height
      attr_list.concat(other_attrs) unless other_attrs.empty?

      attr_suffix = attr_list.empty? ? '' : "{#{attr_list.join(' ')}}"

      "![#{clean_alt}](#{url}#{title_part})#{attr_suffix}"
    end
  end

  # Converts Markdown content into a Microsoft Word (.docx) document via pandoc,
  # embedding all referenced images directly into the document.
  def self.convert_markdown_to_docx(content, filename: nil, walkthrough: nil)
    require 'open3'
    require 'tmpdir'

    pandoc_bin = `which pandoc 2>/dev/null`.strip
    if pandoc_bin.empty? || !File.executable?(pandoc_bin)
      return { ok: false, error: 'pandoc is not installed on the system. Please ensure pandoc is installed.' }
    end

    # Clean up older export note docx files (>1 hour old)
    Dir.glob(File.join(dir, 'export_note_*_*.docx')).each do |old_docx|
      File.delete(old_docx) rescue nil if File.mtime(old_docx) < (Time.now - 3600)
    end

    clean_name = if filename && !filename.to_s.strip.empty?
                   File.basename(filename.to_s.strip).gsub(/[^a-zA-Z0-9_.-]+/, '_').sub(/\A_+/, '').sub(/_+\z/, '')
                 else
                   "note_#{Time.now.strftime('%Y%m%d_%H%M%S')}.docx"
                 end
    clean_name = "#{clean_name}.docx" unless clean_name.downcase.end_with?('.docx')

    target_docx = File.join(dir, "export_note_#{SecureRandom.hex(4)}_#{clean_name}")

    # Preprocess markdown to convert extended image syntax (=400, pipe, curly, html)
    # and resolve image paths so pandoc embeds them with correct dimensions into DOCX
    rewritten = preprocess_markdown_for_docx(content, walkthrough: walkthrough)

    Dir.mktmpdir('ctlabs-docx') do |tmpdir|
      tmp_md = File.join(tmpdir, 'input.md')
      File.write(tmp_md, rewritten, encoding: 'UTF-8')

      stdout, stderr, status = Open3.capture3(pandoc_bin, '-f', 'markdown', '-t', 'docx', '-o', target_docx, tmp_md)
      unless status.success? && File.file?(target_docx)
        err_msg = stderr.strip.empty? ? 'Unknown error during pandoc conversion' : stderr.strip
        return { ok: false, error: "Failed to convert Markdown to DOCX: #{err_msg}" }
      end
    end

    { ok: true, path: target_docx }
  rescue StandardError => e
    { ok: false, error: "DOCX generation error: #{e.message}" }
  end
end
