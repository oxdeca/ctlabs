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

  def safe_endpoint(id)
    parts = id.to_s.strip.split(':').map { |p| safe_id(p) }.reject(&:empty?)
    parts.empty? ? safe_id(id) : parts.join(':')
  end

  def format_dot_val(val)
    return val.to_s if val == true || val == false || val.is_a?(Numeric)
    s = val.to_s
    return s if s.start_with?('<') && s.end_with?('>')
    s.inspect
  end

  def format_dot_attrs(attr)
    return '' if attr.nil? || attr.empty?
    pairs = []
    attr.each do |k, v|
      next if v.nil?
      key = k.to_s.gsub(/[^a-zA-Z0-9_]/, '')
      next if key.empty?
      pairs << "#{key}=#{format_dot_val(v)}"
    end
    pairs.join(', ')
  end

  THEMES = {
    slate: {
      bgcolor: '#1e293b',
      fontname: 'Helvetica, Arial, sans-serif',
      title_color: '#f8fafc',
      node_fill: '#0f172a',
      node_border: '#38bdf8',
      node_text: '#f8fafc',
      edge_color: '#64748b',
      edge_text: '#94a3b8',
      cluster_bg: '#131d31',
      cluster_border: '#475569',
      cluster_text: '#cbd5e1'
    },
    light: {
      bgcolor: '#ffffff',
      fontname: 'Helvetica, Arial, sans-serif',
      title_color: '#0f172a',
      node_fill: '#f8fafc',
      node_border: '#0284c7',
      node_text: '#0f172a',
      edge_color: '#64748b',
      edge_text: '#475569',
      cluster_bg: '#f1f5f9',
      cluster_border: '#cbd5e1',
      cluster_text: '#1e293b'
    },
    nord: {
      bgcolor: '#2e3440',
      fontname: 'Helvetica, Arial, sans-serif',
      title_color: '#eceff4',
      node_fill: '#3b4252',
      node_border: '#88c0d0',
      node_text: '#eceff4',
      edge_color: '#81a1c1',
      edge_text: '#88c0d0',
      cluster_bg: '#434c5e',
      cluster_border: '#4c566a',
      cluster_text: '#8fbcbb'
    },
    dracula: {
      bgcolor: '#282a36',
      fontname: 'Helvetica, Arial, sans-serif',
      title_color: '#f8f8f2',
      node_fill: '#21222c',
      node_border: '#bd93f9',
      node_text: '#f8f8f2',
      edge_color: '#6272a4',
      edge_text: '#8be9fd',
      cluster_bg: '#343746',
      cluster_border: '#6272a4',
      cluster_text: '#ff79c6'
    },
    amber: {
      bgcolor: '#1c1917',
      fontname: 'Helvetica, Arial, sans-serif',
      title_color: '#fef3c7',
      node_fill: '#292524',
      node_border: '#f59e0b',
      node_text: '#fafaf9',
      edge_color: '#78716c',
      edge_text: '#fbbf24',
      cluster_bg: '#44403c',
      cluster_border: '#78716c',
      cluster_text: '#fde68a'
    },
    emerald: {
      bgcolor: '#022c22',
      fontname: 'Helvetica, Arial, sans-serif',
      title_color: '#ecfdf5',
      node_fill: '#064e3b',
      node_border: '#10b981',
      node_text: '#f0fdf4',
      edge_color: '#059669',
      edge_text: '#6ee7b7',
      cluster_bg: '#044335',
      cluster_border: '#059669',
      cluster_text: '#a7f3d0'
    }
  }.freeze

  def current_theme
    @current_theme || THEMES[:slate]
  end

  def graph_header(title = nil, rankdir: 'LR', theme: :slate, bgcolor: nil, fontname: nil, nodesep: '0.6', ranksep: '0.8', title_spacing: 2, **attr)
    th = THEMES[theme.to_sym] || THEMES[:slate]
    @current_theme = th

    bg = bgcolor || th[:bgcolor]
    fn = fontname || th[:fontname]
    tc = th[:title_color]

    spacing_newlines = "\n" * (title_spacing.to_i.clamp(0, 6))
    title_attr = if title && !title.to_s.strip.empty?
                   padded_title = "#{h(title)}#{spacing_newlines}"
                   %(label=#{padded_title.inspect};\n  labelloc="t";\n  fontname="#{fn}";\n  fontsize="16";\n  fontcolor="#{tc}";\n)
                 else
                   ''
                 end
    extra_graph = format_dot_attrs(attr)
    extra_suffix = extra_graph.empty? ? '' : ", #{extra_graph}"
    <<~DOT
      #{title_attr}graph [bgcolor="#{bg}", fontname="#{fn}", rankdir="#{rankdir}", pad="0.4", nodesep="#{nodesep}", ranksep="#{ranksep}"#{extra_suffix}];
      node [shape=rect, style="rounded,filled", fillcolor="#{th[:node_fill]}", penwidth="2", fontname="#{fn}", fontcolor="#{th[:node_text]}", margin="0.2,0.12"];
      edge [color="#{th[:edge_color]}", penwidth="2", fontname="#{fn}", fontsize="11", fontcolor="#{th[:edge_text]}"];
    DOT
  end

  def resolve_icon(icon)
    return '' if icon.nil? || icon == false
    raw = icon.to_s.strip
    return '' if raw.empty?
    code = raw.gsub(/\A:+|:+\z/, '')
    if defined?(GraphvizService::EMOJI_MAP) && GraphvizService::EMOJI_MAP[code]
      GraphvizService::EMOJI_MAP[code]
    elsif defined?(GraphvizService::EMOJI_MAP) && GraphvizService::EMOJI_MAP[code.downcase]
      GraphvizService::EMOJI_MAP[code.downcase]
    elsif code.downcase == 'database'
      '🗄️'
    elsif code.downcase == 'table'
      '📋'
    else
      raw
    end
  end

  def node(id, name: nil, ip: nil, subtitle: nil, icon: nil, color: nil, fillcolor: nil,
           text_color: nil, fontcolor: nil, font: nil, fontname: nil, font_size: 14,
           subtitle_color: nil, border: 0, cellborder: 0, cellpadding: 4, cellspacing: 0, **attr)
    th = current_theme
    border_col = color || th[:node_border]
    fill_col = fillcolor || th[:node_fill]
    display_name = name || id
    details = ip || subtitle
    title_col = text_color || fontcolor || (color || th[:title_color])
    sub_col = subtitle_color || (th[:name] == :light ? '#64748b' : '#94a3b8')
    font_face = font || fontname || th[:fontname]
    face_attr = font_face ? %( face="#{h(font_face)}") : ''
    sub_row = details ? %(<tr><td><font color="#{sub_col}"#{face_attr} point-size="11">#{h(details)}</font></td></tr>) : ''
    ico = resolve_icon(icon)
    icon_str = ico.empty? ? '' : "#{ico} "
    extra = format_dot_attrs(attr)
    extra_prefix = extra.empty? ? '' : ", #{extra}"
    <<~DOT
      #{safe_id(id)} [color="#{border_col}", fillcolor="#{fill_col}"#{extra_prefix}, label=<
        <table border="#{border}" cellborder="#{cellborder}" cellspacing="#{cellspacing}" cellpadding="#{cellpadding}">
          <tr><td><b><font color="#{title_col}"#{face_attr} point-size="#{font_size}">#{icon_str}#{h(display_name)}</font></b></td></tr>
          #{sub_row}
        </table>
      >];
    DOT
  end

  def plain_node(id, label: nil, shape: 'box', color: nil, fillcolor: nil,
                 text_color: nil, fontcolor: nil, font: nil, fontname: nil,
                 fontsize: 13, style: 'rounded,filled', **attr)
    th = current_theme
    border_col = color || th[:node_border]
    fill_col = fillcolor || th[:node_fill]
    display_label = label || id
    tc = text_color || fontcolor || th[:node_text]
    fn = font || fontname || th[:fontname]
    extra = format_dot_attrs(attr)
    extra_suffix = extra.empty? ? '' : ", #{extra}"
    %(#{safe_id(id)} [shape=#{shape}, style="#{style}", color="#{border_col}", fillcolor="#{fill_col}", fontcolor="#{tc}", fontname="#{fn}", fontsize="#{fontsize}"#{extra_suffix}, label=#{h(display_label).inspect}];\n)
  end

  def step(id, label: nil, name: nil, subtitle: nil, icon: nil, color: nil, fillcolor: nil, **attr)
    node(id, name: (label || name || id), subtitle: subtitle, icon: icon, color: color, fillcolor: fillcolor, **attr)
  end

  def decision(id, label: nil, name: nil, subtitle: nil, color: '#f59e0b', fillcolor: nil, **attr)
    th = current_theme
    title_text = label || name || id
    tc = th[:node_text]
    bg = fillcolor || th[:node_fill]
    fn = th[:fontname]
    extra = format_dot_attrs(attr)
    extra_suffix = extra.empty? ? '' : ", #{extra}"
    %(#{safe_id(id)} [shape=diamond, style="filled", color="#{color}", fillcolor="#{bg}", fontcolor="#{tc}", fontname="#{fn}", penwidth="2", margin="0.2,0.1"#{extra_suffix}, label=#{h(title_text).inspect}];\n)
  end

  def state_node(id, label: nil, name: nil, subtitle: nil, type: :normal, color: nil, fillcolor: nil, **attr)
    th = current_theme
    border_col = color || th[:node_border]
    bg = fillcolor || th[:node_fill]
    tc = th[:node_text]
    title_text = label || name || id
    shape = case type.to_sym
            when :start, :initial then 'point'
            when :end, :done, :final, :terminal, :error then 'doublecircle'
            else 'circle'
            end
    extra = format_dot_attrs(attr)
    extra_suffix = extra.empty? ? '' : ", #{extra}"
    if shape == 'point'
      dot_color = color || th[:node_border]
      %(#{safe_id(id)} [shape=point, width="0.2", color="#{dot_color}"#{extra_suffix}];\n)
    else
      fn = th[:fontname]
      %(#{safe_id(id)} [shape=#{shape}, style="filled", color="#{border_col}", fillcolor="#{bg}", fontcolor="#{tc}", fontname="#{fn}", penwidth="2", fixedsize="true", width="1.1"#{extra_suffix}, label=#{h(title_text).inspect}];\n)
    end
  end

  def html_node(id, title: nil, content: nil, subtitle: nil, icon: nil, color: '#38bdf8', fillcolor: '#0f172a', bgcolor: nil,
                text_color: nil, fontcolor: nil, font: nil, fontname: nil, font_size: 13,
                subtitle_color: nil, border: 1, cellborder: 0, cellpadding: 6, cellspacing: 0, html: nil, **attr, &block)
    table_bg = bgcolor || fillcolor
    title_col = text_color || fontcolor || color
    sub_col = subtitle_color || '#cbd5e1'
    font_face = font || fontname
    face_attr = font_face ? %( face="#{h(font_face)}") : ''
    ico = resolve_icon(icon)
    icon_str = ico.empty? ? '' : "#{ico} "
    display_title = title || (id unless html || block_given? || content || subtitle)

    header_row = display_title ? %(<tr><td align="center"><b><font color="#{title_col}"#{face_attr} point-size="#{font_size}">#{icon_str}#{h(display_title)}</font></b></td></tr>) : ''

    body_html = if block_given?
                  yield.to_s
                elsif html
                  html.to_s
                elsif content || subtitle
                  c = content || subtitle
                  %(<tr><td align="left"><font color="#{sub_col}"#{face_attr} point-size="11">#{h(c)}</font></td></tr>)
                else
                  ''
                end

    extra = format_dot_attrs(attr)
    extra_prefix = extra.empty? ? '' : ", #{extra}"
    <<~DOT
      #{safe_id(id)} [shape=plain, style="", margin="0"#{extra_prefix}, label=<
        <table border="#{border}" cellborder="#{cellborder}" cellspacing="#{cellspacing}" cellpadding="#{cellpadding}" bgcolor="#{table_bg}" color="#{color}">
          #{header_row}
          #{body_html}
        </table>
      >];
    DOT
  end

  def host(id, name: nil, ip: nil, subtitle: nil, icon: '💻', color: '#38bdf8', fillcolor: '#0f172a', **attr)
    node(id, name: name, ip: ip, subtitle: subtitle, icon: icon, color: color, fillcolor: fillcolor, **attr)
  end

  def router(id, name: nil, ip: nil, subtitle: nil, icon: '🔀', color: '#f59e0b', fillcolor: '#0f172a', **attr)
    node(id, name: name, ip: ip, subtitle: subtitle, icon: icon, color: color, fillcolor: fillcolor, **attr)
  end

  def switch(id, name: nil, ip: nil, subtitle: nil, icon: '🎛️', color: '#10b981', fillcolor: '#0f172a', **attr)
    node(id, name: name, ip: ip, subtitle: subtitle, icon: icon, color: color, fillcolor: fillcolor, **attr)
  end

  def firewall(id, name: nil, ip: nil, subtitle: nil, icon: '🛡️', color: '#ef4444', fillcolor: '#0f172a', **attr)
    node(id, name: name, ip: ip, subtitle: subtitle, icon: icon, color: color, fillcolor: fillcolor, **attr)
  end

  def gateway(id, name: nil, ip: nil, subtitle: nil, icon: '🚪', color: '#a855f7', fillcolor: '#0f172a', **attr)
    node(id, name: name, ip: ip, subtitle: subtitle, icon: icon, color: color, fillcolor: fillcolor, **attr)
  end

  def loadbalancer(id, name: nil, ip: nil, subtitle: nil, icon: '⚖️', color: '#a855f7', fillcolor: '#0f172a', **attr)
    node(id, name: name, ip: ip, subtitle: subtitle, icon: icon, color: color, fillcolor: fillcolor, **attr)
  end

  def cloud(id, name: nil, ip: nil, subtitle: nil, icon: '☁️', color: '#0ea5e9', fillcolor: '#0f172a', **attr)
    node(id, name: name, ip: ip, subtitle: subtitle, icon: icon, color: color, fillcolor: fillcolor, **attr)
  end

  def database(id, name: nil, ip: nil, engine: nil, subtitle: nil, icon: '🗄️', color: '#ec4899', fillcolor: '#0f172a', **attr)
    details = [engine, ip || subtitle].compact.join(' &bull; ')
    node(id, name: name, subtitle: (details.empty? ? nil : details), icon: icon, color: color, fillcolor: fillcolor, **attr)
  end

  def k8s_pod(id, name: nil, namespace: nil, ip: nil, subtitle: nil, icon: '☸️', color: '#38bdf8', fillcolor: '#0f172a', **attr)
    details = [namespace ? "ns: #{namespace}" : nil, ip || subtitle].compact.join(' &bull; ')
    node(id, name: name, subtitle: (details.empty? ? nil : details), icon: icon, color: color, fillcolor: fillcolor, **attr)
  end

  def badge(id, text, color: '#38bdf8', bg: '#0f172a', text_color: nil, fontcolor: nil, font: nil, fontname: nil, fontsize: 12, **attr)
    tc = text_color || fontcolor || color
    fn = font || fontname
    fn_attr = fn ? %(, fontname="#{fn}") : ''
    extra = format_dot_attrs(attr)
    extra_suffix = extra.empty? ? '' : ", #{extra}"
    %(#{safe_id(id)} [shape=box, style="rounded,filled", color="#{color}", fillcolor="#{bg}", fontcolor="#{tc}", fontsize="#{fontsize}"#{fn_attr}, label=#{h(text).inspect}#{extra_suffix}];\n)
  end

  def same_rank(*nodes)
    rank_group('same', *nodes)
  end

  def rank_source(*nodes)
    rank_group('source', *nodes)
  end

  def rank_sink(*nodes)
    rank_group('sink', *nodes)
  end

  def rank_group(rank_type, *nodes)
    flat = nodes.flatten.map { |n| safe_id(n) }
    return '' if flat.empty?
    "{ rank=#{rank_type}; #{flat.join('; ')}; }\n"
  end

  def spacer(id, width: 0.1, height: 0.1, **attr)
    extra = format_dot_attrs(attr)
    extra_suffix = extra.empty? ? '' : ", #{extra}"
    %(#{safe_id(id)} [style=invis, shape=point, width=#{width}, height=#{height}, label=""#{extra_suffix}];\n)
  end

  def invis_edge(from, to, minlen: 2, weight: 1, directed: true, op: nil, **attr)
    edge_op = op || (directed ? '->' : '--')
    attrs = ['style=invis']
    attrs << "minlen=#{minlen}" if minlen
    attrs << "weight=#{weight}" if weight
    extra = format_dot_attrs(attr)
    attrs << extra unless extra.empty?
    "#{safe_endpoint(from)} #{edge_op} #{safe_endpoint(to)} [#{attrs.join(', ')}];\n"
  end

  def stack_vertical(*nodes, minlen: 2, weight: 10, directed: true, op: nil, **attr)
    flat = nodes.flatten
    return '' if flat.size < 2
    flat.each_cons(2).map { |a, b| invis_edge(a, b, minlen: minlen, weight: weight, directed: directed, op: op, **attr) }.join
  end

  def table_node(id, title: nil, rows: [], icon: '📊', color: nil, fillcolor: nil,
                 text_color: nil, fontcolor: nil, font: nil, fontname: nil, font_size: 13,
                 key_color: nil, val_color: nil,
                 border: 0, cellborder: 0, cellpadding: 4, cellspacing: 0, **attr)
    th = current_theme
    border_col = color || th[:node_border]
    fill_col = fillcolor || th[:node_fill]
    font_face = font || fontname || th[:fontname]
    face_attr = font_face ? %( face="#{h(font_face)}") : ''
    title_col = text_color || fontcolor || (color || th[:title_color])
    kc = key_color || (th[:name] == :light ? '#334155' : '#cbd5e1')
    vc = val_color || (th[:name] == :light ? '#64748b' : '#94a3b8')

    rows_html = rows.map do |r|
      k, v = r.is_a?(Array) ? r : [r.to_s, '']
      %(<tr><td align="left"><font color="#{kc}"#{face_attr} point-size="11">#{h(k)}</font></td><td align="right"><font color="#{vc}"#{face_attr} point-size="11">#{h(v)}</font></td></tr>)
    end.join("\n")

    ico = resolve_icon(icon)
    icon_str = ico.empty? ? '' : "#{ico} "
    extra = format_dot_attrs(attr)
    extra_prefix = extra.empty? ? '' : ", #{extra}"
    <<~DOT
      #{safe_id(id)} [color="#{border_col}", fillcolor="#{fill_col}"#{extra_prefix}, label=<
        <table border="#{border}" cellborder="#{cellborder}" cellspacing="#{cellspacing}" cellpadding="#{cellpadding}">
          <tr><td colspan="2"><b><font color="#{title_col}"#{face_attr} point-size="#{font_size}">#{icon_str}#{h(title || id)}</font></b></td></tr>
          <hr/>
          #{rows_html}
        </table>
      >];
    DOT
  end

  def link(from, to, label: nil, color: nil, style: nil, penwidth: 2, dir: nil, directed: true, op: nil, **attr)
    th = current_theme
    edge_col = color || th[:edge_color]
    edge_op = op || (directed ? '->' : '--')
    attrs = [%(color="#{edge_col}"), %(penwidth="#{penwidth}")]
    attrs << %(label="#{h(label)}") if label
    attrs << %(style="#{style}") if style
    attrs << %(dir="#{dir}") if dir
    extra = format_dot_attrs(attr)
    attrs << extra unless extra.empty?
    "#{safe_endpoint(from)} #{edge_op} #{safe_endpoint(to)} [#{attrs.join(', ')}];\n"
  end

  def ulink(from, to, label: nil, color: '#64748b', style: nil, penwidth: 2, **attr)
    link(from, to, label: label, color: color, style: style, penwidth: penwidth, directed: false, **attr)
  end

  def links(from, *to_nodes, label: nil, color: '#64748b', style: nil, penwidth: 2, dir: nil, directed: true, op: nil, **attr)
    to_nodes.flatten.map { |to| link(from, to, label: label, color: color, style: style, penwidth: penwidth, dir: dir, directed: directed, op: op, **attr) }.join
  end

  def ulinks(from, *to_nodes, label: nil, color: '#64748b', style: nil, penwidth: 2, **attr)
    links(from, *to_nodes, label: label, color: color, style: style, penwidth: penwidth, directed: false, **attr)
  end

  def chain(*nodes, label: nil, color: '#64748b', style: nil, penwidth: 2, dir: nil, directed: true, op: nil, **attr)
    flat = nodes.flatten
    return '' if flat.size < 2
    flat.each_cons(2).map { |a, b| link(a, b, label: label, color: color, style: style, penwidth: penwidth, dir: dir, directed: directed, op: op, **attr) }.join
  end

  def uchain(*nodes, label: nil, color: '#64748b', style: nil, penwidth: 2, **attr)
    chain(*nodes, label: label, color: color, style: style, penwidth: penwidth, directed: false, **attr)
  end

  def cluster_start(id, label: nil, color: nil, fillcolor: nil, fontcolor: nil, style: 'rounded,filled', **attr)
    th = current_theme
    border_col = color || th[:cluster_border]
    bg_col = fillcolor || th[:cluster_bg]
    fc = fontcolor || th[:cluster_text]
    fn = th[:fontname]

    extra_lines = attr.map do |k, v|
      next nil if v.nil?
      key = k.to_s.gsub(/[^a-zA-Z0-9_]/, '')
      next nil if key.empty?
      "  #{key} = #{format_dot_val(v)};\n"
    end.compact.join

    <<~DOT
      subgraph cluster_#{safe_id(id)} {
        label = #{h(label || id).inspect};
        color = "#{border_col}";
        fillcolor = "#{bg_col}";
        style = "#{style}";
        fontcolor = "#{fc}";
        fontname = "#{fn}";
        fontsize = "13";
      #{extra_lines}
    DOT
  end

  def cluster_end
    "  }\n"
  end

  def cluster(id, label: nil, nodes: [], color: '#475569', fillcolor: '#131d31', fontcolor: '#cbd5e1', style: 'rounded,filled', **attr, &block)
    header = cluster_start(id, label: label, color: color, fillcolor: fillcolor, fontcolor: fontcolor, style: style, **attr)
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
