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
  ID_RE      = /\A[a-zA-Z0-9_.-]{1,120}\z/
  NODE_MAX   = 40
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
      node:       header.dig('ctlabs', 'node') || header['title'] || node_from_id(id),
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
end
