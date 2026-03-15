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
  end

  def build_tooltip(node)
    tt = ["#{node.name.upcase}  [ #{node.type.capitalize} ]"]
    tt << "━━━━━━━━━━━━━━━━━━━━━━━━"

    if node.respond_to?(:info) && node.info && !node.info.empty?
      tt << "ℹ️ #{node.info}"
      tt << "━━━━━━━━━━━━━━━━━━━━━━━━"
    end
    
    tt << "🌐 IPv4: #{node.ipv4}" unless node.ipv4.to_s.empty?
    
    if node.nics && !node.nics.empty?
      tt << "🔌 Interfaces:"
      node.nics.each do |k, v| 
        next if v.to_s.strip.empty?
        tt << "   ▪ #{k}  ➔  #{v}"
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
    elsif node.ipv4 && !node.ipv4.to_s.empty?
      ip_only = node.ipv4.split('/').first
      tt << "[TERM:ssh://root@#{ip_only}]"
    end
    
    tt.join('&#10;')
  end

  def get_cons
    @log.write "#{__method__}():  ", "debug"

    %{
        graph <%= @name.sub(/.-/, "_") %> {
          graph [pad="0.5", nodesep="0.8", ranksep="1.8", overlap=false, splines=true, layout=dot, rankdir=TB, bgcolor="#1e293b", fontname="Helvetica, Arial, sans-serif", fontsize="16"]
          edge  [penwidth="3.0", fontname="Helvetica, Arial, sans-serif", fontsize="12"]

        <%-
            @nodes.each do |node|
              if node.kind == "mgmt" || node.type == "controller" || (node.type == 'gateway' && node.dnat.nil?)
                next
              end
              group = node.type
              
              border_color = "#10b981" 
              n_icon = "🎛️"
              case node.type
                when 'host', 'vhost' 
                  border_color = "#38bdf8"
                  n_icon = "💻 "
                when 'router' 
                  border_color = "#f59e0b"
                  n_icon = "🔀 "
                when 'gateway' 
                  border_color = "#a855f7"
                  n_icon = "🚪 "
                when 'controller' 
                  border_color = "#ef4444"
                  n_icon = "⚙️ "
                when 'external', 'rhost' 
                  border_color = "#0ea5e9"
                  n_icon = "☁️ "
              end
              
              server_ip = Socket::getaddrinfo(Socket.gethostname,"echo",Socket::AF_INET)[0][3] rescue "127.0.0.1"
              node_link = node.dnat.nil? || node.type == 'gateway' ? "" : "https://" + server_ip + ":" + node.dnat[0][0].to_s
              col_span = node.nics.size == 0 ? 1 : node.nics.size
        -%>

          subgraph cluster_<%= node.name.sub(/.-/, "_") %> {
            graph[style="invis", group="<%= group %>"]
            node[shape=rect, style="rounded,filled", fillcolor="#0f172a", color="<%= border_color %>", penwidth="2.5", fontname="Helvetica, Arial, sans-serif", fontcolor="#f8fafc", margin="0.1"]
            <%= node.name.sub(/.-/, "_") %>[href="<%= node_link %>",target="_blank",tooltip="<%= @graph.build_tooltip(node) %>",label=<
            <table border="0" cellborder="0" cellspacing="6" cellpadding="4">
        <%- if !['host', 'vhost', 'external', 'rhost'].include?(group) -%>
              <tr>
                <td align="center" colspan="<%= col_span %>"><b><font color="<%= border_color %>" point-size="16"><%= n_icon %><%= node.name %></font></b></td>
              </tr>
        <%- end -%>
              <tr>
        <%-   if node.nics.empty? -%>
                <td bgcolor="#1e293b" align="text"><font color="#cbd5e1" point-size="12">&nbsp;</font></td>
        <%-   else -%>
        <%-     node.nics.each do |nic| -%>
                <td port="<%= nic[0] %>" bgcolor="#1e293b" align="text"><font color="#cbd5e1" point-size="12"> <%= nic[0].to_s.empty? ? '&nbsp;' : nic[0] %> </font></td>
        <%-     end -%>
        <%-   end -%>
              </tr>
        <%- if ['host', 'vhost', 'external', 'rhost'].include?(group) -%>
              <tr>
                <td align="center" colspan="<%= col_span %>"><b><font color="<%= border_color %>" point-size="16"><%= n_icon %><%= node.name %></font></b></td>
              </tr>
        <%- end -%>
            </table> >]
          }
        <%- end -%>

        <%- ext_names = @nodes.select { |n| n.type == 'external' || n.type == 'rhost' }.map(&:name) -%>
        <%- i = 0
            @links.each do |l|
              node_a = l[0].split(':')[0]
              node_b = l[1].split(':')[0]
              if node_a != 'sw0' && node_a != 'ro0' && !ext_names.include?(node_a) && !ext_names.include?(node_b)
        -%>
        <%=     l[0].sub(/.-/, "_") %>:s -- <%= l[1].sub(/.-/, "_") %>:n [color="<%= @graph.colors[i] %>"]
        <%-     i = (i + 1) % @graph.colors.size -%>
        <%-   end -%>
        <%- end -%>

        <%-
            server_ip = Socket::getaddrinfo(Socket.gethostname,"echo",Socket::AF_INET)[0][3] rescue "127.0.0.1"
            host_name = @cfg ? (@cfg.dig('topology', 0, 'vm', 'name') || @cfg.dig('topology', 0, 'name') || 'CTLABS_HOST' rescue 'CTLABS_HOST') : 'CTLABS_HOST'
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
          ctlabs_host:eth0:s -- <%= target_node.name %>:n [color="#ec4899", style="dashed", penwidth="2.0"]
        <%-   @nodes.select { |n| n.type == 'external' || n.type == 'rhost' }.each do |ext_node| 
                ext_port = ext_node.nics.keys.first || 'eth1' -%>
          <%= ext_node.name.sub(/.-/, "_") %>:<%= ext_port %>:s -- <%= target_node.name %>:n [color="#0ea5e9", style="dashed", penwidth="2.0"]
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
        graph <%= @name.sub(/.-/, "_") %> {
          graph [pad="0.5", nodesep="0.8", ranksep="1.8", overlap=false, splines=true, layout=dot, rankdir=TB, bgcolor="#1e293b", fontname="Helvetica, Arial, sans-serif", fontsize="16"]
          edge  [penwidth="3.0", fontname="Helvetica, Arial, sans-serif", fontsize="12"]

        <%-
            @nodes.each do |node|
              group = node.type
              
              border_color = "#10b981" 
              n_icon = "🎛️"
              case node.type
                when 'host', 'vhost'
                  border_color = "#38bdf8"
                  n_icon = "💻 "
                when 'router'
                  border_color = "#f59e0b"
                  n_icon = "🔀 "
                when 'gateway'
                  border_color = "#a855f7"
                  n_icon = "🚪 "
                when 'controller'
                  border_color = "#ef4444"
                  n_icon = "⚙️ "
                when 'external', 'rhost'
                  border_color = "#0ea5e9"
                  n_icon = "☁️ "
              end
              
              server_ip = Socket::getaddrinfo(Socket.gethostname,"echo",Socket::AF_INET)[0][3] rescue "127.0.0.1"
              node_link = node.dnat.nil? || node.type == 'gateway' ? "" : "https://" + server_ip + ":" + node.dnat[0][0].to_s
              col_span = node.nics.size == 0 ? 1 : node.nics.size
        -%>
          subgraph cluster_<%= node.name.sub(/.-/, "_") %> {
            graph[style="invis", group="<%= group %>"]
            node[shape=rect, style="rounded,filled", fillcolor="#0f172a", color="<%= border_color %>", penwidth="2.5", fontname="Helvetica, Arial, sans-serif", fontcolor="#f8fafc", margin="0.1"]
            <%= node.name.sub(/.-/, "_") %>[href="<%= node_link %>",target="_blank",tooltip="<%= @graph.build_tooltip(node) %>",label=<
            <table border="0" cellborder="0" cellspacing="6" cellpadding="4">
        <%- if ![ 'host', 'vhost', 'controller', 'external', 'rhost' ].include?(group) -%>
              <tr>
                <td align="center" colspan="<%= col_span %>"><b><font color="<%= border_color %>" point-size="16"><%= n_icon %><%= node.name %></font></b></td>
              </tr>
        <%- end -%>
              <tr>
        <%-   if node.nics.empty? -%>
                <td bgcolor="#1e293b" align="text"><font color="#cbd5e1" point-size="12">&nbsp;</font></td>
        <%-   else -%>
        <%-     node.nics.each do |nic| -%>
                <td PORT="<%= nic[0] %>" bgcolor="#1e293b" align="text"><font color="#cbd5e1" point-size="12"> <%= nic[0].to_s.empty? ? '&nbsp;' : nic[0] %> </font></td>
        <%-     end -%>
        <%-   end -%>
              </tr>
        <%- if [ 'host', 'vhost', 'controller', 'external', 'rhost' ].include?(group) -%>
              <tr>
                <td align="center" colspan="<%= col_span %>"><b><font color="<%= border_color %>" point-size="16"><%= n_icon %><%= node.name %></font></b></td>
              </tr>
        <%- end -%>
            </table> >]
          }
        <%- end -%>

        <%- ext_names = @nodes.select { |n| n.type == 'external' || n.type == 'rhost' }.map(&:name) -%>
        <%- i = 0
            @links.each do |l|
              node_a = l[0].split(':')[0]
              node_b = l[1].split(':')[0]
              if (node_a == 'sw0' || node_a == 'ro0') && !ext_names.include?(node_a) && !ext_names.include?(node_b)
        -%>
        <%=     l[0].sub(/.-/, "_") %>:s -- <%= l[1].sub(/.-/, "_") %>:n [color="<%= @graph.colors[i] %>"]
        <%-     i = (i + 1) % @graph.colors.size -%>
        <%-   end -%>
        <%- end -%>

        <%-
            server_ip = Socket::getaddrinfo(Socket.gethostname,"echo",Socket::AF_INET)[0][3] rescue "127.0.0.1"
            host_name = @cfg ? (@cfg.dig('topology', 0, 'vm', 'name') || @cfg.dig('topology', 0, 'name') || 'CTLABS_HOST' rescue 'CTLABS_HOST') : 'CTLABS_HOST'
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
          ctlabs_host:eth0:s -- <%= target_node.name %>:n [color="#ec4899", style="dashed", penwidth="2.0"]
        <%-   @nodes.select { |n| n.type == 'external' || n.type == 'rhost' }.each do |ext_node| 
                ext_port = ext_node.nics.keys.first || 'eth1' -%>
          <%= ext_node.name.sub(/.-/, "_") %>:<%= ext_port %>:s -- <%= target_node.name %>:n [color="#0ea5e9", style="dashed", penwidth="2.0"]
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
      graph <%= @name.sub(/.-/, "_") %> {
        graph [pad="0.5", esep="0.5", ranksep="1.4", overlap=false, splines=polyline, layout=neato, bgcolor="#1e293b", fontname="Helvetica, Arial, sans-serif", fontsize="16"]
        node  [shape=rect, style="rounded,filled", fillcolor="#0f172a", penwidth="2.5", fontname="Helvetica, Arial, sans-serif", fontcolor="#f8fafc", margin="0.25,0.15"]
        edge  [color="#64748b", penwidth="3.0", fontname="Helvetica, Arial, sans-serif", fontsize="12", fontcolor="#94a3b8"]

        <%-
            @cfg['topology'].each do |vm|
              nodes = init_nodes(vm['name'])
              nodes.each do |node|
                if node.kind == "mgmt" || node.type == "controller"
                  next
                end
                server_ip = Socket::getaddrinfo(Socket.gethostname,"echo",Socket::AF_INET)[0][3] rescue "127.0.0.1"
                node_link = node.dnat.nil? ? "" : "https://" + server_ip + ":" + node.dnat[0][0].to_s
        -%>
        <%-     if node.type == 'host' || node.type == 'vhost' -%>
        <%=       node.name.sub(/.-/, "_") %> [color="#38bdf8", href="<%= node_link %>",target="_blank",tooltip="<%= @graph.build_tooltip(node) %>",label=< <table cellborder="0" border="0" cellspacing="0" cellpadding="4"><tr><td><b><font color="#38bdf8" point-size="16">💻 <%= node.fqdn || node.name %></font></b></td></tr><tr><td><font color="#cbd5e1" point-size="12"><%= node.nics['eth1'].to_s.empty? ? '&nbsp;' : node.nics['eth1'] %></font></td></tr></table> >]
        <%-     elsif node.type == 'external' || node.type == 'rhost' -%>
        <%=       node.name.sub(/.-/, "_") %> [color="#0ea5e9", href="<%= node_link %>",target="_blank",tooltip="<%= @graph.build_tooltip(node) %>",label=< <table cellborder="0" border="0" cellspacing="0" cellpadding="4"><tr><td><b><font color="#0ea5e9" point-size="16">☁️ <%= node.fqdn || node.name %></font></b></td></tr><tr><td><font color="#cbd5e1" point-size="12"><%= node.nics['eth1'].to_s.empty? ? '&nbsp;' : node.nics['eth1'] %></font></td></tr></table> >]
        <%-     end -%>
        <%-   end -%>
        <%- end -%>

        <%- @cfg['topology'].each do |vm| -%>
        <%-   nodes = init_nodes(vm['name']) -%>
        <%-   nodes.each do |node|
                if node.kind == 'mgmt'
                  next
                end
        -%>
        <%-     if node.type == 'router' -%>
        <%=       node.name %> [color="#f59e0b", tooltip="<%= @graph.build_tooltip(node) %>", label=< <table cellborder="0" border="0" cellspacing="0" cellpadding="4"><tr><td><b><font color="#f59e0b" point-size="16">🔀 <%= node.name %></font></b></td></tr></table> >]
        <%-     end -%>
        <%-   end -%>
        <%- end -%>

        <%-
            @cfg['topology'].each do |vm|
              nodes = init_nodes(vm['name'])
              nodes.each do |node|
                if node.kind == 'mgmt'
                  next
                end
        -%>
        <%-     if node.type == 'switch' && node.snat.nil? -%>
        <%=       node.name %> [color="#10b981", tooltip="<%= @graph.build_tooltip(node) %>", label=<<b><font point-size="16">🎛️<%= node.name %></font></b>>]
        <%-     end -%>
        <%-   end -%>
        <%- end -%>

        <%-
            @nodes.each do |node|
              if node.kind == 'mgmt'
                next
              end
        -%>
        <%-   if node.type == 'gateway' && !node.dnat.nil? -%>
                <%= node.name %> [color="#a855f7", tooltip="<%= @graph.build_tooltip(node) %>", label=<<b><font point-size="16">🚪 <%= node.name %></font></b>>]
        <%-   end -%>
        <%- end -%>

        <%- ext_names = @nodes.select { |n| n.type == 'external' || n.type == 'rhost' }.map(&:name) -%>
        <%- @links.each do |l|
              node_a = l[0].split(':')[0]
              node_b = l[1].split(':')[0]
              if node_a != "sw0" && node_a != 'ro0' && !ext_names.include?(node_a) && !ext_names.include?(node_b)
        -%>
          <%= node_a.sub(/.-/, "_") %> -- <%= node_b.sub(/.-/, "_") %>
        <%-   end -%>
        <%- end -%>

        <%-
            server_ip = Socket::getaddrinfo(Socket.gethostname,"echo",Socket::AF_INET)[0][3] rescue "127.0.0.1"
            host_name = @cfg ? (@cfg.dig('topology', 0, 'vm', 'name') || @cfg.dig('topology', 0, 'name') || 'CTLABS_HOST' rescue 'CTLABS_HOST') : 'CTLABS_HOST'
            host_tt = "CTLABS_HOST  [ Hypervisor ]&#10;━━━━━━━━━━━━━━━━━━━━━━━━&#10;ℹ️ Host VM: " + host_name + "&#10;━━━━━━━━━━━━━━━━━━━━━━━━&#10;🌐 IPv4: " + server_ip
        -%>
        ctlabs_host [color="#ec4899", tooltip="<%= host_tt %>", label=< <table cellborder="0" border="0" cellspacing="0" cellpadding="4"><tr><td><b><font color="#ec4899" point-size="16">🏢 <%= host_name %></font></b></td></tr><tr><td><font color="#cbd5e1" point-size="12"><%= server_ip %></font></td></tr></table> >]
        <%- target_node = @nodes.find { |n| n.name == 'natgw' } || @nodes.find { |n| n.name == 'sw0' } -%>
        <%- if target_node -%>
        ctlabs_host -- <%= target_node.name %> [color="#ec4899", style="dashed", penwidth="2.0"]
        <%-   @nodes.select { |n| n.type == 'external' || n.type == 'rhost' }.each do |ext_node| -%>
        <%= ext_node.name.sub(/.-/, "_") %> -- <%= target_node.name %> [color="#0ea5e9", style="dashed", penwidth="2.0"]
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
      graph <%= @name.sub(/.-/, "_") %> {
        graph [pad="0.5", esep="0.5", ranksep="1.4", overlap=false, splines=polyline, layout=neato, bgcolor="#1e293b", fontname="Helvetica, Arial, sans-serif", fontsize="16"]
        node  [shape=rect, style="rounded,filled", fillcolor="#0f172a", penwidth="2.5", fontname="Helvetica, Arial, sans-serif", fontcolor="#f8fafc", margin="0.25,0.15"]
        edge  [color="#64748b", penwidth="3.0", fontname="Helvetica, Arial, sans-serif", fontsize="12", fontcolor="#94a3b8"]

        <%- @cfg['topology'].each do |vm| -%>
        <%-   nodes = init_nodes(vm['name']) -%>
        <%-   nodes.each do |node| -%>
        <%-     if ['host', 'vhost', 'controller', 'external', 'rhost'].include?(node.type)
                  server_ip = Socket::getaddrinfo(Socket.gethostname,"echo",Socket::AF_INET)[0][3] rescue "127.0.0.1"
                  node_link = node.dnat.nil? ? "" : "https://" + server_ip + ":" + node.dnat[0][0].to_s
                  
                  if node.type == 'controller'
                    node_color = '#ef4444'
                    n_icon = '⚙️ '
                  elsif node.type == 'external' || node.type == 'rhost'
                    node_color = '#0ea5e9'
                    n_icon = '☁️ '
                  else
                    node_color = '#38bdf8'
                    n_icon = '💻 '
                  end
        -%>
        <%=       node.name.sub(/.-/, "_") %> [color="<%= node_color %>", href="<%= node_link %>",target="_blank",tooltip="<%= @graph.build_tooltip(node) %>",label=< <table cellborder="0" border="0" cellspacing="0" cellpadding="4"><tr><td><b><font color="<%= node_color %>" point-size="16"><%= n_icon %><%= node.fqdn || node.name %></font></b></td></tr><tr><td><font color="#cbd5e1" point-size="12"><%= node.nics['eth0'].to_s.empty? ? '&nbsp;' : node.nics['eth0'] %></font></td></tr></table> >]
        <%-     end -%>
        <%-   end -%>
        <%- end -%>

        <%- @cfg['topology'].each do |vm| -%>
        <%-   nodes = init_nodes(vm['name']) -%>
        <%-   nodes.each do |node| -%>
        <%-     if node.type == 'router' -%>
        <%=       node.name %> [color="#f59e0b", tooltip="<%= @graph.build_tooltip(node) %>", label=< <table cellborder="0" border="0" cellspacing="0" cellpadding="4"><tr><td><b><font color="#f59e0b" point-size="16">🔀 <%= node.name %></font></b></td></tr></table> >]
        <%-     end -%>
        <%-   end -%>
        <%- end -%>

        <%-
            @cfg['topology'].each do |vm|
              nodes = init_nodes(vm['name'])
              nodes.each do |node|
        -%>
        <%-     if node.type == 'switch' && node.snat.nil? -%>
        <%=       node.name %> [color="#10b981", tooltip="<%= @graph.build_tooltip(node) %>", label=<<b><font point-size="16">🎛️<%= node.name %></font></b>>]
        <%-     end -%>
        <%-   end -%>
        <%- end -%>

        <%-
            @nodes.each do |node|
        -%>
        <%-   if node.type == 'gateway' -%>
                <%= node.name %> [color="#a855f7", tooltip="<%= @graph.build_tooltip(node) %>", label=<<b><font point-size="16">🚪 <%= node.name %></font></b>>]
        <%-   end -%>
        <%- end -%>

        <%- ext_names = @nodes.select { |n| n.type == 'external' || n.type == 'rhost' }.map(&:name) -%>
        <%- @links.each do |l|
              node_a = l[0].split(':')[0]
              node_b = l[1].split(':')[0]
              # Check BOTH sides to see if this is a management link!
              is_mgmt_link = (node_a == 'sw0' || node_a == 'ro0' || node_b == 'sw0' || node_b == 'ro0')
              
              if is_mgmt_link && !ext_names.include?(node_a) && !ext_names.include?(node_b)
        -%>
          <%= node_a.sub(/.-/, "_") %> -- <%= node_b.sub(/.-/, "_") %>
        <%-   end -%>
        <%- end -%>

        <%-
            server_ip = Socket::getaddrinfo(Socket.gethostname,"echo",Socket::AF_INET)[0][3] rescue "127.0.0.1"
            host_name = @cfg ? (@cfg.dig('topology', 0, 'vm', 'name') || @cfg.dig('topology', 0, 'name') || 'CTLABS_HOST' rescue 'CTLABS_HOST') : 'CTLABS_HOST'
            host_tt = "CTLABS_HOST  [ Hypervisor ]&#10;━━━━━━━━━━━━━━━━━━━━━━━━&#10;ℹ️ Host VM: " + host_name + "&#10;━━━━━━━━━━━━━━━━━━━━━━━━&#10;🌐 IPv4: " + server_ip
        -%>
        ctlabs_host [color="#ec4899", tooltip="<%= host_tt %>", label=< <table cellborder="0" border="0" cellspacing="0" cellpadding="4"><tr><td><b><font color="#ec4899" point-size="16">🏢 <%= host_name %></font></b></td></tr><tr><td><font color="#cbd5e1" point-size="12"><%= server_ip %></font></td></tr></table> >]
        <%- target_node = @nodes.find { |n| n.name == 'natgw' } || @nodes.find { |n| n.name == 'sw0' } -%>
        <%- if target_node -%>
        ctlabs_host -- <%= target_node.name %> [color="#ec4899", style="dashed", penwidth="2.0"]
        <%-   @nodes.select { |n| n.type == 'external' || n.type == 'rhost' }.each do |ext_node| -%>
        <%= ext_node.name.sub(/.-/, "_") %> -- <%= target_node.name %> [color="#0ea5e9", style="dashed", penwidth="2.0"]
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
  <%=     node.name.ljust(24) %> ansible_host=<%= node.nics['eth0'].split('/')[0] %>
  <%-   end -%>
  <%- end -%>

[router]
  <%- @nodes.each do |node| -%>
  <%-   if node.type == 'router' and !node.nics['eth0'].to_s.empty? -%>
  <%=     node.name.ljust(24) %> ansible_host=<%= node.nics['eth0'].split('/')[0] %>
  <%-   end -%>
  <%- end -%>

[switches]
  <%- @nodes.each do |node| -%>
  <%-   if node.type == 'switch' and !node.ipv4.to_s.empty? -%>
  <%=     node.name.ljust(24) %> ansible_host=<%= node.ipv4.split('/')[0] %>
  <%-   elsif node.type == 'switch' and !node.nics['eth0'].to_s.empty? -%>
  <%=     node.name.ljust(24) %> ansible_host=<%= node.nics['eth0'].split('/')[0] %>
  <%-   end -%>
  <%- end -%>

[hosts]
  <%- @nodes.each do |node| -%>
  <%-   if (node.type == 'host' || node.type == 'vhost' || node.type == 'external' || node.type == 'rhost') and !node.nics['eth0'].to_s.empty? -%>
  <%=     node.name.ljust(24) %> ansible_host=<%= node.nics['eth0'].split('/')[0] %>
  <%-   end -%>
  <%- end -%>

[all:vars]
  <%= "ansible_user".ljust(24)         + "= root" %>
  <%= "ansible_ssh_password".ljust(24) + "= secret" %>
    }
  end

  def get_data_inventory
    %{ <%- -%>
[local]
  #localhost

[controller]
  <%- @nodes.each do |node| -%>
  <%-   if node.type == 'controller' and node.nics && !node.nics['eth1'].to_s.empty? -%>
  <%=     node.name.ljust(24) %> ansible_host=<%= node.nics['eth1'].split('/')[0] %>
  <%-   end -%>
  <%- end -%>

[router]
  <%- @nodes.each do |node| -%>
  <%-   ip = node.ipv4 || (node.nics && node.nics['eth1']) -%>
  <%-   if node.type == 'router' && !ip.to_s.empty? -%>
  <%=     node.name.ljust(24) %> ansible_host=<%= ip.split('/')[0] %>
  <%-   end -%>
  <%- end -%>

[switches]
  <%- @nodes.each do |node| -%>
  <%-   if node.type == 'switch' and !node.ipv4.to_s.empty? -%>
  <%=     node.name.ljust(24) %> ansible_host=<%= node.ipv4.split('/')[0] %>
  <%-   end -%>
  <%- end -%>

[hosts]
  <%- @nodes.each do |node| -%>
  <%-   if (node.type == 'host' || node.type == 'vhost' || node.type == 'external' || node.type == 'rhost') and node.nics && !node.nics['eth1'].to_s.empty? -%>
  <%=     node.name.ljust(24) %> ansible_host=<%= node.nics['eth1'].split('/')[0] %>
  <%-   end -%>
  <%- end -%>

[all:vars]
  <%= "ansible_user".ljust(24)         + "= root" %>
  <%= "ansible_ssh_password".ljust(24) + "= secret" %>
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
