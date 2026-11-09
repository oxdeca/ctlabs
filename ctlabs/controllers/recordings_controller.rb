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
    target_dir = RecordingService.walkthrough_dir(target_slug)
    FileUtils.mkdir_p(target_dir)
    path = File.join(target_dir, "#{id}#{RecordingService::EXT}")
    FileUtils.cp(f[:tempfile].path, path)

    RecordingService.add_to_walkthrough(target_slug, [id])

    { ok: true, success: true, id: id, walkthrough: target_slug }.to_json
  rescue StandardError => e
    status 500
    { ok: false, error: e.message }.to_json
  end

  post '/recordings/upload-video' do
    content_type :json
    f = params[:video] || params[:file]
    halt 400, { ok: false, error: 'No video file uploaded' }.to_json unless f && f[:tempfile]

    max_video_bytes = 500 * 1024 * 1024
    halt 413, { ok: false, error: 'Uploaded video exceeds maximum allowed size of 500MB' }.to_json if f[:tempfile].size > max_video_bytes

    wks = RecordingService.load_walkthroughs
    target_slug = params[:walkthrough].to_s
    target_slug = session[:walkthrough].to_s if target_slug.empty? || !wks.key?(target_slug)
    target_slug = wks.keys.first.to_s if target_slug.empty? || !wks.key?(target_slug)

    if target_slug.empty?
      target_slug = RecordingService.create_walkthrough('Walkthrough 1')
      wks = RecordingService.load_walkthroughs
    end

    orig_name = f[:filename].to_s
    ext = File.extname(orig_name).downcase
    ext = RecordingService::VIDEO_EXT unless RecordingService::VIDEO_EXTS.include?(ext)

    id = RecordingService.new_video_id('screen')
    target_dir = RecordingService.walkthrough_dir(target_slug)
    FileUtils.mkdir_p(target_dir)
    path = File.join(target_dir, "#{id}#{ext}")
    FileUtils.cp(f[:tempfile].path, path)

    clean_title = params[:title].to_s.strip
    clean_title = 'Browser Recording' if clean_title.empty?
    duration = params[:duration].to_f

    meta = {
      'title'      => clean_title,
      'duration'   => duration,
      'created_at' => Time.now.to_i,
      'type'       => 'video'
    }
    File.write(File.join(target_dir, "#{id}.json"), JSON.pretty_generate(meta))

    RecordingService.add_to_walkthrough(target_slug, [id])

    { ok: true, success: true, id: id, walkthrough: target_slug }.to_json
  rescue StandardError => e
    status 500
    { ok: false, error: e.message }.to_json
  end

  get '/recordings/download-all' do
    RecordingService.ensure_dir
    bundle      = RecordingService.export_bundle(params[:walkthrough].to_s)
    step_files  = bundle[:recordings] || []
    unint_files = bundle[:unintegrated] || []
    all_files   = (step_files + unint_files).uniq { |rec| rec[:id] }
    halt 404, 'No recordings found to download' if all_files.empty?

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
      all_files.each do |rec|
        next unless File.file?(rec[:path])
        ext = File.extname(rec[:path])
        ext = RecordingService::EXT if ext.empty?
        if ext == RecordingService::MD_EXT
          content = File.read(rec[:path]) rescue ''
          # Rewrite /recordings/images/... to relative images/... for portable ZIP export
          rewritten_content = content.gsub(%r{(?:(?:\.?/)?(?:recordings?/+)+|(?:\./)?|/)images/([a-zA-Z0-9_.-]+)}, 'images/\1')
          zipfile.get_output_stream("#{rec[:id]}#{ext}") do |io|
            io.write(rewritten_content)
          end
        else
          zipfile.add("#{rec[:id]}#{ext}", rec[:path])
          if RecordingService::VIDEO_EXTS.include?(ext)
            sidecar = File.join(File.dirname(rec[:path]), "#{rec[:id]}.json")
            sidecar = File.join(RecordingService::DIR, "#{rec[:id]}.json") unless File.file?(sidecar)
            zipfile.add("#{rec[:id]}.json", sidecar) if File.file?(sidecar)
          end
        end
      end

      # Scan markdown steps and notes for referenced pictures and include them in images/ folder
      images_to_add = {}
      all_files.each do |rec|
        next unless File.file?(rec[:path]) && rec[:path].end_with?(RecordingService::MD_EXT)
        content = File.read(rec[:path]) rescue ''
        content.scan(%r{(?:(?:\.?/)?(?:recordings?/+)+|(?:\./)?|/)images/([a-zA-Z0-9_.-]+)}).flatten.uniq.each do |img_name|
          img_path = RecordingService.image_path(img_name, walkthrough: bundle[:slug])
          images_to_add[img_name] = img_path if img_path && File.file?(img_path)
        end
      end

      # Scan companion .dot diagram sidecars for any additional images referenced in image="..."
      sidecars_to_check = []
      images_to_add.each_value do |img_path|
        sc = File.join(File.dirname(img_path), "#{File.basename(img_path, '.*')}#{RecordingService::DOT_EXT}")
        sidecars_to_check << sc if File.file?(sc)
      end
      wk_img_dir = RecordingService.ensure_images_dir(bundle[:slug])
      Dir.glob(File.join(wk_img_dir, "*#{RecordingService::DOT_EXT}")).each do |sc|
        sidecars_to_check << sc if File.file?(sc)
      end

      sidecars_to_check.uniq.each do |sc_path|
        sc_src = File.read(sc_path, encoding: 'UTF-8') rescue ''
        sc_src.scan(/\b(?:image|src)\s*=\s*(?:"([^"]+)"|'([^']+)'|([a-zA-Z0-9_.\-\/]+))/i).each do |matches|
          ref = matches.compact.first.to_s.strip
          next if ref.empty? || ref.start_with?('data:')
          base_name = File.basename(ref)
          p = RecordingService.image_path(base_name, walkthrough: bundle[:slug])
          images_to_add[base_name] = p if p && File.file?(p)
        end
      end

      images_to_add.each do |img_name, img_path|
        zipfile.add("images/#{img_name}", img_path)
        sidecar = File.join(
          File.dirname(img_path),
          "#{File.basename(img_name, File.extname(img_name))}#{RecordingService::DOT_EXT}"
        )
        if File.file?(sidecar) && !zipfile.find_entry("images/#{File.basename(sidecar)}")
          zipfile.add("images/#{File.basename(sidecar)}", sidecar)
        end
      end

      manifest = {
        'format'           => 'ctlabs-walkthrough',
        'version'          => 1,
        'name'             => bundle[:name],
        'sealed'           => bundle[:sealed],
        'recording_ids'    => step_files.map { |rec| rec[:id] },
        'unintegrated_ids' => unint_files.map { |rec| rec[:id] },
        'exported_at'      => Time.now.utc.strftime('%Y-%m-%dT%H:%M:%SZ')
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
    raw_files = params[:files] || params['files'] || params[:file] || params['file']
    raw_files = [raw_files] unless raw_files.is_a?(Array)
    upload_files = raw_files.select { |f| f.is_a?(Hash) && f[:tempfile] }

    halt 400, { ok: false, error: 'No file uploaded' }.to_json if upload_files.empty?

    RecordingService.ensure_dir
    conflict_action = params[:conflict_action].to_s.strip # 'rename', 'overwrite'
    custom_name     = params[:custom_name].to_s.strip
    target_id       = params[:target_id].to_s.strip

    # Duplicate detection: If no explicit conflict action was specified, check against existing items in active walkthrough
    if conflict_action.empty?
      wk_slug = params[:walkthrough].to_s.strip
      wk_slug = 'default' if wk_slug.empty?
      existing_steps = RecordingService.list_for_walkthrough(wk_slug) + RecordingService.list_unintegrated_for_walkthrough(wk_slug)

      duplicate_info = nil
      upload_files.each do |f|
        break if duplicate_info
        fname = f[:filename].to_s
        fext = File.extname(fname).downcase
        fbase = File.basename(fname, '.*').strip

        if fext == '.zip'
          Zip::File.open(f[:tempfile].path) do |zipfile|
            has_manifest = zipfile.any? { |e| File.basename(e.name) == RecordingService::MANIFEST }
            next if has_manifest # walkthrough package with manifest creates its own new unique set
            zipfile.each do |entry|
              next if entry.name.start_with?('__MACOSX/') || entry.name.include?('/.') || (entry.respond_to?(:directory?) && entry.directory?)
              e_ext = File.extname(entry.name).downcase
              e_base = File.basename(entry.name, e_ext).strip
              next unless [RecordingService::MD_EXT, RecordingService::EXT, *RecordingService::VIDEO_EXTS].include?(e_ext)

              e_title = ''
              if e_ext == RecordingService::MD_EXT
                first_l = entry.get_input_stream.read(1024).to_s.lines.find { |l| !l.strip.empty? }.to_s.strip.sub(/^#+\s*/, '') rescue ''
                e_title = first_l unless first_l.empty?
              elsif e_ext == RecordingService::EXT
                hdr = entry.get_input_stream.read(1024).to_s.lines.first rescue ''
                e_title = (JSON.parse(hdr)['title'] rescue '') || ''
              end

              matched = existing_steps.find do |rec|
                rec_id = rec[:id].to_s
                rec_title = rec[:title].to_s.strip.downcase
                rec_id == e_base || rec_id == fbase ||
                  (!rec_title.empty? && rec_title != 'step note' && rec_title != 'browser recording' &&
                   (rec_title == e_base.downcase || rec_title == fbase.downcase || (!e_title.empty? && rec_title == e_title.downcase)))
              end

              if matched
                matched_title = matched[:title].to_s.strip
                matched_title = e_title unless e_title.empty?
                matched_title = e_base if matched_title.empty?
                duplicate_info = {
                  filename: fname,
                  existing_id: matched[:id],
                  existing_title: matched_title,
                  suggested_name: "#{matched_title} (1)"
                }
                break
              end
            end
          end
        elsif [RecordingService::MD_EXT, RecordingService::EXT, *RecordingService::VIDEO_EXTS].include?(fext)
          item_title = ''
          if fext == RecordingService::MD_EXT
            first_l = File.open(f[:tempfile].path, 'rb') { |io| io.read(1024) }.to_s.lines.find { |l| !l.strip.empty? }.to_s.strip.sub(/^#+\s*/, '') rescue ''
            item_title = first_l unless first_l.empty?
          elsif fext == RecordingService::EXT
            hdr = File.open(f[:tempfile].path, 'rb') { |io| io.gets }.to_s rescue ''
            item_title = (JSON.parse(hdr)['title'] rescue '') || ''
          end

          matched = existing_steps.find do |rec|
            rec_id = rec[:id].to_s
            rec_title = rec[:title].to_s.strip.downcase
            rec_id == fbase ||
              (!rec_title.empty? && rec_title != 'step note' && rec_title != 'browser recording' &&
               (rec_title == fbase.downcase || (!item_title.empty? && rec_title == item_title.downcase)))
          end

          if matched
            matched_title = matched[:title].to_s.strip
            matched_title = item_title unless item_title.empty?
            matched_title = fbase if matched_title.empty?
            duplicate_info = {
              filename: fname,
              existing_id: matched[:id],
              existing_title: matched_title,
              suggested_name: "#{matched_title} (1)"
            }
          end
        end
      end

      if duplicate_info
        return {
          ok: true,
          conflict: true,
          filename: duplicate_info[:filename],
          existing_id: duplicate_info[:existing_id],
          existing_title: duplicate_info[:existing_title],
          suggested_name: duplicate_info[:suggested_name]
        }.to_json
      end
    end

    imported = []
    walkthrough = nil
    image_count = 0
    last_saved_image = nil
    selected_id = nil
    extracted_images = []

    upload_files.each do |f|
      filename = f[:filename].to_s.downcase

      if filename.end_with?('.zip')
        id_map   = {}
        pending_sidecars = {}
        manifest = nil

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

            next if entry.name.start_with?('__MACOSX/') || entry.name.include?('/.') || (entry.respond_to?(:directory?) && entry.directory?)

            ext = File.extname(entry.name).downcase
            clean_base = File.basename(entry.name, File.extname(entry.name))

            if ext == RecordingService::EXT
              old_id = clean_base
              data   = entry.get_input_stream.read
              node   = RecordingService.node_from_cast(data) ||
                       RecordingService.node_from_id(old_id)
              id     = if conflict_action == 'overwrite' && !target_id.empty?
                         target_id
                       elsif conflict_action != 'rename' && old_id =~ /\A[a-zA-Z0-9_-]+\z/ && !RecordingService.path_for(old_id)
                         old_id
                       else
                         RecordingService.new_id(node)
                       end

              File.binwrite(File.join(RecordingService::DIR, "#{id}#{RecordingService::EXT}"), data)
              if conflict_action == 'rename' && !custom_name.empty?
                RecordingService.set_title(id, custom_name)
              end
              id_map[old_id] = id
              id_map[old_id.downcase] = id
              id_map[base] = id
              id_map[base.downcase] = id
              imported << id
            elsif ext == RecordingService::MD_EXT
              old_id = clean_base
              data   = entry.get_input_stream.read
              data   = data.force_encoding('UTF-8') rescue data
              # Update image paths from relative images/ to /recordings/images/ (and normalize any duplicate prefixes)
              data   = data.gsub(%r{(?:(?:\.?/)?(?:recordings?/+)+|(?:\./)?|/)images/([a-zA-Z0-9_.-]+)}, '/recordings/images/\1')

              if conflict_action == 'rename' && !custom_name.empty?
                if data =~ /\A(\s*#+\s*)([^\n]+)/
                  data = data.sub(/\A(\s*#+\s*)([^\n]+)/, "\\1#{custom_name}")
                else
                  data = "# #{custom_name}\n\n" + data
                end
              end

              id = if conflict_action == 'overwrite' && !target_id.empty?
                     target_id
                   elsif conflict_action != 'rename' && old_id =~ /\A[a-zA-Z0-9_-]+\z/ && !RecordingService.path_for(old_id)
                     old_id
                   else
                     RecordingService.new_markdown_id('note')
                   end

              File.binwrite(File.join(RecordingService::DIR, "#{id}#{RecordingService::MD_EXT}"), data)
              id_map[old_id] = id
              id_map[old_id.downcase] = id
              id_map[base] = id
              id_map[base.downcase] = id
              imported << id
            elsif RecordingService::VIDEO_EXTS.include?(ext)
              old_id = clean_base
              id     = if conflict_action == 'overwrite' && !target_id.empty?
                         target_id
                       elsif conflict_action != 'rename' && old_id =~ /\A[a-zA-Z0-9_-]+\z/ && !RecordingService.path_for(old_id)
                         old_id
                       else
                         RecordingService.new_video_id('screen')
                       end

              File.binwrite(File.join(RecordingService::DIR, "#{id}#{ext}"), entry.get_input_stream.read)
              id_map[old_id] = id
              id_map[old_id.downcase] = id
              id_map[base] = id
              id_map[base.downcase] = id
              imported << id
            elsif ext == '.json' && !base.start_with?('_') && base != RecordingService::MANIFEST
              old_id = clean_base
              pending_sidecars[old_id] = entry.get_input_stream.read
            elsif ext == RecordingService::DOT_EXT && (entry.name.start_with?('images/') || entry.name.include?('/images/'))
              dot_basename = base
              dot_data = entry.get_input_stream.read
              File.binwrite(File.join(RecordingService.ensure_images_dir, dot_basename), dot_data)

              wk_target = params[:walkthrough].to_s.strip
              if !wk_target.empty?
                begin
                  scoped_dir = RecordingService.ensure_images_dir(wk_target)
                  File.binwrite(File.join(scoped_dir, dot_basename), dot_data)
                rescue StandardError
                end
              end

              extracted_images << dot_basename
            elsif entry.name.start_with?('images/') || entry.name.include?('/images/') || RecordingService::IMAGE_EXTS.include?(ext)
              img_basename = base
              img_data = entry.get_input_stream.read
              target = File.join(RecordingService.ensure_images_dir, img_basename)
              File.binwrite(target, img_data)

              wk_target = params[:walkthrough].to_s.strip
              if !wk_target.empty?
                begin
                  scoped_img_dir = RecordingService.ensure_images_dir(wk_target)
                  File.binwrite(File.join(scoped_img_dir, img_basename), img_data)
                rescue StandardError
                end
              end

              extracted_images << img_basename
              image_count += 1
              last_saved_image = img_basename
            end
          end
        end

        pending_sidecars.each do |old_id, json_str|
          new_id = id_map[old_id] || id_map[old_id.downcase]
          if new_id
            if conflict_action == 'rename' && !custom_name.empty?
              begin
                parsed = JSON.parse(json_str)
                parsed['title'] = custom_name if parsed.is_a?(Hash)
                json_str = JSON.pretty_generate(parsed)
              rescue StandardError
              end
            end
            File.binwrite(File.join(RecordingService::DIR, "#{new_id}.json"), json_str)
          end
        end

        if manifest.is_a?(Hash) && !manifest['name'].to_s.strip.empty?
          lookup_id = lambda do |raw_id|
            s = raw_id.to_s.strip
            return nil if s.empty?
            id_map[s] ||
              id_map[s.downcase] ||
              id_map[File.basename(s, File.extname(s))] ||
              id_map[File.basename(s, File.extname(s)).downcase]
          end

          ordered = Array(manifest['recording_ids']).filter_map(&lookup_id)
          unint_ordered = Array(manifest['unintegrated_ids']).filter_map(&lookup_id)

          remaining = imported - ordered - unint_ordered
          unint_ordered += remaining

          walkthrough = RecordingService.create_walkthrough(
            manifest['name'],
            recording_ids: ordered,
            unintegrated_ids: unint_ordered,
            unique: true
          )
          target_dir = RecordingService.walkthrough_dir(walkthrough)
          (ordered + unint_ordered).each do |rec_id|
            p = RecordingService.path_for(rec_id)
            if p && File.file?(p) && File.dirname(p) != target_dir
              ext = File.extname(p)
              FileUtils.mv(p, File.join(target_dir, "#{rec_id}#{ext}")) rescue nil
              sc = File.join(File.dirname(p), "#{rec_id}.json")
              FileUtils.mv(sc, File.join(target_dir, "#{rec_id}.json")) if File.file?(sc)
            end
          end
          begin
            wk_img_dir = RecordingService.ensure_images_dir(walkthrough)
            extracted_images.each do |img_name|
              src_img = File.join(RecordingService.ensure_images_dir, img_name)
              dst_img = File.join(wk_img_dir, img_name)
              if File.file?(src_img) && src_img != dst_img
                FileUtils.cp(src_img, dst_img) unless File.exist?(dst_img)
                File.delete(src_img) rescue nil
              end
            end
          rescue StandardError
          end
          selected_id = ordered.first unless ordered.empty?
        end

        # Rewrite any step references (#step-<old_id>, step:<old_id>, /recordings/<old_id>)
        # in markdown notes if any IDs were remapped
        remapped = id_map.select do |k, v|
          k != v && !k.to_s.empty? && !v.to_s.empty? && k =~ /\A[a-zA-Z0-9_-]+\z/
        end
        if remapped.any?
          md_paths = []
          if walkthrough && !walkthrough.empty?
            target_dir = RecordingService.walkthrough_dir(walkthrough)
            md_paths += Dir.glob(File.join(target_dir, "*#{RecordingService::MD_EXT}"))
          end
          imported.each do |rec_id|
            p = RecordingService.path_for(rec_id)
            md_paths << p if p && p.end_with?(RecordingService::MD_EXT)
          end
          md_paths.uniq.each do |md_file|
            next unless File.file?(md_file)
            content = File.read(md_file, encoding: 'UTF-8') rescue nil
            next unless content
            modified = false
            remapped.each do |old_id, new_id|
              pattern = /(#step-|step:|\/recordings\/)#{Regexp.escape(old_id)}(?:\.(cast|md|webm|mp4))?(?=[^a-zA-Z0-9_.-]|\z)/
              new_content = content.gsub(pattern) do
                prefix = $1
                ext_part = $2 ? ".#{$2}" : ""
                "#{prefix}#{new_id}#{ext_part}"
              end
              if new_content != content
                content = new_content
                modified = true
              end
            end
            File.write(md_file, content, encoding: 'UTF-8') if modified
          end
        end
      elsif filename.end_with?(RecordingService::EXT)
        data = File.binread(f[:tempfile].path)
        node = RecordingService.node_from_cast(data) ||
               RecordingService.node_from_id(File.basename(f[:filename].to_s, '.*'))
        old_id = File.basename(f[:filename].to_s, '.*')
        id   = if conflict_action == 'overwrite' && !target_id.empty?
                 target_id
               elsif conflict_action != 'rename' && old_id =~ /\A[a-zA-Z0-9_-]+\z/ && !RecordingService.path_for(old_id)
                 old_id
               else
                 RecordingService.new_id(node)
               end
        File.binwrite(File.join(RecordingService::DIR, "#{id}#{RecordingService::EXT}"), data)

        if conflict_action == 'rename' && !custom_name.empty?
          RecordingService.set_title(id, custom_name)
        else
          begin
            header_json = JSON.parse(data.to_s.lines.first)
            if header_json.is_a?(Hash) && header_json['title'].to_s.strip.empty?
              base_name = File.basename(f[:filename].to_s, '.*').tr('_-', ' ').strip
              RecordingService.set_title(id, base_name) unless base_name.empty?
            end
          rescue StandardError
            # ignore
          end
        end

        imported << id
      elsif filename.end_with?(RecordingService::MD_EXT)
        data = File.binread(f[:tempfile].path)
        data = data.force_encoding('UTF-8') rescue data
        # Update image paths from relative images/ to /recordings/images/ (and normalize any duplicate prefixes)
        data = data.gsub(%r{(?:(?:\.?/)?(?:recordings?/+)+|(?:\./)?|/)images/([a-zA-Z0-9_.-]+)}, '/recordings/images/\1')

        if conflict_action == 'rename' && !custom_name.empty?
          if data =~ /\A(\s*#+\s*)([^\n]+)/
            data = data.sub(/\A(\s*#+\s*)([^\n]+)/, "\\1#{custom_name}")
          else
            data = "# #{custom_name}\n\n" + data
          end
        end

        old_id = File.basename(f[:filename].to_s, '.*')
        id = if conflict_action == 'overwrite' && !target_id.empty?
               target_id
             elsif conflict_action != 'rename' && old_id =~ /\A[a-zA-Z0-9_-]+\z/ && !RecordingService.path_for(old_id)
               old_id
             else
               RecordingService.new_markdown_id('note')
             end
        File.binwrite(File.join(RecordingService::DIR, "#{id}#{RecordingService::MD_EXT}"), data)
        imported << id
      elsif RecordingService::VIDEO_EXTS.include?(File.extname(filename))
        vext = File.extname(filename).downcase
        old_id = File.basename(f[:filename].to_s, '.*')
        id = if conflict_action == 'overwrite' && !target_id.empty?
               target_id
             elsif conflict_action != 'rename' && old_id =~ /\A[a-zA-Z0-9_-]+\z/ && !RecordingService.path_for(old_id)
               old_id
             else
               RecordingService.new_video_id('screen')
             end
        File.binwrite(File.join(RecordingService::DIR, "#{id}#{vext}"), File.binread(f[:tempfile].path))
        base_name = if conflict_action == 'rename' && !custom_name.empty?
                      custom_name
                    else
                      File.basename(f[:filename].to_s, '.*').tr('_-', ' ').strip
                    end
        base_name = 'Browser Recording' if base_name.empty?
        meta = {
          'title'      => base_name,
          'duration'   => 0.0,
          'created_at' => Time.now.to_i,
          'type'       => 'video'
        }
        File.write(File.join(RecordingService::DIR, "#{id}.json"), JSON.pretty_generate(meta))
        imported << id
      elsif RecordingService::IMAGE_EXTS.include?(File.extname(filename))
        last_saved_image = RecordingService.save_image(f[:tempfile], filename, walkthrough: params[:walkthrough].to_s)
        image_count += 1
      end
    end

    if imported.empty? && image_count.zero?
      halt 400, { ok: false, error: 'Unsupported file format. Please upload a .zip, .cast, .md, video (.webm, .mp4), or image file.' }.to_json
    end

    if upload_files.size == 1 && image_count == 1 && imported.empty?
      return { ok: true, count: 1, image: "/recordings/images/#{last_saved_image}" }.to_json
    end

    if !imported.empty? && walkthrough.nil?
      walkthrough = RecordingService.add_to_walkthrough(params[:walkthrough].to_s, imported)
    end

    if !extracted_images.empty? && walkthrough
      begin
        wk_img_dir = RecordingService.ensure_images_dir(walkthrough)
        extracted_images.each do |img_name|
          src_img = File.join(RecordingService.ensure_images_dir, img_name)
          dst_img = File.join(wk_img_dir, img_name)
          FileUtils.cp(src_img, dst_img) if File.file?(src_img) && !File.exist?(dst_img)
        end
      rescue StandardError
      end
    end

    RecordingGitService.commit("Import files#{walkthrough ? " into '#{walkthrough}'" : ''}") rescue nil

    { ok: true, count: imported.size, imported: imported, selected: (selected_id || imported.first), walkthrough: walkthrough }.to_json
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

    wk_slug = params[:walkthrough].to_s.strip
    wk_slug = session[:walkthrough].to_s.strip if wk_slug.empty?
    filename = RecordingService.save_image(file[:tempfile], orig_name, walkthrough: wk_slug)
    { ok: true, filename: filename, url: "/recordings/images/#{filename}" }.to_json
  rescue StandardError => e
    status 500
    { ok: false, error: e.message }.to_json
  end

  post '/recordings/save-annotated-image' do
    content_type :json
    file = params[:file] || params[:image]
    halt 400, { ok: false, error: 'No image provided' }.to_json unless file && file[:tempfile]

    filename = params[:filename].to_s.strip
    halt 400, { ok: false, error: 'No filename provided' }.to_json if filename.empty?

    mode = params[:mode].to_s.downcase
    mode = 'overwrite' unless %w[overwrite copy].include?(mode)

    wk_slug = params[:walkthrough].to_s.strip
    wk_slug = session[:walkthrough].to_s.strip if wk_slug.empty?

    result = RecordingService.save_annotated_image(
      file[:tempfile],
      filename,
      walkthrough: wk_slug,
      mode: mode
    )

    halt 422, { ok: false, error: 'Failed to save annotated image' }.to_json unless result

    cache_bust = Time.now.to_i
    {
      ok: true,
      filename: result[:filename],
      mode: result[:mode],
      url: "/recordings/images/#{result[:filename]}?t=#{cache_bust}",
      clean_url: "/recordings/images/#{result[:filename]}"
    }.to_json
  rescue StandardError => e
    status 500
    { ok: false, error: e.message }.to_json
  end

  post '/recordings/graphviz/preview' do
    content_type :json
    engine = params[:engine].to_s
    wk = params[:walkthrough].to_s.strip
    wk = session[:walkthrough].to_s.strip if wk.empty?
    result = GraphvizService.render(params[:source].to_s, format: 'svg', engine: engine, walkthrough: wk)
    unless result[:ok]
      status 422
      return { ok: false, error: result[:error] }.to_json
    end

    { ok: true, svg: result[:data].dup.force_encoding('UTF-8') }.to_json
  rescue StandardError => e
    status 500
    { ok: false, error: e.message }.to_json
  end

  post '/recordings/graphviz' do
    content_type :json
    source = params[:source].to_s
    format = params[:format].to_s.downcase
    format = 'svg' unless GraphvizService::FORMATS.include?(format)
    engine = params[:engine].to_s
    base   = params[:base].to_s.strip
    name   = params[:name].to_s.strip
    name   = 'diagram' if name.empty?

    wk = params[:walkthrough].to_s.strip
    wk = session[:walkthrough].to_s.strip if wk.empty?

    result = GraphvizService.render(source, format: format, engine: engine, walkthrough: wk)
    unless result[:ok]
      status 422
      return { ok: false, error: result[:error] }.to_json
    end

    saved = RecordingService.save_diagram(
      result[:data], name,
      walkthrough: wk, source: source, format: format, base: base
    )

    {
      ok:       true,
      filename: saved['filename'],
      base:     saved['base'],
      url:      "/recordings/images/#{saved['filename']}"
    }.to_json
  rescue StandardError => e
    status 500
    { ok: false, error: e.message }.to_json
  end

  get '/recordings/images/:filename' do
    headers 'Access-Control-Allow-Origin' => '*'
    path = RecordingService.image_path(params[:filename])
    halt 404, 'Image not found' unless path

    ext = File.extname(path).downcase
    mime = case ext
           when '.png'          then 'image/png'
           when '.jpg', '.jpeg' then 'image/jpeg'
           when '.gif'          then 'image/gif'
           when '.svg'
             magic = (File.binread(path, 8) rescue '')
             magic.start_with?("\x89PNG".b) ? 'image/png' : 'image/svg+xml'
           when '.webp'         then 'image/webp'
           when '.jxl'          then 'image/jxl'
           else 'application/octet-stream'
           end

    send_file path, type: mime, disposition: 'inline'
  end

  get '/recordings/:walkthrough/images/:filename' do
    headers 'Access-Control-Allow-Origin' => '*'
    path = RecordingService.image_path(params[:filename], walkthrough: params[:walkthrough])
    halt 404, 'Image not found' unless path

    ext = File.extname(path).downcase
    mime = case ext
           when '.png'          then 'image/png'
           when '.jpg', '.jpeg' then 'image/jpeg'
           when '.gif'          then 'image/gif'
           when '.svg'
             magic = (File.binread(path, 8) rescue '')
             magic.start_with?("\x89PNG".b) ? 'image/png' : 'image/svg+xml'
           when '.webp'         then 'image/webp'
           when '.jxl'          then 'image/jxl'
           else 'application/octet-stream'
           end

    send_file path, type: mime, disposition: 'inline'
  end

  get %r{/recordings(?:/recordings)+/images/(.+)} do |filename|
    redirect "/recordings/images/#{filename}"
  end

  get '/recordings/:id' do
    headers 'Access-Control-Allow-Origin' => '*'
    path = RecordingService.path_for(params[:id])
    halt 404, 'Recording not found' unless path

    ext = File.extname(path).downcase
    if RecordingService::IMAGE_EXTS.include?(ext)
      mime = case ext
             when '.png'          then 'image/png'
             when '.jpg', '.jpeg' then 'image/jpeg'
             when '.gif'          then 'image/gif'
             when '.svg'
               magic = (File.binread(path, 8) rescue '')
               magic.start_with?("\x89PNG".b) ? 'image/png' : 'image/svg+xml'
             when '.webp'         then 'image/webp'
             when '.jxl'          then 'image/jxl'
             else 'application/octet-stream'
             end
      return send_file path, type: mime, disposition: 'inline'
    end

    if RecordingService::VIDEO_EXTS.include?(ext)
      mime = (ext == '.mp4') ? 'video/mp4' : 'video/webm'
      disposition = params[:download] ? 'attachment' : 'inline'
      return send_file path,
                       filename:    File.basename(path),
                       type:        mime,
                       disposition: disposition
    end

    is_md = path.end_with?(RecordingService::MD_EXT)
    if is_md && (params[:bundle] == '1' || params[:format] == 'zip')
      custom_name = params[:filename].to_s.strip
      custom_name = File.basename(custom_name)
      custom_name = custom_name.gsub(/[^a-zA-Z0-9_.-]+/, '_').sub(/\A_+/, '').sub(/_+\z/, '')

      base_name = if !custom_name.empty? && custom_name != '.zip'
                    File.basename(custom_name, '.*')
                  else
                    File.basename(path, RecordingService::MD_EXT)
                  end

      zip_filename = if !custom_name.empty? && custom_name != '.zip'
                       custom_name.downcase.end_with?('.zip') ? custom_name : "#{custom_name}.zip"
                     else
                       "#{base_name}.zip"
                     end

      # Clean up older export note zip files (>1 hour old)
      Dir.glob(File.join(RecordingService::DIR, 'export_note_*_*.zip')).each do |old_zip|
        File.delete(old_zip) rescue nil if File.mtime(old_zip) < (Time.now - 3600)
      end

      zip_path = File.join(RecordingService::DIR, "export_note_#{SecureRandom.hex(4)}_#{zip_filename}")

      content = File.read(path) rescue ''
      rewritten_content = content.gsub(%r{(?:(?:\.?/)?(?:recordings?/+)+|(?:\./)?|/)images/([a-zA-Z0-9_.-]+)}, 'images/\1')

      walkthrough = params[:walkthrough].to_s.strip
      walkthrough = RecordingService.walkthrough_for(path) if walkthrough.empty?
      images_to_add = {}
      content.scan(%r{(?:(?:\.?/)?(?:recordings?/+)+|(?:\./)?|/)images/([a-zA-Z0-9_.-]+)}).flatten.uniq.each do |img_name|
        img_path = RecordingService.image_path(img_name, walkthrough: walkthrough)
        images_to_add[img_name] = img_path if img_path && File.file?(img_path)
      end

      Zip::File.open(zip_path, create: true) do |zipfile|
        zipfile.get_output_stream("#{base_name}.md") do |io|
          io.write(rewritten_content)
        end
        images_to_add.each do |img_name, img_path|
          zipfile.add("images/#{img_name}", img_path)
          sidecar = File.join(
            File.dirname(img_path),
            "#{File.basename(img_name, File.extname(img_name))}#{RecordingService::DOT_EXT}"
          )
          if File.file?(sidecar)
            zipfile.add("images/#{File.basename(sidecar)}", sidecar)
          end
        end
      end

      return send_file zip_path,
                       filename:    zip_filename,
                       type:        'application/zip',
                       disposition: 'attachment'
    end

    content_type_str = is_md ? 'text/markdown; charset=utf-8' : (params[:download] ? 'application/x-asciicast' : 'application/x-asciicast; charset=utf-8')
    disposition = params[:download] ? 'attachment' : 'inline'

    download_filename = File.basename(path)
    if params[:download] && !params[:filename].to_s.strip.empty?
      custom_name = params[:filename].to_s.strip
      custom_name = File.basename(custom_name)
      custom_name = custom_name.gsub(/[^a-zA-Z0-9_.-]+/, '_').sub(/\A_+/, '').sub(/_+\z/, '')
      if !custom_name.empty?
        ext = is_md ? RecordingService::MD_EXT : RecordingService::EXT
        download_filename = custom_name.downcase.end_with?(ext) ? custom_name : "#{custom_name}#{ext}"
      end
    end

    send_file path,
              filename:    download_filename,
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
    session.delete("last_recording_#{slug}") if session["last_recording_#{slug}"] == params[:id]

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

  get '/walkthroughs/:slug/images/inventory' do
    content_type :json
    RecordingService.image_inventory(params[:slug].to_s).to_json
  rescue StandardError => e
    status 500
    { ok: false, error: e.message }.to_json
  end

  post '/walkthroughs/:slug/images/delete' do
    content_type :json
    filename = params[:filename].to_s
    ok = RecordingService.delete_image(params[:slug].to_s, filename)
    status ok ? 200 : 422
    { ok: ok, filename: filename }.to_json
  rescue StandardError => e
    status 500
    { ok: false, error: e.message }.to_json
  end

  post '/walkthroughs/:slug/images/delete-unused' do
    content_type :json
    count = RecordingService.delete_unused_images(params[:slug].to_s)
    { ok: true, deleted: count }.to_json
  rescue StandardError => e
    status 500
    { ok: false, error: e.message }.to_json
  end

  get '/walkthroughs/:slug/graphviz/sources' do
    content_type :json
    RecordingService.diagram_sources(params[:slug].to_s).to_json
  rescue StandardError => e
    status 500
    { ok: false, error: e.message }.to_json
  end

  get '/walkthroughs/:slug/graphviz/sources/:base' do
    content_type :json
    source = RecordingService.diagram_source(params[:slug].to_s, params[:base].to_s)
    halt 404, { ok: false, error: 'Diagram not found' }.to_json unless source

    { ok: true, base: params[:base].to_s, source: source }.to_json
  rescue StandardError => e
    status 500
    { ok: false, error: e.message }.to_json
  end

  post '/walkthroughs/:slug/graphviz/sources/:base/delete' do
    content_type :json
    slug = params[:slug].to_s
    base = params[:base].to_s.strip
    halt 400, { ok: false, error: 'Invalid diagram name' }.to_json unless RecordingService.diagram_base_valid?(base)

    key, = RecordingService.walkthrough_entry(slug)
    scoped_dir = RecordingService.ensure_images_dir(key)

    svg_name = "#{base}.svg"
    png_name = "#{base}.png"

    # Check if used by any markdown note in this set
    refs = RecordingService.image_references(key)
    if refs.key?(svg_name) || refs.key?(png_name)
      status 422
      return { ok: false, error: 'Diagram is in use and cannot be deleted.' }.to_json
    end

    deleted = false
    [svg_name, png_name].each do |fname|
      deleted = true if RecordingService.delete_image(key, fname)
    end

    # Also remove .dot if it was orphaned without an image
    dot_file = File.join(scoped_dir, "#{base}#{RecordingService::DOT_EXT}")
    if File.file?(dot_file)
      File.delete(dot_file)
      deleted = true
    end

    global_dot = File.join(RecordingService.ensure_images_dir, "#{base}#{RecordingService::DOT_EXT}")
    unless RecordingService.other_sets_reference_image?(svg_name, except_slug: key) ||
           RecordingService.other_sets_reference_image?(png_name, except_slug: key)
      File.delete(global_dot) if File.file?(global_dot)
    end

    if deleted
      { ok: true }.to_json
    else
      status 404
      { ok: false, error: 'Diagram not found' }.to_json
    end
  rescue StandardError => e
    status 500
    { ok: false, error: e.message }.to_json
  end

  post '/recordings/:id/active' do
    slug = params[:walkthrough].to_s
    if RecordingService.valid_id?(params[:id])
      session["last_recording_#{slug}"] = params[:id].to_s unless slug.empty?
    end
    content_type :json
    { ok: true }.to_json
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

  # --- Git Versioning Endpoints ---

  get '/recordings/git/history' do
    content_type :json
    slug = params[:walkthrough] || params[:slug]
    path = params[:path]
    limit = params[:limit] || 40
    commits = RecordingGitService.history(slug: slug, path: path, limit: limit)
    { ok: true, commits: commits }.to_json
  rescue StandardError => e
    status 500
    { ok: false, error: e.message }.to_json
  end

  get '/recordings/git/diff/:hash' do
    content_type :json
    result = RecordingGitService.diff(params[:hash])
    unless result[:ok]
      status 422
      return result.to_json
    end
    result.to_json
  rescue StandardError => e
    status 500
    { ok: false, error: e.message }.to_json
  end

  get '/recordings/git/show' do
    content_type :json
    hash = params[:hash].to_s.strip
    path = params[:path].to_s.strip
    slug = params[:walkthrough] || params[:slug]
    result = RecordingGitService.show_file(hash, path, slug: slug)
    unless result[:ok]
      status 422
      return result.to_json
    end
    result.to_json
  rescue StandardError => e
    status 500
    { ok: false, error: e.message }.to_json
  end

  post '/recordings/git/snapshot' do
    content_type :json
    msg = params[:message].to_s.strip
    msg = "Manual snapshot: #{Time.now.strftime('%Y-%m-%d %H:%M:%S')}" if msg.empty?
    result = RecordingGitService.commit(msg)
    unless result[:ok]
      status 422
      return result.to_json
    end
    result.to_json
  rescue StandardError => e
    status 500
    { ok: false, error: e.message }.to_json
  end

  post '/recordings/git/restore' do
    content_type :json
    hash = params[:hash].to_s.strip
    path = params[:path].to_s.strip
    slug = params[:walkthrough] || params[:slug]
    msg = params[:message]
    result = RecordingGitService.restore_file(hash, path, slug: slug, message: msg)
    unless result[:ok]
      status 422
      return result.to_json
    end
    result.to_json
  rescue StandardError => e
    status 500
    { ok: false, error: e.message }.to_json
  end

  get '/recordings/git/status' do
    content_type :json
    result = RecordingGitService.status
    result.to_json
  rescue StandardError => e
    status 500
    { ok: false, error: e.message }.to_json
  end
end
