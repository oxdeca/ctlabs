#!/usr/bin/env ruby

# -----------------------------------------------------------------------------
# File        : ctlabs/server.rb
# Description : ctlabs main script
# License     : MIT License
# -----------------------------------------------------------------------------

require 'fileutils'
require 'webrick'
require 'sinatra'
require 'erb'

# sinatra settings
set :bind,              '0.0.0.0'
set :port,               4567
set :public_folder,     '/srv/ctlabs-server/public'
set :host_authorization, permitted_hosts: []
set :server_settings,    SSLEnable: true,
                         SSLVerifyClient: OpenSSL::SSL::VERIFY_NONE,
                         SSLCertName:     [[ 'CN', WEBrick::Utils.getservername ]]
CONFIG     = '/srv/ctlabs-server/public/config.yml'
INVENTORY  = '/srv/ctlabs-server/public/inventory.ini'
UPLOAD_DIR = '/srv/ctlabs-server/uploads'
Dir.mkdir(UPLOAD_DIR) unless Dir.exist?(UPLOAD_DIR)

# add basic authentication
use Rack::Auth::Basic, 'Restricted Area' do |user, pass|
  salt = "GGV78Ib5vVRkTc"
  user == 'ctlabs' && pass.crypt("$6$#{salt}$") == "$6$GGV78Ib5vVRkTc$cRAo9wl36SQPkh/UFzgEIOO1rBuju7/h5Lu8fJMDUNDG0HUcL3AhBNEqcYT1UUZkmBHa9.8r/5eh5qXwA8zcr."
end

# add routes
get "/" do
  #ERB.new(home).result(binding)
  erb :home
end

get '/upload' do
  erb :upload
end

get '/con' do
  erb :con
end

get '/topo' do
  erb :topo
end

get '/inventory' do
  erb :inventory
end

get '/config' do
  erb :config
end

get '/demo' do
  erb :demo
end

post '/upload' do
  uploaded_file = params[:file]
  return halt erb(:upload), BADREQ unless uploaded_file

  filename = uploaded_file[:tempfile].path

  puts "File received: #{filename}\nContents: #{File.read(filename).unpack("H*")}"
  if File.zero?(filename)
    puts "Error: The file is empty"
    return halt erb(:upload), BADREQ
  end

  FileUtils.cp(filename, UPLOAD_DIR + '/' + uploaded_file[:filename] )
  #File.rename(filename, UPLOAD_DIR + '/' + uploaded_file[:filename] )
  #File.unlink(filename)

  redirect '/upload'
end


# Templates
BADREQ = %q(
<div class="w3-panel w3-red">
  <h3>Bad Request</h3>
  <p>Something went wrong! [Hint: Did you choose a file?]</p>
</div>
)

HEADER = %q(
<!DOCTYPE html>
<html lang="en">
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <link rel="stylesheet" href="https://www.w3schools.com/w3css/4/w3.css">
  <link rel="stylesheet" href="https://www.w3schools.com/lib/w3-colors-2021.css">
  <link rel="stylesheet" href="/asciinema-player.css" type="text/css" />
  <script src="https://www.w3schools.com/lib/w3.js"></script>
  <body bgcolor="#1c1c1c">
    <div class="w3-top w3-bar w3-black">
      <a href="/"          class="w3-bar-item w3-button">CTLABS</a>
      <a href="/con"       class="w3-bar-item w3-button">Connections</a>
      <a href="/topo"      class="w3-bar-item w3-button">Topology</a>
      <a href="/inventory" class="w3-bar-item w3-button">Inventory</a>
      <a href="/config"    class="w3-bar-item w3-button">Configuration</a>
      <a href="/demo"      class="w3-bar-item w3-button">Walkthrough</a>
<!--      <a href="/upload" class="w3-bar-item w3-button">Upload</a> -->
    </div>
    <div id="ctlabs"><br></div>
)

