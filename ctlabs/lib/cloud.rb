# -----------------------------------------------------------------------------
# File    : ctlabs/lib/cloud.rb
# Purpose : Cloud (GCP) teardown / reconciliation by LABEL.
#
#           "The resources themselves are the durable record." Instead of
#           destroying from a terraform.tfstate (which is lost on a crash,
#           a partial apply or an ad-hoc create and then leaks orphans), every
#           resource a lab creates is stamped with a label naming the lab
#           (`ctlabs_lab=<lab>`), and teardown is simply *list by label +
#           delete*. Self-healing and tool-agnostic (TF or Ansible alike).
#
#           NOTE: GCP routes and firewall rules do NOT support labels, so
#           those two kinds are swept by NAME PREFIX (`<lab>-...`) instead.
#
#           Auth: reuses GcpAuth (Vault GCP secrets engine or Vault WIF) to
#           mint an OAuth2 access token, then talks plain REST to
#           compute.googleapis.com - no gcloud / no Cloud SDK.
#
#           !!! UNVERIFIED !!!  Written without live GCP credentials, so the
#           request/URL shapes have NOT been exercised against a real project.
#           Treat the first real run as a test: use `dry_run: true` first.
# -----------------------------------------------------------------------------
require 'net/http'
require 'uri'
require 'json'

