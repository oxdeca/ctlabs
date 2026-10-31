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

class RecordingService
  DIR             = '/srv/ctlabs-server/recordings'
  IMAGES_DIR      = File.join(DIR, 'images')
  EXT             = '.cast'
  MD_EXT          = '.md'
  VIDEO_EXTS      = ['.webm', '.mp4'].freeze
  VIDEO_EXT       = '.webm'
  IMAGE_EXTS      = ['.png', '.jpg', '.jpeg', '.gif', '.svg', '.webp'].freeze
  MANIFEST        = '_walkthrough.json'
  LEGACY_MANIFEST = '_walkthroughs.json'
  ID_RE           = /\A[a-zA-Z0-9_.-]{1,120}\z/
  NODE_MAX        = 40
  NAME_MAX        = 80
  TAIL_BYTES      = 8192

  def self.ensure_dir
    Dir.mkdir(DIR, 0755) unless Dir.exist?(DIR)
    DIR
  rescue SystemCallError
    DIR
  end

  def self.walkthrough_dir(slug)
    ensure_dir
    clean = slug_for(slug.to_s)
    File.join(DIR, clean)
  end

  def self.ensure_images_dir(slug = nil)
    ensure_dir
    target = slug ? File.join(walkthrough_dir(slug), 'images') : IMAGES_DIR
    FileUtils.mkdir_p(target) unless Dir.exist?(target)
    target
  rescue SystemCallError
    target
  end

  def self.save_image(tempfile_or_path, original_filename, walkthrough: nil)
    ext = File.extname(original_filename.to_s).downcase
    ext = '.png' unless IMAGE_EXTS.include?(ext)

    clean_base = File.basename(original_filename.to_s, ext).gsub(/[^a-zA-Z0-9_-]+/, '_')[0, 30]
    clean_base = 'img' if clean_base.empty?
    timestamp  = Time.now.strftime('%Y%m%d-%H%M%S')
    token      = SecureRandom.hex(3)
    filename   = "#{clean_base}_#{timestamp}_#{token}#{ext}"

    # Determine target images directory
    target_dir = if walkthrough && !walkthrough.to_s.empty?
                   ensure_images_dir(walkthrough)
                 else
                   wks = load_walkthroughs rescue {}
                   first_slug = wks.keys.first
                   first_slug ? ensure_images_dir(first_slug) : ensure_images_dir
                 end

    FileUtils.mkdir_p(target_dir)
    target = File.join(target_dir, filename)

    if tempfile_or_path.respond_to?(:path)
      FileUtils.cp(tempfile_or_path.path, target)
    else
      FileUtils.cp(tempfile_or_path.to_s, target)
    end
    File.chmod(0644, target) rescue nil

    # Keep a copy in global IMAGES_DIR for universal legacy fallback
    begin
      ensure_images_dir
      legacy_target = File.join(IMAGES_DIR, filename)
      FileUtils.cp(target, legacy_target) unless target == legacy_target
    rescue StandardError
    end

    filename
  end

  def self.image_path(filename, walkthrough: nil)
    clean = File.basename(filename.to_s)
    return nil if clean.empty? || clean.include?('..')

    # 1. Check scoped walkthrough's images/
    if walkthrough && !walkthrough.to_s.empty?
      target = File.join(walkthrough_dir(walkthrough), 'images', clean)
      return target if File.file?(target)
    end

    # 2. Check all walkthrough images directories
    Dir.glob(File.join(DIR, '*', 'images', clean)).each do |p|
      return p if File.file?(p)
    end

    # 3. Check legacy/global images directory
    legacy = File.join(ensure_images_dir, clean)
    return legacy if File.file?(legacy)

    # 4. Check root DIR directly
    direct = File.join(ensure_dir, clean)
    return direct if File.file?(direct)

    nil
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

    all_set_dirs = begin
      Dir.children(DIR).filter_map do |d|
        p = File.join(DIR, d)
        p if File.directory?(p) && !d.start_with?('.', '_') && d != 'images'
      end
    rescue StandardError
      []
    end

    candidate_dirs.concat(all_set_dirs)
    candidate_dirs << DIR
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
      if parent != DIR && parent.start_with?(DIR)
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
    ensure_dir
    patterns = if slug
                 dir = walkthrough_dir(slug)
                 [File.join(dir, "*#{EXT}"), File.join(dir, "*#{MD_EXT}")] +
                   VIDEO_EXTS.map { |ext| File.join(dir, "*#{ext}") }
               else
                 [File.join(DIR, '*', "*#{EXT}"), File.join(DIR, '*', "*#{MD_EXT}"),
                  File.join(DIR, "*#{EXT}"), File.join(DIR, "*#{MD_EXT}")] +
                   VIDEO_EXTS.flat_map { |ext| [File.join(DIR, '*', "*#{ext}"), File.join(DIR, "*#{ext}")] }
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
      content = begin
        File.read(path, encoding: 'UTF-8')
      rescue StandardError
        ''
      end
      title = 'Step Note'
      content.to_s.lines.each do |line|
        l = line.strip
        next if l.empty?
        title = l.sub(/^#+\s*/, '')
        break
      end
      return {
        id:         id,
        path:       path,
        node:       'Markdown',
        title:      title,
        type:       :markdown,
        created_at: File.mtime(path),
        duration:   0.0,
        size:       size
      }
    end

    if VIDEO_EXTS.any? { |e| path.end_with?(e) }
      ext  = File.extname(path)
      id   = File.basename(path, ext)
      size = File.size(path)
      meta_file = File.join(File.dirname(path), "#{id}.json")
      meta_file = File.join(DIR, "#{id}.json") unless File.file?(meta_file)
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
    dir = File.dirname(path)
    File.delete(path) rescue nil

    # Clean up sidecar metadata if present
    base_id = File.basename(path, File.extname(path))
    sidecar = File.join(dir, "#{base_id}.json")
    File.delete(sidecar) if File.file?(sidecar)
    root_sidecar = File.join(DIR, "#{base_id}.json")
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
      content = begin
        File.read(path, encoding: 'UTF-8')
      rescue StandardError
        ''
      end
      lines = content.lines
      new_title = title.to_s.strip
      new_title = 'Step Note' if new_title.empty?
      new_heading = "# #{new_title}\n"

      first_non_empty_idx = lines.find_index { |l| !l.strip.empty? }
      if first_non_empty_idx.nil?
        File.write(path, new_heading)
      elsif lines[first_non_empty_idx].strip.start_with?('#')
        lines[first_non_empty_idx] = new_heading
        File.write(path, lines.join)
      else
        lines.insert(first_non_empty_idx, new_heading + "\n")
        File.write(path, lines.join)
      end
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
    add_to_walkthrough(slug, [id])
    id
  end

  def self.read_content(id)
    path = path_for(id)
    return nil unless path && path.end_with?(MD_EXT)
    File.read(path, encoding: 'UTF-8')
  rescue StandardError
    nil
  end

  def self.update_content(id, content)
    path = path_for(id)
    return false unless path && path.end_with?(MD_EXT)
    File.write(path, content.to_s, encoding: 'UTF-8')
    true
  rescue StandardError
    false
  end

  # Saves the drag-and-drop custom order array to an index file
  def self.reorder!(ordered_ids)
    ensure_dir
    order_file = File.join(DIR, '_order.json')
    File.write(order_file, JSON.generate(ordered_ids))
    true
  rescue StandardError
    false
  end

  # Lists recordings ordered by saved drag-and-drop sequence, falling back to newest first
  def self.list
    ensure_dir
    files = all_disk_files
    recs = files.filter_map { |path| meta(path) }

    order_file = File.join(DIR, '_order.json')
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
    legacy_file = File.join(ensure_dir, LEGACY_MANIFEST)
    return unless File.file?(legacy_file)

    data = begin
      JSON.parse(File.read(legacy_file))
    rescue StandardError
      nil
    end
    return unless data.is_a?(Hash) && !data.empty?

    data.each do |slug, entry|
      wk_dir = File.join(DIR, slug)
      wk_images_dir = File.join(wk_dir, 'images')
      FileUtils.mkdir_p(wk_images_dir)

      all_ids = (Array(entry['recording_ids']) + Array(entry['unintegrated_ids'])).map(&:to_s).uniq
      all_ids.each do |id|
        [EXT, MD_EXT, *VIDEO_EXTS].each do |ext|
          src = File.join(DIR, "#{id}#{ext}")
          if File.file?(src)
            dst = File.join(wk_dir, "#{id}#{ext}")
            FileUtils.mv(src, dst) unless src == dst

            # Move sidecar if exists
            sidecar_src = File.join(DIR, "#{id}.json")
            if File.file?(sidecar_src)
              FileUtils.mv(sidecar_src, File.join(wk_dir, "#{id}.json"))
            end

            # If markdown, scan for images and copy them into set's images/
            if ext == MD_EXT
              content = File.read(dst) rescue ''
              imgs = content.scan(%r{(?:(?:recordings?/+)+|/)?images/([a-zA-Z0-9_.-]+)}).flatten.uniq
              imgs.each do |img|
                img_src = File.join(DIR, 'images', img)
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

    # Move any remaining orphan files in root DIR into the first walkthrough set
    first_slug = data.keys.first
    if first_slug
      first_dir = File.join(DIR, first_slug)
      first_manifest = File.join(first_dir, MANIFEST)
      first_data = JSON.parse(File.read(first_manifest)) rescue nil

      if first_data
        orphan_files = (Dir.glob(File.join(DIR, "*#{EXT}")) +
                        Dir.glob(File.join(DIR, "*#{MD_EXT}")) +
                        VIDEO_EXTS.flat_map { |ext| Dir.glob(File.join(DIR, "*#{ext}")) })
                       .reject { |p| File.basename(p).start_with?('_') }

        orphan_ids = []
        orphan_files.each do |p|
          ext = File.extname(p)
          oid = File.basename(p, ext)
          dst = File.join(first_dir, "#{oid}#{ext}")
          FileUtils.mv(p, dst) rescue nil
          sidecar = File.join(DIR, "#{oid}.json")
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
    ensure_dir
    migrate_to_folder_hierarchy! if File.file?(File.join(DIR, LEGACY_MANIFEST))

    data = {}
    # Scan subdirectories that contain _walkthrough.json
    slug_dirs = begin
      Dir.children(DIR).select do |entry|
        p = File.join(DIR, entry)
        File.directory?(p) && !entry.start_with?('.', '_') && entry != 'images'
      end.sort
    rescue StandardError
      []
    end

    slug_dirs.each do |slug|
      manifest_file = File.join(DIR, slug, MANIFEST)
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
          'created_at'       => File.mtime(File.join(DIR, slug)).to_f,
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
    [key, entry['name'].to_s]
  end

  def self.create_walkthrough(name, recording_ids: [], unintegrated_ids: [], unique: false)
    wks   = load_walkthroughs
    clean = name.to_s.strip[0, NAME_MAX]
    clean = 'New Walkthrough' if clean.empty?
    base  = slug_for(clean)

    if wks.key?(base)
      return base unless unique

      base = "#{base}_#{SecureRandom.hex(3)}"
      base = "#{base}_#{SecureRandom.hex(3)}" while wks.key?(base)
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
      'created_at'       => Time.now.to_f
    }
    save_walkthrough(base, entry)
    wks[base] = entry
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

    dir = walkthrough_dir(slug_str)
    if delete_recordings
      FileUtils.rm_rf(dir) if File.directory?(dir)
    else
      if File.directory?(dir)
        archived_dir = File.join(DIR, "_archived_#{slug_str}_#{Time.now.strftime('%Y%m%d_%H%M%S')}")
        FileUtils.mv(dir, archived_dir) rescue nil
      end
    end

    if load_walkthroughs.empty?
      create_walkthrough('Walkthrough 1')
    end

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
end
