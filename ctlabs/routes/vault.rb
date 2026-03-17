# -----------------------------------------------------------------------------
# File        : ctlabs/routes/vault.rb
# License     : MIT License
# -----------------------------------------------------------------------------

post '/api/vault/login' do
  content_type :json
  
  addr   = params[:addr].to_s.strip
  method = params[:method].to_s.strip # 'userpass', 'ldap', or 'approle'
  
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

    # Store the credentials directly in the secure Sinatra web session
    session[:vault_token] = auth_data[:token]
    session[:vault_addr]  = addr
    
    { 
      success: true, 
      message: "Successfully authenticated!", 
      policies: auth_data[:policies] 
    }.to_json

  rescue => e
    status 401
    { success: false, error: e.message }.to_json
  end
end

post '/api/vault/logout' do
  session.delete(:vault_token)
  session.delete(:vault_addr)
  content_type :json
  { success: true, message: "Logged out of Vault successfully." }.to_json
end