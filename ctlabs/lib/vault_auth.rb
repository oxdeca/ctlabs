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

  # Fetches details about the currently active token
  def self.lookup_self(addr, token)
    uri = URI.parse("#{addr.sub(/\/$/, '')}/v1/auth/token/lookup-self")
    http = Net::HTTP.new(uri.host, uri.port)
    
    if uri.scheme == 'https'
      http.use_ssl = true
      http.verify_mode = OpenSSL::SSL::VERIFY_NONE
    end
    request = Net::HTTP::Get.new(uri.request_uri)
    request['X-Vault-Token'] = token
    begin
      response = http.request(request)
      data = JSON.parse(response.body)
      if response.is_a?(Net::HTTPSuccess)
        return data['data']
      else
        return nil
      end
    rescue
      return nil
    end
  end

  # Fetch a dynamic GCP OAuth token directly from Vault (with Vault-defined TTL caching!)
  def self.get_gcp_token(addr, token, project, roleset)
    # --- ADD THIS LINE TO FIX THE NIL ERROR ---
    @gcp_cache ||= {} 
    
    cache_key = "#{addr}_#{project}_#{roleset}"
    cached = @gcp_cache[cache_key]
    
    # 1. Check if we have a valid token in memory that hasn't hit our safe expiration time
    if cached && cached[:expires_at] > Time.now.to_i
      return cached[:token]
    end

    mount_point = "gcp/#{project}"
    uri = URI.parse("#{addr.sub(/\/$/, '')}/v1/#{mount_point}/token/#{roleset}")
    http = Net::HTTP.new(uri.host, uri.port)
    
    if uri.scheme == 'https'
      http.use_ssl = true
      http.verify_mode = OpenSSL::SSL::VERIFY_NONE
    end

    request = Net::HTTP::Get.new(uri.request_uri)
    request['X-Vault-Token'] = token

    begin
      response = http.request(request)
      data = JSON.parse(response.body)

      if response.is_a?(Net::HTTPSuccess) && data['data']
        gcp_token = data['data']['token_oauth2_secret'] || data['data']['token']
        
        # 2. Extract Vault's exact TTL (usually 3600 seconds for GCP tokens)
        raw_ttl = data['lease_duration'] || data.dig('data', 'token_ttl') || 3600
        
        # 3. Subtract 60 seconds as a safety buffer so we don't use dying tokens
        safe_ttl = [raw_ttl.to_i - 60, 60].max
        
        # 4. Save to the cache
        # 4. Save to the cache (Now tracking the metadata!)
        @gcp_cache[cache_key] = {
          token: gcp_token,
          expires_at: Time.now.to_i + safe_ttl,
          addr: addr,
          project: project,
          roleset: roleset
        }
        
        return gcp_token
      else
        error_msg = data['errors'] ? data['errors'].join(', ') : response.message
        raise "Vault GCP Error: #{error_msg}"
      end
    rescue => e
      raise "Failed to fetch GCP Token from Vault: #{e.message}"
    end
  end

  # Returns all currently cached and valid GCP tokens for a specific Vault server
  def self.get_active_gcp_tokens(addr)
    @gcp_cache ||= {}
    now = Time.now.to_i
    @gcp_cache.values.select { |c| c[:addr] == addr && c[:expires_at] > now }
  end

  # Introspects ANY existing GCP OAuth token using Google's public endpoint
  def self.get_gcp_token_info(token_string)
    return { "error" => "No token provided" } if token_string.nil? || token_string.empty?
    
    begin
      uri = URI.parse("https://oauth2.googleapis.com/tokeninfo?access_token=#{token_string}")
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.read_timeout = 10
      
      request = Net::HTTP::Get.new(uri.request_uri)
      response = http.request(request)
      data = JSON.parse(response.body)
      
      if response.is_a?(Net::HTTPSuccess)
        return data
      else
        return { "error" => data["error_description"] || "Google API returned HTTP #{response.code}" }
      end
    rescue => e
      return { "error" => "Network/Ruby error: #{e.class} - #{e.message}" }
    end
  end
end
