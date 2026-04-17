# -----------------------------------------------------------------------------
# File        : ctlabs/routes/links.rb
# License     : MIT License
# -----------------------------------------------------------------------------

# ===================================================
# ROUTES
# ===================================================

post '/labs/*/link/save' do
  lab_name = params[:splat].first
  lab_path = get_lab_file_path(lab_name)
  begin
    yaml = YAML.load_file(lab_path)
    yaml['topology'][0]['links'] ||= []

    ep1 = "#{params[:node_a]}:#{params[:int_a]}"
    ep2 = "#{params[:node_b]}:#{params[:int_b]}"
    new_link = [ep1, ep2]

    if params[:old_ep1] && params[:old_ep2] && !params[:old_ep1].empty?
      if Lab.running? && Lab.current_name == lab_name
        Lab.new(cfg: lab_path, log: LabLog.null).hotunplug_link(params[:old_ep1], params[:old_ep2])
      end

      idx = yaml['topology'][0]['links'].find_index { |l| l.is_a?(Array) && l.include?(params[:old_ep1]) && l.include?(params[:old_ep2]) }
      idx ? (yaml['topology'][0]['links'][idx] = new_link) : (yaml['topology'][0]['links'] << new_link)
    else
      yaml['topology'][0]['links'] << new_link
    end

    write_formatted_yaml(lab_path, yaml)

    if Lab.running? && Lab.current_name == lab_name
      Lab.new(cfg: lab_path, log: LabLog.null).hotplug_link(ep1, ep2)
    end

    { success: true, message: "Link saved and connected successfully." }.to_json
  rescue => e
    status 400
    { success: false, error: e.message }.to_json
  end
end

post '/labs/*/link/delete' do
  lab_name = params[:splat].first
  lab_path = get_lab_file_path(lab_name)
  begin
    yaml = YAML.load_file(lab_path)
    yaml['topology'][0]['links']&.reject! { |l| l.is_a?(Array) && l.include?(params[:ep1]) && l.include?(params[:ep2]) }
    write_formatted_yaml(lab_path, yaml)

    if Lab.running? && Lab.current_name == lab_name
      Lab.new(cfg: lab_path, log: LabLog.null).hotunplug_link(params[:ep1], params[:ep2])
    end

    { success: true, message: "Link deleted and disconnected." }.to_json
  rescue => e
    status 400
    { success: false, error: e.message }.to_json
  end
end
