# -----------------------------------------------------------------------------
# File        : ctlabs/lib/ws_socket_wrapper.rb
# License     : MIT License
# -----------------------------------------------------------------------------

class WSSocketWrapper
  attr_reader :env
  def initialize(env, io, mutex)
    @env = env
    @io = io
    @mutex = mutex
  end
  def url
    scheme = @env['rack.url_scheme'] == 'https' ? 'wss' : 'ws'
    "#{scheme}://#{@env['HTTP_HOST']}#{@env['REQUEST_URI']}"
  end
  def write(data)
    @mutex.synchronize { @io.write(data) } rescue nil
  end
end
