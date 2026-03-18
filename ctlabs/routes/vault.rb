# -----------------------------------------------------------------------------
# File        : ctlabs/routes/vault.rb
# License     : MIT License
# -----------------------------------------------------------------------------

post '/api/vault/login' do
  content_type :json
  addr   = params[:addr].to_s.strip
  method = params[:method].to_s.strip
  halt 400, { success: false, error: "Vault Address is required" }.to_json if addr.empty?

  begin
    auth_data = case method
      when 'userpass', 'ldap'
        VaultAuth.login_userpass(addr, params[:username], params[:password], method)
      when 'approle'
        VaultAuth.login_approle(addr, params[:role_id], params[:secret_id])
      else
        raise "Unsupported authentication method: #{method}"
      end

    session[:vault_token] = auth_data[:token]
    session[:vault_addr]  = addr
    
    # --- NEW: Set an 8-Hour hard TTL on the web session ---
    session[:vault_expires] = Time.now.to_i + (8 * 3600) 
    
    { success: true, message: "Successfully authenticated!", policies: auth_data[:policies] }.to_json
  rescue => e
    status 401
    { success: false, error: e.message }.to_json
  end
end

# Fetch active Vault Session Info
get '/vault/info' do
  content_type :json
  addr = session[:vault_addr] || params[:addr]
  
  # Enforce the 8-Hour Session TTL
  if session[:vault_expires] && Time.now.to_i > session[:vault_expires]
    session.delete(:vault_token)
    session.delete(:vault_addr)
    session.delete(:vault_expires)
    return { success: false, error: "Session expired after 8 hours. Please log in again." }.to_json
  end
  
  if session[:vault_token] && addr && !addr.empty?
    begin
      info = VaultAuth.lookup_self(addr, session[:vault_token])
      if info
        # --- NEW: Fetch and introspect all active GCP leases! ---
        gcp_active = VaultAuth.get_active_gcp_tokens(addr)
        gcp_details = gcp_active.map do |c|
          token_info = VaultAuth.get_gcp_token_info(c[:token])
          {
            project: c[:project],
            roleset: c[:roleset],
            email: token_info['email'],
            expires_in: token_info['expires_in'],
            error: token_info['error']
          }
        end
        
        { success: true, info: info, gcp: gcp_details }.to_json
      else
        { success: false, error: "Token invalid or expired." }.to_json
      end
    rescue => e
      { success: false, error: "Network error: #{e.message}" }.to_json
    end
  else
    { success: false, error: "Not logged in or missing Vault address." }.to_json
  end
end

post '/api/vault/logout' do
  content_type :json
  
  # Safely try to wipe the GCP cache, but never crash the route if it fails
  VaultAuth.clear_gcp_cache(session[:vault_addr]) rescue nil

  session.delete(:vault_token)
  session.delete(:vault_addr)
  session.delete(:vault_expires)
  
  { success: true, message: "Successfully logged out." }.to_json
end

# Secure Logout
post '/vault/logout' do
  content_type :json
  
  # Safely try to wipe the GCP cache, but never crash the route if it fails
  VaultAuth.clear_gcp_cache(session[:vault_addr]) rescue nil

  session.delete(:vault_token)
  session.delete(:vault_addr)
  session.delete(:vault_expires)
  
  { success: true }.to_json
end
