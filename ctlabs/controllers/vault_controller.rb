# -----------------------------------------------------------------------------
# File        : ctlabs/controllers/vault_controller.rb
# Description : Controller for Vault authentication and session management
# License     : MIT License
# -----------------------------------------------------------------------------

require 'tmpdir'

class VaultController < BaseController
  # --- Vault Login ---
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

      # Set an 8-Hour hard TTL on the web session
      session[:vault_expires] = Time.now.to_i + (8 * 3600)

      { success: true, message: "Successfully authenticated!", policies: auth_data[:policies] }.to_json
    rescue => e
      status 401
      { success: false, error: e.message }.to_json
    end
  end

  # --- Vault Session Info ---
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
          # --- Fetch and introspect all active GCP leases! ---
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

          # --- Fetch and introspect active SSH Certificates! ---
          ssh_certs = []
          search_paths = [
            File.expand_path("~/.ssh/*-cert.pub"),
            File.expand_path("~/.ssh/keys/*-cert.pub"),
            File.join(Dir.tmpdir, "vault-ssh-*", "*-cert.pub")
          ]
          
          Dir.glob(search_paths).uniq.each do |file|
            next unless File.file?(file)
            
            cert_string = File.read(file)
            cert_info = VaultAuth.get_ssh_cert_info(cert_string)
            
            unless cert_info["error"]
              ssh_certs << {
                file: file,
                is_ephemeral: file.include?("vault-ssh-"),
                key_id: cert_info[:key_id],
                valid: cert_info[:valid],
                principals: cert_info[:principals]
              }
            end
          end

          { success: true, info: info, gcp: gcp_details, ssh: ssh_certs }.to_json
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

  # --- Vault Logout ---
  post ['/api/vault/logout', '/vault/logout'] do
    content_type :json

    # Safely try to wipe the GCP cache, but never crash the route if it fails
    VaultAuth.clear_gcp_cache(session[:vault_addr]) rescue nil

    session.delete(:vault_token)
    session.delete(:vault_addr)
    session.delete(:vault_expires)

    { success: true, message: "Successfully logged out." }.to_json
  end
end
