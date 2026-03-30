# -----------------------------------------------------------------------------
# File        : ctlabs/lib/graph.rb
# Description : graph class; creating visualizations
# License     : MIT License
# -----------------------------------------------------------------------------
#
# Desc: creates the various graphs by generating modern graphviz code
#
class Graph
  attr_reader :colors

  def initialize(args)
    @log = args[:log] || LabLog.null
    @log.write "== Graph ==", "debug"
    @log.write "#{__method__}(): args=#{args}", "debug"

    @name    = args[:name]
    @pubdir  = args[:pubdir]
    @nodes   = args[:nodes]
    @links   = args[:links]
    @binding = args[:binding]
    @dotfile = "#{@pubdir}/../#{@name}.dot"

    @colors  = [
      '#ef4444', '#3b82f6', '#22c55e', '#eab308',
      '#a855f7', '#06b6d4', '#f97316', '#ec4899',
      '#84cc16', '#6366f1', '#14b8a6', '#d946ef'
    ]

    # --- AUTO-PORT INJECTOR FOR STANDARD LINKS ---
    (@links || []).each do |l|
      next unless l.is_a?(Array) && l.size >= 2
      n_a_name, int_a = l[0].to_s.split(':')
      n_b_name, int_b = l[1].to_s.split(':')

      n_a = @nodes.find { |n| n.name == n_a_name }
      n_b = @nodes.find { |n| n.name == n_b_name }

      n_a.nics[int_a] = '' if n_a && int_a && !n_a.nics.key?(int_a)
      n_b.nics[int_b] = '' if n_b && int_b && !n_b.nics.key?(int_b)
    end

    # --- AUTO-PORT INJECTOR FOR VPN PEERS ---
    (@nodes || []).each do |node|
      if node.type == 'gateway' && ['openvpn', 'wireguard', 'ipsec'].include?(node.provider.to_s.downcase)
        if node.peers && node.peers.is_a?(Hash)
          p_local = node.peers['local'] || node.peers[:local] || {}
          p_remote = node.peers['remote'] || node.peers[:remote] || {}

          l_node_name = p_local['node'] || p_local[:node]
          r_node_name = p_remote['node'] || p_remote[:node]

          # Extract the interface names dynamically (e.g. tun0)
          l_int = p_local.keys.find { |k| k.to_s != 'node' } || 'tun0'
          r_int = p_remote.keys.find { |k| k.to_s != 'node' } || 'tun0'

          # Wipe out default empty eth interfaces for pure VPN gateways
          node.nics.delete_if { |k, v| k.start_with?('eth') && v.to_s.empty? }

          # Inject interfaces into the VPN Gateway
          node.nics[l_int] = p_local[l_int] || ''
          node.nics[r_int] = p_remote[r_int] || ''

          # Inject interfaces into the attached Peers
          l_obj = @nodes.find { |n| n.name == l_node_name }
          r_obj = @nodes.find { |n| n.name == r_node_name }

          l_obj.nics[l_int] = p_local[l_int] || '' if l_obj && !l_obj.nics.key?(l_int)
          r_obj.nics[r_int] = p_remote[r_int] || '' if r_obj && !r_obj.nics.key?(r_int)
        end
      end
    end
  end

  def build_tooltip(node)
    tt = ["#{node.name.upcase}  [ #{node.type.capitalize} ]"]
    tt << "━━━━━━━━━━━━━━━━━━━━━━━━"

    if node.respond_to?(:info) && node.info && !node.info.empty?
      tt << "ℹ️ #{node.info}"
      tt << "━━━━━━━━━━━━━━━━━━━━━━━━"
    end

    if node.remote? && node.nics && node.nics['eth0']
      tt << "🌐 Mgmt (eth0): #{node.nics['eth0']}"
    elsif node.ipv4 && !node.ipv4.to_s.empty?
      tt << "🌐 IPv4: #{node.ipv4}"
    end

    if node.nics && !node.nics.empty?
      has_valid_nics = false
      nic_lines = []
      node.nics.each do |k, v|
        next if v.to_s.strip.empty?
        # Hide the invalid eth0 from remote host tooltips
        next if node.remote? && k == 'eth0'
        nic_lines << "   ▪ #{k}  ➔  #{v}"
        has_valid_nics = true
      end

      if has_valid_nics
        tt << "🔌 Interfaces:"
        tt += nic_lines
      end
    end

    if node.dnat && !node.dnat.empty?
      tt << "🔀 Port Forwarding:"
      if node.dnat.is_a?(Array)
        node.dnat.each { |d| tt << "   ▪ Ext:#{d[0]}  ➔  Int:#{d[1]} (#{d[2] || 'tcp'})" }
      elsif node.dnat.is_a?(String)
        tt << "   ▪ Target ➔  #{node.dnat}"
      end
    end

    if node.dnat && node.dnat.is_a?(Array)
      server_ip = Socket::getaddrinfo(Socket.gethostname,"echo",Socket::AF_INET)[0][3] rescue "127.0.0.1"
      node.dnat.each do |d|
        tt << "[LINK:Web Interface (Port #{d[0]})|https://#{server_ip}:#{d[0]}]"
      end
    end

    if node.respond_to?(:urls) && node.urls.is_a?(Hash)
      node.urls.each do |title, url|
        tt << "[LINK:#{title}|#{url}]"
      end
    end

    if node.respond_to?(:term) && node.term && !node.term.empty?
      tt << "[TERM:#{node.term}]"
    elsif node.remote? && node.gw && !node.gw.to_s.empty?
      ip_only = node.gw.split('/').first
      tt << "[TERM:ssh://root@#{ip_only}]"
    elsif node.ipv4 && !node.ipv4.to_s.empty?
      ip_only = node.ipv4.split('/').first
      tt << "[TERM:ssh://root@#{ip_only}]"
    end

    tt.join('&#10;')
  end

  def get_cons
    @log.write "#{__method__}():  ", "debug"

    %{
        graph <%= @name.gsub(/[.-]/, "_") %> {
          graph [pad="0.5", nodesep="0.8", ranksep="1.8", overlap=false, splines=true, layout=dot, rankdir=TB, bgcolor="#1e293b", fontname="Helvetica, Arial, sans-serif", fontsize="16"]
          edge  [penwidth="3.0", fontname="Helvetica, Arial, sans-serif", fontsize="12"]

        <%-
            @nodes.each do |node|
              is_vpn_gw = node.type == 'gateway' && ['openvpn', 'wireguard', 'ipsec'].include?(node.provider.to_s.downcase)
              if node.kind == "mgmt" || node.plane == "mgmt" || node.type == "controller" || (!node.remote? && node.type == 'gateway' && node.dnat.nil? && !is_vpn_gw)
                next
              end
              group = node.type

              border_color = "#10b981"
              n_icon = "🎛️ "

              if node.remote?
                is_transit = (node.plane == 'transit') || (node.nics && node.nics.keys.any? { |k| k.start_with?('tun', 'wg') })
                border_color = is_transit ? "#14b8a6" : "#0ea5e9"
                n_icon = is_transit ? "🛡️ " : "☁️ "
              else
                case node.type
                  when 'host', 'vhost'
                    border_color = "#38bdf8"
                    n_icon = "💻 "
                  when 'router'
                    border_color = "#f59e0b"
                    n_icon = "🔀 "
                  when 'gateway'
                    if is_vpn_gw
                      border_color = "#14b8a6"
                      n_icon = "🛡️ "
                    else
                      border_color = "#a855f7"
                      n_icon = "🚪 "
                    end
                  when 'controller'
                    border_color = "#ef4444"
                    n_icon = "⚙️ "
                end
              end

              server_ip = Socket::getaddrinfo(Socket.gethostname,"echo",Socket::AF_INET)[0][3] rescue "127.0.0.1"
              node_link = (node.dnat.nil? || !node.dnat.is_a?(Array)) ? "" : "https://" + server_ip + ":" + node.dnat[0][0].to_s
              col_span = node.nics.size == 0 ? 1 : node.nics.size
        -%>

          subgraph cluster_<%= node.name.gsub(/[.-]/, "_") %> {
            graph[style="invis", group="<%= group %>"]
            node[shape=rect, style="rounded,filled", fillcolor="#0f172a", color="<%= border_color %>", penwidth="2.5", fontname="Helvetica, Arial, sans-serif", fontcolor="#f8fafc", margin="0.1"]
            <%= node.name.gsub(/[.-]/, "_") %>[href="<%= node_link %>",target="_blank",tooltip="<%= @graph.build_tooltip(node) %>",label=<
            <table border="0" cellborder="0" cellspacing="6" cellpadding="4">
        <%- if !['host', 'vhost', 'external'].include?(group) -%>
              <tr>
                <td align="center" colspan="<%= col_span %>"><b><font color="<%= border_color %>" point-size="16"><%= n_icon %><%= node.name.gsub(/[.-]/, "_") %></font></b></td>
              </tr>
        <%- end -%>
              <tr>
        <%-
              valid_nics = node.nics.reject { |k, _| node.remote? && k == 'eth0' }
              if valid_nics.empty?
        -%>
                <td bgcolor="#1e293b" align="text"><font color="#cbd5e1" point-size="12">&nbsp;</font></td>
        <%-   else -%>
        <%-     valid_nics.each do |k, v| -%>
                <td port="<%= k %>" bgcolor="#1e293b" align="text"><font color="#cbd5e1" point-size="12"> <%= k.to_s.empty? ? '&nbsp;' : k %> </font></td>
        <%-     end -%>
        <%-   end -%>
              </tr>
        <%- if ['host', 'vhost', 'external'].include?(group) -%>
              <tr>
                <td align="center" colspan="<%= col_span %>"><b><font color="<%= border_color %>" point-size="16"><%= n_icon %><%= node.name.gsub(/[.-]/, "_") %></font></b></td>
              </tr>
        <%- end -%>
            </table> >]
          }
        <%- end -%>

        <%- ext_names = @nodes.select { |n| n.remote? }.map(&:name) -%>
        <%- i = 0
            @links.each do |l|
              node_a, int_a = l[0].split(':')
              node_b, int_b = l[1].split(':')
              is_vpn = int_a.to_s.start_with?('tun', 'wg') || int_b.to_s.start_with?('tun', 'wg')
              
              if (node_a != 'sw0' && node_a != 'ro0' && !ext_names.include?(node_a) && !ext_names.include?(node_b)) || is_vpn
                link_opts = is_vpn ? ', style="dashed"' : ""
        -%>
        <%=     l[0].gsub(/[.-]/, "_") %>:s -- <%= l[1].gsub(/[.-]/, "_") %>:n [color="<%= @graph.colors[i] %>"<%= link_opts %>]
        <%-     i = (i + 1) % @graph.colors.size -%>
        <%-   end -%>
        <%- end -%>

        <%-
            # --- NEW: EXPLICIT VPN GATEWAY PEERING FOR CONN MAPS ---
            @nodes.each do |node|
              if node.type == 'gateway' && ['openvpn', 'wireguard', 'ipsec'].include?(node.provider.to_s.downcase)
                if node.peers && node.peers.is_a?(Hash)
                  p_local = node.peers['local'] || node.peers[:local] || {}
                  p_remote = node.peers['remote'] || node.peers[:remote] || {}

                  l_node = p_local['node'] || p_local[:node]
                  r_node = p_remote['node'] || p_remote[:node]
                  
                  l_int = p_local.keys.find { |k| k.to_s != 'node' } || 'tun0'
                  r_int = p_remote.keys.find { |k| k.to_s != 'node' } || 'tun0'

                  if l_node
        -%>
          <%= l_node.gsub(/[.-]/, "_") %>:<%= l_int %>:s -- <%= node.name.gsub(/[.-]/, "_") %>:<%= l_int %>:n [style="dashed", color="#14b8a6", penwidth="2.5"]
        <%-       end 
                  if r_node
        -%>
          <%= node.name.gsub(/[.-]/, "_") %>:<%= r_int %>:s -- <%= r_node.gsub(/[.-]/, "_") %>:<%= r_int %>:n [style="dashed", color="#14b8a6", penwidth="2.5"]
        <%-       end
                end
              end
            end
        -%>

        <%-
            server_ip = Socket::getaddrinfo(Socket.gethostname,"echo",Socket::AF_INET)[0][3] rescue "127.0.0.1"
            host_name = @cfg ? (@cfg.dig('topology', 0, 'hv') || @cfg.dig('topology', 0, 'vm', 'name') || @cfg.dig('topology', 0, 'name') || 'CTLABS_HOST' rescue 'CTLABS_HOST') : 'CTLABS_HOST'
            host_tt = "CTLABS_HOST  [ Hypervisor ]&#10;━━━━━━━━━━━━━━━━━━━━━━━━&#10;ℹ️ Host VM: " + host_name + "&#10;━━━━━━━━━━━━━━━━━━━━━━━━&#10;🌐 IPv4: " + server_ip
        -%>
          subgraph cluster_ctlabs_host {
            graph[style="invis", group="hypervisor"]
            node[shape=rect, style="rounded,filled", fillcolor="#0f172a", color="#ec4899", penwidth="2.5", fontname="Helvetica, Arial, sans-serif", fontcolor="#f8fafc", margin="0.1"]
            ctlabs_host[tooltip="<%= host_tt %>",label=<
            <table border="0" cellborder="0" cellspacing="6" cellpadding="4">
              <tr><td align="center"><b><font color="#ec4899" point-size="16">🏢 <%= host_name %></font></b></td></tr>
              <tr><td port="eth0" bgcolor="#1e293b" align="text"><font color="#cbd5e1" point-size="12"> <%= server_ip %> </font></td></tr>
            </table> >]
          }
        <%- target_node = @nodes.find { |n| n.name == 'natgw' } || @nodes.find { |n| n.name == 'sw0' } -%>
        <%- if target_node -%>
          ctlabs_host:eth0:s -- <%= target_node.name.gsub(/[.-]/, "_") %>:n [color="#ec4899", style="dashed", penwidth="2.0"]
        <%-   @nodes.select { |n| n.remote? }.each do |ext_node|
                is_transit = (ext_node.plane == 'transit') || (ext_node.nics && ext_node.nics.keys.any? { |k| k.start_with?('tun', 'wg') })
                next if is_transit
                ext_port = ext_node.nics.keys.first || 'eth1' -%>
          <%= ext_node.name.gsub(/[.-]/, "_") %>:<%= ext_port %>:s -- <%= target_node.name.gsub(/[.-]/, "_") %>:n [color="#0ea5e9", style="dashed", penwidth="2.0"]
        <%-   end -%>
        <%- end -%>

          fontsize  = "20"
          fontcolor = "#f8fafc"
          label     = "<%= @name %> [<%= @desc %>]"
          labelloc  = top
          labeljust = left
        }
    }
  end

  def get_mgmt_cons
    @log.write "#{__method__}():  ", "debug"

    %{
        graph <%= @name.gsub(/[.-]/, "_") %> {
          graph [pad="0.5", nodesep="0.8", ranksep="1.8", overlap=false, splines=true, layout=dot, rankdir=TB, bgcolor="#1e293b", fontname="Helvetica, Arial, sans-serif", fontsize="16"]
          edge  [penwidth="3.0", fontname="Helvetica, Arial, sans-serif", fontsize="12"]

        <%-
            @nodes.each do |node|
              is_vpn_gw = node.type == 'gateway' && ['openvpn', 'wireguard', 'ipsec'].include?(node.provider.to_s.downcase)
              group = node.type

              border_color = "#10b981"
              n_icon = "🎛️ "

              if node.remote?
                is_transit = (node.plane == 'transit') || (node.nics && node.nics.keys.any? { |k| k.start_with?('tun', 'wg') })
                border_color = is_transit ? "#14b8a6" : "#0ea5e9"
                n_icon = is_transit ? "🛡️ " : "☁️ "
              else
                case node.type
                  when 'host', 'vhost'
                    border_color = "#38bdf8"
                    n_icon = "💻 "
                  when 'router'
                    border_color = "#f59e0b"
                    n_icon = "🔀 "
                  when 'gateway'
                    if is_vpn_gw
                      border_color = "#14b8a6"
                      n_icon = "🛡️ "
                    else
                      border_color = "#a855f7"
                      n_icon = "🚪 "
                    end
                  when 'controller'
                    border_color = "#ef4444"
                    n_icon = "⚙️ "
                end
              end

              server_ip = Socket::getaddrinfo(Socket.gethostname,"echo",Socket::AF_INET)[0][3] rescue "127.0.0.1"
              node_link = (node.dnat.nil? || !node.dnat.is_a?(Array)) ? "" : "https://" + server_ip + ":" + node.dnat[0][0].to_s
              col_span = node.nics.size == 0 ? 1 : node.nics.size
        -%>
          subgraph cluster_<%= node.name.gsub(/[.-]/, "_") %> {
            graph[style="invis", group="<%= group %>"]
            node[shape=rect, style="rounded,filled", fillcolor="#0f172a", color="<%= border_color %>", penwidth="2.5", fontname="Helvetica, Arial, sans-serif", fontcolor="#f8fafc", margin="0.1"]
            <%= node.name.gsub(/[.-]/, "_") %>[href="<%= node_link %>",target="_blank",tooltip="<%= @graph.build_tooltip(node) %>",label=<
            <table border="0" cellborder="0" cellspacing="6" cellpadding="4">
        <%- if ![ 'host', 'vhost', 'controller', 'external' ].include?(group) -%>
              <tr>
                <td align="center" colspan="<%= col_span %>"><b><font color="<%= border_color %>" point-size="16"><%= n_icon %><%= node.name.gsub(/[.-]/, "_") %></font></b></td>
              </tr>
        <%- end -%>
              <tr>
        <%-
              valid_nics = node.nics.reject { |k, _| node.remote? && k == 'eth0' }
              if valid_nics.empty?
        -%>
                <td bgcolor="#1e293b" align="text"><font color="#cbd5e1" point-size="12">&nbsp;</font></td>
        <%-   else -%>
        <%-     valid_nics.each do |k, v| -%>
                <td port="<%= k %>" bgcolor="#1e293b" align="text"><font color="#cbd5e1" point-size="12"> <%= k.to_s.empty? ? '&nbsp;' : k %> </font></td>
        <%-     end -%>
        <%-   end -%>
              </tr>
        <%- if [ 'host', 'vhost', 'controller', 'external'].include?(group) -%>
              <tr>
                <td align="center" colspan="<%= col_span %>"><b><font color="<%= border_color %>" point-size="16"><%= n_icon %><%= node.name.gsub(/[.-]/, "_") %></font></b></td>
              </tr>
        <%- end -%>
            </table> >]
          }
        <%- end -%>

        <%- ext_names = @nodes.select { |n| n.remote? }.map(&:name) -%>
        <%- i = 0
            @links.each do |l|
              node_a, int_a = l[0].split(':')
              node_b, int_b = l[1].split(':')
              is_vpn = int_a.to_s.start_with?('tun', 'wg') || int_b.to_s.start_with?('tun', 'wg')
              
              if (node_a == 'sw0' || node_a == 'ro0') && (!ext_names.include?(node_a) && !ext_names.include?(node_b) || is_vpn)
                link_opts = is_vpn ? ', style="dashed"' : ""
        -%>
        <%=     l[0].gsub(/[.-]/, "_") %>:s -- <%= l[1].gsub(/[.-]/, "_") %>:n [color="<%= @graph.colors[i] %>"<%= link_opts %>]
        <%-     i = (i + 1) % @graph.colors.size -%>
        <%-   end -%>
        <%- end -%>

        <%-
            # --- NEW: EXPLICIT VPN GATEWAY PEERING FOR CONN MAPS ---
            @nodes.each do |node|
              if node.type == 'gateway' && ['openvpn', 'wireguard', 'ipsec'].include?(node.provider.to_s.downcase)
                if node.peers && node.peers.is_a?(Hash)
                  p_local = node.peers['local'] || node.peers[:local] || {}
                  p_remote = node.peers['remote'] || node.peers[:remote] || {}

                  l_node = p_local['node'] || p_local[:node]
                  r_node = p_remote['node'] || p_remote[:node]
                  
                  l_int = p_local.keys.find { |k| k.to_s != 'node' } || 'tun0'
                  r_int = p_remote.keys.find { |k| k.to_s != 'node' } || 'tun0'

                  if l_node
        -%>
          <%= l_node.gsub(/[.-]/, "_") %>:<%= l_int %>:s -- <%= node.name.gsub(/[.-]/, "_") %>:<%= l_int %>:n [style="dashed", color="#14b8a6", penwidth="2.5"]
        <%-       end 
                  if r_node
        -%>
          <%= node.name.gsub(/[.-]/, "_") %>:<%= r_int %>:s -- <%= r_node.gsub(/[.-]/, "_") %>:<%= r_int %>:n [style="dashed", color="#14b8a6", penwidth="2.5"]
        <%-       end
                end
              end
            end
        -%>

        <%-
            server_ip = Socket::getaddrinfo(Socket.gethostname,"echo",Socket::AF_INET)[0][3] rescue "127.0.0.1"
            host_name = @cfg ? (@cfg.dig('topology', 0, 'hv') || @cfg.dig('topology', 0, 'vm', 'name') || @cfg.dig('topology', 0, 'name') || 'CTLABS_HOST' rescue 'CTLABS_HOST') : 'CTLABS_HOST'
            host_tt = "CTLABS_HOST  [ Hypervisor ]&#10;━━━━━━━━━━━━━━━━━━━━━━━━&#10;ℹ️ Host VM: " + host_name + "&#10;━━━━━━━━━━━━━━━━━━━━━━━━&#10;🌐 IPv4: " + server_ip
        -%>
          subgraph cluster_ctlabs_host {
            graph[style="invis", group="hypervisor"]
            node[shape=rect, style="rounded,filled", fillcolor="#0f172a", color="#ec4899", penwidth="2.5", fontname="Helvetica, Arial, sans-serif", fontcolor="#f8fafc", margin="0.1"]
            ctlabs_host[tooltip="<%= host_tt %>",label=<
            <table border="0" cellborder="0" cellspacing="6" cellpadding="4">
              <tr><td align="center"><b><font color="#ec4899" point-size="16">🏢 <%= host_name %></font></b></td></tr>
              <tr><td port="eth0" bgcolor="#1e293b" align="text"><font color="#cbd5e1" point-size="12"> <%= server_ip %> </font></td></tr>
            </table> >]
          }
        <%- target_node = @nodes.find { |n| n.name == 'natgw' } || @nodes.find { |n| n.name == 'sw0' } -%>
        <%- if target_node -%>
          ctlabs_host:eth0:s -- <%= target_node.name.gsub(/[.-]/, "_") %>:n [color="#ec4899", style="dashed", penwidth="2.0"]
        <%-   @nodes.select { |n| n.remote? }.each do |ext_node|
                is_transit = (ext_node.plane == 'transit') || (ext_node.nics && ext_node.nics.keys.any? { |k| k.start_with?('tun', 'wg') })
                next if is_transit
                ext_port = ext_node.nics.keys.first || 'eth1' -%>
          <%= ext_node.name.gsub(/[.-]/, "_") %>:<%= ext_port %>:s -- <%= target_node.name.gsub(/[.-]/, "_") %>:n [color="#0ea5e9", style="dashed", penwidth="2.0"]
        <%-   end -%>
        <%- end -%>

          fontsize  = "20"
          fontcolor = "#f8fafc"
          label     = "<%= @name %> [<%= @desc %>]"
          labelloc  = top
          labeljust = left
        }
    }
  end

  def get_topology
    %{
      graph <%= @name.gsub(/[.-]/, "_") %> {
        graph [pad="0.5", esep="0.5", ranksep="1.4", overlap=false, splines=polyline, layout=neato, bgcolor="#1e293b", fontname="Helvetica, Arial, sans-serif", fontsize="16"]
        node  [shape=rect, style="rounded,filled", fillcolor="#0f172a", penwidth="2.5", fontname="Helvetica, Arial, sans-serif", fontcolor="#f8fafc", margin="0.25,0.15"]
        edge  [color="#64748b", penwidth="3.0", fontname="Helvetica, Arial, sans-serif", fontsize="12", fontcolor="#94a3b8"]

        <%-
            @cfg['topology'].each do |vm|
              nodes = init_nodes(vm['hv'] || vm['name'])
              nodes.each do |node|
                if node.kind == "mgmt" || node.plane == "mgmt" || node.type == "controller"
                  next
                end
                server_ip = Socket::getaddrinfo(Socket.gethostname,"echo",Socket::AF_INET)[0][3] rescue "127.0.0.1"
                node_link = (node.dnat.nil? || !node.dnat.is_a?(Array)) ? "" : "https://" + server_ip + ":" + node.dnat[0][0].to_s
        -%>
        <%-     if node.type == 'host' || node.type == 'vhost' -%>
        <%=       node.name.gsub(/[.-]/, "_") %> [color="#38bdf8", href="<%= node_link %>",target="_blank",tooltip="<%= @graph.build_tooltip(node) %>",label=< <table cellborder="0" border="0" cellspacing="0" cellpadding="4"><tr><td><b><font color="#38bdf8" point-size="16">💻 <%= node.fqdn || node.name %></font></b></td></tr><tr><td><font color="#cbd5e1" point-size="12"><%= node.nics['eth1'].to_s.empty? ? '&nbsp;' : node.nics['eth1'] %></font></td></tr></table> >]
        <%-     elsif node.remote? -%>
        <%-       is_transit = (node.plane == 'transit') || (node.nics && node.nics.keys.any? { |k| k.start_with?('tun', 'wg') }) -%>
        <%-       n_color = is_transit ? '#14b8a6' : '#0ea5e9' -%>
        <%-       n_icon  = is_transit ? '🛡️' : '☁️' -%>
        <%-       data_ip = node.nics.is_a?(Hash) ? (node.nics['tun0'] || node.nics['wg0'] || node.nics['eth1']) : nil -%>
        <%-       data_ip_str = data_ip.to_s.strip.empty? ? '&nbsp;' : data_ip.to_s.split('/').first -%>
        <%=       node.name.gsub(/[.-]/, "_") %> [color="<%= n_color %>", href="<%= node_link %>",target="_blank",tooltip="<%= @graph.build_tooltip(node) %>",label=< <table cellborder="0" border="0" cellspacing="0" cellpadding="4"><tr><td><b><font color="<%= n_color %>" point-size="16"><%= n_icon %> <%= node.fqdn || node.name %></font></b></td></tr><tr><td><font color="#cbd5e1" point-size="12"><%= data_ip_str %></font></td></tr></table> >]
        <%-     end -%>
        <%-   end -%>
        <%- end -%>

        <%- @cfg['topology'].each do |vm| -%>
        <%-   nodes = init_nodes(vm['hv'] || vm['name']) -%>
        <%-   nodes.each do |node|
                if node.kind == 'mgmt' || node.plane == 'mgmt'
                  next
                end
        -%>
        <%-     if node.type == 'router' -%>
        <%=       node.name.gsub(/[.-]/, "_") %> [color="#f59e0b", tooltip="<%= @graph.build_tooltip(node) %>", label=< <table cellborder="0" border="0" cellspacing="0" cellpadding="4"><tr><td><b><font color="#f59e0b" point-size="16">🔀 <%= node.name %></font></b></td></tr></table> >]
        <%-     end -%>
        <%-   end -%>
        <%- end -%>

        <%-
            @cfg['topology'].each do |vm|
              nodes = init_nodes(vm['hv'] || vm['name'])
              nodes.each do |node|
                if node.kind == 'mgmt' || node.plane == 'mgmt'
                  next
                end
        -%>
        <%-     if node.type == 'switch' && node.snat.nil? -%>
        <%=       node.name.gsub(/[.-]/, "_") %> [color="#10b981", tooltip="<%= @graph.build_tooltip(node) %>", label=<<b><font point-size="16">🎛️ <%= node.name %></font></b>>]
        <%-     end -%>
        <%-   end -%>
        <%- end -%>

        <%-
            @nodes.each do |node|
              if node.kind == 'mgmt' || node.plane == 'mgmt'
                next
              end
        -%>
        <%-   if node.type == 'gateway' && !node.remote? -%>
        <%-     if !node.dnat.nil? -%>
                <%= node.name.gsub(/[.-]/, "_") %> [color="#a855f7", tooltip="<%= @graph.build_tooltip(node) %>", label=<<b><font point-size="16">🚪 <%= node.name %></font></b>>]
        <%-     elsif ['openvpn', 'wireguard', 'ipsec'].include?(node.provider.to_s.downcase) -%>
                <%= node.name.gsub(/[.-]/, "_") %> [color="#14b8a6", tooltip="<%= @graph.build_tooltip(node) %>", label=<<b><font point-size="16">🛡️ <%= node.name %></font></b>>]
        <%-     end -%>
        <%-   end -%>
        <%- end -%>

        <%- ext_names = @nodes.select { |n| n.remote? }.map(&:name) -%>
        <%- @links.each do |l|
              node_a, int_a = l[0].split(':')
              node_b, int_b = l[1].split(':')
              is_vpn = int_a.to_s.start_with?('tun', 'wg') || int_b.to_s.start_with?('tun', 'wg')
              
              if (node_a != "sw0" && node_a != 'ro0' && !ext_names.include?(node_a) && !ext_names.include?(node_b)) || is_vpn
                link_opts = is_vpn ? ' [style="dashed", color="#14b8a6", penwidth="2.5"]' : ""
        -%>
          <%= node_a.gsub(/[.-]/, "_") %> -- <%= node_b.gsub(/[.-]/, "_") %><%= link_opts %>
        <%-   end -%>
        <%- end -%>

        <%-
            # --- NEW: EXPLICIT VPN GATEWAY PEERING ---
            @nodes.each do |node|
              if node.type == 'gateway' && ['openvpn', 'wireguard', 'ipsec'].include?(node.provider.to_s.downcase)
                if node.peers && node.peers.is_a?(Hash)
                  p_local = node.peers['local'] || node.peers[:local] || {}
                  p_remote = node.peers['remote'] || node.peers[:remote] || {}

                  l_node = p_local['node'] || p_local[:node]
                  r_node = p_remote['node'] || p_remote[:node]

                  # Draw line from Local Router to VPN Gateway
                  if l_node
        -%>
          <%= l_node.gsub(/[.-]/, "_") %> -- <%= node.name.gsub(/[.-]/, "_") %> [style="dashed", color="#14b8a6", penwidth="2.5"]
        <%-       end 
                  # Draw line from VPN Gateway to Remote Host
                  if r_node
        -%>
          <%= node.name.gsub(/[.-]/, "_") %> -- <%= r_node.gsub(/[.-]/, "_") %> [style="dashed", color="#14b8a6", penwidth="2.5"]
        <%-       end
                end
              end
            end
        -%>

        <%-
            server_ip = Socket::getaddrinfo(Socket.gethostname,"echo",Socket::AF_INET)[0][3] rescue "127.0.0.1"
            host_name = @cfg ? (@cfg.dig('topology', 0, 'hv') || @cfg.dig('topology', 0, 'vm', 'name') || @cfg.dig('topology', 0, 'name') || 'CTLABS_HOST' rescue 'CTLABS_HOST') : 'CTLABS_HOST'
            host_tt = "CTLABS_HOST  [ Hypervisor ]&#10;━━━━━━━━━━━━━━━━━━━━━━━━&#10;ℹ️ Host VM: " + host_name + "&#10;━━━━━━━━━━━━━━━━━━━━━━━━&#10;🌐 IPv4: " + server_ip
        -%>
        ctlabs_host [color="#ec4899", tooltip="<%= host_tt %>", label=< <table cellborder="0" border="0" cellspacing="0" cellpadding="4"><tr><td><b><font color="#ec4899" point-size="16">🏢 <%= host_name %></font></b></td></tr><tr><td><font color="#cbd5e1" point-size="12"><%= server_ip %></font></td></tr></table> >]
        <%- target_node = @nodes.find { |n| n.name == 'natgw' } || @nodes.find { |n| n.name == 'sw0' } -%>
        <%- if target_node -%>
        ctlabs_host -- <%= target_node.name %> [color="#ec4899", style="dashed", penwidth="2.0"]
        <%-   @nodes.select { |n| n.remote? }.each do |ext_node|
                is_transit = (ext_node.plane == 'transit') || (ext_node.nics && ext_node.nics.keys.any? { |k| k.start_with?('tun', 'wg') })
                next if is_transit -%>
        <%= ext_node.name.gsub(/[.-]/, "_") %> -- <%= target_node.name %> [color="#0ea5e9", style="dashed", penwidth="2.0"]
        <%-   end -%>
        <%- end -%>

          fontsize  = "20"
          fontcolor = "#f8fafc"
          label     = "<%= @name %> [<%= @desc %>]"
          labelloc  = top
          labeljust = left
      }
    }
  end

  def get_mgmt_topo
    %{
      graph <%= @name.gsub(/[.-]/, "_") %> {
        graph [pad="0.5", esep="0.5", ranksep="1.4", overlap=false, splines=polyline, layout=neato, bgcolor="#1e293b", fontname="Helvetica, Arial, sans-serif", fontsize="16"]
        node  [shape=rect, style="rounded,filled", fillcolor="#0f172a", penwidth="2.5", fontname="Helvetica, Arial, sans-serif", fontcolor="#f8fafc", margin="0.25,0.15"]
        edge  [color="#64748b", penwidth="3.0", fontname="Helvetica, Arial, sans-serif", fontsize="12", fontcolor="#94a3b8"]
        <%- @cfg['topology'].each do |vm| -%>
        <%-   nodes = init_nodes(vm['hv'] || vm['name']) -%>
        <%-   nodes.each do |node| -%>
        <%-     if ['host', 'vhost', 'controller'].include?(node.type) || node.remote?
                  server_ip = Socket::getaddrinfo(Socket.gethostname,"echo",Socket::AF_INET)[0][3] rescue "127.0.0.1"
                  node_link = (node.dnat.nil? || !node.dnat.is_a?(Array)) ? "" : "https://" + server_ip + ":" + node.dnat[0][0].to_s

                  if node.type == 'controller'
                    node_color = '#ef4444'
                    n_icon = '⚙️ '
                  elsif node.remote?
                    is_transit = (node.plane == 'transit') || (node.nics && node.nics.keys.any? { |k| k.start_with?('tun', 'wg') })
                    node_color = is_transit ? '#14b8a6' : '#0ea5e9'
                    n_icon = is_transit ? '🛡️ ' : '☁️ '
                  else
                    node_color = '#38bdf8'
                    n_icon = '💻 '
                  end

                  # Use eth0 explicitly for Mgmt Topo (fallback to gw)
                  mgmt_ip = (node.nics && node.nics['eth0']) || node.gw
        -%>
        <%=       node.name.gsub(/[.-]/, "_") %> [color="<%= node_color %>", href="<%= node_link %>",target="_blank",tooltip="<%= @graph.build_tooltip(node) %>",label=< <table cellborder="0" border="0" cellspacing="0" cellpadding="4"><tr><td><b><font color="<%= node_color %>" point-size="16"><%= n_icon %><%= node.fqdn || node.name %></font></b></td></tr><tr><td><font color="#cbd5e1" point-size="12"><%= mgmt_ip.to_s.empty? ? '&nbsp;' : mgmt_ip %></font></td></tr></table> >]
        <%-     end -%>
        <%-   end -%>
        <%- end -%>

        <%- @cfg['topology'].each do |vm| -%>
        <%-   nodes = init_nodes(vm['hv'] || vm['name']) -%>
        <%-   nodes.each do |node| -%>
        <%-     if node.type == 'router' -%>
        <%=       node.name.gsub(/[.-]/, "_") %> [color="#f59e0b", tooltip="<%= @graph.build_tooltip(node) %>", label=< <table cellborder="0" border="0" cellspacing="0" cellpadding="4"><tr><td><b><font color="#f59e0b" point-size="16">🔀 <%= node.name %></font></b></td></tr></table> >]
        <%-     end -%>
        <%-   end -%>
        <%- end -%>

        <%-
            @cfg['topology'].each do |vm|
              nodes = init_nodes(vm['hv'] || vm['name'])
              nodes.each do |node|
        -%>
        <%-     if node.type == 'switch' && node.snat.nil? -%>
        <%=       node.name.gsub(/[.-]/, "_") %> [color="#10b981", tooltip="<%= @graph.build_tooltip(node) %>", label=<<b><font point-size="16">🎛️ <%= node.name %></font></b>>]
        <%-     end -%>
        <%-   end -%>
        <%- end -%>

        <%-
            @nodes.each do |node|
        -%>
        <%-   if node.type == 'gateway' && !node.remote? -%>
        <%-     if !node.dnat.nil? -%>
                <%= node.name.gsub(/[.-]/, "_") %> [color="#a855f7", tooltip="<%= @graph.build_tooltip(node) %>", label=<<b><font point-size="16">🚪 <%= node.name %></font></b>>]
        <%-     elsif ['openvpn', 'wireguard', 'ipsec'].include?(node.provider.to_s.downcase) -%>
                <%= node.name.gsub(/[.-]/, "_") %> [color="#14b8a6", tooltip="<%= @graph.build_tooltip(node) %>", label=<<b><font point-size="16">🛡️ <%= node.name %></font></b>>]
        <%-     end -%>
        <%-   end -%>
        <%- end -%>

        <%- ext_names = @nodes.select { |n| n.remote? }.map(&:name) -%>
        <%- @links.each do |l|
              node_a, int_a = l[0].split(':')
              node_b, int_b = l[1].split(':')
              is_mgmt_link = (node_a == 'sw0' || node_a == 'ro0' || node_b == 'sw0' || node_b == 'ro0')
              is_vpn = int_a.to_s.start_with?('tun', 'wg') || int_b.to_s.start_with?('tun', 'wg')

              if (is_mgmt_link && !ext_names.include?(node_a) && !ext_names.include?(node_b)) || is_vpn
                link_opts = is_vpn ? ' [style="dashed", color="#14b8a6", penwidth="2.5"]' : ""
        -%>
          <%= node_a.gsub(/[.-]/, "_") %> -- <%= node_b.gsub(/[.-]/, "_") %><%= link_opts %>
        <%-   end -%>
        <%- end -%>

        <%-
            # --- NEW: EXPLICIT VPN GATEWAY PEERING ---
            @nodes.each do |node|
              if node.type == 'gateway' && ['openvpn', 'wireguard', 'ipsec'].include?(node.provider.to_s.downcase)
                if node.peers && node.peers.is_a?(Hash)
                  p_local = node.peers['local'] || node.peers[:local] || {}
                  p_remote = node.peers['remote'] || node.peers[:remote] || {}

                  l_node = p_local['node'] || p_local[:node]
                  r_node = p_remote['node'] || p_remote[:node]

                  # Draw line from Local Router to VPN Gateway
                  if l_node
        -%>
          <%= l_node.gsub(/[.-]/, "_") %> -- <%= node.name.gsub(/[.-]/, "_") %> [style="dashed", color="#14b8a6", penwidth="2.5"]
        <%-       end 
                  # Draw line from VPN Gateway to Remote Host
                  if r_node
        -%>
          <%= node.name.gsub(/[.-]/, "_") %> -- <%= r_node.gsub(/[.-]/, "_") %> [style="dashed", color="#14b8a6", penwidth="2.5"]
        <%-       end
                end
              end
            end
        -%>

        <%-
            server_ip = Socket::getaddrinfo(Socket.gethostname,"echo",Socket::AF_INET)[0][3] rescue "127.0.0.1"
            host_name = @cfg ? (@cfg.dig('topology', 0, 'hv') || @cfg.dig('topology', 0, 'vm', 'name') || @cfg.dig('topology', 0, 'name') || 'CTLABS_HOST' rescue 'CTLABS_HOST') : 'CTLABS_HOST'
            host_tt = "CTLABS_HOST  [ Hypervisor ]&#10;━━━━━━━━━━━━━━━━━━━━━━━━&#10;ℹ️ Host VM: " + host_name + "&#10;━━━━━━━━━━━━━━━━━━━━━━━━&#10;🌐 IPv4: " + server_ip
        -%>
        ctlabs_host [color="#ec4899", tooltip="<%= host_tt %>", label=< <table cellborder="0" border="0" cellspacing="0" cellpadding="4"><tr><td><b><font color="#ec4899" point-size="16">🏢 <%= host_name %></font></b></td></tr><tr><td><font color="#cbd5e1" point-size="12"><%= server_ip %></font></td></tr></table> >]
        <%- target_node = @nodes.find { |n| n.name == 'natgw' } || @nodes.find { |n| n.name == 'sw0' } -%>
        <%- if target_node -%>
        ctlabs_host -- <%= target_node.name %> [color="#ec4899", style="dashed", penwidth="2.0"]
        <%-   @nodes.select { |n| n.remote? }.each do |ext_node|
                is_transit = (ext_node.plane == 'transit') || (ext_node.nics && ext_node.nics.keys.any? { |k| k.start_with?('tun', 'wg') })
                next if is_transit -%>
        <%= ext_node.name.gsub(/[.-]/, "_") %> -- <%= target_node.name %> [color="#0ea5e9", style="dashed", penwidth="2.0"]
        <%-   end -%>
        <%- end -%>

          fontsize  = "20"
          fontcolor = "#f8fafc"
          label     = "<%= @name %> [<%= @desc %>]"
          labelloc  = top
          labeljust = left
      }
    }
  end

  def get_inventory
    %{ <%- -%>
[local]
  #localhost

[controller]
  <%- @nodes.each do |node| -%>
  <%-   if node.type == 'controller' and !node.nics['eth0'].to_s.empty? -%>
  <%=     node.name.ljust(24) %> ansible_host=<%= node.nics['eth0'].split('/')[0] %> ansible_user=<%= node.user %><%= node.user == 'root' ? '' : ' ansible_become=yes' %>
  <%-   end -%>
  <%- end -%>

[router]
  <%- @nodes.each do |node| -%>
  <%-   if node.type == 'router' and !node.nics['eth0'].to_s.empty? -%>
  <%=     node.name.ljust(24) %> ansible_host=<%= node.nics['eth0'].split('/')[0] %> ansible_user=<%= node.user %><%= node.user == 'root' ? '' : ' ansible_become=yes' %>
  <%-   end -%>
  <%- end -%>

[switches]
  <%- @nodes.each do |node| -%>
  <%-   if node.type == 'switch' and !node.ipv4.to_s.empty? -%>
  <%=     node.name.ljust(24) %> ansible_host=<%= node.ipv4.split('/')[0] %> ansible_user=<%= node.user %><%= node.user == 'root' ? '' : ' ansible_become=yes' %>
  <%-   elsif node.type == 'switch' and !node.nics['eth0'].to_s.empty? -%>
  <%=     node.name.ljust(24) %> ansible_host=<%= node.nics['eth0'].split('/')[0] %> ansible_user=<%= node.user %><%= node.user == 'root' ? '' : ' ansible_become=yes' %>
  <%-   end -%>
  <%- end -%>

[hosts]
  <%- @nodes.each do |node| -%>
  <%-   if ['host', 'vhost', 'server'].include?(node.type) and node.nics && !node.nics['eth0'].to_s.empty? -%>
  <%=     node.name.ljust(24) %> ansible_host=<%= node.nics['eth0'].split('/')[0] %> ansible_user=<%= node.user %><%= node.user == 'root' ? '' : ' ansible_become=yes' %>
  <%-   end -%>
  <%- end -%>
    }
  end

  def get_data_inventory
    %{ <%- -%>
[local]
  #localhost

[controller]
  <%- @nodes.each do |node| -%>
  <%-   if node.type == 'controller' and node.nics && !node.nics['eth1'].to_s.empty? -%>
  <%=     node.name.ljust(24) %> ansible_host=<%= node.nics['eth1'].split('/')[0] %> ansible_user=<%= node.user %><%= node.user == 'root' ? '' : ' ansible_become=yes' %>
  <%-   end -%>
  <%- end -%>

[router]
  <%- @nodes.each do |node| -%>
  <%-   ip = node.ipv4 || (node.nics && node.nics['eth1']) -%>
  <%-   if node.type == 'router' && !ip.to_s.empty? -%>
  <%=     node.name.ljust(24) %> ansible_host=<%= ip.split('/')[0] %> ansible_user=<%= node.user %><%= node.user == 'root' ? '' : ' ansible_become=yes' %>
  <%-   end -%>
  <%- end -%>

[switches]
  <%- @nodes.each do |node| -%>
  <%-   if node.type == 'switch' and !node.ipv4.to_s.empty? -%>
  <%=     node.name.ljust(24) %> ansible_host=<%= node.ipv4.split('/')[0] %> ansible_user=<%= node.user %><%= node.user == 'root' ? '' : ' ansible_become=yes' %>
  <%-   end -%>
  <%- end -%>

[hosts]
  <%- @nodes.each do |node| -%>
  <%-   is_target = ['host', 'vhost', 'server'].include?(node.type) -%>
  <%-   data_ip = node.nics ? (node.nics['eth1'] || node.nics['tun0']) : nil -%>
  <%-   if is_target && data_ip && !data_ip.to_s.empty? && !node.remote? -%>
  <%=     node.name.ljust(24) %> ansible_host=<%= data_ip.to_s.split('/')[0] %> ansible_user=<%= node.user %><%= node.user == 'root' ? '' : ' ansible_become=yes' %>
  <%-   end -%>
  <%- end -%>
    }
  end

  def to_data_ini(data, name)
    @log.write "#{__method__}(): data=#{data},name=#{name}", "debug"

    File.open("../../ctlabs-ansible/inventories/#{name}_data.ini", "w") do |f|
      f.write( ERB.new(data, trim_mode:'-').result(@binding))
    end
    File.open("#{@pubdir}/inventory_data.ini", "w") do |f|
      f.write( ERB.new(data, trim_mode:'-').result(@binding))
    end
  end

  def to_dot(data)
    @log.write "#{__method__}(): data=#{data}", "debug"

    File.open("#{@dotfile}", "w" ) do |f|
      f.write( ERB.new(data, trim_mode:'-').result(@binding) )
    end
  end

  def to_png(data, name)
    @log.write "#{__method__}(): data=#{data},name=#{name}", "debug"

    to_dot(data)
    %x( dot -Tpng #{@dotfile} -o #{@pubdir}/#{name}.png )
  end

  def to_svg(data, name)
    @log.write "#{__method__}(): data=#{data},name=#{name}", "debug"

    to_dot(data)
    %x( dot -Tsvg #{@dotfile} -o #{@pubdir}/#{name}.svg )
  end

  def to_ini(data, name)
    @log.write "#{__method__}(): data=#{data},name=#{name}", "debug"

    File.open("../../ctlabs-ansible/inventories/#{name}.ini", "w") do |f|
      f.write( ERB.new(data, trim_mode:'-').result(@binding))
    end
    File.open("#{@pubdir}/inventory.ini", "w") do |f|
      f.write( ERB.new(data, trim_mode:'-').result(@binding))
    end
  end
end
