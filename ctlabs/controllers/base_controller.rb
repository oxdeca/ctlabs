# -----------------------------------------------------------------------------
# File        : ctlabs/controllers/base_controller.rb
# Description : Base controller for CT Labs Sinatra application
# License     : MIT License
# -----------------------------------------------------------------------------

class BaseController < Sinatra::Base
  # --- Load Helpers ---
  helpers ApplicationHelper
  #helpers YamlHelper
  helpers LabHelper
  helpers ImageHelper

  # --- Sinatra Settings ---
  configure do
    disable :logging
    enable  :sessions
    set     :server,             'webrick'
    set     :session_secret,     SecureRandom.hex(64)
    set     :bind,               '0.0.0.0'
    set     :port,               4567
    set     :public_folder,      '/srv/ctlabs-server/public'
    set     :host_authorization, permitted_hosts: []
    set     :markdown,           input: 'GFM'
    set     :views,              File.expand_path('../views', __dir__)
  end

  # --- Middleware (Basic Auth) ---
  use Rack::Auth::Basic, 'Restricted Area' do |user, pass|
    # Default credentials
    username      = 'ctlabs'
    salt          = "GGV78Ib5vVRkTc"
    password_hash = "$6$GGV78Ib5vVRkTc$cRAo9wl36SQPkh/UFzgEIOO1rBuju7/h5Lu8fJMDUNDG0HUcL3AhBNEqcYT1UUZkmBHa9.8r/5eh5qXwA8zcr."

    # Override with credentials from ~/.ctlabs-server/auth if it exists
    auth_file = File.expand_path('~/.ctlabs-server/auth')
    if File.exist?(auth_file)
      begin
        auth_content = File.read(auth_file).strip
        f_user, f_pass = auth_content.split(':', 2)
        next user == f_user && pass == f_pass
      rescue
        # Fallback to default on error
      end
    end

    user == username && pass.crypt("$6$#{salt}$") == password_hash
  end

  # Custom error handling can be added here
  error 400..599 do
    # You can customize the error page if needed
    # erb :error
    "An error occurred: #{env['sinatra.error'].message if env['sinatra.error']}"
  end
end