# -----------------------------------------------------------------------------
# File        : ctlabs/controllers/terminal_controller.rb
# Description : Controller for Web Terminal WebSocket and UI
# License     : MIT License
# -----------------------------------------------------------------------------

class TerminalController < BaseController
  get '/terminal/:node_name' do
    if request.env['HTTP_UPGRADE']&.downcase == 'websocket'
      request.env['rack.hijack'].call
      io = request.env['rack.hijack_io']

      ssl_mutex = Mutex.new
      wrapper = WSSocketWrapper.new(request.env, io, ssl_mutex)
      driver = WebSocket::Driver.rack(wrapper)
      
      node_name = params[:node_name]
      cmd = TerminalService.resolve_terminal_command(node_name, session)
      
      TerminalService.handle_websocket(driver, cmd, io, ssl_mutex)

      return [-1, {}, []]
    else
      @node_name = params[:node_name]
      erb :terminal, layout: false
    end
  end
end
