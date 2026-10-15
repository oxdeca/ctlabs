#!/usr/bin/env ruby

# -----------------------------------------------------------------------------
# File        : ctlabs/server.rb
# Description : Main secure Sinatra server for CT Labs
# License     : MIT License
# -----------------------------------------------------------------------------

require 'sinatra'
require 'sinatra/base'
require 'json'
require 'yaml'
require 'fileutils'
require 'securerandom'
require 'uri'
require 'openssl'
require 'websocket/driver'
require 'pty'
require 'timeout'

# Add lib to load path
$LOAD_PATH.unshift(File.expand_path('./lib', File.dirname(__FILE__)))

require 'lab'
require 'node'
require 'link'
require 'graph'
require 'controller'
require 'lablog'
require 'ws_socket_wrapper'
require 'vault_auth'
require 'gcp_auth'

# --- Load Helpers ---
require_relative 'helpers/application_helper'
require_relative 'helpers/lab_helper'
require_relative 'helpers/image_helper'

# --- Load Services ---
require_relative 'services/lab_repository'
require_relative 'services/automation_service'
require_relative 'services/image_service'
require_relative 'services/terminal_service'

# --- Load Controllers ---
require_relative 'controllers/base_controller'
require_relative 'controllers/labs_controller'
require_relative 'controllers/nodes_controller'
require_relative 'controllers/automation_controller'
require_relative 'controllers/images_controller'
require_relative 'controllers/profiles_controller'
require_relative 'controllers/topology_controller'
require_relative 'controllers/vault_controller'
require_relative 'controllers/main_controller'
require_relative 'controllers/terminal_controller'
require_relative 'controllers/logs_controller'
require_relative 'controllers/dnat_controller'
require_relative 'controllers/links_controller'

# --- Sinatra Settings (Classic for root app) ---
disable :logging
enable  :sessions
set     :server,             'webrick'
set     :session_secret,     SecureRandom.hex(64)
set     :bind,               '0.0.0.0'
set     :port,               4567
set     :public_folder,      '/srv/ctlabs-server/public'
set     :host_authorization, permitted_hosts: []
set     :markdown,           input: 'GFM'
disable :run

# --- Global Constants ---
CONFIG          = '/srv/ctlabs-server/public/config.yml'
INVENTORY       = '/srv/ctlabs-server/public/inventory.ini'
UPLOAD_DIR      = '/srv/ctlabs-server/uploads'
SCRIPT_DIR      = File.dirname(File.expand_path(__FILE__))
LABS_DIR        = "#{SCRIPT_DIR}/../labs"
CTLABS_SCRIPT   = './ctlabs.rb'
LOCK_DIR        = '/var/run/ctlabs'
LOCK_FILE       = "#{LOCK_DIR}/running_lab"
LOG_DIR         = '/var/log/ctlabs'

Dir.mkdir(LOG_DIR,    0755) unless Dir.exist?(LOG_DIR)
Dir.mkdir(LOCK_DIR,   0755) unless Dir.exist?(LOCK_DIR)
Dir.mkdir(UPLOAD_DIR, 0755) unless Dir.exist?(UPLOAD_DIR)

# --- Mount Controllers ---
# LinksController must precede LabsController so the more specific
# /labs/*/link/save route is matched before the greedy /labs/*/save.
use LinksController
use LabsController
use NodesController
use AutomationController
use ImagesController
use ProfilesController
use TopologyController
use VaultController
use MainController
use TerminalController
use LogsController
use DnatController

