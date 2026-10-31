# -----------------------------------------------------------------------------
# File        : ctlabs/services/automation_service.rb
# Description : Service for Ansible and Terraform operations
# License     : MIT License
# -----------------------------------------------------------------------------

require 'fileutils'
require 'json'
require 'yaml'

class AutomationService
  ANS_BASE_DIR = '/root/ctlabs-ansible'.freeze
  TF_BASE_DIR = '/root/ctlabs-terraform'.freeze

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

  def self.ansible_tree(root_dir = nil)
    base = resolve_ansible_dir(root_dir)
    return [] unless Dir.exist?(base)
    Dir.glob(File.join(base, "**", "*"))
       .reject { |f| File.directory?(f) || f.include?('/.git/') || f.include?('/__pycache__/') || f.include?('/.idea/') }
       .map { |f| f.sub(base + '/', '') }
       .sort
  end

  def self.read_ansible_file(filepath, root_dir = nil)
    base = resolve_ansible_dir(root_dir)
    full_path = File.join(base, filepath)
    File.file?(full_path) ? File.read(full_path) : "# New file: #{filepath}\n"
  end

  def self.write_ansible_files(files_hash, root_dir = nil)
    base = resolve_ansible_dir(root_dir)
    files_hash.each do |filepath, content|
      next if filepath.include?('..') || filepath.start_with?('/')
      full_path = File.join(base, filepath)
      FileUtils.mkdir_p(File.dirname(full_path))
      File.write(full_path, content)
      FileUtils.chmod("+x", full_path) if filepath.end_with?('.py') || filepath.end_with?('.sh')
    end
  end

  def self.delete_ansible_file(filepath, root_dir = nil)
    base = resolve_ansible_dir(root_dir)
    full_path = File.join(base, filepath)
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

  def self.terraform_tree(root_dir = nil)
    base = resolve_terraform_dir(root_dir)
    return [] unless Dir.exist?(base)
    Dir.glob(File.join(base, "**", "*"))
       .reject { |f| f.include?('/.terraform/') || f.include?('/.git/') || f.end_with?('.tfstate') || f.end_with?('.tfstate.backup') }
       .map { |f| File.directory?(f) ? "#{f.sub(base + '/', '')}/" : f.sub(base + '/', '') }
       .sort
  end

  def self.read_terraform_file(filepath, root_dir = nil)
    base = resolve_terraform_dir(root_dir)
    full_path = File.join(base, filepath)
    File.file?(full_path) ? File.read(full_path) : "# New file: #{filepath}\n"
  end

  def self.read_terraform_workdir_files(work_dir, root_dir = nil)
    base = resolve_terraform_dir(root_dir)
    target_dir = File.join(base, work_dir)
    response = {'config.yml' => "", 'main.tf' => "", 'provider.tf' => ""}
    
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

  def self.write_terraform_files(files_hash, root_dir = nil)
    base = resolve_terraform_dir(root_dir)
    files_hash.each do |filepath, content|
      next if filepath.include?('..') || filepath.start_with?('/')
      full_path = File.join(base, filepath)
      FileUtils.mkdir_p(File.dirname(full_path))
      File.write(full_path, content)
    end
  end

  def self.delete_terraform_file(filepath, root_dir = nil)
    base = resolve_terraform_dir(root_dir)
    full_path = File.join(base, filepath)
    File.delete(full_path) if File.exist?(full_path)
  end

  def self.available_repositories
    repos = { ansible: [ANS_BASE_DIR], terraform: [TF_BASE_DIR] }
    Dir.glob('/root/*').each do |p|
      next unless File.directory?(p)
      repos[:ansible] << p if File.file?(File.join(p, 'ansible.cfg')) || Dir.exist?(File.join(p, 'playbooks')) || Dir.exist?(File.join(p, 'roles'))
      repos[:terraform] << p if Dir.glob(File.join(p, '*.tf')).any? || Dir.glob(File.join(p, '**', '*.tf')).any?
    end
    repos[:ansible].uniq!
    repos[:terraform].uniq!
    repos
  end
end