SCRIPT = %q(
<script>
function updateEmbedWidth(embedId, percent) {
  const embed = document.getElementById(embedId);
  if (!embed) return;
  // Use current window width as base (or fallback to last known width)
  const baseWidth = parseInt(embed.dataset.baseWidth) || window.innerWidth;
  const newWidth = (baseWidth * percent) / 100;
  embed.style.width = `${newWidth}px`;
  embed.style.height = "auto"; // Maintain aspect ratio
  const labelId = `zoom-value-${embedId.replace('-embed', '')}`;
  const label = document.getElementById(labelId);
  if (label) label.textContent = percent;
}

document.addEventListener('DOMContentLoaded', function () {
  const sliders = document.querySelectorAll('.zoom-slider');
  if (!sliders.length) return;
  // Set initial baseWidth for each embed
  sliders.forEach(slider => {
    const embedId = slider.getAttribute('data-embed-id');
    const embed = document.getElementById(embedId);
    if (embed && !embed.dataset.baseWidth) {
      embed.dataset.baseWidth = window.innerWidth; // Store once
    }
  });

  sliders.forEach(slider => {
    // Prevent scrolling when interacting with slider
    slider.addEventListener('touchstart', e => {
      e.preventDefault();
    }, { passive: false });
    slider.addEventListener('input', function () {
      const embedId = this.getAttribute('data-embed-id');
      const percent = this.value;
      updateEmbedWidth(embedId, percent);
    });
  });
});
</script>
)

FOOTER = %q(
    <br>
  </body>
</html>
)

__END__


@@home
<%= HEADER %>
    <div id="con" class="w3-panel w3-green">
      <h2> Connections [Data Network] </h2>
    </div>
    <div class="w3-card-4" style="max-width: 100%; overflow: auto; position: relative;">
      <div class="w3-panel w3-text-yellow" display: flex; flex-direction: column;>
        <span>Zoom: <strong><span id="zoom-value-con">100</span>%</strong></span></br>
        <input type="range" min="50" max="200" value="100" step="5" class="zoom-slider" data-embed-id="con-embed">
      </div>
      <div class="svg-container">
        <embed id="con-embed" src="con.svg" class="w3-round" alt="Connections" type="image/svg+xml" width="100%">
      </div>
    </div>
    <div id="topo" class="w3-panel w3-green">
      <h2> Topology [Data Network]</h2>
    </div>
    <div class="w3-card-4" style="max-width: 100%; overflow: auto; position: relative;">
      <div class="w3-panel w3-text-yellow" display: flex; flex-direction: column;>
        <span> Zoom: <strong><span id="zoom-value-topo">100</span>%</strong></span></br>
        <input type="range" min="50" max="200" value="100" step="5" class="zoom-slider" data-embed-id="topo-embed">
      </div>
      <div class="svg-container">
        <embed id="topo-embed" src="topo.svg" class="w3-round" alt="Management" type="image/svg+xml" width="100%">
      </div>
    </div>
<%= SCRIPT %>
<%= FOOTER %>

@@con
<%= HEADER %>
    <div id="con" class="w3-panel w3-green">
      <h2> Connections [Data Network]</h2>
    </div>
    <div class="w3-card-4" style="max-width: 100%; overflow: auto; position: relative;">
      <div class="w3-panel w3-text-yellow" display: flex; flex-direction: column;>
        <input type="range" min="50" max="200" value="100" step="5" class="zoom-slider" data-embed-id="con-embed">
        <span>Zoom: <strong><span id="zoom-value-con">100</span>%</strong></span>
      </div>
      <div class="svg-container">
        <embed id="con-embed" src="con.svg" class="w3-round" alt="Connections" type="image/svg+xml" width="100%">
      </div>
    </div>
    <div id="mgmt_con" class="w3-panel w3-green">
      <h2> Connections [Management Network] </h2>
    </div>
    <div class="w3-card-4" style="max-width: 100%; overflow: auto; position: relative;">
      <div class="w3-panel w3-text-yellow" display: flex; flex-direction: column;>
        <input type="range" min="50" max="200" value="100" step="5" class="zoom-slider" data-embed-id="mgmt-con-embed">
        <span>Zoom: <strong><span id="zoom-value-mgmt-con">100</span>%</strong></span>
      </div>
      <div class="svg-container">
        <embed id="mgmt-con-embed" src="mgmt_con.svg" class="w3-round" alt="Management" type="image/svg+xml" width="100%">
      </div>
    </div>
