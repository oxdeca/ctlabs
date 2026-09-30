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


  def self.ansible_tree
    return [] unless Dir.exist?(ANS_BASE_DIR)
    Dir.glob(File.join(ANS_BASE_DIR, "**", "*"))
       .reject { |f| File.directory?(f) || f.include?('/.git/') || f.include?('/__pycache__/') || f.include?('/.idea/') }
       .map { |f| f.sub(ANS_BASE_DIR + '/', '') }
       .sort
  end

  def self.read_ansible_file(filepath)
    full_path = File.join(ANS_BASE_DIR, filepath)
    File.file?(full_path) ? File.read(full_path) : "# New file: #{filepath}\n"
  end

  def self.write_ansible_files(files_hash)
    files_hash.each do |filepath, content|
      next if filepath.include?('..') || filepath.start_with?('/')
      full_path = File.join(ANS_BASE_DIR, filepath)
      FileUtils.mkdir_p(File.dirname(full_path))
      File.write(full_path, content)
      FileUtils.chmod("+x", full_path) if filepath.end_with?('.py') || filepath.end_with?('.sh')
    end
  end

  def self.delete_ansible_file(filepath)
    full_path = File.join(ANS_BASE_DIR, filepath)
    File.delete(full_path) if File.exist?(full_path)
  end

  # --- Global role/setup profile files (live under /root/ctlabs/labs/, or
  # /root/.ctlabs/labs/ when box-locally overridden - resolved fresh on every
  # call via Lab.*_profiles_path, not cached, so a long-lived webgui process
  # picks up an override dropped in after boot) ---
  def self.profile_files
    {
      'role_profiles.yml'      => Lab.role_profiles_path,
      'setup_profiles.yml'     => Lab.setup_profiles_path,
      'terraform_profiles.yml' => Lab.terraform_profiles_path
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
        YAML.safe_load(content)
      rescue => e
        raise "Invalid YAML in #{filepath}: #{e.message}"
      end
      File.write(paths[filepath], content)
    end
  end

  def self.terraform_tree
    return [] unless Dir.exist?(TF_BASE_DIR)
    Dir.glob(File.join(TF_BASE_DIR, "**", "*"))
       .reject { |f| File.directory?(f) || f.include?('/.terraform/') || f.include?('/.git/') || f.end_with?('.tfstate') || f.end_with?('.tfstate.backup') }
       .map { |f| f.sub(TF_BASE_DIR + '/', '') }
       .sort
  end

  def self.read_terraform_file(filepath)
    full_path = File.join(TF_BASE_DIR, filepath)
    File.file?(full_path) ? File.read(full_path) : "# New file: #{filepath}\n"
  end

  def self.read_terraform_workdir_files(work_dir)
    target_dir = File.join(TF_BASE_DIR, work_dir)
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

  def self.write_terraform_files(files_hash)
    files_hash.each do |filepath, content|
      next if filepath.include?('..') || filepath.start_with?('/')
      full_path = File.join(TF_BASE_DIR, filepath)
      FileUtils.mkdir_p(File.dirname(full_path))
      File.write(full_path, content)
    end
  end

  def self.delete_terraform_file(filepath)
    full_path = File.join(TF_BASE_DIR, filepath)
    File.delete(full_path) if File.exist?(full_path)
  end
end
