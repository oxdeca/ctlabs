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

post '/upload' do
  uploaded_file = params[:file]
  return halt erb(:upload), 400 unless uploaded_file

  filename = uploaded_file[:tempfile].path

  puts "File received: #{filename}\nContents: #{File.read(filename).unpack("H*")}"

  File.rename(filename, UPLOAD_DIR + '/' + uploaded_file[:filename] )
  #File.unlink(filename)

  redirect '/upload'
end

__END__

@@home
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
      <a href="/upload" class="w3-bar-item w3-button">Upload</a>
    </div>
    <div id="ctlabs"></div>
    <div id="con" class="w3-container w3-green">
      <br/><br/>
      <h2> Connections </h2>
    </div>
    <img src="con.svg" class="w3-round" alt="Connections">
    <div id="topo" class="w3-container w3-green">
      <h2> Topology </h2>
    </div>
    <img src="topo.svg" class="w3-round" alt="Topology">
  </body>
</html>


@@upload
<!DOCTYPE html>
<html lang="en">
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <link rel="stylesheet" href="https://www.w3schools.com/w3css/4/w3.css">
  <script src="https://www.w3schools.com/lib/w3.js"></script>
  <body>
    <div class="w3-top w3-bar w3-black">
      <a href="/#ctlabs" class="w3-bar-item w3-button">CTLABS</a>
      <a href="/#con"    class="w3-bar-item w3-button">Connections</a>
      <a href="/#topo"   class="w3-bar-item w3-button">Topology</a>
      <a href="/upload"  class="w3-bar-item w3-button">Upload</a>
    </div>
    <div class="w3-container w3-teal" id="upload"></div>
      <div id="topo" class="w3-container w3-green">
        <br/><br/>
        <h2> Upload </h2>
      </div>
      <form class="w3-container" action="/upload" method="post" enctype="multipart/form-data">
        <label class="w3-text-teal"><b>Select a file:</b></label>
        <input class="w3-input w3-border" type="file" name="file" id="file"/>

        <input class="w3-btn w3-blue-grey" type="submit" value="Send File"/>
      </form>
    </div>
    <br/><br/>
    <div class="w3-container">
    <text>
      <% Dir.entries(UPLOAD_DIR, encoding: "ascii" ).each do |f| %>
        <%  if f =~ /[a-zA-Z0-9].*/ %>
          - <%= f %><br/>
        <% end %>
      <% end %>
    </div>
  </body>
</html>

