# -----------------------------------------------------------------------------
# File    : ctlabs/lib/gcp_auth.rb
# Purpose : Single dispatch point for GCP OAuth2 token acquisition, used by
#           every place that execs into the ansible/ctrl container to run
#           Terraform or gcloud (terraform apply, background auto-provision,
#           interactive terminal). Supports multiple `terraform.auth.method`
#           values so new GCP auth methods only need to be added here:
#             - "vault" : Vault GCP secrets engine (dynamic/static-account
#                         tokens), via VaultAuth.get_gcp_token.
#             - "wif"   : Workload Identity Federation. Vault signs a short-
#                         lived OIDC identity token, which is exchanged
#                         directly with Google's STS endpoint and then used
#                         to impersonate a target service account. No
#                         service-account key is ever stored in Vault or GCP,
#                         and no gcloud/SDK install is required - just three
#                         plain HTTPS calls.
# -----------------------------------------------------------------------------
require 'net/http'
require 'uri'
require 'json'
require 'openssl'
require 'time'
require 'yaml'
require_relative 'vault_auth'

class GcpAuth
  DEFAULT_VAULT_ROLESET = 'terraform-runner'
  GCP_SCOPE             = 'https://www.googleapis.com/auth/cloud-platform'
  TERRAFORM_PROFILES_FILE = defined?(Lab::TERRAFORM_PROFILES) ? Lab::TERRAFORM_PROFILES : '/root/ctlabs/labs/terraform_profiles.yml'

  # tf_cfg    : the node's `terraform` config hash (reads tf_cfg['auth'], with
  #             a fallback to the legacy tf_cfg['vault'] shape).
  # vault_ctx : { addr:, token: } - the caller's already-authenticated Vault session.
  #
  # Returns the env vars to inject into the container, or {} when this node
  # has no GCP auth configured at all.
  def self.env_vars(tf_cfg, vault_ctx)
    token = fetch_token(tf_cfg, vault_ctx)
    return {} unless token
    { 'GOOGLE_OAUTH_ACCESS_TOKEN' => token, 'CLOUDSDK_AUTH_ACCESS_TOKEN' => token }
  end

  def self.fetch_token(tf_cfg, vault_ctx)
    auth_cfg = resolve_auth_cfg(tf_cfg)
    return nil unless auth_cfg

    vault_ctx ||= {}
    raise "Missing Vault Token for GCP Authentication." if vault_ctx[:token].to_s.empty?

    case auth_cfg['method']
    when 'wif'
      fetch_wif_token(auth_cfg, vault_ctx)
    else
      fetch_vault_token(auth_cfg, vault_ctx)
    end
  end

  # Normalizes the inline `terraform.auth` block, a named `terraform.profile`
  # (looked up in the global labs/terraform_profiles.yml, all-or-nothing - a
  # profile is never merged with inline auth), and the legacy `terraform.vault`
  # block into one { 'method' => ..., ... } hash (or nil if GCP auth isn't
  # configured for this node).
  def self.resolve_auth_cfg(tf_cfg)
    tf_cfg = tf_cfg || {}

    auth = tf_cfg['auth']
    if auth && !auth.empty?
      method = auth['method'].to_s.strip
      return nil if method.empty?
      return auth.merge('method' => method)
    end

    profile_name = tf_cfg['profile'].to_s.strip
    unless profile_name.empty?
      profile = load_terraform_profile(profile_name)
      raise "Terraform auth profile '#{profile_name}' not found in #{TERRAFORM_PROFILES_FILE}" unless profile
      method = profile['method'].to_s.strip
      return nil if method.empty?
      return profile.merge('method' => method)
    end

    legacy_vault = tf_cfg['vault']
    return nil unless legacy_vault && !legacy_vault['project'].to_s.strip.empty?
    legacy_vault.merge('method' => 'vault')
  end

  def self.load_terraform_profile(name)
    return nil unless File.file?(TERRAFORM_PROFILES_FILE)
    profiles = YAML.load_file(TERRAFORM_PROFILES_FILE)['profiles'] || {}
    profiles[name]
  end

  # ------------------------------------------------------------------------
  # Method: vault (GCP secrets engine)
  # ------------------------------------------------------------------------
  def self.fetch_vault_token(cfg, vault_ctx)
    project = cfg['project'].to_s.strip
    return nil if project.empty?

    roleset = cfg['roleset'].to_s.strip
    roleset = DEFAULT_VAULT_ROLESET if roleset.empty?

    VaultAuth.get_gcp_token(vault_ctx[:addr], vault_ctx[:token], project, roleset)
  end

  # ------------------------------------------------------------------------
  # Method: wif (Workload Identity Federation via Vault OIDC identity tokens)
  # ------------------------------------------------------------------------
  def self.fetch_wif_token(cfg, vault_ctx)
    vault_role = cfg['vault_role'].to_s.strip
    audience   = cfg['audience'].to_s.strip
    sa_email   = cfg['service_account'].to_s.strip

    if vault_role.empty? || audience.empty? || sa_email.empty?
      raise "WIF auth requires vault_role, audience and service_account to be set."
    end

    @wif_cache ||= {}
    cache_key = "#{vault_ctx[:addr]}_#{vault_role}_#{audience}_#{sa_email}"
    cached = @wif_cache[cache_key]
    return cached[:token] if cached && cached[:expires_at] > Time.now.to_i

    oidc_token      = fetch_vault_oidc_token(vault_ctx[:addr], vault_ctx[:token], vault_role)
    federated_token = exchange_for_federated_token(audience, oidc_token)
    access_token, expires_in = generate_access_token(sa_email, federated_token)

    safe_ttl = [expires_in - 60, 60].max
    @wif_cache[cache_key] = {
      token: access_token,
      expires_at: Time.now.to_i + safe_ttl,
      addr: vault_ctx[:addr],
      vault_role: vault_role,
      audience: audience,
      service_account: sa_email
    }
    access_token
  end

  # Returns all currently cached and valid WIF tokens for a specific Vault
  # server (mirrors VaultAuth.get_active_gcp_tokens)
  def self.get_active_tokens(addr)
    @wif_cache ||= {}
    now = Time.now.to_i
    @wif_cache.values.select { |c| c[:addr] == addr && c[:expires_at] > now }
  end

  # 1. Ask Vault to sign a short-lived OIDC identity token for `role`.
  #    (Built into Vault's core identity/oidc engine - no GCP credential of
  #    any kind is stored in Vault for this method.)
  def self.fetch_vault_oidc_token(addr, vault_token, role)
    uri = URI.parse("#{addr.sub(/\/$/, '')}/v1/identity/oidc/token/#{role}")
    http = Net::HTTP.new(uri.host, uri.port)
    if uri.scheme == 'https'
      http.use_ssl = true
      http.verify_mode = OpenSSL::SSL::VERIFY_NONE
    end

    request = Net::HTTP::Get.new(uri.request_uri)
    request['X-Vault-Token'] = vault_token
    response = http.request(request)
    data = JSON.parse(response.body)

    unless response.is_a?(Net::HTTPSuccess) && data.dig('data', 'token')
      error_msg = data['errors'] ? data['errors'].join(', ') : response.message
      raise "Vault OIDC Error: #{error_msg}"
    end
    data['data']['token']
  end

  # 2. Exchange the Vault-signed JWT for a federated GCP token via GCP's STS
  #    token-exchange endpoint. Google trusts Vault's signature directly (the
  #    Workload Identity Pool provider is configured with Vault as issuer),
  #    so this is a plain HTTPS call - no gcloud/SDK required.
  def self.exchange_for_federated_token(audience, subject_jwt)
    uri = URI.parse('https://sts.googleapis.com/v1/token')
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true

    request = Net::HTTP::Post.new(uri.request_uri, { 'Content-Type' => 'application/json' })
    request.body = {
      audience:           audience,
      grantType:          'urn:ietf:params:oauth:grant-type:token-exchange',
      requestedTokenType: 'urn:ietf:params:oauth:token-type:access_token',
      scope:              GCP_SCOPE,
      subjectTokenType:   'urn:ietf:params:oauth:token-type:jwt',
      subjectToken:       subject_jwt
    }.to_json

    response = http.request(request)
    data = JSON.parse(response.body)

    unless response.is_a?(Net::HTTPSuccess) && data['access_token']
      raise "GCP STS Token Exchange Error: #{data['error_description'] || data['error'] || response.message}"
    end
    data['access_token']
  end

  # 3. Impersonate the target service account with the federated token to
  #    obtain a normal OAuth2 access token scoped to that SA's IAM roles.
  #    The service account itself lives only in GCP - no key is ever created.
  def self.generate_access_token(sa_email, federated_token)
    uri = URI.parse("https://iamcredentials.googleapis.com/v1/projects/-/serviceAccounts/#{sa_email}:generateAccessToken")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true

    request = Net::HTTP::Post.new(uri.request_uri, {
      'Content-Type'  => 'application/json',
      'Authorization' => "Bearer #{federated_token}"
    })
    request.body = { scope: [GCP_SCOPE] }.to_json

    response = http.request(request)
    data = JSON.parse(response.body)

    unless response.is_a?(Net::HTTPSuccess) && data['accessToken']
      error_msg = data.dig('error', 'message') || response.message
      raise "GCP IAM Credentials Error: #{error_msg}"
    end

    expires_in = begin
      data['expireTime'] ? [(Time.parse(data['expireTime']) - Time.now).to_i, 60].max : 3600
    rescue
      3600
    end

    [data['accessToken'], expires_in]
  end

  # Safely wipe cached WIF tokens for a Vault address (mirrors VaultAuth.clear_gcp_cache)
  def self.clear_wif_cache(addr)
    @wif_cache ||= {}
    @wif_cache.reject! { |key, _| key.start_with?("#{addr}_") }
  end
end
