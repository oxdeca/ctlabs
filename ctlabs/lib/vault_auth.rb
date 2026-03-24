# -----------------------------------------------------------------------------
# File    : ctlabs/lib/vault_auth.rb
# Purpose : Native Ruby Vault Authentication Client for the Web UI
# -----------------------------------------------------------------------------
require 'net/http'
require 'uri'
require 'json'
require 'openssl'
require 'tempfile'

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

  # Fetch a dynamic GCP OAuth token directly from Vault (Supports both Dynamic & Static Paths!)
  def self.get_gcp_token(addr, token, project, roleset)
    @gcp_cache ||= {} 
    
    cache_key = "#{addr}_#{project}_#{roleset}"
    cached = @gcp_cache[cache_key]
    
    # 1. Check if we have a valid token in memory that hasn't hit our safe expiration time
    if cached && cached[:expires_at] > Time.now.to_i
      return cached[:token]
    end

    mount_point = "gcp/#{project}"
    base_url = "#{addr.sub(/\/$/, '')}/v1/#{mount_point}"
    
    # 🌟 NEW LOGIC: Define both paths to support the billing workaround
    dynamic_path = "#{base_url}/token/#{roleset}"
    static_path = "#{base_url}/static-account/#{roleset}/token"

    # 2. Attempt Static Account Path FIRST (Overrides take precedence!)
    uri = URI.parse(static_path)
    http = Net::HTTP.new(uri.host, uri.port)
    
    if uri.scheme == 'https'
      http.use_ssl = true
      http.verify_mode = OpenSSL::SSL::VERIFY_NONE
    end

    request = Net::HTTP::Get.new(uri.request_uri)
    request['X-Vault-Token'] = token

    begin
      response = http.request(request)
      
      # 3. If static fails (e.g. 404 Not Found), seamlessly fallback to Dynamic Roleset path
      unless response.is_a?(Net::HTTPSuccess)
        uri = URI.parse(dynamic_path)
        request = Net::HTTP::Get.new(uri.request_uri)
        request['X-Vault-Token'] = token
        response = http.request(request)
      end

      data = JSON.parse(response.body)

      if response.is_a?(Net::HTTPSuccess) && data['data']
        # Account for varying Vault response formats depending on engine type
        gcp_token = data['data']['token_oauth2_secret'] || data['data']['token']
        
        # 4. Extract Vault's exact TTL safely, ignoring 0s!
        ttls = [data['lease_duration'], data.dig('data', 'token_ttl')].map(&:to_i).reject { |v| v == 0 }
        raw_ttl = ttls.first || 3600
        
        # 5. Subtract 60 seconds as a safety buffer so we don't use dying tokens
        safe_ttl = [raw_ttl - 60, 60].max
        
        # 6. Save to the cache
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

  # Safely wipe GCP tokens from memory for a specific Vault address
  def self.clear_gcp_cache(addr)
    @gcp_cache ||= {}
    # Reject/delete any cache entries that belong to this server address
    @gcp_cache.reject! { |key, data| data[:addr] == addr }
  end

  # Signs an SSH Public Key using a Vault SSH CA Engine
  # Mount defaults to 'ssh' but can be 'ssh/ca-dev', etc.
  def self.sign_ssh_key(addr, token, mount, role, public_key, valid_principals = nil)
    # Ensure mount path is formatted correctly
    safe_mount = mount.to_s.sub(/^\//, '').sub(/\/$/, '')
    uri = URI.parse("#{addr.sub(/\/$/, '')}/v1/#{safe_mount}/sign/#{role}")
    
    http = Net::HTTP.new(uri.host, uri.port)

    if uri.scheme == 'https'
      http.use_ssl = true
      http.verify_mode = OpenSSL::SSL::VERIFY_NONE
    end

    request = Net::HTTP::Post.new(uri.request_uri, { 'Content-Type' => 'application/json' })
    request['X-Vault-Token'] = token

    # Build the payload
    payload = { "public_key" => public_key }
    
    # If specific principals (like 'ubuntu' or 'root') are requested, pass them
    # Otherwise, Vault will use the default_user defined in the role
    if valid_principals && !valid_principals.to_s.strip.empty?
      payload["valid_principals"] = valid_principals
    end

    request.body = payload.to_json

    begin
      response = http.request(request)
      data = JSON.parse(response.body)

      if response.is_a?(Net::HTTPSuccess) && data['data'] && data['data']['signed_key']
        return data['data']['signed_key']
      else
        error_msg = data['errors'] ? data['errors'].join(', ') : response.message
        raise "Vault SSH Signing Error: #{error_msg}"
      end
    rescue => e
      raise "Failed to sign SSH key via Vault: #{e.message}"
    end
  end

  # Introspects a Vault-signed OpenSSH Certificate string using the local ssh-keygen utility
  def self.get_ssh_cert_info(cert_string)
    return { "error" => "No certificate provided" } if cert_string.nil? || cert_string.empty?

    begin
      parsed_info = { principals: [] }
      
      # Write the certificate to a temporary file so ssh-keygen can read it
      Tempfile.create(['vault_cert', '.pub']) do |f|
        f.write(cert_string)
        f.flush
        
        # Run ssh-keygen and capture both stdout and stderr
        output = `ssh-keygen -L -f #{f.path} 2>&1`
        
        unless $?.success?
          return { "error" => "ssh-keygen failed: #{output.strip}" }
        end
        
        parsing_principals = false
        
        output.each_line do |line|
          line = line.strip
          if line.start_with?("Key ID:")
            parsed_info[:key_id] = line.split(":", 2)[1].strip.delete('"')
          elsif line.start_with?("Valid:")
            parsed_info[:valid] = line.split(":", 2)[1].strip
          elsif line.start_with?("Principals:")
            parsing_principals = true
          elsif parsing_principals
            if line.start_with?("Critical Options:") || line.start_with?("Extensions:")
              parsing_principals = false
            elsif !line.empty? && line != "(none)"
              parsed_info[:principals] << line
            end
          end
        end
      end
      
      return parsed_info
    rescue => e
      return { "error" => "Ruby error parsing SSH certificate: #{e.message}" }
    end
  end

end

