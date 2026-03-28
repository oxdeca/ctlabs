#!/usr/bin/env ruby

# -----------------------------------------------------------------------------
# File        : ctlabs/server.rb
# Description : ctlabs main script
# License     : MIT License
# -----------------------------------------------------------------------------

require 'fileutils'
require 'openssl'
require 'sinatra'
require 'erb'
require 'net/http'
require 'shellwords'
require 'set'
require 'securerandom'
require 'websocket/driver'
require 'pty'
require 'json'

# --- Load Libraries ---
$LOAD_PATH.unshift File.join(File.dirname(__FILE__), 'lib')
require 'lab'
require 'node'
require 'link'
require 'graph'
require 'lablog'
require 'ws_socket_wrapper' # <--- Your extracted class!
require 'vault_auth'

# --- Sinatra Settings ---
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
GLOBAL_PROFILES = "#{SCRIPT_DIR}/../labs/node_profiles.yml"
CTLABS_SCRIPT   = './ctlabs.rb'
LOCK_DIR        = '/var/run/ctlabs'
LOCK_FILE       = "#{LOCK_DIR}/running_lab"
LOG_DIR         = '/var/log/ctlabs'

Dir.mkdir(LOG_DIR,    0755) unless Dir.exist?(LOG_DIR)
Dir.mkdir(LOCK_DIR,   0755) unless Dir.exist?(LOCK_DIR)
Dir.mkdir(UPLOAD_DIR, 0755) unless Dir.exist?(UPLOAD_DIR)

# --- Middleware (Basic Auth) ---
use Rack::Auth::Basic, 'Restricted Area' do |user, pass|
  salt = "GGV78Ib5vVRkTc"
  user == 'ctlabs' && pass.crypt("$6$#{salt}$") == "$6$GGV78Ib5vVRkTc$cRAo9wl36SQPkh/UFzgEIOO1rBuju7/h5Lu8fJMDUNDG0HUcL3AhBNEqcYT1UUZkmBHa9.8r/5eh5qXwA8zcr."
end

# --- Load Helpers ---
require_relative 'helpers/application_helper'
require_relative 'helpers/yaml_helper'
require_relative 'helpers/lab_helper'
require_relative 'helpers/image_helper'

helpers ApplicationHelper
helpers YamlHelper
helpers LabHelper
helpers ImageHelper

# --- Load Routes ---
require_relative 'routes/main'
require_relative 'routes/terminal'
require_relative 'routes/images'
require_relative 'routes/logs'
require_relative 'routes/misc'
require_relative 'routes/automation'
require_relative 'routes/topology'
require_relative 'routes/labs'
require_relative 'routes/vault'

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
    c.bind "ssl://0.0.0.0:4567?key=#{KEY_PATH}&cert=#{CERT_PATH}&verify_mode=none"
    c.app Sinatra::Application
  end

  Puma::Launcher.new(conf).run
end