class Cloud
  API = 'https://compute.googleapis.com/compute/v1'.freeze

  # GCP label values: lowercase letters, digits, '-' and '_', <= 63 chars.
  LAB_LABEL     = 'ctlabs_lab'.freeze
  ROLE_LABEL    = 'ctlabs_role'.freeze
  MANAGED_LABEL = 'ctlabs_created'.freeze

  # kind => collection path segment for the delete URL (zonal vs regional).
  AGGREGATED = {
    'instances' => 'zones',
    'disks'     => 'zones',
    'addresses' => 'regions'
  }.freeze

  # Label map to stamp on a lab's resources. Terraform/Ansible MUST use this
  # (via the terraform agent's modules) so teardown stays tool-agnostic.
  def self.labels(lab:, role: nil)
    l = { MANAGED_LABEL => 'true', LAB_LABEL => sanitize(lab) }
    l[ROLE_LABEL] = sanitize(role) if role
    l
  end

  def self.sanitize(value)
    value.to_s.downcase.gsub(/[^a-z0-9_-]/, '-').slice(0, 63)
  end

  # log: a LabLog (write/2) or an IO (puts). Either works.
  def initialize(project:, token:, log: nil)
    raise ArgumentError, "Cloud: project is required" if project.to_s.strip.empty?
    raise ArgumentError, "Cloud: access token is required" if token.to_s.strip.empty?
    @project = project
    @token   = token
    @log     = log
  end

  # Delete every resource this lab owns. Returns a summary hash.
  #   dry_run: list + report what WOULD be deleted, delete nothing.
  def teardown!(lab, dry_run: false)
    label  = self.class.sanitize(lab)
    prefix = "#{label}-"
    @summary = {
      lab: lab, label: label, dry_run: dry_run,
      deleted: Hash.new(0), found: Hash.new(0), errors: []
    }

    log "cloud: teardown lab=#{lab} #{LAB_LABEL}=#{label} project=#{@project}#{dry_run ? ' (DRY-RUN)' : ''}", 'warn'

    AGGREGATED.each_key { |kind| reap_aggregated(kind, label, dry_run) }
    reap_global_labelled('addresses', label, dry_run)
    reap_global_by_prefix('routes', prefix, dry_run)
    reap_global_by_prefix('firewalls', prefix, dry_run)

    log "cloud: teardown summary #{@summary[:deleted].inspect} " \
        "found=#{@summary[:found].inspect} errors=#{@summary[:errors].length}", 'warn'
    @summary
  end

  private

  # Instances / disks / (regional) addresses: list via aggregatedList, keep the
  # ones labelled for this lab, delete each from its own zone/region.
  def reap_aggregated(kind, label, dry_run)
    mine = aggregated_items(kind).select { |it| it.dig('labels', LAB_LABEL) == label }
    @summary[:found][kind] = mine.size
    log "cloud:   #{kind}: #{mine.size} labelled #{LAB_LABEL}=#{label}"
    mine.each do |it|
      url = aggregated_delete_url(kind, it)
      if dry_run
        log "cloud:   would delete #{kind} #{it['name']} (#{url})"
      else
        delete_url url, kind, it['name']
      end
    end
  end

  # Global addresses live at /global/addresses and carry labels.
  def reap_global_labelled(collection, label, dry_run)
    mine = global_items(collection).select { |it| it.dig('labels', LAB_LABEL) == label }
    @summary[:found]["global_#{collection}"] = mine.size
    log "cloud:   global #{collection}: #{mine.size}"
    mine.each do |it|
      url = "#{API}/projects/#{@project}/global/#{collection}/#{it['name']}"
      dry_run ? log("cloud:   would delete global #{collection} #{it['name']}") : delete_url(url, collection, it['name'])
    end
  end

  # Routes / firewalls: no GCP labels -> sweep by name prefix `<lab>-`.
  def reap_global_by_prefix(collection, prefix, dry_run)
    mine = global_items(collection).select { |it| it['name'].to_s.start_with?(prefix) }
    @summary[:found][collection] = mine.size
    log "cloud:   #{collection} (prefix #{prefix}): #{mine.size}"
    mine.each do |it|
      url = "#{API}/projects/#{@project}/global/#{collection}/#{it['name']}"
      dry_run ? log("cloud:   would delete #{collection} #{it['name']} (name prefix)") : delete_url(url, collection, it['name'])
    end
  end

  def aggregated_delete_url(kind, item)
    scope_seg = item['zone'] || item['region'] || ''
    scope     = scope_seg.rpartition('/').last
    "#{API}/projects/#{@project}/#{AGGREGATED[kind]}/#{scope}/#{kind}/#{item['name']}"
  end

  # ---------------------------------------------------------------------------
  # HTTP
  # ---------------------------------------------------------------------------
  def get_json(url)
    res, data = request(:get, url)
    unless res.is_a?(Net::HTTPSuccess)
      msg = data.dig('error', 'message') || res.body.to_s[0, 200]
      raise "GCP GET #{url} -> #{res.code} #{res.message}: #{msg}"
    end
    data
  end

  def delete_url(url, kind, name)
    res, data = request(:delete, url)
    if res.is_a?(Net::HTTPSuccess)
      @summary[:deleted][kind] += 1
      log "cloud:   deleted #{kind} #{name} (#{res.code})"
    else
      msg = "delete #{kind} #{name} -> #{res.code} #{res.message}: #{data.dig('error', 'message')}"
      @summary[:errors] << msg
      log "cloud:   ! #{msg}", 'error'
    end
  end

  def request(method, url)
    uri  = URI.parse(url)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl      = true
    http.open_timeout = 15
    http.read_timeout = 60

    req = method == :delete ? Net::HTTP::Delete.new(uri.request_uri) : Net::HTTP::Get.new(uri.request_uri)
    req['Authorization'] = "Bearer #{@token}"
    req['Accept']        = 'application/json'

    res  = http.request(req)
    data = (JSON.parse(res.body) rescue {})
    [res, data]
  end

  # Aggregated list (instances/disks/addresses): flatten every zone/region's
  # array under `items`, following nextPageToken.
  def aggregated_items(kind)
    items = []
    path  = "#{API}/projects/#{@project}/aggregated/#{kind}"
    loop do
      data = get_json(path)
      (data['items'] || {}).each_value { |scope| (scope[kind] || []).each { |it| items << it } }
      token = data['nextPageToken'].to_s
      break if token.empty?
      path = "#{API}/projects/#{@project}/aggregated/#{kind}?pageToken=#{token}"
    end
    items
  end

  def global_items(collection)
    items = []
    path  = "#{API}/projects/#{@project}/global/#{collection}"
    loop do
      data   = get_json(path)
      items += (data['items'] || [])
      token  = data['nextPageToken'].to_s
      break if token.empty?
      path = "#{API}/projects/#{@project}/global/#{collection}?pageToken=#{token}"
    end
    items
  end

  def log(msg, level = 'info')
    if @log.respond_to?(:write)
      @log.write(msg, level)
    elsif @log.respond_to?(:puts)
      @log.puts(msg)
    end
  end
end
