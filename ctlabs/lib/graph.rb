
# -----------------------------------------------------------------------------
# File        : ctlabs/lib/graph.rb
# Description : graph class; creating visualizations
# License     : License
# -----------------------------------------------------------------------------
#
# Desc: creates the various graphs by generating graphviz code
#
class Graph
  def initialize(args)
    @log = args[:log] || LabLog.new
    @log.write "== Graph =="
    @log.write "#{__method__}(): args=#{args}"

    @name    = args[:name]
    @nodes   = args[:nodes]
    @links   = args[:links]
    @binding = args[:binding]
    @dotfile = "/tmp/#{@name}.dot"
  end

  def get_connections
    @log.write "#{__method__}():  "

    %{
        graph <%= @name.sub(/.-/, "_") %> {
          graph [pad="0.2",nodesep="0.3",ranksep="2",overlap=false,splines=true,layout=dot,rankdir=TB,bgcolor="beige"]

        <%- @nodes.each do |node| -%>
          subgraph cluster_<%= node.name.sub(/.-/, "_") %> {
            graph[style="rounded"]
            node[shape=none,style=""]
            <%= node.name.sub(/.-/, "_") %>[label=<
            <table bgcolor="darkseagreen2" color="slategrey" border="2" cellborder="0">
              <tr>
                <td align="center" colspan="<%= node.nics.size %>"> <%= node.name %> </td>
              </tr>
              <hr/>
              <tr><td></td></tr>
              <tr>
                <%- node.nics.each do |nic| -%>
                <td PORT="<%= nic[0] %>" bgcolor="grey" color="purple" border="1" align="text"><%= nic[0] %></td>
                <%- end -%>
                <%- if !node.bonds.nil? -%>
                  <%- node.bonds.each do |bond| -%>
                    <%- bond[1]['nics'].each do |nic| -%>
                <td PORT="<%= nic %>" bgcolor="grey" color="purple" border="1" align="text"><%= nic %></td>
                    <%- end -%>
                  <%- end -%>
                <%- end -%>
                <%- if ! node.ipv4.nil? -%>
                <td PORT="ipv4" bgcolor="grey" color="purple" border="1" align="text">default</td>
                <%- end -%>
              </tr>
            </table> >]
          }
        <%- end -%>

          edge[color=red,penwidth=2]
        <%- colors = ['red', 'grey', 'blue', 'orange', 'magenta', 'black', 'olivedrab3', 'cyan2', 'purple'] -%>
        <% i = 0 -%>
        <%- @links.each do |l| -%>
          edge[color=<%= colors[i] -%>]
          <%- i = (i + 1) % colors.size -%>
          <%= l[0].sub(/.-/, "_") %> -- <%= l[1].sub(/.-/, "_") %>
        <%- end -%>

          fontsize  = "18"
          label     = "<%= @name %> [<%= @desc %>]"
          labelloc  = top
          labeljust = left
        }
    }
  end

  def get_topology
    %{
      graph Overview {
        #layout=twopi
        #layout=neato
        #layout=sfdp
        #layout=circo
        #graph [pad="0.2",esep="0.1",ranksep="1",overlap=false,splines=true,layout=twopi]
        graph [pad="0.2",esep="0.1",ranksep="1",overlap=false,splines=true,layout=neato]

        node[shape=rectangle,style="rounded,filled",fillcolor="lemonchiffon3"]
        <%- @cfg['topology'].each do |vm| -%>
        <%-   nodes = init_nodes(vm['name']) -%>
        <%-   nodes.each do |node| -%>
        <%-     if node.type == 'host' -%>
        <%=       node.name.sub(/.-/, "_") %> [label=< <table cellborder="0" bgcolor="lemonchiffon3" color="lemonchiffon4"><tr><td><%= node.fqdn || node.name %></td></tr><hr/><tr><td><%= node.nics['eth1'] %></td></tr></table> >]
        #<%=       node.name.sub(/.-/, "_") %> [label="<%= node.fqdn %>\\n<%= node.nics['eth1'] %>"]
        <%-     end -%>
        <%-   end -%>
        <%- end -%>

        node[shape=circle,style="filled",fillcolor="dodgerblue"]
        #node[shape=none,style=""]
        <%- @cfg['topology'].each do |vm| -%>
        <%-   nodes = init_nodes(vm['name']) -%>
        <%-   nodes.each do |node| -%>
        <%-     if node.type == 'router' -%>
        <%=       node.name %> [label="<%= node.name %>\\n<%= node.ipv4 %>"]
        #<%=       node.name %> [label=< <table border="0"><tr><td><br/><br/><br/><br/><br/><%= node.name %></td></tr></table> >,image="./router.png",height="0.7",width="0.7",fixedsize=true]
        <%-     end -%>
        <%-   end -%>
        <%- end -%>

        node[shape=diamond,style="rounded,filled",fillcolor="olivedrab3"]
        #node[shape=none,style=""]
        <%- @cfg['topology'].each do |vm| -%>
        <%-   nodes = init_nodes(vm['name']) -%>
        <%-   nodes.each do |node| -%>
        <%-     if node.type == 'switch' && node.snat.nil? -%>
        <%=       node.name %> [label="<%= node.name %>"]
        <%-     end -%>
        <%-   end -%>
        <%- end -%>

        node[shape=diamond,style="rounded,filled",fillcolor="skyblue2"]
        <%- @nodes.each do |node| -%>
        <%-   if node.type == 'switch' && node.snat -%>
        <%=     node.name %> [label="<%= node.name %>"]
        #<%=     node.name %> [label=< <table border="0"><tr><td><%= node.name %></td></tr><tr><td><%= node.ipv4 %></td></tr></table> >]
        #<%=     node.name %> [label=< <table border="0"><tr><td><br/><br/><br/><br/><%= node.name %></td></tr></table> >,image="./switch.png",height="0.5",width="0.8",fixedsize=true]
        <%-   end -%>
        <%- end -%>

        edge[color="lightsteelblue",penwidth=2]
        <%- @links.each do |l| -%>
        <%=   l[0].split(':')[0].sub(/.-/, "_") %> -- <%= l[1].split(':')[0].sub(/.-/, "_") %>
        <%- end -%>

      }
    }
  end

  def get_inventory
    %{
[local]
  localhost

[switches]
  <%- @nodes.each do |node| -%>
  <%-   if node.type == 'switch' and !node.nics['eth1'].to_s.empty? -%>
  <%=     node.name %> ansible_host=<%= node.nics['eth1'].split('/')[0] %>
  <%-   end -%>
  <%- end -%>


[router]
  <%- @nodes.each do |node| -%>
  <%-   if node.type == 'router' and !node.nics['eth1'].to_s.empty? -%>
  <%=     node.name %> ansible_host=<%= node.nics['eth1'].split('/')[0] %>
  <%-   end -%>
  <%- end -%>

[hosts]
  <%- @nodes.each do |node| -%>
  <%-   if node.type == 'host' and !node.nics['eth1'].to_s.empty? -%>
  <%=     node.name %> ansible_host=<%= node.nics['eth1'].split('/')[0] %>
  <%-   end -%>
  <%- end -%>

[all:vars]
  ansible_user         = root
  ansible_ssh_password = secret

    }
  end

  def to_dot(data)
    @log.write "#{__method__}(): data=#{data}"

    File.open("#{@dotfile}", "w" ) do |f|
      f.write( ERB.new(data, nil, '-').result(@binding) )
    end
  end

  def to_png(data, name)
    @log.write "#{__method__}(): data=#{data},name=#{name}"

    to_dot(data)
    %x( dot -Tpng #{@dotfile} -o /tmp/public/#{name}.png )
  end

  def to_svg(data, name)
    @log.write "#{__method__}(): data=#{data},name=#{name}"

    to_dot(data)
    %x( dot -Tsvg #{@dotfile} -o /tmp/public/#{name}.svg )
  end

  def to_ini(data, name)
    @log.write "#{__method__}(): data=#{data},name=#{name}"

    File.open("#{name}.ini", "w") do |f|
      f.write( ERB.new(data, nil, '-').result(@binding))
    end
  end
end
