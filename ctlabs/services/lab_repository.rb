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

  # Render a single key/value pair as YAML lines, shifted to `indent` columns.
  # Psych decides the shape (block vs flow, quoting, nesting); we only move the
  # left edge. This is the one primitive the surgical editors build on.
  def self.pair_lines(key, value, indent)
    { key => value }.to_yaml
                     .sub(/\A---\r?\n/, '')
                     .lines
                     .reject { |l| l.strip.empty? }
                     .map { |l| (" " * indent) + l }
  end

  # Write a lab YAML file: Psych's serialization of `data`, with the original
  # file's header comment block glued back on top.
  #
  # Psych is the only thing that decides YAML shape here. No regex passes, no
  # hand-shaped lists, no key alignment -- patching serialized output textually
  # is what produced half-rewritten values (a `tags: [a, b, c]` key left sitting
  # on top of its own orphaned `- a` / `- b` items, which doesn't parse), and it
  # breaks again on every Psych upgrade. Lists come out in whatever style Psych
  # writes; that is always valid.
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
    yaml_str.sub!(/\A---\r?\n/, '') # Drop the generic '---' document marker Psych adds

    # 2. Write it to disk with the original header safely glued on top!
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

  # End of the block that belongs to the key starting at `idx`.
  #
  # A key owns every following line indented deeper than it, *plus* any block
  # sequence item written flush with the key itself. Psych's `to_yaml` puts
  # `- item` at the key's own indent (`tags:` then `- up`), so a purely
  # "deeper than the key" scan leaves those items orphaned behind and the
  # spliced-in short form lands on top of them.
  def self.block_span_end(lines, idx, block_end, key_indent)
    kend = idx + 1
    while kend < block_end
      line = lines[kend]
      break if line.strip.empty?

      indent = line[/\A\s+/].to_s.length
      if indent > key_indent
        kend += 1
      elsif indent == key_indent && line =~ /\A\s*-(?:\s|\z)/
        kend += 1
      else
        break
      end
    end
    kend
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
        spans[key] = { start: kstart, finish: block_span_end(lines, idx, block_end, play_indent + 2) }
      end
      idx += 1
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
                rebuilt.concat(pair_lines(key, new_play[key], body_indent))
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
        rebuilt.concat(pair_lines(key, new_play[key], body_indent))
      end
    end

    File.write(path, original.lines[0...play_idx].join + lines[play_idx] + rebuilt.join + original.lines[block_end..-1].join)
    true
  end

  # Index of `key:` inside `lines[from...to]`, or nil.
  def self.find_key(lines, from, to, key, indent)
    return nil if indent.nil?
    (from...to).each do |i|
      next unless lines[i][/\A\s*/].to_s.length == indent
      return i if lines[i] =~ /\A\s*#{Regexp.escape(key)}\s*:/
    end
    nil
  end

  # Lab Meta Edit. Supports the current schema only:
  #
  #   name / desc                      (top level)
  #   - hv: <vm_name>                  (vm level; the diagram's "Hypervisor" label)
  #   dns : [...]                      (vm level)
  #   planes: mgmt: vrfid/dns/net/gw   (mgmt plane)
  #
  # The legacy `- vm:` + vm-level `mgmt:` layout was deliberately dropped. It
  # used a boolean state machine keyed off `- vm:` and `mgmt:`, so on every
  # modern lab it silently rewrote nothing but `name`/`desc` instead of erroring.
  # Navigation is indent-driven off `block_span_end` now, and `hv`/`planes.mgmt`
  # must be found or the edit is refused -- a lab that changes shape later fails
  # loudly rather than half-applying.
  def self.update_metadata(lab_name, params)
    full_path = File.join(labs_dir, lab_name)
    raise "Lab file not found: #{full_path}" unless File.exist?(full_path)

    lines = File.readlines(full_path)
    n     = lines.length

    vm_dns   = params[:vm_dns].to_s.split(',').map(&:strip).reject(&:empty?)
    mgmt_dns = params[:mgmt_dns].to_s.split(',').map(&:strip).reject(&:empty?)

    # The form hands every value back as a String, but `vrfid` lives in the file
    # as an Integer. Coerce back, otherwise Psych -- correctly -- quotes "99" and
    # the VRF id silently changes type on every meta edit.
    mgmt_vrfid = params[:mgmt_vrfid].to_s.strip
    mgmt_vrfid = Integer(mgmt_vrfid, exception: false) || mgmt_vrfid

    top_idx = find_key(lines, 0, n, 'topology', 0)
    raise "No 'topology:' block in #{lab_name}" if top_idx.nil?
    top_end = block_span_end(lines, top_idx, n, 0)

    hv_idx = (top_idx...top_end).find { |i| lines[i] =~ /\A\s*-\s+hv\s*:/ }
    raise "No '- hv:' VM entry in #{lab_name} (legacy '- vm:' schema is no longer supported)" if hv_idx.nil?

    hv_indent = lines[hv_idx][/\A\s*/].length
    planes_idx = find_key(lines, hv_idx + 1, top_end, 'planes', hv_indent + 2)
    raise "No 'planes:' block under the VM in #{lab_name}" if planes_idx.nil?
    planes_end = block_span_end(lines, planes_idx, top_end, hv_indent + 2)

    mgmt_idx = find_key(lines, planes_idx + 1, planes_end, 'mgmt', hv_indent + 4)
    raise "No 'mgmt:' plane in #{lab_name}" if mgmt_idx.nil?
    mgmt_end = block_span_end(lines, mgmt_idx, planes_end, hv_indent + 4)
    mgmt_indent = hv_indent + 6

    edits  = {}   # idx => replacement lines
    ins    = {}   # idx => lines to insert before it
    cut    = {}   # idx => first line index NOT consumed by the edit at idx
    seen   = {}

    # A key's span, not just its line: `dns:` may be a block list, and replacing
    # only the key line leaves the old `- item` entries dangling underneath the
    # new ones (rke201, srv03, sys02 all hit this). block_span_end swallows them.
    span = lambda do |idx, limit, indent|
      cut[idx] = block_span_end(lines, idx, limit, indent)
    end

    [['name', :name], ['desc', :desc]].each do |key, field|
      i = find_key(lines, 0, top_idx, key, 0)
      if i
        edits[i] = pair_lines(key, params[field], 0)
        span.call(i, top_idx, 0)
        seen[field] = true
      elsif !params[field].to_s.empty?
        ins[top_idx] ||= []
        ins[top_idx].concat(pair_lines(key, params[field], 0))
      end
    end

    # `hv` holds the value, so rewrite the scalar in place instead of emitting a
    # `hv:` key line -- keeps the hand-written `- hv: name` sequence-item form.
    # The scalar itself still comes from Psych, so quoting stays correct.
    hv_val = params[:vm_name].to_s.strip
    unless hv_val.empty?
      prefix    = lines[hv_idx][/\A[ \t]*/]
      rest     = lines[hv_idx].sub(/\A[ \t]*/, '')
      key_part = rest[/\A-[ \t]*hv[ \t]*:/]
      rendered = pair_lines('x', hv_val, 0).first.chomp.sub(/\Ax:[ \t]*/, '')
      edits[hv_idx] = ["#{prefix}#{key_part} #{rendered}\n"]
      # No span: `hv` is a scalar on the `- hv:` sequence item. Its "key indent"
      # is the sequence indent, so every nested line is deeper and a span would
      # swallow the entire topology.
    end

    dns_idx = find_key(lines, hv_idx + 1, planes_idx, 'dns', hv_indent + 2)
    if dns_idx
      edits[dns_idx] = pair_lines('dns', vm_dns, hv_indent + 2)
      span.call(dns_idx, planes_idx, hv_indent + 2)
      seen[:vm_dns] = true
    elsif !vm_dns.empty?
      ins[planes_idx] ||= []
      ins[planes_idx].concat(pair_lines('dns', vm_dns, hv_indent + 2))
    end

    mgmt_fields = {
      'vrfid' => mgmt_vrfid,
      'dns'   => mgmt_dns,
      'net'   => params[:mgmt_net],
      'gw'    => params[:mgmt_gw]
    }
    mgmt_fields.each do |key, val|
      i = find_key(lines, mgmt_idx + 1, mgmt_end, key, mgmt_indent)
      if i
        edits[i] = pair_lines(key, val, mgmt_indent)
        span.call(i, mgmt_end, mgmt_indent)
        seen[key.to_sym] = true
      elsif !val.to_s.empty?
        nodes_idx = find_key(lines, mgmt_idx + 1, mgmt_end, 'nodes', mgmt_indent)
        anchor    = nodes_idx || mgmt_end
        ins[anchor] ||= []
        ins[anchor].concat(pair_lines(key, val, mgmt_indent))
      end
    end

    out = []
    i = 0
    while i < n
      out.concat(ins[i])   if ins[i]
      out.concat(edits[i]) if edits[i]
      out << lines[i] unless edits[i]
      i = cut[i] || (i + 1)
    end

    File.write(full_path, out.join)
    true
  end
end