<%= SCRIPT %>
<%= FOOTER %>

@@topo
<%= HEADER %>
    <div id="topo" class="w3-panel w3-green">
      <h2> Topology [Data Network]</h2>
    </div>
    <div class="w3-card-4" style="max-width: 100%; overflow: auto; position: relative;">
      <div class="w3-panel w3-text-yellow" display: flex; flex-direction: column;>
        <input type="range" min="50" max="200" value="100" step="5" class="zoom-slider" data-embed-id="topo-embed">
        <span>Zoom: <strong><span id="zoom-value-topo">100</span>%</strong></span>
      </div>
      <div class="svg-container">
        <embed id="topo-embed" src="topo.svg" class="w3-round" alt="Topology" type="image/svg+xml" width="100%">
      </div>
    </div>
    <div id="mgmt_topo" class="w3-panel w3-green">
      <h2> Topology [Management Network]</h2>
    </div>
    <div class="w3-card-4" style="max-width: 100%; overflow: auto; position: relative;">
      <div class="w3-panel w3-text-yellow" display: flex; flex-direction: column;>
        <input type="range" min="50" max="200" value="100" step="5" class="zoom-slider" data-embed-id="mgmt-topo-embed">
        <span>Zoom: <strong><span id="zoom-value-mgmt-topo">100</span>%</strong></span>
      </div>
      <div class="svg-container">
        <embed id="mgmt-topo-embed" src="mgmt_topo.svg" class="w3-round" alt="Management" type="image/svg+xml" width="100%">
      </div>
    </div>
<%= SCRIPT %>
<%= FOOTER %>

@@upload
<%= HEADER %>
    <div id="upload" class="w3-panel w3-green">
      <h2> Upload </h2>
    </div>
    <div class="w3-container w3-teal">
    <form action="/upload" method="post" enctype="multipart/form-data">
      <label class="w3-text-teal"><b>Select a file:</b></label>
      <input class="w3-input w3-border"  type="file"   name="file" id="file"/>
      <input class="w3-btn w3-blue-grey" type="submit" value="Send File"/>
    </form>
    </div>
    <br/><br/>
    <div class="w3-container">
      <ul class="w3-ul w3-border w3-hoverable">
        <li class="w3-teal"><h3>Uploaded Files:</h3></li>
      <% Dir.entries(UPLOAD_DIR, encoding: "ascii" ).each do |f| %>
        <%  if f =~ /[a-zA-Z0-9].*/ %>
          <li><%= f %><br/></li>
        <% end %>
      <% end %>
      </ul>
    </divc>
<%= FOOTER %>

@@inventory
<%= HEADER %>
    <div id="inventory" class="w3-panel w3-green">
      <h2> Inventory [Management Network]</h2>
    </div>
    <div class="w3-container">
      <div class="w3-container w3-card-4 w3-2021-inkwell" style="max-width: 100%; max-height: 100%; overflow: auto;">
        <pre><%= File.file?(INVENTORY) ? File.read(INVENTORY) : "Error: No Inventory found!" %></pre>
      </div>
    </div>
<%= FOOTER %>

@@config
<%= HEADER %>
    <div id="config" class="w3-panel w3-green">
      <h2> Lab Configuration </h2>
    </div>
    <div class="w3-container">
      <div class="w3-container w3-card-4 w3-2021-inkwell" style="max-width: 100%; max-height: 100%; overflow: auto;">
        <pre><%= File.file?(CONFIG) ? File.read(CONFIG) : "Error: No Configuration found!" %></pre>
      </div>
    </div>
<%= FOOTER %>

@@demo
<%= HEADER %>
    <div class="w3-panel w3-green">
      <h2> Walkthrough </h2>
    </div>
    <div id="demo" class="w3-container w3-card-4" style="max-width: 100%; max-height: 100%; overflow: auto;">
      <div class="w3-round">
      <script src="/asciinema-player.min.js"></script>
      <script>
        AsciinemaPlayer.create('/demo.cast', document.getElementById('demo'));
      </script>
      </div>
    </div>
<%= FOOTER %>
