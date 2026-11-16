# -----------------------------------------------------------------------------
# File        : ctlabs/controllers/walkthrough_git_controller.rb
# Description : JSON endpoints for walkthrough repository & git sync
# License     : MIT License
# -----------------------------------------------------------------------------

class WalkthroughGitController < BaseController
  helpers do
    def walkthrough_git_params
      if request.media_type == 'application/json'
        body = request.body.read
        request.body.rewind if request.body.respond_to?(:rewind)
        JSON.parse(body) rescue {}
      else
        params
      end
    end

    def walkthrough_git_respond(result, error_status: 422)
      content_type :json
      status(result[:ok] ? 200 : error_status)
      result.to_json
    end
  end

  # --- Repository Container Endpoints (Multiple Sets per Repository) ---------

  get '/repositories' do
    walkthrough_git_respond({
      ok: true,
      active: RecordingService.active_repo,
      active_name: RecordingService.active_repo_name,
      repositories: RecordingService.repositories_summary
    })
  rescue StandardError => e
    walkthrough_git_respond({ ok: false, error: e.message }, error_status: 500)
  end

  post '/repositories/switch' do
    data = walkthrough_git_params
    target = (data['repo'] || data[:repo] || data['slug'] || data[:slug]).to_s.strip
    unless RecordingService.switch_repository(target)
      return walkthrough_git_respond({ ok: false, error: "Repository '#{target}' not found" }, error_status: 404)
    end

    wks = RecordingService.load_walkthroughs
    first_set = wks.keys.first.to_s
    session[:walkthrough] = first_set

    walkthrough_git_respond({
      ok: true,
      repo: RecordingService.active_repo,
      repo_name: RecordingService.active_repo_name,
      walkthrough: first_set,
      repositories: RecordingService.repositories_summary
    })
  rescue StandardError => e
    walkthrough_git_respond({ ok: false, error: e.message }, error_status: 500)
  end

  post '/repositories/create' do
    data = walkthrough_git_params
    name = (data['name'] || data[:name]).to_s.strip
    slug = (data['slug'] || data[:slug]).to_s.strip
    url = (data['url'] || data[:url]).to_s.strip
    branch = (data['branch'] || data[:branch]).to_s.strip

    if name.empty? && slug.empty?
      return walkthrough_git_respond({ ok: false, error: 'Repository name is required' })
    end

    repo_slug = RecordingService.create_repository(name.empty? ? slug : name, slug: (slug.empty? ? nil : slug), switch: true)
    auth = data['auth'] || data[:auth]
    if !url.empty? || (auth && !auth.empty?)
      remote_res = WalkthroughGitService.set_remote(repo_slug, url: url, branch: branch, auth: auth)
      unless remote_res[:ok]
        return walkthrough_git_respond(remote_res)
      end
    end

    wks = RecordingService.load_walkthroughs
    first_set = wks.keys.first.to_s
    session[:walkthrough] = first_set

    walkthrough_git_respond({
      ok: true,
      repo: repo_slug,
      repo_name: RecordingService.active_repo_name,
      walkthrough: first_set,
      repositories: RecordingService.repositories_summary
    })
  rescue StandardError => e
    walkthrough_git_respond({ ok: false, error: e.message }, error_status: 500)
  end

  post '/repositories/:repo/rename' do
    data = walkthrough_git_params
    new_name = (data['name'] || data[:name]).to_s.strip
    return walkthrough_git_respond({ ok: false, error: 'New repository name is required' }) if new_name.empty?

    res = RecordingService.rename_repository(params[:repo], new_name)
    return walkthrough_git_respond({ ok: false, error: 'Repository not found' }, error_status: 404) unless res

    walkthrough_git_respond({
      ok: true,
      repo: res[0],
      repo_name: res[1],
      repositories: RecordingService.repositories_summary
    })
  rescue StandardError => e
    walkthrough_git_respond({ ok: false, error: e.message }, error_status: 500)
  end

  post '/repositories/:repo/delete' do
    rslug = params[:repo].to_s.strip
    if rslug == 'default'
      return walkthrough_git_respond({ ok: false, error: 'The default Local Workspace repository cannot be deleted' })
    end

    unless RecordingService.delete_repository(rslug)
      return walkthrough_git_respond({ ok: false, error: 'Repository not found' }, error_status: 404)
    end

    wks = RecordingService.load_walkthroughs
    first_set = wks.keys.first.to_s
    session[:walkthrough] = first_set

    walkthrough_git_respond({
      ok: true,
      deleted: rslug,
      repo: RecordingService.active_repo,
      repo_name: RecordingService.active_repo_name,
      walkthrough: first_set,
      repositories: RecordingService.repositories_summary
    })
  rescue StandardError => e
    walkthrough_git_respond({ ok: false, error: e.message }, error_status: 500)
  end

  # --- Git Sync Endpoints (Operate on Active Repository) ---------------------

  get '/walkthroughs/:slug/git/status' do
    walkthrough_git_respond(WalkthroughGitService.status(params[:slug]))
  rescue StandardError => e
    walkthrough_git_respond({ ok: false, error: e.message }, error_status: 500)
  end

  post '/walkthroughs/git/clone' do
    data = walkthrough_git_params
    result = WalkthroughGitService.clone(
      url: data['url'] || data[:url],
      branch: data['branch'] || data[:branch],
      name: data['name'] || data[:name],
      slug: data['slug'] || data[:slug],
      auth: data['auth'] || data[:auth]
    )
    if result[:ok] && result[:slug]
      session[:walkthrough] = result[:slug]
    end
    walkthrough_git_respond(result)
  rescue StandardError => e
    walkthrough_git_respond({ ok: false, error: e.message }, error_status: 500)
  end

  post '/walkthroughs/:slug/git/remote' do
    data = walkthrough_git_params
    result = WalkthroughGitService.set_remote(
      params[:slug],
      url: data['url'] || data[:url],
      branch: data['branch'] || data[:branch],
      auth: data['auth'] || data[:auth]
    )
    walkthrough_git_respond(result)
  rescue StandardError => e
    walkthrough_git_respond({ ok: false, error: e.message }, error_status: 500)
  end

  post '/walkthroughs/git/key/generate' do
    data = walkthrough_git_params
    slug = (data['slug'] || data[:slug] || data['repo'] || data[:repo] || 'key').to_s.strip
    passphrase = (data['passphrase'] || data[:passphrase]).to_s
    result = WalkthroughGitService.generate_ssh_key(slug, passphrase: passphrase)
    walkthrough_git_respond(result)
  rescue StandardError => e
    walkthrough_git_respond({ ok: false, error: e.message }, error_status: 500)
  end

  post '/walkthroughs/:slug/git/key/generate' do
    data = walkthrough_git_params
    slug = (data['slug'] || data[:slug] || params[:slug] || 'key').to_s.strip
    passphrase = (data['passphrase'] || data[:passphrase]).to_s
    result = WalkthroughGitService.generate_ssh_key(slug, passphrase: passphrase)
    walkthrough_git_respond(result)
  rescue StandardError => e
    walkthrough_git_respond({ ok: false, error: e.message }, error_status: 500)
  end

  post '/walkthroughs/:slug/git/fetch' do
    walkthrough_git_respond(WalkthroughGitService.fetch(params[:slug]))
  rescue StandardError => e
    walkthrough_git_respond({ ok: false, error: e.message }, error_status: 500)
  end

  post '/walkthroughs/:slug/git/pull' do
    data = walkthrough_git_params
    result = WalkthroughGitService.pull(params[:slug], branch: data['branch'] || data[:branch])
    walkthrough_git_respond(result)
  rescue StandardError => e
    walkthrough_git_respond({ ok: false, error: e.message }, error_status: 500)
  end

  post '/walkthroughs/:slug/git/push' do
    data = walkthrough_git_params
    result = WalkthroughGitService.push(
      params[:slug],
      message: data['message'] || data[:message],
      branch: data['branch'] || data[:branch]
    )
    walkthrough_git_respond(result)
  rescue StandardError => e
    walkthrough_git_respond({ ok: false, error: e.message }, error_status: 500)
  end

  post '/walkthroughs/:slug/git/commit' do
    data = walkthrough_git_params
    result = WalkthroughGitService.commit(
      params[:slug],
      message: data['message'] || data[:message]
    )
    walkthrough_git_respond(result)
  rescue StandardError => e
    walkthrough_git_respond({ ok: false, error: e.message }, error_status: 500)
  end

  post '/walkthroughs/:slug/git/unlink' do
    walkthrough_git_respond(WalkthroughGitService.unlink(params[:slug]))
  rescue StandardError => e
    walkthrough_git_respond({ ok: false, error: e.message }, error_status: 500)
  end
end
