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

  helpers do
    def register_log(path)
      return nil unless path
      session[:log_map] ||= {}
      id = session[:log_map].key(path)
      unless id
        id = SecureRandom.hex(8)
        session[:log_map][id] = path
      end
      id
    end

    def resolve_log_path(id)
      path = session[:log_map]&.[](id)
      return nil unless path
      
      log_dir = LabLog::LOG_DIR
      basename = File.basename(path)
      is_valid_prefix = basename.start_with?('ctlabs_') || basename.start_with?('build_') || basename == 'ctlabs.log'
      
      unless (path.start_with?(log_dir) || path == '/var/log/ctlabs.log') && is_valid_prefix && path.end_with?('.log')
        return nil
      end
      path
    end
  end

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
        f_user, f_stored = auth_content.split(':', 2)

        # Handle both hashed and plaintext credentials for backward compatibility
        if f_stored&.start_with?('$6$')
          next user == f_user && pass.crypt(f_stored) == f_stored
        else
          next user == f_user && pass == f_stored
        end
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