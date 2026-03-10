# -----------------------------------------------------------------------------
# File        : ctlabs/config/environment.rb
# Description : setup environment
# License     : MIT License
# -----------------------------------------------------------------------------

# SSL configuration ONLY - no app logic
module CTLabsSSL
  def self.configure(app)
    cert_path = ENV['CTLABS_SSL_CERT'] || '/etc/ctlabs/ssl/server.crt'
    key_path  = ENV['CTLABS_SSL_KEY']  || '/etc/ctlabs/ssl/server.key'
    
    if File.exist?(cert_path) && File.exist?(key_path)
      app.set :server_settings, {
        SSLEnable: true,
        SSLVerifyClient: OpenSSL::SSL::VERIFY_NONE,
        SSLCertificate: OpenSSL::X509::Certificate.new(File.read(cert_path)),
        SSLPrivateKey: OpenSSL::PKey::RSA.new(File.read(key_path)),
        SSLOptions: OpenSSL::SSL::OP_NO_SSLv2 | OpenSSL::SSL::OP_NO_SSLv3,
        SSLCipherList: 'HIGH:!aNULL:!MD5'
      }
      puts "✓ Using custom SSL cert: #{cert_path}"
    else
      app.set :server_settings, {
        SSLEnable: true,
        SSLVerifyClient: OpenSSL::SSL::VERIFY_NONE,
        SSLCertName: [['CN', WEBrick::Utils.getservername]]
      }
      puts "⚠️ Using self-signed cert (set CTLABS_SSL_CERT/KEY for custom)"
    end
  end
end