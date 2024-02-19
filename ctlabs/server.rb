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

UPLOAD_DIR = '/tmp/uploads'
Dir.mkdir(UPLOAD_DIR) unless Dir.exist?(UPLOAD_DIR)

# add basic authentication
use Rack::Auth::Basic, 'Restricted Area' do |user, pass|
  user == 'ctlabs' && pass == 's3cr3t5!'
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


post '/upload' do
  uploaded_file = params[:file]
  return halt erb(:upload), BADREQ unless uploaded_file

  filename = uploaded_file[:tempfile].path

  puts "File received: #{filename}\nContents: #{File.read(filename).unpack("H*")}"
  if File.zero?(filename)
    puts "Error: The file is empty"
    return halt erb(:upload), BADREQ
  end

  File.rename(filename, UPLOAD_DIR + '/' + uploaded_file[:filename] )
  #File.unlink(filename)

  redirect '/upload'
end

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
  <script src="https://www.w3schools.com/lib/w3.js"></script>
  <body bgcolor="seashell">
    <div class="w3-top w3-bar w3-black">
      <a href="/"       class="w3-bar-item w3-button">CTLABS</a>
      <a href="/con"    class="w3-bar-item w3-button">Connections</a>
      <a href="/topo"   class="w3-bar-item w3-button">Topology</a>
<!--      <a href="/upload" class="w3-bar-item w3-button">Upload</a> -->
    </div>
    <div id="ctlabs"><br></div>
)

FOOTER = %q(
  </body>
</html>
)

__END__


@@home
<%= HEADER %>
<!DOCTYPE html>
    <div id="con" class="w3-panel w3-green">
      <h2> Connections [Core Network]</h2>
    </div>
    <div class="w3-card-4" style="max-width: 100%; overflow: auto;">
      <img src="con.svg" class="w3-round" alt="Connections">
    </div>
    <div id="topo" class="w3-panel w3-green">
      <h2> Topology [Core Network]</h2>
    </div>
    <div class="w3-card-4" style="max-width: 100%; overflow: auto;">
      <img src="topo.svg" class="w3-round" alt="Topology">
    </div>
<%= FOOTER %>


@@con
<%= HEADER %>
    <div id="con" class="w3-panel w3-green">
      <h2> Connections [Core Network]</h2>
    </div>
    <div class="w3-card-4" style="max-width: 100%; overflow: auto;">
      <img src="con.svg" class="w3-round" alt="Connections">
    </div>
    <div id="mgmt_con" class="w3-panel w3-green">
      <h2> Connections [Management Network] </h2>
    </div>
    <div class="w3-card-4" style="max-width: 100%; overflow: auto;">
      <img src="mgmt_con.svg" class="w3-round" alt="Manegement">
    </div>
<%= FOOTER %>


@@topo
<%= HEADER %>
    <div id="topo" class="w3-panel w3-green">
      <h2> Topology [Core Network]</h2>
    </div>
    <div class="w3-card-4" style="max-width: 100%; overflow: auto;">
      <img src="topo.svg" class="w3-round" alt="Topology">
    </div>
    <div id="mgmt_topo" class="w3-panel w3-green">
      <h2> Topology [Management Network]</h2>
    </div>
    <div class="w3-card-4" style="max-width: 100%; overflow: auto;">
      <img src="mgmt_topo.svg" class="w3-round" alt="Manegement">
    </div>
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
    </div>
<%= FOOTER %>
