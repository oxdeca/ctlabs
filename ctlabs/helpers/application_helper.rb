# -----------------------------------------------------------------------------
# File        : ctlabs/helpers/application_helper.rb
# License     : MIT License
# -----------------------------------------------------------------------------

module ApplicationHelper
  def ansi_to_html(text)
    color_map = {
      '30' => '#000',   '31' => '#a00',   '32' => '#0a0',   '33' => '#aa0',
      '34' => '#00a',   '35' => '#a0a',   '36' => '#0aa',   '37' => '#aaa',
      '90' => '#555',   '91' => '#f55',   '92' => '#5f5',   '93' => '#ff5',
      '94' => '#55f',   '95' => '#f5f',   '96' => '#5ff',   '97' => '#fff',
    }

    html = ''
    current_color = nil

    parts = text.split(/(\e\[[\d;]*m)/)
    parts.each do |part|
      if part.start_with?("\e[")
        code = part[2..-2] || ''
        if code == '0' || code.empty?
          if current_color
            html += '</span>'
            current_color = nil
          end
        else
          color_codes = code.split(';').grep(/\A\d+\z/)
          fg = color_codes.find { |c| c.start_with?('3') || c.start_with?('9') }
          if fg && color_map[fg]
            if current_color
              html += '</span>'
            end
            html += "<span style='color:#{color_map[fg]}'>"
            current_color = fg
          end
        end
      else
        html += ERB::Util.h(part)
      end
    end

    html += '</span>' if current_color
    html 
  end

  # Accent colors for the pill "tag" badges below, keyed by node type.
  NODE_TYPE_COLORS = {
    'controller' => '#a78bfa',
    'switch'     => '#22d3ee',
    'router'     => '#fb923c',
    'host'       => '#34d399',
    'gateway'    => '#f472b6',
    'server'     => '#60a5fa',
    'firewall'   => '#f87171',
    'rhost'      => '#94a3b8',
    'external'   => '#94a3b8',
  }.freeze

  # A small pill "tag" matching the Ansible-tag styling in the Automation card
  # (views/cards/automation.erb): dark slate fill, colored text + matching
  # border. Use this instead of the low-contrast `w3-badge` grey chips.
  def tag_badge(text, color: '#34d399')
    return '' if text.nil? || text.to_s.strip.empty?

    "<span style=\"display: inline-block; background-color: #1e293b; " \
      "color: #{color}; border: 1px solid #{color}; padding: 1px 8px; " \
      "border-radius: 10px; font-weight: 600; margin: 0 4px 2px 0; " \
      "white-space: nowrap;\">#{ERB::Util.h(text)}</span>"
  end

  def node_type_badge(type)
    return '' if type.nil?

    tag_badge(type, color: NODE_TYPE_COLORS[type.to_s] || '#cbd5e1')
  end

  def proto_badge(proto)
    p = proto.to_s.upcase
    tag_badge(p, color: p == 'UDP' ? '#fbbf24' : '#60a5fa')
  end

  def all_labs
    Lab.all
  end

  # Lab name for display: drops the trailing `.yml` (e.g. 'net/net01.yml' ->
  # 'net/net01'). Display-only; never use the result for path lookups.
  def lab_display_name(name)
    Lab.display_name(name)
  end

  def running_lab?
    Lab.running?
  end

  def get_running_lab
    Lab.current_name
  end

  def parse_lab_info(yaml_file_path, adhoc_rules_by_lab = {})
    Lab.metadata(yaml_file_path, adhoc_rules_by_lab)
  end

  def refresh_lab_visuals(lab_name, force: false)
    Lab.refresh_visuals(lab_name, force: force)
  end
end
