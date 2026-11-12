# -----------------------------------------------------------------------------
# File        : ctlabs/services/graphviz_service.rb
# Description : Render Graphviz DOT source to SVG/PNG for walkthrough diagrams
# License     : MIT License
# -----------------------------------------------------------------------------

require 'open3'
require 'tmpdir'
require 'base64'
require 'fileutils'
require 'json'
require_relative 'graphviz_template_engine'

class GraphvizService
  MAX_SOURCE_BYTES = 256 * 1024
  TIMEOUT_SECONDS  = 10
  FORMATS          = %w[svg png].freeze
  ENGINES          = %w[dot neato fdp sfdp circo twopi osage patchwork].freeze
  MAX_ERROR_BYTES  = 4000

  EMOJI_FILE = File.expand_path('../config/emojis.json', __dir__)
  EMOJI_MAP  = begin
    map = {}
    if File.file?(EMOJI_FILE)
      list = JSON.parse(File.read(EMOJI_FILE)) rescue []
      list.each do |item|
        map[item['code']] = item['char'] if item['code'] && item['char']
      end
    end
    map.freeze
  end

  def self.expand_emoji_shortcodes(text)
    return text if text.nil? || EMOJI_MAP.empty?
    text.to_s.gsub(/:([a-zA-Z0-9_+-]+):/) do |match|
      code = $1
      EMOJI_MAP[code] || EMOJI_MAP[code.downcase] || match
    end
  end

  IMAGE_ATTR_RE = /\b(?:image|src)\s*=\s*(?:"([^"]+)"|'([^']+)'|([a-zA-Z0-9_.\-\/]+))/i

  IMAGE_MIME_TYPES = {
    '.png'  => 'image/png',
    '.jpg'  => 'image/jpeg',
    '.jpeg' => 'image/jpeg',
    '.gif'  => 'image/gif',
    '.svg'  => 'image/svg+xml',
    '.webp' => 'image/webp'
  }.freeze

  def self.render(source, format: 'svg', engine: 'dot', walkthrough: nil)
    fmt = format.to_s.downcase
    fmt = 'svg' unless FORMATS.include?(fmt)

    eng = engine.to_s.downcase
    eng = 'dot' unless ENGINES.include?(eng)

    src = source.to_s
    return { ok: false, error: 'Diagram source is empty' } if src.strip.empty?
    return { ok: false, error: 'Diagram source is too large' } if src.bytesize > MAX_SOURCE_BYTES

    dot_source = src
    if GraphvizTemplateEngine.template?(src)
      tpl_result = GraphvizTemplateEngine.render(src)
      return tpl_result unless tpl_result[:ok]
      dot_source = tpl_result[:dot].to_s
      return { ok: false, error: 'Template generated empty DOT output' } if dot_source.strip.empty?
    end

    dot_source = expand_emoji_shortcodes(dot_source)

    Dir.mktmpdir('ctlabs-graphviz') do |dir|
      staged_images = stage_referenced_images(dot_source, dir, walkthrough: walkthrough)
      processed_src = rewrite_dot_image_refs(dot_source, staged_images)

      dot_path = File.join(dir, 'input.dot')
      out_path = File.join(dir, "output.#{fmt}")
      File.write(dot_path, processed_src)

      _stdout, stderr, status = run_dot(dir, 'dot', "-K#{eng}", "-T#{fmt}", dot_path, '-o', out_path)

      unless status && status.success? && File.file?(out_path)
        message = stderr.to_s.strip
        message = 'Graphviz failed to render the diagram' if message.empty?
        message = message.encode('UTF-8', invalid: :replace, undef: :replace)
        return { ok: false, error: message[0, MAX_ERROR_BYTES].scrub }
      end

      data = if fmt == 'svg'
               inline_svg_images(File.read(out_path, encoding: 'UTF-8'), staged_images)
             else
               File.binread(out_path)
             end

      { ok: true, data: data, dot: dot_source, format: fmt, engine: eng }
    end
  rescue StandardError => e
    { ok: false, error: e.message }
  end

  def self.stage_referenced_images(source, dir, walkthrough: nil)
    staged = {}
    source.scan(IMAGE_ATTR_RE).each do |matches|
      ref = matches.compact.first.to_s.strip
      next if ref.empty? || ref.start_with?('data:') || staged.key?(ref)

      resolved = resolve_image_file(ref, walkthrough: walkthrough)
      next unless resolved && File.file?(resolved)

      safe_name = File.basename(resolved).gsub(/[^a-zA-Z0-9_.-]/, '_')
      dest = File.join(dir, safe_name)
      FileUtils.cp(resolved, dest) unless File.exist?(dest)

      staged[ref] = { safe_name: safe_name, path: resolved }
    end
    staged
  end
  private_class_method :stage_referenced_images

  def self.resolve_image_file(ref, walkthrough: nil)
    clean_base = File.basename(ref)
    if defined?(RecordingService)
      found = RecordingService.image_path(clean_base, walkthrough: walkthrough)
      return found if found && File.file?(found)
    end

    if File.file?(ref)
      return File.expand_path(ref)
    end

    nil
  end
  private_class_method :resolve_image_file

  def self.rewrite_dot_image_refs(source, staged)
    return source if staged.empty?

    modified = source.dup
    staged.each do |original_ref, info|
      next if original_ref == info[:safe_name]
      modified.gsub!(/(\b(?:image|src)\s*=\s*)(["']?)#{Regexp.escape(original_ref)}\2/i) do
        %(#{$1}#{$2}#{info[:safe_name]}#{$2})
      end
    end
    modified
  end
  private_class_method :rewrite_dot_image_refs

  def self.inline_svg_images(svg_content, staged)
    return svg_content if staged.empty?

    svg = svg_content.dup
    images = {}
    staged.each_value { |info| images[info[:safe_name]] = info[:path] }

    images.each do |safe_name, path|
      next unless File.file?(path)

      ext = File.extname(path).downcase
      mime = IMAGE_MIME_TYPES[ext] || 'application/octet-stream'
      bytes = File.binread(path)
      data_uri = "data:#{mime};base64,#{Base64.strict_encode64(bytes)}"

      svg.gsub!(/(<image\b[^>]*\b(?:xlink:)?href=)(["'])#{Regexp.escape(safe_name)}\2/) do
        q = $2
        %(#{$1}#{q}#{data_uri}#{q} href=#{q}#{data_uri}#{q})
      end
    end
    svg
  end
  private_class_method :inline_svg_images

  def self.run_dot(dir, *cmd)
    Open3.popen3(*cmd, chdir: dir) do |stdin, stdout, stderr, wait_thr|
      stdin.close
      out_thread = Thread.new { stdout.read }
      err_thread = Thread.new { stderr.read }

      unless wait_thr.join(TIMEOUT_SECONDS)
        begin
          Process.kill('KILL', wait_thr.pid)
        rescue StandardError
        end
        wait_thr.join(1)
        out_thread.kill
        err_thread.kill
        return ['', 'Graphviz render timed out', nil]
      end

      [out_thread.value, err_thread.value, wait_thr.value]
    end
  end
  private_class_method :run_dot
end
