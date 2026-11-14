# frozen_string_literal: true

# -----------------------------------------------------------------------------
# File        : ctlabs/services/walkthrough_git_service.rb
# Description : Git repository & remote sync service for walkthrough repositories.
#               A repository holds multiple walkthrough sets (each in its own
#               subdirectory) and CTLabs maintains one active repository at a time.
# License     : MIT License
# -----------------------------------------------------------------------------

require 'open3'
require 'fileutils'
require 'json'
require 'timeout'
require 'pathname'

class WalkthroughGitService
  SLUG_RE          = /\A[a-zA-Z0-9_-]{1,120}\z/
  MANIFEST         = '_walkthrough.json'
  VIDEO_PATTERNS   = %w[*.webm *.mp4 *.mkv *.mov *.avi *.flv *.wmv].freeze
  EXCLUDE_PATTERNS = (VIDEO_PATTERNS + %w[*.tmp temp_* export_*.zip export_note_*.zip .DS_Store _repos.json]).freeze
  SSH_COMMAND      = 'ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=20'
  DEFAULT_TIMEOUT  = 90

  @mutex = Mutex.new

  def self.git_available?
    @git_available = system('git', '--version', out: File::NULL, err: File::NULL) if @git_available.nil?
    @git_available
  end

  # Resolves a repository slug. If nil, empty, or a walkthrough set slug inside
  # the active repository is passed, returns the currently active repository slug.
  def self.resolve_repo_slug(slug_or_repo = nil)
    return 'default' unless defined?(RecordingService)

    candidate = slug_or_repo.to_s.strip
    return RecordingService.active_repo if candidate.empty?

    repos = RecordingService.load_repositories['repos'] || {}
    return candidate if repos.key?(candidate)

    RecordingService.active_repo
  rescue StandardError
    'default'
  end

  def self.repo_dir(slug_or_repo = nil)
    rslug = resolve_repo_slug(slug_or_repo)
    defined?(RecordingService) ? RecordingService.repo_dir(rslug) : '/srv/ctlabs-server/recordings'
  end

  def self.git_dir(slug_or_repo = nil)
    File.join(repo_dir(slug_or_repo), '.git')
  end

  def self.repo_initialized?(slug_or_repo = nil)
    File.directory?(git_dir(slug_or_repo))
  end

  def self.ensure_repo!(slug_or_repo = nil)
    return false unless git_available?

    rslug = resolve_repo_slug(slug_or_repo)
    @mutex.synchronize do
      ensure_repo_locked!(rslug)
    end
  rescue StandardError => e
    warn "WalkthroughGitService.ensure_repo! error: #{e.message}"
    false
  end

  def self.ensure_repo_locked!(slug_or_repo = nil, branch: nil)
    return false unless git_available?

    rslug = resolve_repo_slug(slug_or_repo)
    work_path = repo_dir(rslug)
    g_path = git_dir(rslug)
    FileUtils.mkdir_p(work_path) unless File.directory?(work_path)

    unless File.directory?(g_path)
      init = initialize_repo_locked(rslug, branch: branch)
      return init[:ok]
    end

    configure_repo_dir(work_path)
    write_excludes(g_path)

    unless run_in_dir(work_path, 'rev-parse', '--verify', 'HEAD')[:ok]
      run_in_dir(work_path, 'add', '-A')
      staged = run_in_dir(work_path, 'diff', '--cached', '--quiet')
      if staged[:status] != 0
        run_in_dir(work_path, 'commit', '-m', "Initialize repository '#{rslug}'")
      end
    end
    true
  end

  def self.status(slug_or_repo = nil)
    rslug = resolve_repo_slug(slug_or_repo)
    work_path = repo_dir(rslug)
    repo_exists = File.directory?(work_path)
    available = git_available?
    ensure_repo!(rslug) if repo_exists && available

    initialized = repo_initialized?(rslug)
    has_remote = initialized && remote_url_present?(rslug)
    repo_name = defined?(RecordingService) ? RecordingService.active_repo_name : rslug
    repos_list = defined?(RecordingService) ? RecordingService.repositories_summary : []

    base = {
      ok: true,
      repo: rslug,
      repo_name: repo_name,
      repositories: repos_list,
      slug: (slug_or_repo.to_s.strip.empty? ? rslug : slug_or_repo.to_s.strip),
      set_exists: repo_exists,
      git_available: available,
      initialized: initialized,
      linked: initialized,
      remote_linked: has_remote
    }
    return base unless initialized

    unless available
      return base.merge(
        branch: nil, remote: nil, clean: true, changes: [],
        ahead: 0, behind: 0, last_commit: nil, detached: false,
        error: 'git is not installed on the server'
      )
    end

    branch = current_branch(rslug)
    ahead = 0
    behind = 0
    if branch && has_remote
      remote_ref = run_repo(rslug, 'rev-parse', '--verify', "origin/#{branch}")
      if remote_ref[:ok]
        counts = run_repo(rslug, 'rev-list', '--left-right', '--count', "HEAD...origin/#{branch}")
        if counts[:ok] && counts[:out] =~ /\A(\d+)\s+(\d+)/
          ahead  = Regexp.last_match(1).to_i
          behind = Regexp.last_match(2).to_i
        end
      end
    end
    changes = porcelain_changes(rslug)

    base.merge(
      branch: branch,
      remote: redact_url(remote_url(rslug)),
      clean: changes.empty?,
      changes: changes,
      ahead: ahead,
      behind: behind,
      last_commit: last_commit(rslug),
      detached: branch.nil?
    )
  rescue StandardError => e
    failure(e.message)
  end

  # Clones a remote Git repository into a standalone repository directory under
  # /srv/ctlabs-server/walkthrough-repos/<repo_slug> and switches the active
  # repository to it.
  def self.clone(url:, branch: nil, name: nil, slug: nil)
    return failure('git is not installed on the server') unless git_available?

    url = url.to_s.strip
    url_error = remote_url_error(url)
    return failure(url_error) if url_error

    derived = derive_name(url)
    label = name.to_s.strip
    label = derived if label.empty?
    label = 'Cloned Repository' if label.empty?

    base = slug.to_s.strip
    base = label if base.empty?
    clean = slugify(base)
    clean = "repo_#{clean}" if clean == 'default'
    return failure('Invalid repository name') if clean.empty?

    branch_arg = branch.to_s.strip
    return failure('Invalid branch name') unless branch_arg.empty? || valid_branch?(branch_arg)

    repos_root = defined?(RecordingService) ? RecordingService::REPOS_BASE_DIR : '/srv/ctlabs-server/walkthrough-repos'
    FileUtils.mkdir_p(repos_root)
    target_dir = File.join(repos_root, clean)

    if File.exist?(target_dir) && !Dir.empty?(target_dir)
      return failure("A repository named '#{clean}' already exists")
    end

    @mutex.synchronize do
      FileUtils.rm_rf(target_dir) if File.exist?(target_dir)

      args = ['clone']
      args += ['--branch', branch_arg] unless branch_arg.empty?
      args += [url, target_dir]

      res = run_git(args, timeout: 180)
      unless res[:ok]
        FileUtils.rm_rf(target_dir) rescue nil
        return failure("Clone failed: #{res[:err].to_s.strip}")
      end

      configure_repo_dir(target_dir)
      write_excludes(File.join(target_dir, '.git'))

      chosen = current_branch_for_dir(target_dir) || branch_arg
      if chosen.to_s.empty?
        chosen = detect_default_branch_for_dir(target_dir) || 'main'
      end

      adopt_single_set_root_if_needed(target_dir, clean, label)

      if defined?(RecordingService)
        RecordingService.register_repository(clean, name: label, switch: true)
        wks = RecordingService.load_walkthroughs
        first_set = wks.keys.first.to_s
      else
        first_set = clean
      end

      {
        ok: true,
        repo: clean,
        repo_name: label,
        slug: first_set,
        branch: chosen,
        remote: redact_url(url),
        name: label
      }
    end
  rescue StandardError => e
    failure(e.message)
  end

  def self.set_remote(slug_or_repo = nil, url: nil, branch: nil)
    return failure('git is not installed on the server') unless git_available?

    rslug = resolve_repo_slug(slug_or_repo)
    work_path = repo_dir(rslug)
    return failure('Repository directory not found') unless File.directory?(work_path)

    url = url.to_s.strip
    branch = branch.to_s.strip
    return failure('Invalid branch name') unless branch.empty? || valid_branch?(branch)

    has_remote = repo_initialized?(rslug) && remote_url_present?(rslug)
    if url.empty?
      return failure('Remote URL is required to link this repository') unless has_remote || !branch.empty?
    else
      url_error = remote_url_error(url)
      return failure(url_error) if url_error
    end

    @mutex.synchronize do
      unless ensure_repo_locked!(rslug, branch: branch)
        return failure('Could not initialize git repository')
      end

      unless url.empty?
        run_in_dir(work_path, 'remote', 'remove', 'origin')
        added = run_in_dir(work_path, 'remote', 'add', 'origin', url)
        return failure("Could not set remote: #{added[:err].to_s.strip}") unless added[:ok]
        run_in_dir(work_path, 'config', 'remote.origin.fetch', '+refs/heads/*:refs/remotes/origin/*')
      end

      unless branch.empty?
        current = current_branch_for_dir(work_path)
        if current && current != branch
          renamed = run_in_dir(work_path, 'branch', '-M', branch)
          return failure("Could not switch branch: #{renamed[:err].to_s.strip}") unless renamed[:ok]
        end
      end

      {
        ok: true,
        repo: rslug,
        linked: true,
        remote_linked: remote_url_present?(rslug),
        remote: redact_url(remote_url(rslug)),
        branch: current_branch(rslug)
      }
    end
  rescue StandardError => e
    failure(e.message)
  end

  def self.fetch(slug_or_repo = nil)
    return failure('git is not installed on the server') unless git_available?

    rslug = resolve_repo_slug(slug_or_repo)
    return failure('Could not initialize repository') unless ensure_repo!(rslug)
    return failure('No remote repository linked yet. Enter a Remote URL and click Link / Save Remote first.') unless remote_url_present?(rslug)

    @mutex.synchronize do
      res = run_repo(rslug, 'fetch', 'origin', '--prune', timeout: 180)
      return failure("Fetch failed: #{res[:err].to_s.strip}") unless res[:ok]

      { ok: true, repo: rslug, output: (res[:out] + res[:err]).strip }
    end
  rescue StandardError => e
    failure(e.message)
  end

  def self.pull(slug_or_repo = nil, branch: nil)
    return failure('git is not installed on the server') unless git_available?

    rslug = resolve_repo_slug(slug_or_repo)
    return failure('Could not initialize repository') unless ensure_repo!(rslug)
    return failure('No remote repository linked yet. Enter a Remote URL and click Link / Save Remote first.') unless remote_url_present?(rslug)

    @mutex.synchronize do
      target = resolve_branch(rslug, branch)
      return failure('Invalid branch name') if !branch.to_s.strip.empty? && target.nil?
      return failure('No branch checked out') unless target

      fetched = run_repo(rslug, 'fetch', 'origin', '--prune', timeout: 180)
      return failure("Fetch failed: #{fetched[:err].to_s.strip}") unless fetched[:ok]

      exists = run_repo(rslug, 'rev-parse', '--verify', "origin/#{target}")
      return failure("Remote branch 'origin/#{target}' not found on remote") unless exists[:ok]

      before = head_hash(rslug)
      merge = run_repo(rslug, 'merge', '--ff-only', "origin/#{target}", timeout: 120)
      unless merge[:ok]
        detail = (merge[:err] + merge[:out]).to_s
        message = if detail =~ /local changes|would be overwritten|fast-forward|diverg/i
                    'Pull refused: local changes or divergent history. Commit/push or discard local changes first.'
                  else
                    "Pull failed: #{detail.strip}"
                  end
        return failure(message)
      end

      after = head_hash(rslug)
      RecordingService.load_walkthroughs if defined?(RecordingService)
      {
        ok: true,
        repo: rslug,
        branch: target,
        updated: before != after,
        from: before,
        to: after,
        output: (merge[:out] + merge[:err]).strip
      }
    end
  rescue StandardError => e
    failure(e.message)
  end

  def self.push(slug_or_repo = nil, message: nil, branch: nil)
    return failure('git is not installed on the server') unless git_available?

    rslug = resolve_repo_slug(slug_or_repo)
    return failure('Could not initialize repository') unless ensure_repo!(rslug)
    return failure('No remote repository linked yet. Enter a Remote URL and click Link / Save Remote first.') unless remote_url_present?(rslug)

    @mutex.synchronize do
      target = resolve_branch(rslug, branch)
      return failure('Invalid branch name') if !branch.to_s.strip.empty? && target.nil?
      return failure('No branch checked out') unless target

      added = run_repo(rslug, 'add', '-A')
      return failure("git add failed: #{added[:err].to_s.strip}") unless added[:ok]

      staged = run_repo(rslug, 'diff', '--cached', '--quiet')
      committed = false
      if staged[:status] != 0
        msg = message.to_s.strip
        msg = "Update repository '#{rslug}' from CTLABS" if msg.empty?
        commit_res = run_repo(rslug, 'commit', '-m', msg)
        return failure("Commit failed: #{commit_res[:err].to_s.strip}") unless commit_res[:ok]
        committed = true
      end

      upstream = run_repo(rslug, 'rev-parse', '--abbrev-ref', '--symbolic-full-name', '@{u}')
      args = ['push']
      args << '-u' unless upstream[:ok]
      args += ['origin', target]

      pushed = run_repo(rslug, *args, timeout: 180)
      return failure("Push failed: #{pushed[:err].to_s.strip}") unless pushed[:ok]

      {
        ok: true,
        repo: rslug,
        branch: target,
        committed: committed,
        pushed: true,
        hash: head_hash(rslug),
        output: (pushed[:out] + pushed[:err]).strip
      }
    end
  rescue StandardError => e
    failure(e.message)
  end

  def self.commit(slug_or_repo = nil, message: nil, files: nil, author: nil)
    return failure('git is not installed on the server') unless git_available?

    rslug = resolve_repo_slug(slug_or_repo)
    return failure('Could not initialize repository') unless ensure_repo!(rslug)

    work_path = repo_dir(rslug)
    @mutex.synchronize do
      rel_files = Array(files).filter_map { |f| relative_to_repo(work_path, f) }.uniq
      added = if rel_files.empty? || rel_files.include?('.')
                run_in_dir(work_path, 'add', '-A')
              else
                run_in_dir(work_path, 'add', '-A', '--', *rel_files)
              end
      return failure("git add failed: #{added[:err].to_s.strip}") unless added[:ok]

      staged = run_in_dir(work_path, 'diff', '--cached', '--quiet')
      if staged[:status] == 0
        return {
          ok: true,
          repo: rslug,
          committed: false,
          message: 'No changes to commit',
          hash: head_hash(rslug),
          output: 'No changes to commit.'
        }
      end

      msg = message.to_s.strip
      msg = "Update walkthroughs in '#{rslug}'" if msg.empty?
      commit_args = ['commit', '-m', msg]
      commit_args += ['--author', author.strip] if author && !author.to_s.strip.empty?

      res = run_in_dir(work_path, *commit_args)
      return failure("Commit failed: #{res[:err].to_s.strip}") unless res[:ok]

      h = head_hash(rslug)
      {
        ok: true,
        repo: rslug,
        committed: true,
        message: msg,
        hash: h,
        output: "Committed #{h ? h[0, 7] : ''}: #{msg}"
      }
    end
  rescue StandardError => e
    failure(e.message)
  end

  def self.unlink(slug_or_repo = nil)
    rslug = resolve_repo_slug(slug_or_repo)
    @mutex.synchronize do
      if repo_initialized?(rslug) && remote_url_present?(rslug)
        run_repo(rslug, 'remote', 'remove', 'origin')
      end
      {
        ok: true,
        repo: rslug,
        unlinked: true,
        slug: rslug,
        output: 'Remote link removed. Local walkthrough sets and commit history were kept.'
      }
    end
  rescue StandardError => e
    failure(e.message)
  end

  def self.purge_repo(_slug = nil)
    true
  end

  def self.relative_to_repo(work_path, path)
    p = path.to_s.strip
    return nil if p.empty?
    return '.' if p == '.'

    root = File.expand_path(work_path)
    p = p.sub(%r{\A#{Regexp.escape(root)}/?}, '')
    return '.' if p.empty? || p == '.'

    clean = Pathname.new(p).cleanpath.to_s
    return nil if clean.start_with?('..') || clean.start_with?('/')
    clean
  end

  def self.initialize_repo_locked(rslug, branch: nil)
    work_path = repo_dir(rslug)
    g_path = git_dir(rslug)
    FileUtils.mkdir_p(work_path)

    init_branch = branch.to_s.strip
    init_branch = 'main' if init_branch.empty?
    res = run_in_dir(work_path, '-c', "init.defaultBranch=#{init_branch}", 'init', timeout: 30)
    return failure("Could not initialize repository: #{res[:err].to_s.strip}") unless res[:ok]

    configure_repo_dir(work_path)
    write_excludes(g_path)

    run_in_dir(work_path, 'add', '-A')
    staged = run_in_dir(work_path, 'diff', '--cached', '--quiet')
    if staged[:status] != 0
      run_in_dir(work_path, 'commit', '-m', "Initialize repository '#{rslug}'")
    end

    { ok: true, branch: init_branch }
  rescue StandardError => e
    failure(e.message)
  end

  # If a freshly cloned repository has root-level walkthrough files (_walkthrough.json
  # or .cast/.md files at the root) and no set subdirectories yet, organize them into
  # a set subdirectory so the multi-set structure is consistent.
  def self.adopt_single_set_root_if_needed(target_dir, repo_slug, label)
    entries = Dir.children(target_dir).reject { |e| e.start_with?('.') }
    subdirs = entries.select { |e| File.directory?(File.join(target_dir, e)) && e != 'images' }
    return unless subdirs.empty?

    root_files = entries.select do |e|
      File.file?(File.join(target_dir, e)) &&
        (e == MANIFEST || e.end_with?('.cast', '.md', '.webm', '.mp4', '.json'))
    end
    return if root_files.empty?

    set_slug = slugify(repo_slug)
    set_dir_path = File.join(target_dir, set_slug)
    FileUtils.mkdir_p(set_dir_path)

    root_files.each do |fname|
      FileUtils.mv(File.join(target_dir, fname), File.join(set_dir_path, fname)) rescue nil
    end
    root_images = File.join(target_dir, 'images')
    if File.directory?(root_images)
      FileUtils.mv(root_images, File.join(set_dir_path, 'images')) rescue nil
    end

    manifest_file = File.join(set_dir_path, MANIFEST)
    unless File.file?(manifest_file)
      md_and_cast = Dir.children(set_dir_path).select { |f| f.end_with?('.md', '.cast', '.webm', '.mp4') }.sort
      ids = md_and_cast.map { |f| File.basename(f, File.extname(f)) }
      manifest = {
        'name' => label.to_s.strip.empty? ? display_name(set_slug) : label.to_s.strip[0, 80],
        'created_at' => Time.now.to_f,
        'recording_ids' => ids,
        'unintegrated_ids' => []
      }
      File.write(manifest_file, JSON.pretty_generate(manifest))
    end
  rescue StandardError
    nil
  end

  def self.detect_default_branch_for_dir(work_path)
    %w[main master trunk].each do |candidate|
      return candidate if run_in_dir(work_path, 'rev-parse', '--verify', "refs/heads/#{candidate}")[:ok]
      return candidate if run_in_dir(work_path, 'rev-parse', '--verify', "refs/remotes/origin/#{candidate}")[:ok]
    end
    res = run_in_dir(work_path, 'for-each-ref', '--format=%(refname:short)', 'refs/remotes/origin')
    return nil unless res[:ok]
    found = res[:out].lines.map(&:strip).find { |line| !line.empty? && !line.end_with?('/HEAD') }
    found && found.sub(%r{\Aorigin/}, '')
  end

  def self.configure_repo_dir(work_path)
    run_in_dir(work_path, 'config', 'user.name', 'ctlabs')
    run_in_dir(work_path, 'config', 'user.email', 'ctlabs@localhost')
  end

  def self.write_excludes(git_path)
    info_dir = File.join(git_path, 'info')
    FileUtils.mkdir_p(info_dir)
    exclude_path = File.join(info_dir, 'exclude')
    existing = File.file?(exclude_path) ? File.read(exclude_path) : ''
    present = existing.lines.map(&:strip)
    missing = EXCLUDE_PATTERNS.reject { |pattern| present.include?(pattern) }
    return if missing.empty?

    separator = existing.empty? || existing.end_with?("\n") ? '' : "\n"
    File.write(exclude_path, existing + separator + missing.join("\n") + "\n")
  end

  def self.valid_slug?(slug)
    !!(slug.to_s =~ SLUG_RE)
  end

  def self.slugify(value)
    slug = value.to_s.strip.downcase.gsub(/[^a-z0-9_-]+/, '_').gsub(/\A_+|_+\z/, '')
    slug = 'walkthrough' if slug.empty?
    slug[0, 120]
  end

  def self.display_name(slug)
    slug.to_s.tr('_-', ' ').split.map(&:capitalize).join(' ')
  end

  def self.derive_name(url)
    clean = url.to_s.sub(/[#?].*\z/, '').sub(%r{/+\z}, '')
    File.basename(clean, '.git')
  end

  def self.current_branch_for_dir(work_path)
    res = run_in_dir(work_path, 'symbolic-ref', '--short', '-q', 'HEAD')
    res[:ok] ? res[:out].strip : nil
  end

  def self.current_branch(slug_or_repo = nil)
    current_branch_for_dir(repo_dir(slug_or_repo))
  end

  def self.resolve_branch(slug_or_repo, branch)
    requested = branch.to_s.strip
    return current_branch(slug_or_repo) if requested.empty?
    return nil unless valid_branch?(requested)
    requested
  end

  def self.valid_branch?(name)
    value = name.to_s
    return false if value.empty? || value.length > 200
    return false unless value =~ %r{\A[A-Za-z0-9._/-]+\z}
    return false if value.start_with?('-', '.', '/')
    return false if value.end_with?('/', '.')
    return false if value.include?('..') || value.include?('//') || value.include?('@{')
    return false if value.end_with?('.lock')
    true
  end

  def self.head_hash(slug_or_repo = nil)
    res = run_repo(slug_or_repo, 'rev-parse', 'HEAD')
    res[:ok] ? res[:out].strip : nil
  end

  def self.remote_url_for_dir(work_path)
    res = run_in_dir(work_path, 'config', '--get', 'remote.origin.url')
    res[:ok] ? res[:out].strip : nil
  end

  def self.remote_url(slug_or_repo = nil)
    remote_url_for_dir(repo_dir(slug_or_repo))
  end

  def self.remote_url_present?(slug_or_repo = nil)
    !remote_url(slug_or_repo).to_s.empty?
  end

  def self.last_commit(slug_or_repo = nil)
    res = run_repo(slug_or_repo, 'log', '-1', '--pretty=format:%H%x1f%h%x1f%an%x1f%ad%x1f%s', '--date=iso')
    return nil unless res[:ok] && !res[:out].strip.empty?

    hash, short, author, date, subject = res[:out].strip.split("\x1f", 5)
    { hash: hash, short_hash: short, author: author, date: date, message: subject }
  end

  def self.porcelain_changes(slug_or_repo = nil)
    res = run_repo(slug_or_repo, 'status', '--porcelain')
    return [] unless res[:ok]

    res[:out].lines.filter_map do |line|
      code = line[0, 2]
      file = line[3..].to_s.strip
      next if file.empty?
      { code: code, file: file }
    end.first(200)
  end

  def self.remote_url_error(url)
    value = url.to_s
    return 'Remote URL is required' if value.strip.empty?
    return 'Invalid remote URL' if value =~ /[\x00-\x1f\x7f]/
    return 'Invalid remote URL' if value =~ /\s/
    return 'Invalid remote URL' if value.start_with?('-')
    return 'Unsupported remote helper' if value =~ /\A[a-zA-Z][a-zA-Z0-9+.-]*::/

    return nil if value =~ %r{\A(?:https?|ssh|git)://\S+\z}i
    return nil if value =~ %r{\A[^/@\s]+@[^/:\s]+:.+\z}

    if local_remotes_allowed?
      return nil if value =~ %r{\Afile://\S+\z}i
      return nil if value.start_with?('/')
    end

    'Unsupported remote URL (use https://, ssh://, git://, or user@host:path)'
  end

  def self.local_remotes_allowed?
    ENV['CTLABS_GIT_ALLOW_LOCAL_REMOTES'].to_s == '1'
  end

  def self.redact_url(url)
    value = url.to_s
    return value if value.empty?

    if value =~ %r{\A([a-zA-Z][a-zA-Z0-9+.-]*://)([^/@]+)@(.+)\z}
      "#{Regexp.last_match(1)}***@#{Regexp.last_match(3)}"
    else
      value
    end
  end

  def self.failure(message)
    { ok: false, error: message.to_s }
  end

  def self.run_repo(slug_or_repo, *args, timeout: DEFAULT_TIMEOUT)
    run_in_dir(repo_dir(slug_or_repo), *args, timeout: timeout)
  end

  def self.run_in_dir(work_path, *args, timeout: DEFAULT_TIMEOUT)
    run_git(['-C', work_path, *args], timeout: timeout)
  end

  def self.run_git(args, env: {}, timeout: DEFAULT_TIMEOUT)
    command = ['git', *args]

    child_env = {
      'GIT_TERMINAL_PROMPT' => '0',
      'GIT_ASKPASS' => 'true',
      'GIT_EDITOR' => 'true',
      'GIT_MERGE_AUTOEDIT' => 'no',
      'GIT_SSH_COMMAND' => SSH_COMMAND,
      'LC_ALL' => 'C'
    }.merge(env)

    out = +''
    err = +''
    status = nil

    Open3.popen3(child_env, *command, pgroup: true) do |stdin, stdout, stderr, wait_thr|
      stdin.close
      out_thread = Thread.new { out << stdout.read }
      err_thread = Thread.new { err << stderr.read }
      begin
        status = Timeout.timeout(timeout) { wait_thr.value }
      rescue Timeout::Error
        begin
          Process.kill('TERM', -wait_thr.pid)
          sleep 0.2
          Process.kill('KILL', -wait_thr.pid)
        rescue StandardError
        end
        out_thread.kill
        err_thread.kill
        return { ok: false, out: out, err: "git command timed out after #{timeout}s", status: nil }
      end
      out_thread.join(2)
      err_thread.join(2)
    end

    { ok: status&.success?, out: out, err: err, status: status&.exitstatus }
  rescue Errno::ENOENT
    { ok: false, out: '', err: 'git executable not found', status: nil }
  rescue StandardError => e
    { ok: false, out: out, err: e.message, status: nil }
  end
end
