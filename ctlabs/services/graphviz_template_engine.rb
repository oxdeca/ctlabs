# -----------------------------------------------------------------------------
# File        : ctlabs/services/graphviz_template_engine.rb
# Description : ERB templating engine and building blocks DSL for Graphviz DOT
# License     : MIT License
# -----------------------------------------------------------------------------

require 'erb'
require_relative 'graphviz_custom_blocks_service'

class GraphvizTemplateContext
  def h(str)
    str.to_s.gsub('&', '&amp;').gsub('<', '&lt;').gsub('>', '&gt;').gsub('"', '&quot;')
  end

  def safe_id(id)
    id.to_s.strip.gsub(/[^a-zA-Z0-9_]/, '_')
  end

  def graph_header(title = nil, rankdir: 'LR', bgcolor: '#1e293b', fontname: 'Helvetica, Arial, sans-serif', nodesep: '0.6', ranksep: '0.8')
    title_attr = title ? %(label=#{h(title).inspect};\n  labelloc="t";\n  fontname="#{fontname}";\n  fontsize="16";\n  fontcolor="#f8fafc";\n) : ''
    <<~DOT
      #{title_attr}graph [bgcolor="#{bgcolor}", fontname="#{fontname}", rankdir="#{rankdir}", pad="0.4", nodesep="#{nodesep}", ranksep="#{ranksep}"];
      node [shape=rect, style="rounded,filled", fillcolor="#0f172a", penwidth="2", fontname="#{fontname}", fontcolor="#f8fafc", margin="0.2,0.12"];
      edge [color="#64748b", penwidth="2", fontname="#{fontname}", fontsize="11", fontcolor="#94a3b8"];
    DOT
  end

  def node(id, name: nil, ip: nil, subtitle: nil, icon: nil, color: '#38bdf8', fillcolor: '#0f172a')
    display_name = name || id
    details = ip || subtitle
    sub_row = details ? %(<tr><td><font color="#94a3b8" point-size="11">#{h(details)}</font></td></tr>) : ''
    icon_str = icon ? "#{icon} " : ''
    <<~DOT
      #{safe_id(id)} [color="#{color}", fillcolor="#{fillcolor}", label=<
        <table border="0" cellborder="0" cellspacing="0" cellpadding="4">
          <tr><td><b><font color="#{color}" point-size="14">#{icon_str}#{h(display_name)}</font></b></td></tr>
          #{sub_row}
        </table>
      >];
    DOT
  end

  def host(id, name: nil, ip: nil, subtitle: nil, icon: '💻', color: '#38bdf8', fillcolor: '#0f172a')
    node(id, name: name, ip: ip, subtitle: subtitle, icon: icon, color: color, fillcolor: fillcolor)
  end

  def router(id, name: nil, ip: nil, subtitle: nil, icon: '🔀', color: '#f59e0b', fillcolor: '#0f172a')
    node(id, name: name, ip: ip, subtitle: subtitle, icon: icon, color: color, fillcolor: fillcolor)
  end

  def switch(id, name: nil, subtitle: nil, icon: '🎛️', color: '#10b981', fillcolor: '#0f172a')
    node(id, name: name, subtitle: subtitle, icon: icon, color: color, fillcolor: fillcolor)
  end

  def firewall(id, name: nil, ip: nil, subtitle: nil, icon: '🛡️', color: '#ef4444', fillcolor: '#0f172a')
    node(id, name: name, ip: ip, subtitle: subtitle, icon: icon, color: color, fillcolor: fillcolor)
  end

  def gateway(id, name: nil, ip: nil, subtitle: nil, icon: '🚪', color: '#a855f7', fillcolor: '#0f172a')
    node(id, name: name, ip: ip, subtitle: subtitle, icon: icon, color: color, fillcolor: fillcolor)
  end

  def cloud(id, name: nil, subtitle: nil, icon: '☁️', color: '#0ea5e9', fillcolor: '#0f172a')
    node(id, name: name, subtitle: subtitle, icon: icon, color: color, fillcolor: fillcolor)
  end

  def database(id, name: nil, ip: nil, engine: nil, subtitle: nil, icon: '🗄️', color: '#ec4899', fillcolor: '#0f172a')
    details = [engine, ip || subtitle].compact.join(' &bull; ')
    node(id, name: name, subtitle: (details.empty? ? nil : details), icon: icon, color: color, fillcolor: fillcolor)
  end

  def k8s_pod(id, name: nil, namespace: nil, ip: nil, subtitle: nil, icon: '☸️', color: '#38bdf8', fillcolor: '#0f172a')
    details = [namespace ? "ns: #{namespace}" : nil, ip || subtitle].compact.join(' &bull; ')
    node(id, name: name, subtitle: (details.empty? ? nil : details), icon: icon, color: color, fillcolor: fillcolor)
  end

  def badge(id, text, color: '#38bdf8', bg: '#0f172a')
    %(#{safe_id(id)} [shape=box, style="rounded,filled", color="#{color}", fillcolor="#{bg}", fontcolor="#{color}", fontsize="12", label=#{h(text).inspect}];\n)
  end

  def table_node(id, title: nil, rows: [], icon: '📊', color: '#38bdf8', fillcolor: '#0f172a')
    rows_html = rows.map do |r|
      k, v = r.is_a?(Array) ? r : [r.to_s, '']
      %(<tr><td align="left"><font color="#cbd5e1" point-size="11">#{h(k)}</font></td><td align="right"><font color="#94a3b8" point-size="11">#{h(v)}</font></td></tr>)
    end.join("\n")

    icon_str = icon ? "#{icon} " : ''
    <<~DOT
      #{safe_id(id)} [color="#{color}", fillcolor="#{fillcolor}", label=<
        <table border="0" cellborder="0" cellspacing="0" cellpadding="4">
          <tr><td colspan="2"><b><font color="#{color}" point-size="13">#{icon_str}#{h(title || id)}</font></b></td></tr>
          <hr/>
          #{rows_html}
        </table>
      >];
    DOT
  end

  def link(from, to, label: nil, color: '#64748b', style: nil, penwidth: 2, dir: nil)
    attrs = [%(color="#{color}"), %(penwidth="#{penwidth}")]
    attrs << %(label="#{h(label)}") if label
    attrs << %(style="#{style}") if style
    attrs << %(dir="#{dir}") if dir
    "#{safe_id(from)} -> #{safe_id(to)} [#{attrs.join(', ')}];\n"
  end

  def links(from, *to_nodes, color: '#64748b', style: nil, penwidth: 2)
    to_nodes.flatten.map { |to| link(from, to, color: color, style: style, penwidth: penwidth) }.join
  end

  def chain(*nodes, color: '#64748b', style: nil, penwidth: 2)
    flat = nodes.flatten
    return '' if flat.size < 2
    flat.each_cons(2).map { |a, b| link(a, b, color: color, style: style, penwidth: penwidth) }.join
  end

  def cluster_start(id, label: nil, color: '#475569', fillcolor: '#131d31', fontcolor: '#cbd5e1', style: 'rounded,filled')
    <<~DOT
      subgraph cluster_#{safe_id(id)} {
        label = #{h(label || id).inspect};
        color = "#{color}";
        fillcolor = "#{fillcolor}";
        style = "#{style}";
        fontcolor = "#{fontcolor}";
        fontname = "Helvetica, Arial, sans-serif";
        fontsize = "13";
    DOT
  end

  def cluster_end
    "  }\n"
  end

  def cluster(id, label: nil, nodes: [], color: '#475569', fillcolor: '#131d31', fontcolor: '#cbd5e1', style: 'rounded,filled', &block)
    header = cluster_start(id, label: label, color: color, fillcolor: fillcolor, fontcolor: fontcolor, style: style)
    footer = cluster_end

    if block_given?
      erbout = begin
        eval('_erbout', block.binding)
      rescue NameError
        nil
      end

      if erbout
        erbout << header
        yield
        erbout << footer
        ''
      else
        res = header.dup
        res << yield.to_s << "\n"
        res << footer
      end
    elsif nodes.is_a?(Array) && !nodes.empty?
      res = header.dup
      res << nodes.join("\n") << "\n"
      res << footer
    else
      header + footer
    end
  end
end

class GraphvizTemplateEngine
  def self.template?(source)
    s = source.to_s
    s.include?('<%') && s.include?('%>')
  end

  def self.render(source)
    ctx = GraphvizTemplateContext.new
    GraphvizCustomBlocksService.load_into(ctx) if defined?(GraphvizCustomBlocksService)
    binding_ctx = ctx.instance_eval { binding }

    # Normalize <%= ... do %> to <% ... do %> so ERB allows block helpers with either tag
    clean_source = source.to_s.gsub(/<%=\s*(.*?\bdo(?:\s*\|.*?\|)?)\s*%>/, '<% \1 %>')

    erb = ERB.new(clean_source, trim_mode: '-')
    erb.filename = '(template)'

    compiled = erb.result(binding_ctx)
    { ok: true, dot: compiled }
  rescue SyntaxError => e
    line = extract_line_number(e.message, '(template)')
    clean_msg = sanitize_error_message(e.message)
    prefix = line ? "Template syntax error on line #{line}:" : "Template syntax error:"
    { ok: false, error: "#{prefix} #{clean_msg}" }
  rescue StandardError => e
    line = extract_line_from_backtrace(e.backtrace, '(template)')
    prefix = line ? "Template error on line #{line}:" : "Template error:"
    { ok: false, error: "#{prefix} #{e.message}" }
  end

  def self.extract_line_number(msg, filename)
    if msg =~ /#{Regexp.escape(filename)}:(\d+):/
      Regexp.last_match(1).to_i
    end
  end
  private_class_method :extract_line_number

  def self.extract_line_from_backtrace(backtrace, filename)
    return nil unless backtrace.is_a?(Array)
    backtrace.each do |line|
      if line =~ /#{Regexp.escape(filename)}:(\d+):/
        return Regexp.last_match(1).to_i
      end
    end
    nil
  end
  private_class_method :extract_line_from_backtrace

  def self.sanitize_error_message(msg)
    msg.to_s.sub(/\A\(template\):\d+:\s*/, '').strip
  end
  private_class_method :sanitize_error_message
end
