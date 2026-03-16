# -----------------------------------------------------------------------------
# File        : ctlabs/routes/misc.rb
# License     : MIT License
# -----------------------------------------------------------------------------

get '/demo' do
  erb :demo
end

get '/markdown' do
  erb :markdown
end

get '/flashcards' do
  @read_only = Lab.running?
  erb :flashcards
end

post '/flashcards/data' do
  content_type :json
  if Lab.running?
     status 403
     return { success: false, error: 'Read-Only Mode: Cannot save while Lab is running.' }.to_json
  end
  
  begin
    data = JSON.parse(request.body.read)
    public_file = '/srv/ctlabs-server/public/flashcards.json'
    if !data['set'] || !data['set']['cards'] || data['set']['cards'].empty?
      halt 400, { success: false, error: 'Cannot save empty flashcard set' }.to_json
    end
    File.write(public_file, JSON.pretty_generate(data))
    { success: true }.to_json
  rescue => e
    status 400
    { success: false, error: e.message }.to_json
  end
end

post '/upload' do
  uploaded_file = params[:file]
  return halt erb(:upload), BADREQ unless uploaded_file

  filename = uploaded_file[:tempfile].path
  if File.zero?(filename)
    return halt erb(:upload), BADREQ
  end

  FileUtils.cp(filename, UPLOAD_DIR + '/' + uploaded_file[:filename] )
  redirect '/upload'
end
