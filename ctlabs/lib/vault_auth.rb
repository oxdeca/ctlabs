# -----------------------------------------------------------------------------
# File    : ctlabs/lib/vault_auth.rb
# Purpose : Native Ruby Vault Authentication Client for the Web UI
# -----------------------------------------------------------------------------
require 'net/http'
require 'uri'
require 'json'
require 'openssl'

class VaultAuth
  # Handles both pure Userpass and LDAP based on the mount parameter
  def self.login_userpass(addr, username, password, mount = 'userpass')
    payload = { password: password }
    post_login(addr, "/v1/auth/#{mount}/login/#{username}", payload)
  end

  # Handles Machine-to-Machine AppRole login
  def self.login_approle(addr, role_id, secret_id)
    payload = { role_id: role_id, secret_id: secret_id }
    post_login(addr, "/v1/auth/approle/login", payload)
  end

  private

  def self.post_login(addr, path, payload)
    uri = URI.parse("#{addr.sub(/\/$/, '')}#{path}")
    http = Net::HTTP.new(uri.host, uri.port)
    
    if uri.scheme == 'https'
      http.use_ssl = true
      http.verify_mode = OpenSSL::SSL::VERIFY_NONE # Match Python's warnings.filterwarnings('ignore')
    end

    request = Net::HTTP::Post.new(uri.request_uri, { 'Content-Type' => 'application/json' })
    request.body = payload.to_json

    begin
      response = http.request(request)
      data = JSON.parse(response.body)

      if response.is_a?(Net::HTTPSuccess) && data['auth']
        # Return the client token and the TTL
        return {
          token: data['auth']['client_token'],
          ttl: data['auth']['lease_duration'],
          policies: data['auth']['policies']
        }
      else
        error_msg = data['errors'] ? data['errors'].join(', ') : response.message
        raise "Vault API Error: #{error_msg}"
      end
    rescue => e
      raise "Authentication Failed: #{e.message}"
    end
  end
end