# ------------------------------------------------------------------------------
# SHUTDOWN REAPER
# ------------------------------------------------------------------------------
# systemd stops the unit with KillMode=control-group: it SIGTERMs every PID in
# the unit's cgroup and then waits for that cgroup to drain before the stop is
# considered complete. The podman/docker *exec* conmon that our web terminals
# (services/terminal_service.rb) and playbook streams (lib/automation.rb) spawn
# ignores SIGTERM, so `systemctl restart ctlabs-server` would otherwise block
# until TimeoutStopSec and then SIGKILL the whole cgroup -- leaving the webui
# unreachable for the duration. Reap those stragglers ourselves on shutdown so
# the stop completes immediately.
#
# Only conmon/podman/docker PIDs inside *our own* cgroup are killed, so Puma and
# its threads are never at risk. Container conmons live in their own
# ctlabs-node-*.scope units (see Node#scoped_run) and are not in this cgroup.
def reap_exec_stragglers
  line = File.read('/proc/self/cgroup').lines.map(&:strip).find { |l| l.include?('::') }
  return unless line

  procs = "/sys/fs/cgroup#{line.split('::', 2).last}/cgroup.procs"
  return unless File.file?(procs)

  me = Process.pid
  File.readlines(procs).each do |entry|
    pid = entry.to_i
    next if pid == me

    comm = begin
      File.read("/proc/#{pid}/comm").strip
    rescue StandardError
      nil
    end
    next unless %w[conmon podman docker].include?(comm)

    Process.kill('KILL', pid) rescue nil
  end
rescue StandardError
  nil
end

# ------------------------------------------------------------------------------
# SECURE PUMA BOOTLOADER
# ------------------------------------------------------------------------------
if __FILE__ == $0
  require 'webrick'
  require 'puma'
  require 'puma/configuration'
  require 'puma/launcher'

  CERT_DIR = '/srv/ctlabs-server/ssl'
  FileUtils.mkdir_p(CERT_DIR)
  CERT_PATH = File.join(CERT_DIR, 'cert.pem')
  KEY_PATH  = File.join(CERT_DIR, 'key.pem')

  unless File.exist?(CERT_PATH) && File.exist?(KEY_PATH)
    puts "Generating secure self-signed SSL certificates for Puma..."
    key             = OpenSSL::PKey::RSA.new(4096)
    cert            = OpenSSL::X509::Certificate.new
    cert.version    = 2
    cert.serial     = 1
    cn_name         = WEBrick::Utils.getservername rescue 'localhost'
    cert.subject    = OpenSSL::X509::Name.parse("/CN=#{cn_name}")
    cert.issuer     = cert.subject
    cert.public_key = key.public_key
    cert.not_before = Time.now
    cert.not_after  = cert.not_before + (365 * 24 * 60 * 60)
    cert.sign(key, OpenSSL::Digest.new('SHA256'))
    
    File.write(KEY_PATH, key.to_pem)
    File.write(CERT_PATH, cert.to_pem)
  end

  puts "🚀 Starting CTLABS Secure Terminal Engine on https://0.0.0.0:4567"

  conf = Puma::Configuration.new do |c|
    # Bound graceful shutdown. The webui streams long playbook runs over
    # hijacked WebSocket connections; Puma's default (:forever) makes
    # `systemctl restart` block on those until systemd's 90s TimeoutStopSec
    # SIGKILLs the whole cgroup -- the webui is unreachable the entire time.
    # 5s is enough for normal requests to drain, then Puma force-closes.
    c.force_shutdown_after 5
    c.bind "ssl://0.0.0.0:4567?key=#{KEY_PATH}&cert=#{CERT_PATH}&verify_mode=none"
    c.app Sinatra::Application
  end

  launcher = Puma::Launcher.new(conf)

  # A directly-constructed Launcher owns its own Events sink (Puma only shares
  # the config's events when booted via the CLI), so register on the launcher's
  # sink. after_stopped fires during graceful stop -- before the process exits
  # and before systemd inspects the cgroup -- which is exactly when the reap
  # needs to run. at_exit is a belt-and-suspenders fallback for other stop paths.
  if launcher.events.respond_to?(:after_stopped)
    launcher.events.after_stopped { reap_exec_stragglers }
  else
    launcher.events.on_stopped { reap_exec_stragglers }
  end
  at_exit { reap_exec_stragglers }

  launcher.run
end
