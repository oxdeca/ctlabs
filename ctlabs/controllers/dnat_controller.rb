# -----------------------------------------------------------------------------
# File        : ctlabs/controllers/dnat_controller.rb
# Description : Controller for DNAT management
# License     : MIT License
# -----------------------------------------------------------------------------

class DnatController < BaseController
  post '/labs/*/dnat' do
    lab_name = params[:splat].first
    halt 400, "AdHoc DNAT only allowed on the running lab" unless Lab.current_name == lab_name

    begin
      lab_path = Lab.get_file_path(lab_name)
      lab = Lab.new(cfg: lab_path)
      lab.add_adhoc_dnat(params[:node], params[:external_port].to_i, params[:internal_port].to_i, (params[:protocol] || 'tcp').downcase)

      data = YAML.load_file(lab_path)
      node_cfg, _ = Lab.find_node_in_raw_yaml(data['topology'][0], params[:node])

      if node_cfg
        node_cfg['dnat'] ||= []
        node_cfg['dnat'] << [params[:external_port].to_i, params[:internal_port].to_i, (params[:protocol] || 'tcp').downcase]
        LabRepository.write_formatted_yaml(lab_path, data)
      end

      content_type :json
      { success: true, message: "AdHoc DNAT rule added" }.to_json
    rescue => e
      status 400
      { success: false, error: e.message }.to_json
    end
  end

  post '/labs/*/dnat/delete' do
    lab_name = params[:splat].first
    lab_path = Lab.get_file_path(lab_name)
    begin
      yaml = YAML.load_file(lab_path)
      node = params[:node]
      node_cfg, _ = Lab.find_node_in_raw_yaml(yaml['topology'][0], node)
      dnat_rules = node_cfg['dnat'] rescue nil

      if dnat_rules
        dnat_rules.reject! { |r| r[0].to_s == params[:ext].to_s && r[1].to_s == params[:int].to_s && (r[2] || 'tcp').to_s == params[:proto].to_s }
        node_cfg.delete('dnat') if dnat_rules.empty?
        LabRepository.write_formatted_yaml(lab_path, yaml)
      end
      { success: true, message: "DNAT rule deleted." }.to_json
    rescue => e
      status 400
      { success: false, error: e.message }.to_json
    end
  end
end
