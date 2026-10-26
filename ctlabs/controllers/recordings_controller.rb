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
    bundle = RecordingService.export_bundle(params[:walkthrough].to_s)
    files  = bundle[:recordings]
    halt 404, 'No recordings found to download' if files.empty?

    label = RecordingService.node_slug(bundle[:name])
    label = bundle[:slug] if label.empty?
    label = 'walkthrough' if label.empty?

    # Write directly to a safe path in DIR to prevent premature Tempfile unlinking issues
    zip_filename = "ctlabs_walkthrough_#{label}_#{Time.now.strftime('%Y%m%d_%H%M%S')}.zip"
    zip_path = File.join(RecordingService::DIR, zip_filename)

    Zip::File.open(zip_path, create: true) do |zipfile|
      files.each do |rec|
        next unless File.file?(rec[:path])
        zipfile.add("#{rec[:id]}#{RecordingService::EXT}", rec[:path])
      end

      manifest = {
        'format'         => 'ctlabs-walkthrough',
        'version'        => 1,
        'name'           => bundle[:name],
        'recording_ids'  => files.map { |rec| rec[:id] },
        'exported_at'    => Time.now.utc.strftime('%Y-%m-%dT%H:%M:%SZ')
      }
      zipfile.get_output_stream(RecordingService::MANIFEST) do |io|
        io.write(JSON.pretty_generate(manifest))
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
      imported   = []
      id_map     = {}
      manifest   = nil

      Zip::File.open(f[:tempfile].path) do |zipfile|
        zipfile.each do |entry|
          base = File.basename(entry.name)

          if base == RecordingService::MANIFEST
            manifest = begin
              JSON.parse(entry.get_input_stream.read)
            rescue StandardError
              nil
            end
            next
          end
          next unless entry.name.end_with?(RecordingService::EXT)

          old_id = File.basename(entry.name, RecordingService::EXT)
          data   = entry.get_input_stream.read
          node   = RecordingService.node_from_cast(data) ||
                   RecordingService.node_from_id(old_id)
          id     = RecordingService.new_id(node)

          File.binwrite(File.join(RecordingService::DIR, "#{id}#{RecordingService::EXT}"), data)
          id_map[old_id] = id
          imported << id
        end
      end

      walkthrough = nil
      if manifest.is_a?(Hash) && !manifest['name'].to_s.strip.empty?
        ordered = Array(manifest['recording_ids']).filter_map do |old_id|
          id_map[old_id.to_s] || id_map[File.basename(old_id.to_s, RecordingService::EXT)]
        end
        ordered += imported - ordered
        walkthrough = RecordingService.create_walkthrough(
          manifest['name'], recording_ids: ordered, sealed: true, unique: true
        )
      elsif !imported.empty?
        walkthrough = RecordingService.add_to_walkthrough(params[:walkthrough].to_s, imported)
      end
    elsif filename.end_with?(RecordingService::EXT)
      data = File.binread(f[:tempfile].path)
      node = RecordingService.node_from_cast(data) ||
             RecordingService.node_from_id(File.basename(f[:filename].to_s, '.*'))
      id   = RecordingService.new_id(node)
      File.binwrite(File.join(RecordingService::DIR, "#{id}#{RecordingService::EXT}"), data)
      walkthrough = RecordingService.add_to_walkthrough(params[:walkthrough].to_s, [id])
    else
      halt 400, { ok: false, error: 'Unsupported file format. Please upload a .zip or .cast file.' }.to_json
    end

    { ok: true, walkthrough: walkthrough }.to_json
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

    wks  = RecordingService.load_walkthroughs
    slug = params[:walkthrough].to_s
    slug = 'default' unless wks.key?(slug)
    redirect "/demo?walkthrough=#{slug}&recording=#{params[:id]}"
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

  post '/walkthroughs/:slug/rename' do
    slug, = RecordingService.rename_walkthrough(params[:slug].to_s, params[:name].to_s)
    redirect "/demo?walkthrough=#{slug}"
  end
end
