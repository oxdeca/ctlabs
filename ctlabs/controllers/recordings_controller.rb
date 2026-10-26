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

    wks = RecordingService.load_walkthroughs
    target_slug = params[:walkthrough].to_s
    target_slug = session[:walkthrough].to_s if target_slug.empty? || !wks.key?(target_slug)
    target_slug = wks.keys.first.to_s if target_slug.empty? || !wks.key?(target_slug)

    if target_slug.empty?
      target_slug = RecordingService.create_walkthrough('Walkthrough 1')
      wks = RecordingService.load_walkthroughs
    end

    id = RecordingService.new_id(node.empty? ? 'terminal' : node)
    path = File.join(RecordingService::DIR, "#{id}#{RecordingService::EXT}")
    FileUtils.mkdir_p(File.dirname(path))
    FileUtils.cp(f[:tempfile].path, path)

    RecordingService.add_to_walkthrough(target_slug, [id])

    { ok: true, id: id, walkthrough: target_slug }.to_json
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

    # Custom export filename if provided
    custom_name = params[:filename].to_s.strip
    custom_name = File.basename(custom_name)
    custom_name = custom_name.gsub(/[^a-zA-Z0-9_.-]+/, '_').sub(/\A_+/, '').sub(/_+\z/, '')

    zip_filename = if !custom_name.empty? && custom_name != '.zip'
                     custom_name.downcase.end_with?('.zip') ? custom_name : "#{custom_name}.zip"
                   else
                     "ctlabs_walkthrough_#{label}_#{Time.now.strftime('%Y%m%d_%H%M%S')}.zip"
                   end

    # Clean up older export zip files (>1 hour old)
    Dir.glob(File.join(RecordingService::DIR, 'export_*_*.zip')).each do |old_zip|
      File.delete(old_zip) rescue nil if File.mtime(old_zip) < (Time.now - 3600)
    end

    zip_path = File.join(RecordingService::DIR, "export_#{SecureRandom.hex(4)}_#{zip_filename}")

    Zip::File.open(zip_path, create: true) do |zipfile|
      files.each do |rec|
        next unless File.file?(rec[:path])
        ext = File.extname(rec[:path])
        ext = RecordingService::EXT if ext.empty?
        zipfile.add("#{rec[:id]}#{ext}", rec[:path])
      end

      # Scan markdown steps for referenced pictures and include them in images/ folder
      images_to_add = {}
      files.each do |rec|
        next unless File.file?(rec[:path]) && rec[:path].end_with?(RecordingService::MD_EXT)
        content = File.read(rec[:path]) rescue ''
        content.scan(%r{(?:/recordings)?/images/([a-zA-Z0-9_.-]+)}).flatten.uniq.each do |img_name|
          img_path = RecordingService.image_path(img_name)
          images_to_add[img_name] = img_path if img_path
        end
      end

      images_to_add.each do |img_name, img_path|
        zipfile.add("images/#{img_name}", img_path)
      end

      manifest = {
        'format'         => 'ctlabs-walkthrough',
        'version'        => 1,
        'name'           => bundle[:name],
        'sealed'         => bundle[:sealed],
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

          if entry.name.end_with?(RecordingService::EXT)
            old_id = File.basename(entry.name, RecordingService::EXT)
            data   = entry.get_input_stream.read
            node   = RecordingService.node_from_cast(data) ||
                     RecordingService.node_from_id(old_id)
            id     = RecordingService.new_id(node)

            File.binwrite(File.join(RecordingService::DIR, "#{id}#{RecordingService::EXT}"), data)
            id_map[old_id] = id
            imported << id
          elsif entry.name.end_with?(RecordingService::MD_EXT)
            old_id = File.basename(entry.name, RecordingService::MD_EXT)
            data   = entry.get_input_stream.read
            id     = RecordingService.new_markdown_id('note')

            File.binwrite(File.join(RecordingService::DIR, "#{id}#{RecordingService::MD_EXT}"), data)
            id_map[old_id] = id
            imported << id
          elsif entry.name.start_with?('images/') || RecordingService::IMAGE_EXTS.include?(File.extname(entry.name).downcase)
            img_basename = File.basename(entry.name)
            target = File.join(RecordingService.ensure_images_dir, img_basename)
            File.binwrite(target, entry.get_input_stream.read)
          end
        end
      end

      walkthrough = nil
      if manifest.is_a?(Hash) && !manifest['name'].to_s.strip.empty?
        ordered = Array(manifest['recording_ids']).filter_map do |old_id|
          id_map[old_id.to_s] ||
            id_map[File.basename(old_id.to_s, RecordingService::EXT)] ||
            id_map[File.basename(old_id.to_s, RecordingService::MD_EXT)]
        end
        ordered += imported - ordered
        walkthrough = RecordingService.create_walkthrough(
          manifest['name'], recording_ids: ordered, unique: true
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
    elsif filename.end_with?(RecordingService::MD_EXT)
      data = File.binread(f[:tempfile].path)
      id   = RecordingService.new_markdown_id('note')
      File.binwrite(File.join(RecordingService::DIR, "#{id}#{RecordingService::MD_EXT}"), data)
      walkthrough = RecordingService.add_to_walkthrough(params[:walkthrough].to_s, [id])
    elsif RecordingService::IMAGE_EXTS.include?(File.extname(filename))
      saved_name = RecordingService.save_image(f[:tempfile], filename)
      return { ok: true, count: 1, image: "/recordings/images/#{saved_name}" }.to_json
    else
      halt 400, { ok: false, error: 'Unsupported file format. Please upload a .zip, .cast, .md, or image file.' }.to_json
    end

    { ok: true, walkthrough: walkthrough }.to_json
  rescue StandardError => e
    status 500
    { ok: false, error: e.message }.to_json
  end

  post '/recordings/upload-image' do
    content_type :json
    file = params[:file] || params[:image]
    halt 400, { ok: false, error: 'No image provided' }.to_json unless file && file[:tempfile]

    orig_name = file[:filename] || 'image.png'
    ext = File.extname(orig_name).downcase
    unless RecordingService::IMAGE_EXTS.include?(ext)
      halt 400, { ok: false, error: "Unsupported image format #{ext}" }.to_json
    end

    filename = RecordingService.save_image(file[:tempfile], orig_name)
    { ok: true, filename: filename, url: "/recordings/images/#{filename}" }.to_json
  rescue StandardError => e
    status 500
    { ok: false, error: e.message }.to_json
  end

  get '/recordings/images/:filename' do
    path = RecordingService.image_path(params[:filename])
    halt 404, 'Image not found' unless path

    ext = File.extname(path).downcase
    mime = case ext
           when '.png'          then 'image/png'
           when '.jpg', '.jpeg' then 'image/jpeg'
           when '.gif'          then 'image/gif'
           when '.svg'          then 'image/svg+xml'
           when '.webp'         then 'image/webp'
           else 'application/octet-stream'
           end

    send_file path, type: mime, disposition: 'inline'
  end

  get '/recordings/:id' do
    path = RecordingService.path_for(params[:id])
    halt 404, 'Recording not found' unless path

    ext = File.extname(path).downcase
    if RecordingService::IMAGE_EXTS.include?(ext)
      mime = case ext
             when '.png'          then 'image/png'
             when '.jpg', '.jpeg' then 'image/jpeg'
             when '.gif'          then 'image/gif'
             when '.svg'          then 'image/svg+xml'
             when '.webp'         then 'image/webp'
             else 'application/octet-stream'
             end
      return send_file path, type: mime, disposition: 'inline'
    end

    is_md = path.end_with?(RecordingService::MD_EXT)
    content_type_str = is_md ? 'text/markdown; charset=utf-8' : (params[:download] ? 'application/x-asciicast' : 'application/x-asciicast; charset=utf-8')
    disposition = params[:download] ? 'attachment' : 'inline'

    send_file path,
              filename:    File.basename(path),
              type:        content_type_str,
              disposition: disposition
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
    slug = wks.keys.first.to_s unless wks.key?(slug)
    redirect "/demo?walkthrough=#{slug}&recording=#{params[:id]}"
  end

  post '/recordings/:id/delete' do
    halt 403, 'Invalid recording id' unless RecordingService.valid_id?(params[:id])

    deleted = RecordingService.delete(params[:id])
    halt 404, 'Recording not found' unless deleted

    slug = params[:walkthrough].to_s
    wks  = RecordingService.load_walkthroughs
    if wks.key?(slug)
      redirect "/demo?walkthrough=#{slug}"
    else
      redirect '/demo'
    end
  end

  post '/recordings/reorder' do
    content_type :json
    body = request.body.read
    halt 400, { ok: false, error: 'Empty request body' }.to_json if body.empty?

    data = JSON.parse(body)
    ordered_ids = data['order']
    wks = RecordingService.load_walkthroughs
    walkthrough_slug = data['walkthrough'] || session[:walkthrough] || wks.keys.first.to_s
    
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
    rec = params[:recording].to_s
    redirect_url = "/demo?walkthrough=#{slug}"
    redirect_url += "&recording=#{rec}" if RecordingService.valid_id?(rec)
    redirect redirect_url
  end

  post '/walkthroughs/:slug/delete' do
    slug = params[:slug].to_s
    delete_recs = %w[1 true yes on].include?(params[:delete_recordings].to_s.downcase)
    RecordingService.delete_walkthrough(slug, delete_recordings: delete_recs)
    session.delete(:walkthrough) if session[:walkthrough] == slug
    redirect '/demo'
  end

  post '/walkthroughs/:slug/markdown' do
    slug = params[:slug].to_s
    title = params[:title].to_s.strip
    title = 'Step Note' if title.empty?
    id = RecordingService.create_markdown_step(slug, title: title)
    redirect "/demo?walkthrough=#{slug}&recording=#{id}"
  end

  get '/recordings/:id/content' do
    halt 403, 'Invalid recording id' unless RecordingService.valid_id?(params[:id])
    content = RecordingService.read_content(params[:id])
    halt 404, 'Markdown step not found' if content.nil?
    content_type 'text/plain; charset=utf-8'
    content
  end

  post '/recordings/:id/content' do
    content_type :json
    halt 403, { ok: false, error: 'Invalid recording id' }.to_json unless RecordingService.valid_id?(params[:id])

    body = request.body.read
    content = if request.media_type == 'application/json'
                begin
                  JSON.parse(body)['content'].to_s
                rescue StandardError
                  params[:content].to_s
                end
              else
                params[:content] || body
              end

    ok = RecordingService.update_content(params[:id], content)
    halt 500, { ok: false, error: 'Failed to save content' }.to_json unless ok

    path = RecordingService.path_for(params[:id])
    meta_info = path ? RecordingService.meta(path) : {}

    { ok: true, id: params[:id], title: meta_info[:title] }.to_json
  end
end
