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

  def all_labs
    Lab.all
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
