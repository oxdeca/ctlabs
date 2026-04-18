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

      defaults:
        controller:
          linux:
            image: ctlabs/c9/ctrl
        switch:
          mgmt:
            image: ctlabs/c9/ctrl
            ports: 16
          linux:
            image: ctlabs/c9/base
            ports: 6
        host:
          linux:
            image: ctlabs/c9/base
          db2:
            image: ctlabs/misc/db2
            caps: [SYS_NICE,IPC_LOCK,IPC_OWNER]
          cbeaver:
            image: ctlabs/misc/cbeaver
          d12:
            image: ctlabs/d12/base
          kali:
            image: ctlabs/kali/base
          parrot:
            image: ctlabs/parrot/base
          slapd:
            image: ctlabs/d12/base
            caps: [SYS_PTRACE]
        router:
          frr:
            image: ctlabs/c9/frr
            caps : [SYS_NICE,NET_BIND_SERVICE]
          mgmt:
            image: ctlabs/c9/frr
            caps : [SYS_NICE,NET_BIND_SERVICE]

      topology:
        - name: #{base_name}-vm1
          dns : [192.168.10.11, 192.168.10.12, 8.8.8.8]
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
              type  : switch
              kind  : mgmt
              ipv4  : 192.168.99.11/24
              gw    : 192.168.99.1
            ro0:
              type : router
              kind : mgmt
              gw   : 192.168.15.1
              nics :
                eth0: 192.168.99.1/24
                eth1: 192.168.15.2/29
            natgw:
              type : gateway
              ipv4 : 192.168.15.1/29
              snat : true
              dnat : ro1:eth1
            sw1:
              type : switch
            sw2:
              type : switch
            sw3:
              type : switch
            ro1:
              type : router
              kind : frr
              gw   : 192.168.15.1
              nics :
                eth1: 192.168.15.3/29
                eth2: 192.168.10.1/24
                eth3: 192.168.20.1/24
                eth4: 192.168.30.1/24
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
