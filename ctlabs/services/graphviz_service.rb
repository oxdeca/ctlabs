# -----------------------------------------------------------------------------
# File        : ctlabs/services/graphviz_service.rb
# Description : Render Graphviz DOT source to SVG/PNG for walkthrough diagrams
# License     : MIT License
# -----------------------------------------------------------------------------

require 'open3'
require 'tmpdir'

class GraphvizService
  MAX_SOURCE_BYTES = 256 * 1024
  TIMEOUT_SECONDS  = 10
  FORMATS          = %w[svg png].freeze
  ENGINES          = %w[dot neato fdp sfdp circo twopi osage patchwork].freeze
  MAX_ERROR_BYTES  = 4000

  def self.render(source, format: 'svg', engine: 'dot')
    fmt = format.to_s.downcase
    fmt = 'svg' unless FORMATS.include?(fmt)

    eng = engine.to_s.downcase
    eng = 'dot' unless ENGINES.include?(eng)

    src = source.to_s
    return { ok: false, error: 'Diagram source is empty' } if src.strip.empty?
    return { ok: false, error: 'Diagram source is too large' } if src.bytesize > MAX_SOURCE_BYTES

    Dir.mktmpdir('ctlabs-graphviz') do |dir|
      dot_path = File.join(dir, 'input.dot')
      out_path = File.join(dir, "output.#{fmt}")
      File.write(dot_path, src)

      _stdout, stderr, status = run_dot(dir, 'dot', "-K#{eng}", "-T#{fmt}", dot_path, '-o', out_path)

      unless status && status.success? && File.file?(out_path)
        message = stderr.to_s.strip
        message = 'Graphviz failed to render the diagram' if message.empty?
        message = message.encode('UTF-8', invalid: :replace, undef: :replace)
        return { ok: false, error: message[0, MAX_ERROR_BYTES].scrub }
      end

      { ok: true, data: File.binread(out_path), format: fmt, engine: eng }
    end
  rescue StandardError => e
    { ok: false, error: e.message }
  end

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
