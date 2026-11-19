# -----------------------------------------------------------------------------
# File        : ctlabs/services/automation_service.rb
# Description : Service for Ansible and Terraform operations
# License     : MIT License
# -----------------------------------------------------------------------------

require 'fileutils'
require 'json'
require 'yaml'
require 'open3'
require 'shellwords'
require 'tempfile'

class AutomationService
  ANS_BASE_DIR = '/root/ctlabs-ansible'.freeze
  TF_BASE_DIR = '/root/ctlabs-terraform'.freeze

  def self.container_running?(name)
    return false if name.to_s.strip.empty?
    out = `docker inspect -f '{{.State.Running}}' #{Shellwords.escape(name)} 2>/dev/null`.to_s.strip
    out == 'true'
  end

  def self.resolve_ansible_dir(dir = nil)
    d = dir.to_s.strip
    return ANS_BASE_DIR if d.empty?
    d.start_with?('/') ? d : File.join(ANS_BASE_DIR, d)
  end

  def self.resolve_terraform_dir(dir = nil)
    d = dir.to_s.strip
    return TF_BASE_DIR if d.empty?
    d.start_with?('/') ? d : File.join(TF_BASE_DIR, d)
  end

  def self.ansible_tree(root_dir = nil, container: nil)
    base = resolve_ansible_dir(root_dir)

    # 1. If container is specified and running, query inside the container directly
    if container_running?(container)
      has_dir = system("docker exec #{container} test -d #{Shellwords.escape(base)} 2>/dev/null")
      if has_dir
        cmd = "docker exec #{container} find -L #{Shellwords.escape(base)} -mindepth 1 -not -path '*/.*' -printf '%p|%Y\\n' 2>/dev/null"
        out = `#{cmd}` rescue ''
        if out && !out.strip.empty?
          prefix = base.end_with?('/') ? base : "#{base}/"
          return out.lines.map(&:strip).reject(&:empty?).map do |line|
            p, type = line.split('|', 2)
            rel = p.sub(%r{\A#{Regexp.escape(prefix)}}, '')
            next if rel.empty? || rel.include?('/.git/') || rel.include?('/__pycache__/') || rel.include?('/.idea/')
            type == 'd' ? "#{rel}/" : rel
          end.compact.sort
        end
      end
    end

    # 2. Host fallback if directory exists on host
    if Dir.exist?(base)
      Dir.glob(File.join(base, "**", "*"))
         .reject { |f| f.include?('/.git/') || f.include?('/__pycache__/') || f.include?('/.idea/') }
         .map { |f| File.directory?(f) ? "#{f.sub(base + '/', '')}/" : f.sub(base + '/', '') }
         .sort
    else
      # 3. Secondary fallback: check known controller containers
      items = []
      cnames = [defined?(Controller::NAME) ? Controller::NAME : 'ctl-ctrl', 'ansible']
      cnames.each do |cname|
        next unless container_running?(cname)
        has_dir = system("docker exec #{cname} test -d #{Shellwords.escape(base)} 2>/dev/null")
        if has_dir
          cmd = "docker exec #{cname} find -L #{Shellwords.escape(base)} -mindepth 1 -not -path '*/.*' -printf '%p|%Y\\n' 2>/dev/null"
          out = `#{cmd}` rescue ''
          if out && !out.strip.empty?
            prefix = base.end_with?('/') ? base : "#{base}/"
            items = out.lines.map(&:strip).reject(&:empty?).map do |line|
              p, type = line.split('|', 2)
              rel = p.sub(%r{\A#{Regexp.escape(prefix)}}, '')
              next if rel.empty? || rel.include?('/.git/') || rel.include?('/__pycache__/') || rel.include?('/.idea/')
              type == 'd' ? "#{rel}/" : rel
            end.compact.sort
            break
          end
        end
      end
      items
    end
  end

  def self.read_ansible_file(filepath, root_dir = nil, container: nil)
    base = resolve_ansible_dir(root_dir)
    full_path = File.join(base, filepath)

    # 1. If container is specified and running, read from container directly
    if container_running?(container)
      out, status = Open3.capture2("docker exec #{container} cat #{Shellwords.escape(full_path)} 2>/dev/null")
      return out if status.success?
    end

    # 2. Host fallback
    if File.file?(full_path)
      File.read(full_path)
    else
      # 3. Secondary container fallback
      content = nil
      cnames = [defined?(Controller::NAME) ? Controller::NAME : 'ctl-ctrl', 'ansible']
      cnames.each do |cname|
        next unless container_running?(cname)
        out, status = Open3.capture2("docker exec #{cname} cat #{Shellwords.escape(full_path)} 2>/dev/null")
        if status.success?
          content = out
          break
        end
      end
      content || "# New file: #{filepath}\n"
    end
  end

  def self.write_ansible_files(files_hash, root_dir = nil, container: nil)
    base = resolve_ansible_dir(root_dir)
    target_containers = []
    target_containers << container if container && container_running?(container)
    if target_containers.empty?
      cnames = [defined?(Controller::NAME) ? Controller::NAME : 'ctl-ctrl', 'ansible']
      target_containers = cnames.select { |c| container_running?(c) }
    end

    files_hash.each do |filepath, content|
      next if filepath.include?('..') || filepath.start_with?('/')
      full_path = File.join(base, filepath)

      # 1. Write to container(s)
      target_containers.each do |cname|
        c_dir = File.dirname(full_path)
        system("docker exec #{cname} mkdir -p #{Shellwords.escape(c_dir)} 2>/dev/null")
        t = Tempfile.new('ans_write')
        t.write(content)
        t.close
        system("docker cp #{Shellwords.escape(t.path)} #{cname}:#{Shellwords.escape(full_path)} 2>/dev/null")
        if filepath.end_with?('.py') || filepath.end_with?('.sh')
          system("docker exec #{cname} chmod 0755 #{Shellwords.escape(full_path)} 2>/dev/null")
        else
          system("docker exec #{cname} chmod 0644 #{Shellwords.escape(full_path)} 2>/dev/null")
        end
        system("docker exec #{cname} chown ansible:ansible #{Shellwords.escape(full_path)} 2>/dev/null")
        t.unlink
      end

      # 2. Write to host if base directory exists on host or if no containers are running
      if Dir.exist?(base) || target_containers.empty?
        begin
          FileUtils.mkdir_p(File.dirname(full_path))
          File.write(full_path, content)
          FileUtils.chmod(filepath.end_with?('.py') || filepath.end_with?('.sh') ? 0755 : 0644, full_path)
        rescue => e
        end
      end
    end
  end

  def self.delete_ansible_file(filepath, root_dir = nil, container: nil)
    base = resolve_ansible_dir(root_dir)
    full_path = File.join(base, filepath)

    target_containers = []
    target_containers << container if container && container_running?(container)
    if target_containers.empty?
      cnames = [defined?(Controller::NAME) ? Controller::NAME : 'ctl-ctrl', 'ansible']
      target_containers = cnames.select { |c| container_running?(c) }
    end

    target_containers.each do |cname|
      system("docker exec #{cname} rm -f #{Shellwords.escape(full_path)} 2>/dev/null")
    end

    File.delete(full_path) if File.exist?(full_path)
  end

  # --- Global role/setup/terraform profile files. The lab instance reads
  # automation/lab/, the control-plane controller automation/ctl/ (both in-repo
  # under /root/ctlabs/ctlabs/, or /root/.ctlabs/automation/<scope>/ when
  # box-locally overridden - resolved fresh on every call via the Automation
  # path helpers, not cached, so a long-lived webgui process picks up an
  # override dropped in after boot) ---
  def self.profile_files
    {
      'play_profiles.yml'          => Automation.play_profiles_path,
      'setup_profiles.yml'         => Automation.setup_profiles_path,
      'terraform_profiles.yml'     => Automation.terraform_profiles_path,
      'play_profiles_ctl.yml'      => Automation.play_profiles_ctl_path,
      'setup_profiles_ctl.yml'     => Automation.setup_profiles_ctl_path,
      'terraform_profiles_ctl.yml' => Automation.terraform_profiles_ctl_path
    }
  end

  def self.read_profile_files
    profile_files.transform_values { |path| File.file?(path) ? File.read(path) : nil }
  end

  def self.write_profile_files(files_hash)
    paths = profile_files
    files_hash.each do |filepath, content|
      next unless paths.key?(filepath)
      next if content.nil?
      begin
        YAML.safe_load(content, aliases: true)
      rescue => e
        raise "Invalid YAML in #{filepath}: #{e.message}"
      end
      File.write(paths[filepath], content)
    end
  end

  def self.terraform_tree(root_dir = nil, container: nil)
    base = resolve_terraform_dir(root_dir)

    # 1. If container is specified and running, query inside the container directly
    if container_running?(container)
      has_dir = system("docker exec #{container} test -d #{Shellwords.escape(base)} 2>/dev/null")
      if has_dir
        cmd = "docker exec #{container} find -L #{Shellwords.escape(base)} -mindepth 1 -not -path '*/.*' -printf '%p|%Y\\n' 2>/dev/null"
        out = `#{cmd}` rescue ''
        if out && !out.strip.empty?
          prefix = base.end_with?('/') ? base : "#{base}/"
          return out.lines.map(&:strip).reject(&:empty?).map do |line|
            p, type = line.split('|', 2)
            rel = p.sub(%r{\A#{Regexp.escape(prefix)}}, '')
            next if rel.empty? || rel.include?('/.terraform/') || rel.include?('/.git/') || rel.end_with?('.tfstate') || rel.end_with?('.tfstate.backup')
            type == 'd' ? "#{rel}/" : rel
          end.compact.sort
        end
      end
    end

    return [] unless Dir.exist?(base)
    Dir.glob(File.join(base, "**", "*"))
       .reject { |f| f.include?('/.terraform/') || f.include?('/.git/') || f.end_with?('.tfstate') || f.end_with?('.tfstate.backup') }
       .map { |f| File.directory?(f) ? "#{f.sub(base + '/', '')}/" : f.sub(base + '/', '') }
       .sort
  end

  def self.read_terraform_file(filepath, root_dir = nil, container: nil)
    base = resolve_terraform_dir(root_dir)
    full_path = File.join(base, filepath)

    if container_running?(container)
      out, status = Open3.capture2("docker exec #{container} cat #{Shellwords.escape(full_path)} 2>/dev/null")
      return out if status.success?
    end

    File.file?(full_path) ? File.read(full_path) : "# New file: #{filepath}\n"
  end

  def self.read_terraform_workdir_files(work_dir, root_dir = nil, container: nil)
    base = resolve_terraform_dir(root_dir)
    target_dir = File.join(base, work_dir)
    response = {'config.yml' => "", 'main.tf' => "", 'provider.tf' => ""}

    if container_running?(container)
      has_dir = system("docker exec #{container} test -d #{Shellwords.escape(target_dir)} 2>/dev/null")
      if has_dir
        cmd = "docker exec #{container} find -L #{Shellwords.escape(target_dir)} -maxdepth 1 -type f 2>/dev/null"
        out = `#{cmd}` rescue ''
        out.lines.map(&:strip).reject(&:empty?).each do |file_path|
          filename = File.basename(file_path)
          if filename.match?(/\.(tf|yml|yaml|json|sh|txt|tfvars|conf)$/i) || filename == 'Makefile'
            fcontent, fstatus = Open3.capture2("docker exec #{container} cat #{Shellwords.escape(file_path)} 2>/dev/null")
            response[filename] = fcontent if fstatus.success?
          end
        end
        return response if response.values.any? { |v| !v.empty? }
      end
    end

    if Dir.exist?(target_dir)
      Dir.glob(File.join(target_dir, "*")).each do |file_path|
        next if File.directory?(file_path)
        filename = File.basename(file_path)
        if filename.match?(/\.(tf|yml|yaml|json|sh|txt|tfvars|conf)$/i) || filename == 'Makefile'
          response[filename] = File.read(file_path)
        end
      end
    end
    response
  end

  def self.write_terraform_files(files_hash, root_dir = nil, container: nil)
    base = resolve_terraform_dir(root_dir)
    target_containers = []
    target_containers << container if container && container_running?(container)
    if target_containers.empty?
      cnames = [defined?(Controller::NAME) ? Controller::NAME : 'ctl-ctrl', 'ansible']
      target_containers = cnames.select { |c| container_running?(c) }
    end

    files_hash.each do |filepath, content|
      next if filepath.include?('..') || filepath.start_with?('/')
      full_path = File.join(base, filepath)

      target_containers.each do |cname|
        c_dir = File.dirname(full_path)
        system("docker exec #{cname} mkdir -p #{Shellwords.escape(c_dir)} 2>/dev/null")
        t = Tempfile.new('tf_write')
        t.write(content)
        t.close
        system("docker cp #{Shellwords.escape(t.path)} #{cname}:#{Shellwords.escape(full_path)} 2>/dev/null")
        t.unlink
      end

      if Dir.exist?(base) || target_containers.empty?
        begin
          FileUtils.mkdir_p(File.dirname(full_path))
          File.write(full_path, content)
        rescue => e
        end
      end
    end
  end

  def self.delete_terraform_file(filepath, root_dir = nil, container: nil)
    base = resolve_terraform_dir(root_dir)
    full_path = File.join(base, filepath)

    target_containers = []
    target_containers << container if container && container_running?(container)
    if target_containers.empty?
      cnames = [defined?(Controller::NAME) ? Controller::NAME : 'ctl-ctrl', 'ansible']
      target_containers = cnames.select { |c| container_running?(c) }
    end

    target_containers.each do |cname|
      system("docker exec #{cname} rm -f #{Shellwords.escape(full_path)} 2>/dev/null")
    end

    File.delete(full_path) if File.exist?(full_path)
  end

  def self.container_directories(req_path = nil, container: nil)
    req_path = req_path.to_s.strip
    req_path = '/root' if req_path.empty?

    if container && container_running?(container)
      py = <<-'PY'
import os, sys, json
req = sys.argv[1] if len(sys.argv) > 1 and sys.argv[1] else '/root'
p = os.path.realpath(req) if os.path.isdir(req) else ('/root' if os.path.isdir('/root') else '/')
if not os.path.isdir(req): req = p
parent = os.path.dirname(req.rstrip('/')) if req != '/' else None
if parent == '': parent = '/'
entries = []
try:
    for e in sorted(os.listdir(p)):
        if e.startswith('.') and e != '.ctlabs': continue
        full = os.path.join(p, e)
        if os.path.isdir(full):
            has_ans = os.path.isfile(os.path.join(full, 'ansible.cfg')) or os.path.isdir(os.path.join(full, 'playbooks')) or os.path.isdir(os.path.join(full, 'roles'))
            has_tf = any(f.endswith('.tf') for f in os.listdir(full)) if os.path.isdir(full) else False
            has_git = os.path.isdir(os.path.join(full, '.git'))
            display_path = os.path.join(req.rstrip('/'), e)
            entries.append({'name': e, 'path': display_path, 'has_ansible': has_ans, 'has_terraform': has_tf, 'has_git': has_git})
except Exception:
    pass

repos = {'ansible': ['/root/ctlabs-ansible'], 'terraform': ['/root/ctlabs-terraform']}
for scan_dir in ['/root', '/srv', '/srv/ctlabs', '/home']:
    if not os.path.isdir(scan_dir): continue
    try:
        for item in sorted(os.listdir(scan_dir)):
            full = os.path.join(scan_dir, item)
            if not os.path.isdir(full): continue
            if os.path.isfile(os.path.join(full, 'ansible.cfg')) or os.path.isdir(os.path.join(full, 'playbooks')) or os.path.isdir(os.path.join(full, 'roles')):
                if full not in repos['ansible']: repos['ansible'].append(full)
            if any(f.endswith('.tf') for f in os.listdir(full)):
                if full not in repos['terraform']: repos['terraform'].append(full)
    except Exception: pass

print(json.dumps({'success': True, 'current': req, 'parent': parent, 'directories': entries, 'repositories': repos}))
PY
      cmd = "docker exec #{container} python3 -c #{Shellwords.escape(py)} #{Shellwords.escape(req_path)} 2>/dev/null"
      out = `#{cmd}` rescue ''
      if out && !out.strip.empty?
        begin
          return JSON.parse(out)
        rescue => e
        end
      end
    end

    # Fallback to host
    req_path = File.expand_path(req_path)
    parent = req_path == '/' ? nil : File.dirname(req_path)
    entries = []
    if Dir.exist?(req_path)
      begin
        Dir.children(req_path).sort.each do |child|
          next if child.start_with?('.') && child != '.ctlabs'
          full_child = File.join(req_path, child)
          if File.directory?(full_child)
            has_ans = File.file?(File.join(full_child, 'ansible.cfg')) || Dir.exist?(File.join(full_child, 'playbooks')) || Dir.exist?(File.join(full_child, 'roles'))
            has_tf = Dir.glob(File.join(full_child, '*.tf')).any?
            has_git = Dir.exist?(File.join(full_child, '.git'))
            entries << { name: child, path: full_child, has_ansible: has_ans, has_terraform: has_tf, has_git: has_git }
          end
        end
      rescue Errno::EACCES
      end
    end
    repos = available_repositories
    { 'success' => true, 'current' => req_path, 'parent' => parent, 'directories' => entries, 'repositories' => repos }
  end

  def self.container_repositories(container: nil)
    if container && container_running?(container)
      py = <<-'PY'
import os, json
repos = {'ansible': ['/root/ctlabs-ansible'], 'terraform': ['/root/ctlabs-terraform']}
for scan_dir in ['/root', '/srv', '/srv/ctlabs', '/home']:
    if not os.path.isdir(scan_dir): continue
    try:
        for item in sorted(os.listdir(scan_dir)):
            full = os.path.join(scan_dir, item)
            if not os.path.isdir(full): continue
            if os.path.isfile(os.path.join(full, 'ansible.cfg')) or os.path.isdir(os.path.join(full, 'playbooks')) or os.path.isdir(os.path.join(full, 'roles')):
                if full not in repos['ansible']: repos['ansible'].append(full)
            if any(f.endswith('.tf') for f in os.listdir(full)):
                if full not in repos['terraform']: repos['terraform'].append(full)
    except Exception: pass
print(json.dumps(repos))
PY
      cmd = "docker exec #{container} python3 -c #{Shellwords.escape(py)} 2>/dev/null"
      out = `#{cmd}` rescue ''
      if out && !out.strip.empty?
        begin
          return JSON.parse(out)
        rescue => e
        end
      end
    end

    available_repositories
  end

  def self.available_repositories
    repos = { ansible: [ANS_BASE_DIR], terraform: [TF_BASE_DIR] }
    (Dir.glob('/root/*') + Dir.glob('/srv/*') + Dir.glob('/home/*/*')).each do |p|
      next unless File.directory?(p)
      repos[:ansible] << p if File.file?(File.join(p, 'ansible.cfg')) || Dir.exist?(File.join(p, 'playbooks')) || Dir.exist?(File.join(p, 'roles'))
      repos[:terraform] << p if Dir.glob(File.join(p, '*.tf')).any? || Dir.glob(File.join(p, '**', '*.tf')).any?
    end
    repos[:ansible].uniq!
    repos[:terraform].uniq!
    repos
  end

  # =========================================================================
  # GIT OPERATIONS (Ansible & Automation Repositories)
  # =========================================================================

  def self.git_available?
    @git_available ||= system('git --version > /dev/null 2>&1')
  end

  def self.run_git_in_dir(dir, *args, container: nil)
    base = resolve_ansible_dir(dir)
    if Dir.exist?(base)
      cmd = ['git', '-C', base] + args
      out, err, status = Open3.capture3(*cmd)
      return { ok: status.success?, stdout: out.to_s, stderr: err.to_s, exitstatus: status.exitstatus }
    elsif container && container_running?(container)
      esc_cmd = (['git', '-C', base] + args).map { |a| Shellwords.escape(a) }.join(' ')
      out, err, status = Open3.capture3("docker exec #{container} #{esc_cmd} 2>&1")
      return { ok: status.success?, stdout: out.to_s, stderr: err.to_s, exitstatus: status.exitstatus }
    else
      return { ok: false, stdout: '', stderr: "Directory #{base} not found", exitstatus: 1 }
    end
  end

  def self.git_status(dir = nil, container: nil)
    base = resolve_ansible_dir(dir)
    res = run_git_in_dir(base, 'status', '--porcelain=v1', '-b', container: container)
    return { ok: false, success: false, git_repo: false, error: res[:stderr].empty? ? 'Git command failed' : res[:stderr] } unless res[:ok]

    lines = res[:stdout].lines.map(&:chomp)
    branch_header = lines.first || '## unknown'
    branch_match = branch_header.match(/\A##\s+([^\s\.]+)/)
    branch = branch_match ? branch_match[1] : 'unknown'
    ahead = branch_header[/ahead (\d+)/, 1]&.to_i || 0
    behind = branch_header[/behind (\d+)/, 1]&.to_i || 0

    entries = lines[1..-1] || []
    modified = []
    untracked = []
    staged = []

    entries.each do |line|
      next if line.strip.empty?
      code = line[0..1]
      path = line[3..-1].to_s.strip
      if code[0] != ' ' && code[0] != '?'
        staged << path
      end
      if code[1] == 'M' || code[1] == 'D'
        modified << path
      elsif code == '??'
        untracked << path
      end
    end

    head_res = run_git_in_dir(base, 'rev-parse', '--short', 'HEAD', container: container)
    head_hash = head_res[:ok] ? head_res[:stdout].strip : ''

    {
      ok: true,
      success: true,
      git_repo: true,
      branch: branch,
      hash: head_hash,
      clean: entries.empty?,
      ahead: ahead,
      behind: behind,
      staged: staged,
      modified: modified,
      untracked: untracked,
      total_changes: entries.size,
      raw: res[:stdout]
    }
  end

  def self.git_commit(message, dir = nil, author: nil, files: nil, container: nil)
    base = resolve_ansible_dir(dir)
    msg = message.to_s.strip
    return { ok: false, success: false, error: 'Commit message is required' } if msg.empty?

    # Ensure git user config exists if not set
    name_check = run_git_in_dir(base, 'config', 'user.name', container: container)
    if !name_check[:ok] || name_check[:stdout].strip.empty?
      run_git_in_dir(base, 'config', 'user.name', 'ctlabs', container: container)
    end
    email_check = run_git_in_dir(base, 'config', 'user.email', container: container)
    if !email_check[:ok] || email_check[:stdout].strip.empty?
      run_git_in_dir(base, 'config', 'user.email', 'ctlabs@ctlabs.internal', container: container)
    end

    if files && !files.empty?
      Array(files).each do |f|
        run_git_in_dir(base, 'add', '--', f, container: container)
      end
    else
      run_git_in_dir(base, 'add', '-A', container: container)
    end

    args = ['commit', '-m', msg]
    args += ['--author', author] if author && !author.strip.empty?
    res = run_git_in_dir(base, *args, container: container)

    if res[:ok]
      head_res = run_git_in_dir(base, 'rev-parse', '--short', 'HEAD', container: container)
      { ok: true, success: true, message: msg, hash: head_res[:stdout].strip }
    else
      { ok: false, success: false, error: res[:stderr].empty? ? res[:stdout] : res[:stderr] }
    end
  end

  def self.git_pull(dir = nil, remote: 'origin', branch: nil, container: nil)
    base = resolve_ansible_dir(dir)
    args = ['pull']
    args << remote if remote && !remote.strip.empty?
    args << branch if branch && !branch.strip.empty?
    res = run_git_in_dir(base, *args, container: container)
    { ok: res[:ok], success: res[:ok], output: res[:stdout], error: res[:stderr] }
  end

  def self.git_push(dir = nil, remote: 'origin', branch: nil, container: nil)
    base = resolve_ansible_dir(dir)
    args = ['push']
    args << remote if remote && !remote.strip.empty?
    args << branch if branch && !branch.strip.empty?
    res = run_git_in_dir(base, *args, container: container)
    { ok: res[:ok], success: res[:ok], output: res[:stdout], error: res[:stderr] }
  end

  def self.git_history(dir = nil, limit: 30, container: nil)
    base = resolve_ansible_dir(dir)
    res = run_git_in_dir(base, 'log', "-n", limit.to_s, '--pretty=format:%h|%an|%ar|%s', container: container)
    return { ok: false, success: false, error: res[:stderr] } unless res[:ok]

    commits = res[:stdout].lines.map do |l|
      parts = l.strip.split('|', 4)
      next unless parts && parts.length >= 4
      { hash: parts[0], author: parts[1], date: parts[2], message: parts[3] }
    end.compact

    { ok: true, success: true, commits: commits }
  end

  def self.git_branches(dir = nil, container: nil)
    base = resolve_ansible_dir(dir)
    res = run_git_in_dir(base, 'branch', '--no-color', container: container)
    return { ok: false, success: false, error: res[:stderr] } unless res[:ok]

    current = 'main'
    branches_list = []
    res[:stdout].lines.each do |l|
      line = l.strip
      if line.start_with?('* ')
        bname = line.sub('* ', '').strip
        current = bname
        branches_list << { name: bname, current: true }
      elsif !line.empty?
        branches_list << { name: line, current: false }
      end
    end

    { ok: true, success: true, current: current, branches: branches_list }
  end

  def self.git_checkout(branch, dir = nil, create: false, container: nil)
    base = resolve_ansible_dir(dir)
    args = ['checkout']
    args << '-b' if create
    args << branch.to_s.strip
    res = run_git_in_dir(base, *args, container: container)
    { ok: res[:ok], success: res[:ok], output: res[:stdout], error: res[:stderr] }
  end

  def self.git_diff(hash, dir = nil, container: nil)
    base = resolve_ansible_dir(dir)
    clean_hash = hash.to_s.strip
    return { ok: false, success: false, error: 'Invalid commit hash' } unless clean_hash =~ /\A[a-f0-9]{4,40}\z/i

    stat_res = run_git_in_dir(base, 'show', '--stat', '--oneline', clean_hash, container: container)
    patch_res = run_git_in_dir(base, 'show', '-p', clean_hash, container: container)

    if patch_res[:ok]
      { ok: true, success: true, hash: clean_hash, stat: stat_res[:stdout], diff: patch_res[:stdout] }
    else
      { ok: false, success: false, error: patch_res[:stderr].empty? ? patch_res[:stdout] : patch_res[:stderr] }
    end
  end

  def self.git_diff_working(dir = nil, container: nil)
    base = resolve_ansible_dir(dir)
    stat_res = run_git_in_dir(base, 'diff', '--stat', 'HEAD', container: container)
    patch_res = run_git_in_dir(base, 'diff', 'HEAD', container: container)

    patch_text = patch_res[:stdout].to_s
    stat_text = stat_res[:stdout].to_s

    # Include untracked files in working tree diff
    p_res = run_git_in_dir(base, 'status', '--porcelain', container: container)
    if p_res[:ok]
      p_res[:stdout].lines.each do |line|
        code = line[0..1]
        file = line[3..-1].to_s.strip
        if code == '??' && !file.empty?
          u_res = run_git_in_dir(base, 'diff', '--no-index', '--', '/dev/null', file, container: container)
          patch_text = [patch_text, u_res[:stdout].to_s].reject(&:empty?).join("\n") unless u_res[:stdout].to_s.empty?
        end
      end
    end

    { ok: true, success: true, hash: 'working', stat: stat_text, diff: patch_text }
  end
end
