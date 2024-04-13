
# -----------------------------------------------------------------------------
# File        : ctlabs/lib/graph.rb
# Description : graph class; creating visualizations
# License     : MIT License
# -----------------------------------------------------------------------------
#
# Desc: creates the various graphs by generating graphviz code
#
class Graph
  attr_reader :colors

  def initialize(args)
    @log = args[:log] || LabLog.new
    @log.write "== Graph =="
    @log.write "#{__method__}(): args=#{args}"

    @name    = args[:name]
    @nodes   = args[:nodes]
    @links   = args[:links]
    @binding = args[:binding]
    @dotfile = "/tmp/#{@name}.dot"
    @colors  = ['red', 'grey', 'blue', 'orange', 'magenta', 'black', 'olivedrab3', 'cyan2', 'salmon', 'darkgreen']
  end

  def get_cons
    @log.write "#{__method__}():  "

    %{
        graph <%= @name.sub(/.-/, "_") %> {
          graph [pad="0.2",nodesep="0.3",ranksep="2.5",overlap=false,splines=true,layout=dot,rankdir=TB,bgcolor="seashell",fontname="Courier New",fontsize="11"]

        <%- 
            @nodes.each do |node|
              # skip management nodes
              #if node.name == "sw0" || node.nics.size == 1
              if node.type == "switch" && node.kind == "mgmt" || node.type == "controller"
                next
              end
              group   = node.type
              bgcolor = "darkseagreen2"
              case node.type
                when 'host'
                  bgcolor = "lightsteelblue"
                when 'router'
                  bgcolor = "cadetblue"
                when 'gateway'
                  bgcolor = 'olivedrab3'
              end
        -%>

          subgraph cluster_<%= node.name.sub(/.-/, "_") %> {
            graph[style="rounded,filled",group="<%= group %>",fillcolor="<%= bgcolor %>"]
            node[shape=none,style="rounded,filled",fillcolor="<%= bgcolor %>",fontname="Courier New",fontsize="11"]
            <%= node.name.sub(/.-/, "_") %>[label=<
            <table bgcolor="<%= bgcolor %>" color="deeppink" border="1" cellborder="0">
        <%- if group != 'host' -%>
              <tr>
                <td align="center" colspan="<%= node.nics.size %>"> <b><%= node.name %></b> </td>
              </tr>
        <%- end -%>
              <tr><td></td></tr>
              <tr>
        <%-   node.nics.each do |nic| -%>
                <td port="<%= nic[0] %>" bgcolor="lightgrey" color="indigo" border="1" align="text"><%= nic[0] %></td>
        <%-   end -%>
        <%- 
              if !node.bonds.nil?
                node.bonds.each do |bond|
                  bond[1]['nics'].each do |nic|
        -%>
<!--                <td port="<%= nic %>" bgcolor="grey" color="indigo" border="1" align="text"><%= nic %></td>  -->
        <%-       end
                end
              end
        -%>
        <%-   if ! node.ipv4.nil? -%>
              <!--  <td port="ipv4" bgcolor="grey" color="indigo" border="1" align="text">eth0</td> -->
        <%-   end -%>
              </tr>
        <%- if group == 'host' -%>
              <tr><td></td></tr>
              <tr>
                <td align="center" colspan="<%= node.nics.size %>"> <b><%= node.name %></b> </td>
              </tr>
        <%- end -%>
            </table> >]
          }
        <%- end -%>

          edge[color=red,penwidth=2]
       
        <%- i = 0
            @links.each do |l|
              if l[0].split(':')[0] != 'sw0'
        -%>
          edge[color=<%= @graph.colors[i] -%>]
            <%- i = (i + 1) % @graph.colors.size -%>
            <%= l[0].sub(/.-/, "_") %>:s -- <%= l[1].sub(/.-/, "_") %>:n
          <%- end -%>
        <%- end -%>

          fontsize  = "18"
          label     = "<%= @name %> [<%= @desc %>]"
          labelloc  = top
          labeljust = left
        }
    }
  end

  def get_mgmt_cons
    @log.write "#{__method__}():  "

    %{
        graph <%= @name.sub(/.-/, "_") %> {
          graph [pad="0.2",nodesep="0.3",ranksep="2.5",overlap=false,splines=true,layout=dot,rankdir=TB,bgcolor="seashell",fontname="Courier New",fontsize="11"]

        <%- 
            @nodes.each do |node|
              if node.type == 'gateway'
                next
              end
              group   = node.type
              bgcolor = "darkseagreen2"
              case node.type
                when 'controller'
                  bgcolor = "lightsteelblue"
                when 'host'
                  bgcolor = "lightsteelblue"
                when 'router'
                  bgcolor = "cadetblue"
                when 'gateway'
                  bgcolor = 'olivedrab3'                  
              end              
        -%>
          subgraph cluster_<%= node.name.sub(/.-/, "_") %> {
            graph[style="rounded,filled",group="<%= group %>",fillcolor="<%= bgcolor %>"]
            node[shape=none,style="filled",fillcolor="<%= bgcolor %>",fontname="Courier New",fontsize="11"]
            <%= node.name.sub(/.-/, "_") %>[label=<
            <table bgcolor="<%= bgcolor %>" color="deeppink" border="1" cellborder="0">
        <%- if ![ 'host', 'controller' ].include?(group) -%>
              <tr>
                <td align="center" colspan="<%= node.nics.size %>"> <b><%= node.name %></b> </td>
              </tr>
        <%- end -%>
              <tr><td></td></tr>
              <tr>
        <%-   node.nics.each do |nic| -%>
                <td PORT="<%= nic[0] %>" bgcolor="lightgrey" color="indigo" border="1" align="text"><%= nic[0] %></td>
        <%-   end -%>
        <%- 
              if !node.bonds.nil?
                node.bonds.each do |bond|
                  bond[1]['nics'].each do |nic|
        -%>
<!--                <td PORT="<%= nic %>" bgcolor="grey" color="indigo" border="1" align="text"><%= nic %></td> -->
        <%-       end
                end
              end
        -%>
              </tr>
        <%- if [ 'host', 'controller' ].include?(group) -%>
              <tr><td></td></tr>
              <tr>
                <td align="center" colspan="<%= node.nics.size %>"> <b><%= node.name %></b> </td>
              </tr>
        <%- end -%>
            </table> >]
          }
        <%- end -%>

          edge[color=red,penwidth=2]
        <%- 
            i = 0
            @links.each do |l|
              if l[0].split(':')[0] == 'sw0'
              # if l[0].split(':')[0] in (@node.map{|n| n.type == 'mgmt' })
        -%>
          edge[color=<%= @graph.colors[i] -%>]
        <%-     i = (i + 1) % @graph.colors.size -%>
            <%= l[0].sub(/.-/, "_") %>:s -- <%= l[1].sub(/.-/, "_") %>:n
          <%- end -%>
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
      graph <%= @name.sub(/.-/, "_") %> {
        #layout=twopi
        #layout=neato
        #layout=sfdp
        #layout=circo
        #graph [pad="0.2",esep="0.1",ranksep="1",overlap=false,splines=true,layout=twopi,bgcolor="seashell"]
        graph [pad="0.2",esep="0.1",ranksep="1",overlap=false,splines=true,layout=neato,bgcolor="seashell",fontname="Courier New",fontsize="11"]

        node[shape=rectangle,style="rounded,filled",fillcolor="lightsteelblue"]
        <%- 
            @cfg['topology'].each do |vm|
              nodes = init_nodes(vm['name'])
              nodes.each do |node|
                # skip management nodes
                #if node.nics.size == 1
                if node.type == "switch" and node.kind == "mgmt" || node.type == "controller"
                  next
                end
        -%>
        <%-     if node.type == 'host' -%>
        <%=       node.name.sub(/.-/, "_") %> [label=< <table cellborder="0" bgcolor="lightsteelblue" color="deeppink" border="1"><tr><td><b><%= node.fqdn || node.name %></b></td></tr><hr/><tr><td><%= node.nics['eth1'] %></td></tr></table> >]
        #<%=       node.name.sub(/.-/, "_") %> [label="<%= node.fqdn %>\\n<%= node.nics['eth1'] %>"]
        <%-     end -%>
        <%-   end -%>
        <%- end -%>

        node[shape=circle,style="filled",fillcolor="cadetblue"]
        #node[shape=none,style=""]
        <%- @cfg['topology'].each do |vm| -%>
        <%-   nodes = init_nodes(vm['name']) -%>
        <%-   nodes.each do |node| -%>
        <%-     if node.type == 'router' -%>
        <%=       node.name %> [label=<<b><%= node.name %></b><br/><%= node.ipv4 %>>]
        #<%=       node.name %> [label=< <table border="0"><tr><td><br/><br/><br/><br/><br/><b><%= node.name %></b></td></tr></table> >,image="./router.png",height="0.7",width="0.7",fixedsize=true]
        <%-     end -%>
        <%-   end -%>
        <%- end -%>

        node[shape=diamond,style="rounded,filled",fillcolor="darkseagreen2"]
        #node[shape=none,style=""]
        <%- 
            @cfg['topology'].each do |vm|
              nodes = init_nodes(vm['name'])
              nodes.each do |node|
                # skip management nodes
                if node.name == "sw0"
                  next
                end
        -%>
        <%-     if node.type == 'switch' && node.snat.nil? -%>
        <%=       node.name %> [label=<<b><%= node.name %></b>>]
        <%-     end -%>
        <%-   end -%>
        <%- end -%>

        node[shape=diamond,style="rounded,filled",fillcolor="olivedrab3"]
        <%- 
            @nodes.each do |node|
              # skip management nodes
              if node.name == "sw0"
                next
              end
        -%>
        <%-   if node.type == 'gateway' -%>
                <%= node.name %> [label=<<b><%= node.name %></b>>]
        #<%=     node.name %> [label=< <table border="0"><tr><td><%= node.name %></td></tr><tr><td><%= node.ipv4 %></td></tr></table> >]
        #<%=     node.name %> [label=< <table border="0"><tr><td><br/><br/><br/><br/><%= node.name %></td></tr></table> >,image="./switch.png",height="0.5",width="0.8",fixedsize=true]
        <%-   end -%>
        <%- end -%>

        edge[color="lightsteelblue",penwidth=2]
        <%- 
            @links.each do |l|
              if l[0].split(':')[0] == "sw0"
                next
              end
        -%>
          <%= l[0].split(':')[0].sub(/.-/, "_") %> -- <%= l[1].split(':')[0].sub(/.-/, "_") %>
        <%- end -%>

          fontsize  = "18"
          label     = "<%= @name %> [<%= @desc %>]"
          labelloc  = top
          labeljust = left

      }
    }
  end

  def get_mgmt_topo
    %{
      graph <%= @name.sub(/.-/, "_") %> {
        #layout=twopi
        #layout=neato
        #layout=sfdp
        #layout=circo
        #graph [pad="0.2",esep="0.1",ranksep="1",overlap=false,splines=true,layout=twopi,bgcolor="seashell"]
        graph [pad="0.2",esep="0.1",ranksep="1",overlap=false,splines=true,layout=neato,bgcolor="seashell",fontname="Courier New",fontsize="11"]

        node[shape=rectangle,style="rounded,filled",fillcolor="lightsteelblue"]
        <%- @cfg['topology'].each do |vm| -%>
        <%-   nodes = init_nodes(vm['name']) -%>
        <%-   nodes.each do |node| -%>
        <%-     if node.type == 'host' || node.type == 'controller' -%>
        <%=       node.name.sub(/.-/, "_") %> [label=< <table cellborder="0" bgcolor="lightsteelblue" color="deeppink" border="1"><tr><td><b><%= node.fqdn || node.name %></b></td></tr><hr/><tr><td><%= node.nics['eth0'] %></td></tr></table> >]
        #<%=       node.name.sub(/.-/, "_") %> [label="<%= node.fqdn %>\\n<%= node.nics['eth0'] %>"]
        <%-     end -%>
        <%-   end -%>
        <%- end -%>

        node[shape=circle,style="filled",fillcolor="cadetblue"]
        #node[shape=none,style=""]
        <%- @cfg['topology'].each do |vm| -%>
        <%-   nodes = init_nodes(vm['name']) -%>
        <%-   nodes.each do |node| -%>
        <%-     if node.type == 'router' -%>
        <%=       node.name %> [label=<<b><%= node.name %></b><br/><%= node.ipv4 %>>]
        #<%=       node.name %> [label=< <table border="0"><tr><td><br/><br/><br/><br/><br/><%= node.name %></td></tr></table> >,image="./router.png",height="0.7",width="0.7",fixedsize=true]
        <%-     end -%>
        <%-   end -%>
        <%- end -%>

        node[shape=diamond,style="rounded,filled",fillcolor="darkseagreen2"]
        #node[shape=none,style=""]
        <%- 
            @cfg['topology'].each do |vm|
              nodes = init_nodes(vm['name'])
              nodes.each do |node|
                # skip management nodes
                #if node.name != "sw0"
                #  next
                #end
        -%>
        <%-     if node.type == 'switch' && node.snat.nil? -%>        
        <%=       node.name %> [label=<<b><%= node.name %></b>>]
        <%-     end -%>
        <%-   end -%>
        <%- end -%>

        node[shape=diamond,style="rounded,filled",fillcolor="olivedrab3"]
        <%- 
            @nodes.each do |node|
              # skip management nodes
              if !(node.type == "switch" && node.kind == "mgmt") || node.type != "controller"
                next
              end
        -%>
        <%-   if node.type == 'gateway' -%>
                <%= node.name %> [label=<<b><%= node.name %></b>>]
        #<%=     node.name %> [label=< <table border="0"><tr><td><%= node.name %></td></tr><tr><td><%= node.ipv4 %></td></tr></table> >]
        #<%=     node.name %> [label=< <table border="0"><tr><td><br/><br/><br/><br/><%= node.name %></td></tr></table> >,image="./switch.png",height="0.5",width="0.8",fixedsize=true]
        <%-   end -%>
        <%- end -%>

        edge[color="lightsteelblue",penwidth=2]
        <%- 
            @links.each do |l|
              if l[0].split(':')[0] != "sw0"
                next
              end
        -%>
          <%= l[0].split(':')[0].sub(/.-/, "_") %> -- <%= l[1].split(':')[0].sub(/.-/, "_") %>
        <%- end -%>

          fontsize  = "18"
          label     = "<%= @name %> [<%= @desc %>]"
          labelloc  = top
          labeljust = left

      }
    }
  end

  def get_inventory
    %{ <%- -%>
[local]
  localhost

[switches]
  <%- @nodes.each do |node| -%>
  <%-   if node.type == 'switch' and !node.ipv4.to_s.empty? -%>
  <%=     node.name.ljust(24) %> ansible_host=<%= node.ipv4.split('/')[0] %>
  <%-   elsif node.type == 'switch' and !node.nics['eth0'].to_s.empty? -%>
  <%=     node.name.ljust(24) %> ansible_host=<%= node.nics['eth0'].split('/')[0] %>
  <%-   end -%>
  <%- end -%>

[router]
  <%- @nodes.each do |node| -%>
  <%-   if node.type == 'router' and !node.nics['eth0'].to_s.empty? -%>
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

    File.open("../../ctlabs-ansible/inventories/#{name}.ini", "w") do |f|
      f.write( ERB.new(data, nil, '-').result(@binding))
    end
    File.open("/tmp/public/inventory.ini", "w") do |f|
      f.write( ERB.new(data, nil, '-').result(@binding))
    end
  end
end
