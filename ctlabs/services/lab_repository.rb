# -----------------------------------------------------------------------------
# File        : ctlabs/services/lab_repository.rb
# Description : Service object for Lab file system operations
# License     : MIT License
# -----------------------------------------------------------------------------

require 'yaml'
require 'fileutils'

class LabRepository
  def self.labs_dir
    defined?(::LABS_DIR) ? ::LABS_DIR : File.expand_path('../../labs', __dir__)
  end

  def self.create_lab(lab_name, desc)
    lab_name = lab_name.to_s.strip.gsub(/[^a-zA-Z0-9_\-\/]/, '') # sanitize
    lab_name += '.yml' unless lab_name.end_with?('.yml')
    lab_path = File.join(labs_dir, lab_name)

    raise "A lab with that filename already exists!" if File.exist?(lab_path)

    FileUtils.mkdir_p(File.dirname(lab_path))
    
    # Base name without the .yml extension
    base_name = File.basename(lab_name, '.yml')

    # Use a Heredoc to perfectly preserve spacing, alignment, and arrays!
    default_yaml = <<~YAML
      # -----------------------------------------------------------------------------
      # File        : ctlabs/labs/#{lab_name}
      # Description : #{desc}
      # -----------------------------------------------------------------------------

      name: #{base_name}
      desc: #{desc}

      topology:
        - hv: #{base_name}-vm1
          dns : [192.168.10.11, 192.168.10.12, 8.8.8.8]
          planes:
            mgmt:
              vrfid : 99
              dns   : [1.1.1.1, 8.8.8.8]
              net   : 192.168.99.0/24
              gw    : 192.168.99.1
            nodes:
              ansible :
                type : controller
                gw   : 192.168.99.1
                nics :
                  eth0: 192.168.99.3/24
                vols : ['/root/ctlabs-ansible/:/root/ctlabs-ansible/:Z,rw', '/srv/jupyter/ansible/:/srv/jupyter/work/:Z,rw']
                play: 
                  book: ctlabs.yml
                  tags: [up, setup, ca, bind, jupyter, smbadc, slapd, sssd]
                dnat :
                  - [9988, 8888]
              sw0:
                profile: mgmt
                type: switch
                ipv4: 192.168.99.11/24
                gw  : 192.168.99.1
              ro0:
                profile: mgmt
                type: router
                gw  : 192.168.15.1
                nics:
                  eth0: 192.168.99.1/24
                  eth1: 192.168.15.2/29

          edge:
            nodes:
              natgw:
                type: gateway
                ipv4: 192.168.15.1/29
                snat: true
                dnat: 
                  data: ro1:eth1
                  mgmt: ro0:eth1

          transit:
            nodes:
              ro1:
                profile: frr
                type: router
                gw  : 192.168.15.1
                nics:
                  eth1: 192.168.15.3/29
                  eth2: 192.168.10.1/24
                  eth3: 192.168.20.1/24
                  eth4: 192.168.30.1/24

          data:
            nodes:
              sw1:
                type : switch
              sw2:
                type : switch
              sw3:
                type : switch

          links: []
    YAML

    File.write(lab_path, default_yaml)
    lab_name
  end

  def self.save_lab(lab_name, data, original_path = nil)
    lab_path = File.join(labs_dir, lab_name)
    write_formatted_yaml(lab_path, data, original_path)
  end

  # Helper to beautifully format nested YAML arrays strictly inline (Moved from YamlHelper)
  def self.write_formatted_yaml(path, data, original_path = nil)
    # 1. Steal the header from the original file (if it exists)
    header_text = ""
    source_file = original_path || path
    
    if File.exist?(source_file)
      content = File.read(source_file)
      header_match = content.match(/\A(?:---\r?\n)?(?:#.*\r?\n|\s*\r?\n)*/)
      header_text = header_match ? header_match[0] : ""
    end

    yaml_str = data.to_yaml
    yaml_str.sub!(/\A---\r?\n/, '') # Strip generic '---' added by Ruby

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

  # Dedent + extract the raw `setup:` block of the ansible controller's `play:`
  # section as text (for display/metadata). Returns '' when absent.
  def self.extract_play_setup_raw(path)
    lines = File.read(path).lines
    play_idx = lines.index { |l| l =~ /^\s*play:\s*/ }
    return '' unless play_idx

    play_indent = lines[play_idx][/\A\s+/].to_s.length
    block_end = play_idx + 1
    while block_end < lines.length
      l = lines[block_end]
      break if l =~ /\S/ && l[/\A\s+/].to_s.length <= play_indent
      block_end += 1
    end

    setup_idx = nil
    (play_idx + 1...block_end).each do |i|
      if lines[i] =~ /^(\s*)setup:/
        setup_idx = i
        break
      end
    end
    return '' unless setup_idx

    setup_indent = lines[setup_idx][/\A\s+/].to_s.length
    end_idx = setup_idx + 1
    end_idx += 1 while end_idx < block_end && lines[end_idx][/\A\s+/].to_s.length > setup_indent

    body = lines[(setup_idx + 1)...end_idx]
    base = body.reject { |l| l.strip.empty? }.map { |l| l[/\A\s+/].to_s.length }.min || setup_indent + 2
    base = [base, setup_indent + 2].min
    body.map do |l|
      if l.strip.empty?
        "\n"
      else
        l.sub(/\A {#{base}}/, '')
      end
    end.join
  end

  # Surgical patch of the ansible controller's `play:` block.
  # Only the play keys that differ from `old_play` are rewritten; all other
  # lines of the file are preserved byte-for-byte (comments, flow style,
  # alignment, other nodes). `raw_overrides` maps a play key (e.g. 'setup') to
  # the verbatim text the user typed in the editor; those keys are spliced
  # verbatim instead of re-serialized. Returns true if any change was written.
  def self.update_ansible_play(path, old_play, new_play, raw_overrides = {})
    original = File.read(path)
    lines = original.lines

    play_idx = lines.index { |l| l =~ /^\s*play:\s*/ }
    raise "No 'play:' block found in #{path}" unless play_idx

    play_indent = lines[play_idx][/\A\s+/].to_s.length
    # block spans from 'play:' line to the first line at same-or-lesser indent
    block_end = play_idx + 1
    while block_end < lines.length
      l = lines[block_end]
      break if l =~ /\S/ && l[/\A\s+/].to_s.length <= play_indent
      block_end += 1
    end

    old_play = {} if old_play.nil? || !old_play.is_a?(Hash)
    new_play = {} if new_play.nil? || !new_play.is_a?(Hash)

    changed_keys = (old_play.keys | new_play.keys).select do |k|
      next true if new_play.key?(k) && raw_overrides.key?(k) && !new_play[k].nil? # raw keys always spliced
      old_play[k] != new_play[k]
    end
    return false if changed_keys.empty?

    # Helper: locate each key's span within the play block (start..finish).
    spans = {}
    idx = play_idx + 1
    while idx < block_end
      indent = lines[idx][/\A\s+/].to_s.length
      if indent == play_indent + 2 && lines[idx] =~ /^\s*([A-Za-z0-9_]+):/
        key = $1
        kstart = idx
        kend = idx + 1
        kend += 1 while kend < block_end && lines[kend][/\A\s+/].to_s.length > play_indent + 2
        spans[key] = { start: kstart, finish: kend }
      end
      idx += 1
    end

    # Serialize a single play key value back into indented lines.
    serializer = lambda do |key, value, base_indent|
      key_line = " " * base_indent + "#{key}:"
      return [key_line + "\n"] if value.nil? || value == false || value == true

      if value.is_a?(String) || value.is_a?(Numeric)
        [key_line + " " + value.to_s + "\n"]
      elsif value.is_a?(Array)
        flow = value.map { |v| v.is_a?(String) ? v : v.to_s }
        [key_line + " [" + flow.join(", ") + "]\n"]
      elsif value.is_a?(Hash)
        out = [key_line + "\n"]
        yaml_str = value.to_yaml
        yaml_str.sub!(/\A---\r?\n/, "")
        yaml_str.lines.each do |l|
          next if l.strip.empty?
          out << (" " * (base_indent + 2)) + l.sub(/^\s+/, "").sub(/\n\z/, "") + "\n"
        end
        out
      else
        [key_line + " " + value.to_s + "\n"]
      end
    end

    # Re-indent a verbatim raw block under a key. Raw text is dedented to a
    # base (rel=0 at the body's first key); map rel -> key_indent+2+rel so the
    # user's exact relative structure byte-survives.
    verbatim = lambda do |key, raw, key_indent|
      out = [" " * key_indent + "#{key}:" + "\n"]
      raw.each_line do |l|
        l = l.sub(/\r?\n\z/, '')
        next if l.strip.empty?
        rel = l[/\A\s+/].to_s.length
        content = l.strip
        out << (" " * (key_indent + 2 + rel) + content + "\n")
      end
      out
    end

    body_indent = play_indent + 2

    # Build the new block by splicing only changed keys in original key order.
    rebuilt = []
    used = {}
    idx = play_idx + 1
    while idx < block_end
      line = lines[idx]
      indent = line[/\A\s+/].to_s.length
      if indent == body_indent && line =~ /^\s*([A-Za-z0-9_]+):/
        key = $1
        if changed_keys.include?(key)
          span = spans[key]
          if span && span[:finish]
            if new_play.key?(key) && !new_play[key].nil?
              if raw_overrides.key?(key) && !raw_overrides[key].to_s.strip.empty? && new_play[key].is_a?(Hash)
                rebuilt.concat(verbatim.call(key, raw_overrides[key].to_s, body_indent))
              else
                rebuilt.concat(serializer.call(key, new_play[key], body_indent))
              end
            end
            used[key] = true
            idx = span[:finish]
            next
          end
        end
      end
      rebuilt << line
      idx += 1
    end

    # Append any brand-new keys (not already spliced) at the end of the play block.
    (new_play.keys - old_play.keys - used.keys).each do |key|
      if raw_overrides.key?(key) && new_play[key].is_a?(Hash) && !raw_overrides[key].to_s.strip.empty?
        rebuilt.concat(verbatim.call(key, raw_overrides[key].to_s, body_indent))
      else
        rebuilt.concat(serializer.call(key, new_play[key], body_indent))
      end
    end

    File.write(path, original.lines[0...play_idx].join + lines[play_idx] + rebuilt.join + original.lines[block_end..-1].join)
    true
  end

  # Heavy text-replacement scanner for the Lab Meta Edit feature (Moved from YamlHelper)
  def self.update_metadata(lab_name, params)
    full_path = File.join(labs_dir, lab_name)
    raise "Lab file not found: #{full_path}" unless File.exist?(full_path)

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
