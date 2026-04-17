# -----------------------------------------------------------------------------
# File        : ctlabs/routes/profiles.rb
# License     : MIT License
# -----------------------------------------------------------------------------

# ===================================================
# HELPER: Check if a profile is used by any node
# ===================================================
def profile_in_use?(yaml, target_type, target_profile)
  vm = yaml['topology']&.first || {}
  
  # Gather all nodes across all planes (or flat nodes array)
  nodes_to_scan = vm['planes'] ? vm['planes'].values.map { |p| p['nodes'] } : [vm['nodes']]
  
  nodes_to_scan.compact.each do |node_group|
    node_group.values.each do |n|
      node_type = n['type'] || 'host'
      node_prof = n['profile'] || n['kind'] || 'linux'
      
      # If we find a match, it is in use!
      if node_type.to_s == target_type.to_s && node_prof.to_s == target_profile.to_s
        return true
      end
    end
  end
  false
end

# ===================================================
# EDIT PROFILE (Schema Aware)
# ===================================================
post '/labs/*/image/edit' do
  lab_name = params[:splat].first
  lab_path = get_lab_file_path(lab_name)

  begin
    full_yaml = YAML.load_file(lab_path) || {}

    type = params[:type].to_s.strip
    kind = params[:kind].to_s.strip

    halt 400, { error: "Type and Kind are required" }.to_json if type.empty? || kind.empty?

    # Detect if lab is using v2 'profiles' or v1 'defaults'
    profile_key = full_yaml.key?('profiles') ? 'profiles' : 'defaults'
    
    full_yaml[profile_key] ||= {}
    full_yaml[profile_key][type] ||= {}
    full_yaml[profile_key][type][kind] ||= {}

    profile = full_yaml[profile_key][type][kind]
    
    # Update properties
    params[:image].to_s.strip.empty? ? profile.delete('image') : profile['image'] = params[:image].strip

    # --- NEW: Inject Provider ---
    provider_val = params[:provider].to_s.strip.downcase
    if provider_val.empty? || provider_val == 'local'
      profile.delete('provider') # Keep YAML clean by omitting default 'local'
    else
      profile['provider'] = provider_val
    end
    # ----------------------------

    caps = params[:caps].to_s.split(',').map(&:strip).reject(&:empty?)
    caps.empty? ? profile.delete('caps') : profile['caps'] = caps

    env = params[:env].to_s.split(/\r?\n/).map(&:strip).reject(&:empty?)
    env.empty? ? profile.delete('env') : profile['env'] = env

    if params[:extras] && !params[:extras].strip.empty?
      begin
        profile.merge!(YAML.safe_load(params[:extras]))
      rescue => e
        raise "Invalid YAML in Extras: #{e.message}"
      end
    end

    write_formatted_yaml(lab_path, full_yaml)

    content_type :json
    { success: true, message: "Profile updated successfully." }.to_json
  rescue Exception => e
    status 400
    content_type :json
    { success: false, error: e.message }.to_json
  end
end

# ===================================================
# DELETE PROFILE (Protected)
# ===================================================
post '/labs/*/image/:type/:kind/delete' do
  lab_name = params[:splat].first
  lab_path = get_lab_file_path(lab_name)
  
  begin
    yaml = YAML.load_file(lab_path)
    
    # 1. Protection Check!
    if profile_in_use?(yaml, params[:type], params[:kind])
      halt 400, { error: "Cannot delete '#{params[:kind]}'. It is currently being used by a node in this lab!" }.to_json
    end

    # 2. Safe Deletion
    profile_key = yaml.key?('profiles') ? 'profiles' : 'defaults'
    
    if yaml[profile_key] && yaml[profile_key][params[:type]]
      yaml[profile_key][params[:type]].delete(params[:kind])
      yaml[profile_key].delete(params[:type]) if yaml[profile_key][params[:type]].empty?
      write_formatted_yaml(lab_path, yaml)
    end
    
    content_type :json
    { success: true, message: "Image profile deleted." }.to_json
  rescue => e
    status 400
    content_type :json
    { success: false, error: e.message }.to_json
  end
end
