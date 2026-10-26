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
  # A walkthrough is a named set of recordings stored in _walkthroughs.json.
  # Each set contains:
  #   - `recording_ids`: recordings integrated as ordered steps in the walkthrough.
  #   - `unintegrated_ids`: recordings belonging to this set, but not integrated as a step.
  #
  # Every recording belongs to a set — no recordings exist without a set.

  def self.walkthroughs_file
    File.join(ensure_dir, '_walkthroughs.json')
  end

  def self.load_walkthroughs
    file = walkthroughs_file
    data = nil
    if File.file?(file)
      begin
        parsed = JSON.parse(File.read(file))
        data = parsed if parsed.is_a?(Hash) && !parsed.empty?
      rescue StandardError
        # Fall through
      end
    end

    data ||= {
      'walkthrough_1' => {
        'name'             => 'Walkthrough 1',
        'recording_ids'    => Dir.glob(File.join(DIR, "*#{EXT}"))
                                 .map { |f| File.basename(f, EXT) }
                                 .sort
                                 .reverse,
        'unintegrated_ids' => []
      }
    }

    # Ensure each recording belongs to only one set and steps take precedence
    step_owners = {}
    data.each do |slug, entry|
      Array(entry['recording_ids']).each do |id|
        step_owners[id.to_s] ||= slug
      end
    end

    seen_unint = {}
    data.each do |slug, entry|
      entry['recording_ids'] = Array(entry['recording_ids']).map(&:to_s).select { |id| step_owners[id] == slug }

      entry_unint = (Array(entry['unintegrated_ids']) + Array(entry['excluded_ids'])).map(&:to_s)
      entry['unintegrated_ids'] = entry_unint.reject do |id|
        step_owners[id] || seen_unint[id]
      end
      entry['unintegrated_ids'].each { |id| seen_unint[id] = true }
      entry.delete('excluded_ids')
    end

    # Ensure no recordings exist that are not part of a set.
    # Any cast on disk not yet in any set gets claimed into the first set.
    existing_casts = Dir.glob(File.join(DIR, "*#{EXT}"))
                        .map { |f| File.basename(f, EXT) }
    known_members = {}
    data.each_value do |entry|
      (Array(entry['recording_ids']) + Array(entry['unintegrated_ids'])).each do |id|
        known_members[id.to_s] = true
      end
    end

    orphans = existing_casts.reject { |id| known_members[id] }
    if orphans.any?
      target_key = data.keys.first
      if target_key && data[target_key]
        current_unint = Array(data[target_key]['unintegrated_ids']).map(&:to_s)
        data[target_key]['unintegrated_ids'] = (current_unint + orphans).uniq - Array(data[target_key]['recording_ids']).map(&:to_s)
      end
    end

    data
  end

  def self.save_walkthroughs(walkthroughs)
    ensure_dir
    cleaned = walkthroughs.each_with_object({}) do |(k, v), h|
      entry = v.dup
      entry.delete('sealed')
      if entry['excluded_ids']
        unint = (Array(entry['unintegrated_ids']) + Array(entry['excluded_ids'])).map(&:to_s).uniq
        entry['unintegrated_ids'] = unint - Array(entry['recording_ids']).map(&:to_s)
        entry.delete('excluded_ids')
      end
      h[k] = entry
    end
    File.write(walkthroughs_file, JSON.pretty_generate(cleaned))
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
    save_walkthroughs(wks)
    [key, entry['name'].to_s]
  end

  def self.create_walkthrough(name, recording_ids: [], unique: false)
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
      'name'             => clean,
      'recording_ids'    => Array(recording_ids).map(&:to_s),
      'unintegrated_ids' => [],
      'created_at'       => Time.now.to_f
    }
    wks[base] = entry
    save_walkthroughs(wks)
    base
  end

  # Appends ids to a set's steps without duplicating membership.
  # Removes them from unintegrated_ids and purges them from all other sets.
  def self.add_to_walkthrough(slug, recording_ids)
    key, entry, wks = walkthrough_entry(slug)
    wanted  = Array(recording_ids).map(&:to_s)

    wks.each do |k, other_entry|
      next if k == key
      other_entry['recording_ids'] = Array(other_entry['recording_ids']).map(&:to_s) - wanted
      other_entry['unintegrated_ids'] = (Array(other_entry['unintegrated_ids']) + Array(other_entry['excluded_ids'])).map(&:to_s) - wanted
      other_entry.delete('excluded_ids')
    end

    current = Array(entry['recording_ids']).map(&:to_s)
    entry['recording_ids'] = current + (wanted - current)
    unint = (Array(entry['unintegrated_ids']) + Array(entry['excluded_ids'])).map(&:to_s)
    entry['unintegrated_ids'] = unint - wanted
    entry.delete('excluded_ids')
    save_walkthroughs(wks)
    key
  end

  def self.list_for_walkthrough(slug = 'default')
    wks = load_walkthroughs
    key, wk, = walkthrough_entry(slug, wks)
    allowed_ids = Array(wk['recording_ids']).map(&:to_s)

    all_recs = Dir.glob(File.join(DIR, "*#{EXT}"))
                  .filter_map { |path| meta(path) }
                  .sort_by { |m| [m[:created_at], m[:id]] }
                  .reverse
    recs_map = all_recs.map { |r| [r[:id], r] }.to_h

    if allowed_ids.empty? && Array(wk['unintegrated_ids']).empty? && Array(wk['excluded_ids']).empty? && wks.size <= 1
      all_recs
    else
      allowed_ids.filter_map { |id| recs_map[id] }
    end
  end

  # Returns recordings that belong to this walkthrough set but are not integrated as steps.
  def self.list_unintegrated_for_walkthrough(slug = 'default')
    wks = load_walkthroughs
    key, wk, = walkthrough_entry(slug, wks)
    step_ids = Array(wk['recording_ids']).map(&:to_s)
    unint_ids = (Array(wk['unintegrated_ids']) + Array(wk['excluded_ids'])).map(&:to_s).uniq - step_ids

    all_recs = Dir.glob(File.join(DIR, "*#{EXT}"))
                  .filter_map { |path| meta(path) }
                  .sort_by { |m| [m[:created_at], m[:id]] }
                  .reverse
    recs_map = all_recs.map { |r| [r[:id], r] }.to_h

    unint_ids.filter_map { |id| recs_map[id] }
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

  # Deletes a complete walkthrough set. If delete_recordings is true, any
  # recording file belonging to this set (step or unintegrated) that is not also
  # referenced by another set will be permanently removed from disk.
  def self.delete_walkthrough(slug, delete_recordings: false)
    wks = load_walkthroughs
    slug_str = slug.to_s
    return false unless wks.key?(slug_str)

    entry = wks.delete(slug_str)
    if delete_recordings
      ids = (Array(entry['recording_ids']) + Array(entry['unintegrated_ids']) + Array(entry['excluded_ids'])).map(&:to_s).uniq
      remaining_members = all_set_member_ids(wks)
      ids.each do |rec_id|
        next if remaining_members[rec_id]
        path = path_for(rec_id)
        begin
          File.delete(path) if path && File.file?(path)
        rescue SystemCallError
          # continue deleting others
        end
      end
    end

    if wks.empty?
      wks['walkthrough_1'] = { 'name' => 'Walkthrough 1', 'recording_ids' => [], 'unintegrated_ids' => [] }
    end

    save_walkthroughs(wks)
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
    end

    current = Array(entry['recording_ids']).map(&:to_s)
    removed = current - ordered

    entry['recording_ids'] = ordered
    unint = (Array(entry['unintegrated_ids']) + Array(entry['excluded_ids'])).map(&:to_s)
    entry['unintegrated_ids'] = (unint + removed).uniq - ordered
    entry.delete('excluded_ids')

    save_walkthroughs(wks)
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

    save_walkthroughs(wks)
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
      slug:       key,
      name:       entry['name'].to_s,
      sealed:     false,
      recordings: list_for_walkthrough(key)
    }
  end
end
