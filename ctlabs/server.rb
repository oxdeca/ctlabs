#!/usr/bin/env ruby

# -----------------------------------------------------------------------------
# File        : ctlabs/server.rb
# Description : ctlabs main script
# License     : MIT License
# -----------------------------------------------------------------------------

require 'sinatra'
require 'erb'

# sinatra settings
set :bind,           '0.0.0.0'
set :port,            4567
set :public_folder,  '/tmp/public'

# add basic authentication
use Rack::Auth::Basic, 'Restricted Area' do |user, pass|
  user == 'ctlabs' && pass == 's3cr3t5!' 
end

home = %q(
<!DOCTYPE html>
<html lang="en">
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <link rel="stylesheet" href="https://www.w3schools.com/w3css/4/w3.css">
  <script src="https://www.w3schools.com/lib/w3.js"></script>
  <body>
    <div class="w3-top w3-bar w3-black">
      <a href="#ctlabs" class="w3-bar-item w3-button">CTLABS</a>
      <a href="#con"    class="w3-bar-item w3-button">Connections</a>
      <a href="#topo"   class="w3-bar-item w3-button">Topology</a>
    </div>
    <div id="ctlabs"></div>
    <br/><br/>
    <div id="con" class="w3-container w3-green"><h2> Connections </h2></div>
    <img src="con.svg" class="w3-round" alt="Connections">
    <div id="topo" class="w3-container w3-green"><h2> Topology </h2></div>
    <img src="topo.svg" class="w3-round" alt="Topology">
  </body>
</html>
)

# add routes
get "/" do
  ERB.new(home).result(binding)
end
