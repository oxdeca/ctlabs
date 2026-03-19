# -----------------------------------------------------------------------------
# File        : ctlabs/helpers/yaml_helper.rb
# License     : MIT License
# -----------------------------------------------------------------------------

module YamlHelper
  # Helper to beautifully format nested YAML arrays strictly inline
  def write_formatted_yaml(path, data, original_path = nil)
    # 1. Steal the header from the original file (if it exists)
    header_text = ""
    source_file = original_path || path
    
    if File.exist?(source_file)
      content = File.read(source_file)
      
      # FIX: Match the optional '---' at the top, then grab all comments and blank lines!
      header_match = content.match(/\A(?:---\r?\n)?(?:#.*\r?\n|\s*\r?\n)*/)
      header_text = header_match ? header_match[0] : ""
    end

    yaml_str = data.to_yaml
    yaml_str.sub!(/\A---\r?\n/, '') # Strip generic '---' added by Ruby (the header text already has yours)

    # 2. Clean up psych array formatting for nested 2-element or 3-element arrays
    yaml_str.gsub!(/^(\s*)-\s*-\s*(.+?)\n\1\s{2}-\s*(.+?)\n(?:\1\s{2}-\s*(.+?)\n)?/) do |match|
      indent = $1
      v1, v2, v3 = $2.strip, $3.strip, $4&.strip

      # Remove surrounding quotes if psych added them
      v1 = v1[1..-2] if v1.start_with?('"') && v1.end_with?('"') || v1.start_with?("'") && v1.end_with?("'")
      v2 = v2[1..-2] if v2.start_with?('"') && v2.end_with?('"') || v2.start_with?("'") && v2.end_with?("'")
      v3 = v3[1..-2] if v3 && (v3.start_with?('"') && v3.end_with?('"') || v3.start_with?("'") && v3.end_with?("'"))

      # Re-quote if it looks like an interface string
      v1 = "\"#{v1}\"" if v1.match?(/[a-zA-Z]+.*:/)
      v2 = "\"#{v2}\"" if v2.match?(/[a-zA-Z]+.*:/)

      if v3
        v3 = "\"#{v3}\"" if v3.match?(/[a-zA-Z]+.*:/)
        "#{indent}- [ #{v1}, #{v2}, #{v3} ]\n"
      else
        "#{indent}- [ #{v1}, #{v2} ]\n"
      end
    end

    # Remove empty 'nics: {}' if it was stripped down to nothing
    yaml_str.gsub!(/\n\s*nics:\s*\{\}/, '')

    # 3. Inject blank lines before major sections to restore readability
    yaml_str.gsub!(/^(defaults|topology|links):/, "\n\\1:")

    # 4. Write it to disk with the original header safely glued on top!
    File.write(path, header_text + yaml_str)
  end

  # Heavy text-replacement scanner for the Lab Meta Edit feature
  def update_lab_metadata_file(full_path, params)
    lines = File.readlines(full_path)

    formatted_vm_dns = params[:vm_dns].to_s.split(',').map(&:strip).reject(&:empty?).join(', ')
    formatted_mgmt_dns = params[:mgmt_dns].to_s.split(',').map(&:strip).reject(&:empty?).join(', ')

    new_lines = []
    in_topology = false
    in_vm = false
    in_mgmt = false
    in_nodes = false

    seen = { name: false, desc: false, vm_name: false, vm_dns: false, vrfid: false, mgmt_dns: false, net: false, gw: false }

    lines.each do |line|
      if line.match?(/^\s+nodes:/) || line.match?(/^\s+links:/)
        in_nodes = true
      end

      if in_nodes
        new_lines << line
        next
      end

      if line.match?(/^topology:/)
        in_topology = true
      elsif in_topology && line.match?(/^\s+- vm:/)
        in_vm = true
      elsif in_vm && line.match?(/^\s+mgmt:/)
        in_mgmt = true
      end

      if !in_topology && line.match?(/^name:/)
        new_lines << "name: #{params[:name]}\n"
        seen[:name] = true
      elsif !in_topology && line.match?(/^desc:/)
        new_lines << "desc: #{params[:desc]}\n"
        seen[:desc] = true
      elsif in_vm && !in_mgmt && line.match?(/^\s+name:/)
        new_lines << "    name: #{params[:vm_name]}\n"
        seen[:vm_name] = true
      elsif in_vm && !in_mgmt && line.match?(/^\s+dns\s*:/)
        new_lines << "    dns : [#{formatted_vm_dns}]\n"
        seen[:vm_dns] = true
      elsif in_mgmt && line.match?(/^\s+vrfid\s*:/)
        new_lines << "      vrfid : #{params[:mgmt_vrfid]}\n"
        seen[:vrfid] = true
      elsif in_mgmt && line.match?(/^\s+dns\s*:/)
        new_lines << "      dns   : [#{formatted_mgmt_dns}]\n"
        seen[:mgmt_dns] = true
      elsif in_mgmt && line.match?(/^\s+net\s*:/)
        new_lines << "      net   : #{params[:mgmt_net]}\n"
        seen[:net] = true
      elsif in_mgmt && line.match?(/^\s+gw\s*:/)
        new_lines << "      gw    : #{params[:mgmt_gw]}\n"
        seen[:gw] = true
      elsif line.match?(/^defaults:/) || line.match?(/^topology:/)
        new_lines << "name: #{params[:name]}\n" unless seen[:name]
        new_lines << "desc: #{params[:desc]}\n" unless seen[:desc]
        new_lines << line
      elsif in_vm && !in_mgmt && line.match?(/^\s+mgmt:/)
        new_lines << "    name: #{params[:vm_name]}\n" unless seen[:vm_name] || params[:vm_name].empty?
        new_lines << "    dns : [#{formatted_vm_dns}]\n" unless seen[:vm_dns] || formatted_vm_dns.empty?
        new_lines << line
      elsif in_mgmt && line.match?(/^\s+nodes:/)
        new_lines << "      vrfid : #{params[:mgmt_vrfid]}\n" unless seen[:vrfid] || params[:mgmt_vrfid].empty?
        new_lines << "      dns   : [#{formatted_mgmt_dns}]\n" unless seen[:mgmt_dns] || formatted_mgmt_dns.empty?
        new_lines << "      net   : #{params[:mgmt_net]}\n" unless seen[:net] || params[:mgmt_net].empty?
        new_lines << "      gw    : #{params[:mgmt_gw]}\n" unless seen[:gw] || params[:mgmt_gw].empty?
        new_lines << line
      else
        new_lines << line
      end
    end

    File.write(full_path, new_lines.join)
  end
end
