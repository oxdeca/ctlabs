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

class RecordingService
  DIR        = '/srv/ctlabs-server/recordings'
  EXT        = '.cast'
  MANIFEST   = '_walkthrough.json'
  ID_RE      = /\A[a-zA-Z0-9_.-]{1,120}\z/
  NODE_MAX   = 40
  NAME_MAX   = 80
  TAIL_BYTES = 8192

  def self.ensure_dir
    Dir.mkdir(DIR, 0755) unless Dir.exist?(DIR)
    DIR
  rescue SystemCallError
    DIR
  end

  # The public id is the basename without extension. It travels in URLs, so
  # never allow separators or a traversal sequence.
  def self.valid_id?(id)
    s = id.to_s
    !s.empty? && !s.include?('..') && !!(s =~ ID_RE)
  end

  def self.path_for(id)
    return nil unless valid_id?(id)
    path = File.join(ensure_dir, "#{id}#{EXT}")
    File.file?(path) ? path : nil
  end

  def self.node_slug(node)
    node.to_s.gsub(/[^a-zA-Z0-9_.-]+/, '_').gsub(/\A_+|_+\z/, '')[0, NODE_MAX].to_s
  end

  def self.new_id(node)
    "#{Time.now.strftime('%Y%m%d-%H%M%S')}_#{node_slug(node)}_#{SecureRandom.hex(3)}"
  end

  # Opens a recording, writes the asciicast v2 header and returns [id, io].
  # The caller owns the io and must close it when recording stops.
  def self.open(node:, cols: nil, rows: nil, title: nil)
    ensure_dir
    id   = new_id(node)
    path = File.join(DIR, "#{id}#{EXT}")
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
    Dir.glob(File.join(DIR, "*#{EXT}"))
       .filter_map { |path| meta(path) }
       .sort_by { |m| [m[:created_at], m[:id]] }
       .reverse
  end

  def self.meta(path)
    return nil unless File.file?(path)

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
    File.delete(path)
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


  # Updates the title in the JSON header of the .cast file
  def self.update_meta(id, title:)
    path = path_for(id)
    return false unless path

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
    files = Dir.glob(File.join(DIR, "*#{EXT}"))
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
  # A walkthrough is a named, ordered list of recording ids stored in
  # _walkthroughs.json. New recordings are appended to the set being viewed so
  # that the simple "record then open Walkthrough" flow keeps working. Imported
  # sets are marked `sealed` so unrelated local recordings are not pulled into
  # a restored bundle.

  def self.walkthroughs_file
    File.join(ensure_dir, '_walkthroughs.json')
  end

  def self.load_walkthroughs
    file = walkthroughs_file
    if File.file?(file)
      begin
        data = JSON.parse(File.read(file))
        return data if data.is_a?(Hash)
      rescue StandardError
        # Fall through to default
      end
    end

    # Default fallback walkthrough if none exist. Ids start with a timestamp,
    # so a reverse sort is newest first (matching the old list behaviour).
    {
      'default' => {
        'name' => 'Default Walkthrough',
        'recording_ids' => Dir.glob(File.join(DIR, "*#{EXT}"))
                              .map { |f| File.basename(f, EXT) }
                              .sort
                              .reverse
      }
    }
  end

  def self.save_walkthroughs(walkthroughs)
    ensure_dir
    File.write(walkthroughs_file, JSON.pretty_generate(walkthroughs))
  end

  def self.slug_for(name)
    slug = name.to_s.strip.downcase.gsub(/[^a-z0-9_-]+/, '_')
    slug.empty? ? "walkthrough_#{SecureRandom.hex(3)}" : slug
  end

  def self.walkthrough_entry(slug, walkthroughs = nil)
    wks   = walkthroughs || load_walkthroughs
    key   = wks.key?(slug.to_s) ? slug.to_s : 'default'
    entry = wks[key] ||= { 'name' => 'Default Walkthrough', 'recording_ids' => [] }
    [key, entry, wks]
  end

  def self.walkthrough_name(slug = 'default')
    _key, entry = walkthrough_entry(slug)
    entry['name'].to_s
  end

  def self.rename_walkthrough(slug, name)
    key, entry, wks = walkthrough_entry(slug)
    clean = name.to_s.strip[0, NAME_MAX]
    entry['name'] = clean unless clean.empty?
    save_walkthroughs(wks)
    [key, entry['name'].to_s]
  end

  def self.create_walkthrough(name, recording_ids: [], sealed: false, unique: false)
    wks   = load_walkthroughs
    clean = name.to_s.strip[0, NAME_MAX]
    clean = 'New Walkthrough' if clean.empty?
    base  = slug_for(clean)

    if wks.key?(base)
      return base unless unique

      base = "#{base}_#{SecureRandom.hex(3)}"
      base = "#{base}_#{SecureRandom.hex(3)}" while wks.key?(base)
    end

    entry = {
      'name'          => clean,
      'recording_ids' => Array(recording_ids).map(&:to_s),
      # Only recordings uploaded from now on are auto-appended, so a new set
      # starts empty instead of inheriting every existing cast.
      'created_at'    => Time.now.to_f
    }
    entry['sealed'] = true if sealed
    wks[base] = entry
    save_walkthroughs(wks)
    base
  end

  # Appends ids to a set (used by import) without duplicating membership.
  def self.add_to_walkthrough(slug, recording_ids)
    key, entry, wks = walkthrough_entry(slug)
    current = Array(entry['recording_ids']).map(&:to_s)
    wanted  = Array(recording_ids).map(&:to_s)
    entry['recording_ids'] = current + (wanted - current)
    save_walkthroughs(wks)
    key
  end

  def self.list_for_walkthrough(slug = 'default')
    wks = load_walkthroughs
    key, wk, = walkthrough_entry(slug, wks)
    allowed_ids = Array(wk['recording_ids']).map(&:to_s)

    # Newest first makes the appended order deterministic.
    all_recs = Dir.glob(File.join(DIR, "*#{EXT}"))
                  .filter_map { |path| meta(path) }
                  .sort_by { |m| [m[:created_at], m[:id]] }
                  .reverse
    recs_map = all_recs.map { |r| [r[:id], r] }.to_h

    unless wk['sealed']
      known  = allowed_ids.each_with_object({}) { |id, h| h[id] = true }
      cutoff = wk['created_at'].to_f
      new_ids = all_recs.filter_map do |rec|
        next if known[rec[:id]]
        next if cutoff.positive? && File.mtime(rec[:path]).to_f < cutoff
        rec[:id]
      end

      unless new_ids.empty?
        wk['recording_ids'] = allowed_ids + new_ids
        save_walkthroughs(wks)
        allowed_ids = wk['recording_ids']
      end
    end

    if key == 'default' && allowed_ids.empty?
      all_recs
    else
      allowed_ids.filter_map { |id| recs_map[id] }
    end
  end

  def self.update_walkthrough_order(slug, ordered_ids)
    key, entry, wks = walkthrough_entry(slug)
    entry['recording_ids'] = Array(ordered_ids).map(&:to_s)
    save_walkthroughs(wks)
    key
  end

  # Everything the ZIP export needs: the resolved set name/membership, in the
  # exact order the page shows them.
  def self.export_bundle(slug = 'default')
    key, entry = walkthrough_entry(slug)
    {
      slug:       key,
      name:       entry['name'].to_s,
      recordings: list_for_walkthrough(key)
    }
  end
end
