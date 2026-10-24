# -----------------------------------------------------------------------------
# File        : ctlabs/controllers/recordings_controller.rb
# Description : Serve and manage terminal walkthrough recordings (asciicast)
# License     : MIT License
# -----------------------------------------------------------------------------

require 'zip'
require 'tempfile'

class RecordingsController < BaseController
  # The Walkthrough page lives at /demo (MainController); these routes only
  # deal with the cast files themselves.

  get '/recordings' do
    redirect '/demo'
  end

  post '/recordings/upload' do
    content_type :json
    f = params[:file]
    halt 400, { ok: false }.to_json unless f && f[:tempfile]
    node = params[:node].to_s
    id = RecordingService.new_id(node.empty? ? 'terminal' : node)
    path = File.join(RecordingService::DIR, "#{id}#{RecordingService::EXT}")
    FileUtils.mkdir_p(File.dirname(path))
    FileUtils.cp(f[:tempfile].path, path)
    { ok: true, id: id }.to_json
  rescue StandardError => e
    status 500
    { ok: false, error: e.message }.to_json
  end

  get '/recordings/download-all' do
    RecordingService.ensure_dir
    files = Dir.glob(File.join(RecordingService::DIR, "*#{RecordingService::EXT}"))
    halt 404, 'No recordings found to download' if files.empty?

    # Write directly to a safe path in DIR to prevent premature Tempfile unlinking issues
    zip_filename = "ctlabs_walkthrough_#{Time.now.strftime('%Y%m%d_%H%M%S')}.zip"
    zip_path = File.join(RecordingService::DIR, zip_filename)

    Zip::File.open(zip_path, create: true) do |zipfile|
      files.each do |file|
        zipfile.add(File.basename(file), file)
      end
    end

    send_file zip_path,
              type: 'application/zip',
              disposition: 'attachment',
              filename: zip_filename
  end

  post '/recordings/import' do
    content_type :json
    f = params[:file]
    halt 400, { ok: false, error: 'No file uploaded' }.to_json unless f && f[:tempfile]

    filename = f[:filename].to_s.downcase
    RecordingService.ensure_dir

    if filename.end_with?('.zip')
      Zip::File.open(f[:tempfile].path) do |zipfile|
        zipfile.each do |entry|
          next unless entry.name.end_with?(RecordingService::EXT)
          dest_path = File.join(RecordingService::DIR, File.basename(entry.name))
          
          # Ensure target directory exists and write stream directly
          FileUtils.mkdir_p(File.dirname(dest_path))
          File.write(dest_path, entry.get_input_stream.read)
        end
      end
    elsif filename.end_with?(RecordingService::EXT)
      id = RecordingService.new_id('imported')
      dest_path = File.join(RecordingService::DIR, "#{id}#{RecordingService::EXT}")
      FileUtils.mkdir_p(File.dirname(dest_path))
      FileUtils.cp(f[:tempfile].path, dest_path)
    else
      halt 400, { ok: false, error: 'Unsupported file format. Please upload a .zip or .cast file.' }.to_json
    end

    { ok: true }.to_json
  rescue StandardError => e
    status 500
    { ok: false, error: e.message }.to_json
  end

  get '/recordings/:id' do
    path = RecordingService.path_for(params[:id])
    halt 404, 'Recording not found' unless path

    if params[:download]
      send_file path,
                filename:    File.basename(path),
                type:        'application/x-asciicast',
                disposition: 'attachment'
    else
      send_file path,
                type:        'application/x-asciicast; charset=utf-8',
                disposition: 'inline'
    end
  end

#  post '/recordings/:id/meta' do
#    halt 403, 'Invalid recording id' unless RecordingService.valid_id?(params[:id])
#    
#    title = params[:title].to_s.strip
#    RecordingService.update_meta(params[:id], title: title) if RecordingService.respond_to?(:update_meta)
#
#    redirect '/demo'
#  end

  post '/recordings/:id/meta' do
    halt 403, 'Invalid recording id' unless RecordingService.valid_id?(params[:id])

    title = params[:title].to_s.strip
    
    # Ensure update_meta only updates the title field and never touches the node identifier
    if RecordingService.respond_to?(:update_meta)
      RecordingService.update_meta(params[:id], title: title)
    end

    redirect '/demo'
  end

  post '/recordings/:id/delete' do
    halt 403, 'Invalid recording id' unless RecordingService.valid_id?(params[:id])

    deleted = RecordingService.delete(params[:id])
    halt 404, 'Recording not found' unless deleted

    redirect '/demo'
  end

  post '/recordings/reorder' do
    content_type :json
    body = request.body.read
    halt 400, { ok: false, error: 'Empty request body' }.to_json if body.empty?

    data = JSON.parse(body)
    ordered_ids = data['order']
    walkthrough_slug = data['walkthrough'] || 'default'
    
    halt 400, { ok: false, error: 'Invalid order data' }.to_json unless ordered_ids.is_a?(Array)

    if RecordingService.respond_to?(:update_walkthrough_order)
      RecordingService.update_walkthrough_order(walkthrough_slug, ordered_ids)
    elsif RecordingService.respond_to?(:reorder!)
      RecordingService.reorder!(ordered_ids)
    end

    { ok: true }.to_json
  rescue StandardError => e
    status 500
    { ok: false, error: e.message }.to_json
  end

  post '/walkthroughs/create' do
    name = params[:name].to_s.strip
    name = "New Walkthrough" if name.empty?
    slug = RecordingService.create_walkthrough(name)
    redirect "/demo?walkthrough=#{slug}"
  end
end
