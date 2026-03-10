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
    
    # Modern vivid palette for network cables
    #@colors  = ['#ef4444', '#f97316', '#f59e0b', '#eab308', '#84cc16', '#22c55e', '#10b981', '#14b8a6', '#06b6d4', '#0ea5e9', '#3b82f6', '#6366f1', '#8b5cf6', '#a855f7', '#d946ef', '#ec4899', '#f43f5e']
    # High-contrast, alternating palette to easily distinguish intertwined cables
    @colors  = [
      '#ef4444', # Red
      '#3b82f6', # Blue
      '#22c55e', # Green
      '#eab308', # Yellow
      '#a855f7', # Purple
      '#06b6d4', # Cyan
      '#f97316', # Orange
      '#ec4899', # Pink
      '#84cc16', # Lime
      '#6366f1', # Indigo
      '#14b8a6', # Teal
      '#d946ef'  # Fuchsia
    ]
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
              border_color = "#10b981" # Default Switch Green
              case node.type
                when 'host' then border_color = "#38bdf8"      # Blue
                when 'router' then border_color = "#f59e0b"    # Orange
                when 'gateway' then border_color = "#a855f7"   # Purple
                when 'controller' then border_color = "#ef4444"# Red
              end
              server_ip = Socket::getaddrinfo(Socket.gethostname,"echo",Socket::AF_INET)[0][3]
              node_link = node.dnat.nil? || node.type == 'gateway' ? "" : "https://" + server_ip + ":" + node.dnat[0][0].to_s
              col_span = node.nics.size == 0 ? 1 : node.nics.size
        -%>

          subgraph cluster_<%= node.name.sub(/.-/, "_") %> {
            graph[style="invis", group="<%= group %>"]
            node[shape=rect, style="rounded,filled", fillcolor="#0f172a", color="<%= border_color %>", penwidth="2.5", fontname="Helvetica, Arial, sans-serif", fontcolor="#f8fafc", margin="0.1"]
            <%= node.name.sub(/.-/, "_") %>[href="<%= node_link %>",target="_blank",tooltip="<%= node.name.sub(/.-/,"_") %>",label=<
            <table border="0" cellborder="0" cellspacing="6" cellpadding="4">
        <%- if group != 'host' -%>
              <tr>
                <td align="center" colspan="<%= col_span %>"><b><font color="<%= border_color %>" point-size="16"><%= node.name %></font></b></td>
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
        <%- if group == 'host' -%>
              <tr>
                <td align="center" colspan="<%= col_span %>"><b><font color="<%= border_color %>" point-size="16"><%= node.name %></font></b></td>
              </tr>
        <%- end -%>
            </table> >]
          }
        <%- end -%>

        <%- i = 0
            @links.each do |l|
              if l[0].split(':')[0] != 'sw0' && l[0].split(':')[0] != 'ro0'
        -%>
        <%=     l[0].sub(/.-/, "_") %>:s -- <%= l[1].sub(/.-/, "_") %>:n [color="<%= @graph.colors[i] %>"]
        <%-     i = (i + 1) % @graph.colors.size -%>
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
              border_color = "#10b981" # Default Switch Green
              case node.type
                when 'host' then border_color = "#38bdf8"
                when 'router' then border_color = "#f59e0b"
                when 'gateway' then border_color = "#a855f7"
                when 'controller' then border_color = "#ef4444"
              end
              server_ip = Socket::getaddrinfo(Socket.gethostname,"echo",Socket::AF_INET)[0][3]
              node_link = node.dnat.nil? || node.type == 'gateway' ? "" : "https://" + server_ip + ":" + node.dnat[0][0].to_s
              col_span = node.nics.size == 0 ? 1 : node.nics.size
        -%>
          subgraph cluster_<%= node.name.sub(/.-/, "_") %> {
            graph[style="invis", group="<%= group %>"]
            node[shape=rect, style="rounded,filled", fillcolor="#0f172a", color="<%= border_color %>", penwidth="2.5", fontname="Helvetica, Arial, sans-serif", fontcolor="#f8fafc", margin="0.1"]
            <%= node.name.sub(/.-/, "_") %>[href="<%= node_link %>",target="_blank",tooltip="<%= node.name.sub(/.-/,"_") %>",label=<
            <table border="0" cellborder="0" cellspacing="6" cellpadding="4">
        <%- if ![ 'host', 'controller' ].include?(group) -%>
              <tr>
                <td align="center" colspan="<%= col_span %>"><b><font color="<%= border_color %>" point-size="16"><%= node.name %></font></b></td>
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
        <%- if [ 'host', 'controller' ].include?(group) -%>
              <tr>
                <td align="center" colspan="<%= col_span %>"><b><font color="<%= border_color %>" point-size="16"><%= node.name %></font></b></td>
              </tr>
        <%- end -%>
            </table> >]
          }
        <%- end -%>

        <%-
            i = 0
            @links.each do |l|
              if l[0].split(':')[0] == 'sw0' || l[0].split(':')[0] == 'ro0'
        -%>
        <%=     l[0].sub(/.-/, "_") %>:s -- <%= l[1].sub(/.-/, "_") %>:n [color="<%= @graph.colors[i] %>"]
        <%-     i = (i + 1) % @graph.colors.size -%>
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
                server_ip = Socket::getaddrinfo(Socket.gethostname,"echo",Socket::AF_INET)[0][3]
                node_link = node.dnat.nil? ? "" : "https://" + server_ip + ":" + node.dnat[0][0].to_s
        -%>
        <%-     if node.type == 'host' -%>
        <%=       node.name.sub(/.-/, "_") %> [color="#38bdf8", href="<%= node_link %>",target="_blank",tooltip="<%= node.name.sub(/.-/,"_") %>",label=< <table cellborder="0" border="0" cellspacing="0" cellpadding="4"><tr><td><b><font color="#38bdf8" point-size="16"><%= node.fqdn || node.name %></font></b></td></tr><tr><td><font color="#cbd5e1" point-size="12"><%= node.nics['eth1'].to_s.empty? ? '&nbsp;' : node.nics['eth1'] %></font></td></tr></table> >]
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
        <%=       node.name %> [color="#f59e0b", label=< <table cellborder="0" border="0" cellspacing="0" cellpadding="4"><tr><td><b><font color="#f59e0b" point-size="16"><%= node.name %></font></b></td></tr><tr><td><font color="#cbd5e1" point-size="12"><%= node.ipv4.to_s.empty? ? '&nbsp;' : node.ipv4 %></font></td></tr></table> >]
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
        <%=       node.name %> [color="#10b981", label=<<b><font point-size="16"><%= node.name %></font></b>>]
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
                <%= node.name %> [color="#a855f7", label=<<b><font point-size="16"><%= node.name %></font></b>>]
        <%-   end -%>
        <%- end -%>

        <%-
            @links.each do |l|
              if l[0].split(':')[0] == "sw0" || l[0].split(':')[0] == 'ro0'
                next
              end
        -%>
          <%= l[0].split(':')[0].sub(/.-/, "_") %> -- <%= l[1].split(':')[0].sub(/.-/, "_") %>
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
        <%-     if node.type == 'host' || node.type == 'controller'
                  server_ip = Socket::getaddrinfo(Socket.gethostname,"echo",Socket::AF_INET)[0][3]
                  node_link = node.dnat.nil? ? "" : "https://" + server_ip + ":" + node.dnat[0][0].to_s
                  node_color = node.type == 'controller' ? '#ef4444' : '#38bdf8'
        -%>
        <%=       node.name.sub(/.-/, "_") %> [color="<%= node_color %>", href="<%= node_link %>",target="_blank",tooltip="<%= node.name.sub(/.-/,"_") %>",label=< <table cellborder="0" border="0" cellspacing="0" cellpadding="4"><tr><td><b><font color="<%= node_color %>" point-size="16"><%= node.fqdn || node.name %></font></b></td></tr><tr><td><font color="#cbd5e1" point-size="12"><%= node.nics['eth0'].to_s.empty? ? '&nbsp;' : node.nics['eth0'] %></font></td></tr></table> >]
        <%-     end -%>
        <%-   end -%>
        <%- end -%>

        <%- @cfg['topology'].each do |vm| -%>
        <%-   nodes = init_nodes(vm['name']) -%>
        <%-   nodes.each do |node| -%>
        <%-     if node.type == 'router' -%>
        <%=       node.name %> [color="#f59e0b", label=< <table cellborder="0" border="0" cellspacing="0" cellpadding="4"><tr><td><b><font color="#f59e0b" point-size="16"><%= node.name %></font></b></td></tr><tr><td><font color="#cbd5e1" point-size="12"><%= node.ipv4.to_s.empty? ? '&nbsp;' : node.ipv4 %></font></td></tr></table> >]
        <%-     end -%>
        <%-   end -%>
        <%- end -%>

        <%-
            @cfg['topology'].each do |vm|
              nodes = init_nodes(vm['name'])
              nodes.each do |node|
        -%>
        <%-     if node.type == 'switch' && node.snat.nil? -%>
        <%=       node.name %> [color="#10b981", label=<<b><font point-size="16"><%= node.name %></font></b>>]
        <%-     end -%>
        <%-   end -%>
        <%- end -%>

        <%-
            @nodes.each do |node|
        -%>
        <%-   if node.type == 'gateway' -%>
                <%= node.name %> [color="#a855f7", label=<<b><font point-size="16"><%= node.name %></font></b>>]
        <%-   end -%>
        <%- end -%>

        <%-
            @links.each do |l|
              if l[0].split(':')[0] != "sw0" && l[0].split(':')[0] != 'ro0'
                next
              end
        -%>
          <%= l[0].split(':')[0].sub(/.-/, "_") %> -- <%= l[1].split(':')[0].sub(/.-/, "_") %>
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
  <%-   if node.type == 'host' and !node.nics['eth0'].to_s.empty? -%>
  <%=     node.name.ljust(24) %> ansible_host=<%= node.nics['eth0'].split('/')[0] %>
  <%-   end -%>
  <%- end -%>

[all:vars]
  <%= "ansible_user".ljust(24)         + "= root" %>
  <%= "ansible_ssh_password".ljust(24) + "= secret" %>
    }
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
