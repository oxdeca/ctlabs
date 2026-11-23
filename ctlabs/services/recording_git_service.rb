# frozen_string_literal: true

# -----------------------------------------------------------------------------
# File        : ctlabs/services/recording_git_service.rb
# Description : Git versioning service for the active walkthrough repository
#               (containing multiple walkthrough sets, markdown notes,
#               graphviz diagrams, terminal recordings (.cast), and images).
#               Video casts (.webm, .mp4) are ignored and not stored in git.
# License     : MIT License
# -----------------------------------------------------------------------------

require 'open3'
require 'fileutils'
require 'shellwords'
require 'pathname'

class RecordingGitService
  ROOT = File.expand_path('/srv/ctlabs-server/recordings')

  GITIGNORE_CONTENT = <<~GITIGNORE
    # Temporary files & export archives
    *.tmp
    temp_*
    export_*.zip
    export_note_*.zip
    export_*.docx
    export_note_*.docx
    export_*.pdf
    export_note_*.pdf
    .DS_Store
  GITIGNORE

  GITATTRIBUTES_CONTENT = <<~GITATTRIBUTES
    # Git LFS tracking for video recordings & media
    *.webm filter=lfs diff=lfs merge=lfs -text
    *.mp4 filter=lfs diff=lfs merge=lfs -text
    *.mkv filter=lfs diff=lfs merge=lfs -text
    *.mov filter=lfs diff=lfs merge=lfs -text
    *.avi filter=lfs diff=lfs merge=lfs -text
    *.flv filter=lfs diff=lfs merge=lfs -text
    *.wmv filter=lfs diff=lfs merge=lfs -text
  GITATTRIBUTES

  def self.root_dir
    defined?(RecordingService) ? File.expand_path(RecordingService.dir) : ROOT
  end

  def self.git_available?
    @git_available ||= system('git --version > /dev/null 2>&1')
  end

  def self.repo_initialized?
    File.directory?(File.join(root_dir, '.git'))
  end

  def self.ensure_repo!
    return false unless git_available?

    rdir = root_dir
    FileUtils.mkdir_p(rdir) unless File.directory?(rdir)

    unless repo_initialized?
      run_git('init')
      run_git('config', 'user.name', 'ctlabs')
      run_git('config', 'user.email', 'ctlabs@localhost')
    end

    gitignore_path = File.join(rdir, '.gitignore')
    File.write(gitignore_path, GITIGNORE_CONTENT)

    gitattributes_path = File.join(rdir, '.gitattributes')
    unless File.exist?(gitattributes_path)
      File.write(gitattributes_path, GITATTRIBUTES_CONTENT)
    end

    if defined?(WalkthroughGitService)
      WalkthroughGitService.ensure_lfs_installed!(rdir) rescue nil
      WalkthroughGitService.write_excludes(File.join(rdir, '.git')) rescue nil
    end

    # Initial commit if no commits exist yet
    _out, _err, status = run_git('rev-parse', '--verify', 'HEAD')
    if status.exitstatus != 0
      run_git('add', '-A')
      run_git('commit', '-m', 'Initialize walkthrough repository')
    end

    true
  rescue StandardError => e
    warn "RecordingGitService.ensure_repo! error: #{e.message}"
    false
  end

  def self.scoped_set_slug?(slug)
    s = slug.to_s.strip
    !s.empty? && s != 'default' && s != 'all'
  end

  def self.resolve_relative_target(slug: nil, path: nil)
    clean_path = path.to_s.strip
    clean_slug = slug.to_s.strip
    if !clean_path.empty? && clean_path != '.'
      if scoped_set_slug?(clean_slug) && !clean_path.start_with?('/') && !clean_path.start_with?("#{clean_slug}/")
        clean_path = File.join(clean_slug, clean_path)
      end
      return relative_path(clean_path)
    elsif scoped_set_slug?(clean_slug)
      return relative_path(clean_slug)
    end
    '.'
  end

  def self.commit(message, author: nil, files: nil, slug: nil)
    return { ok: false, error: 'git not available' } unless ensure_repo!

    msg = message.to_s.strip
    msg = 'Update walkthrough / recordings' if msg.empty?

    if files && !files.empty?
      Array(files).each do |f|
        rel = relative_path(f)
        run_git('add', '-A', '--', rel) if rel
      end
    elsif scoped_set_slug?(slug)
      rel = relative_path(slug.to_s.strip)
      run_git('add', '-A', '--', rel) if rel
    else
      run_git('add', '-A')
    end

    # Check if there is anything to commit in active repo
    _out, _err, status = run_git('diff', '--cached', '--quiet')
    if status.exitstatus == 0
      head_hash = current_head_hash
      return { ok: true, committed: false, message: 'No changes to commit', hash: head_hash }
    end

    args = ['commit', '-m', msg]
    args += ['--author', author] if author && !author.strip.empty?
    out, err, commit_status = run_git(*args)

    if commit_status.exitstatus == 0
      head_hash = current_head_hash
      { ok: true, committed: true, message: msg, hash: head_hash }
    else
      { ok: false, error: (err.empty? ? out : err).strip }
    end
  rescue StandardError => e
    { ok: false, error: e.message }
  end

  def self.current_head_hash
    out, _err, status = run_git('rev-parse', 'HEAD')
    status.exitstatus == 0 ? out.strip : nil
  end

  def self.history(slug: nil, path: nil, limit: 40)
    return [] unless ensure_repo!

    lim = limit.to_i.positive? ? limit.to_i : 40
    args = ['log', "-n#{lim}", '--pretty=format:%H%x1f%h%x1f%an%x1f%ae%x1f%ad%x1f%s', '--date=iso']

    rel = resolve_relative_target(slug: slug, path: path)
    args += ['--', rel] if rel && rel != '.'

    out, _err, status = run_git(*args)
    return [] unless status.exitstatus == 0

    commits = out.lines.filter_map do |line|
      parts = line.strip.split("\x1f", 6)
      next nil unless parts.size == 6

      full_hash, short_hash, aname, aemail, adate, subject = parts
      {
        hash: full_hash,
        short_hash: short_hash,
        author: aname,
        email: aemail,
        date: adate,
        message: subject
      }
    end

    # Enrich with changed files
    commits.each do |c|
      fout, _ferr, fstatus = run_git('diff-tree', '--no-commit-id', '--name-status', '-r', c[:hash])
      if fstatus.exitstatus == 0
        c[:files] = fout.lines.filter_map do |fl|
          status_char, filepath = fl.strip.split(/\s+/, 2)
          next nil unless filepath
          { status: status_char, path: filepath }
        end
      else
        c[:files] = []
      end
    end

    commits
  rescue StandardError => e
    warn "RecordingGitService.history error: #{e.message}"
    []
  end

  def self.diff_working(path: nil, slug: nil)
    return { ok: false, error: 'git not available' } unless ensure_repo!

    args = ['diff', 'HEAD']
    stat_args = ['diff', '--stat', 'HEAD']
    rel = resolve_relative_target(slug: slug, path: path)
    if rel && rel != '.'
      args += ['--', rel]
      stat_args += ['--', rel]
    end

    stat_out, _err, _st = run_git(*stat_args)
    patch_out, err, st = run_git(*args)
    return { ok: false, error: err.strip } unless st.exitstatus == 0

    patch_text = patch_out.to_s
    stat_text = stat_out.to_s

    # Include untracked files in working tree diff
    p_out, _p_err, p_st = run_git('status', '--porcelain')
    if p_st.exitstatus == 0
      untracked = p_out.lines.filter_map do |line|
        code = line[0, 2]
        file = line[3..].to_s.strip
        file if code == '??' && !file.empty?
      end
      if rel && rel != '.'
        untracked.select! { |f| f == rel || f.start_with?("#{rel}/") }
      end
      rdir = root_dir
      untracked.each do |uf|
        full_p = File.join(rdir, uf)
        next unless File.file?(full_p)
        u_out, _u_err, _u_st = Open3.capture3('git', 'diff', '--no-index', '--', '/dev/null', full_p)
        patch_text = [patch_text, u_out.to_s].reject(&:empty?).join("\n") unless u_out.to_s.empty?
      end
    end

    { ok: true, hash: 'working', stat: stat_text, diff: patch_text }
  rescue StandardError => e
    { ok: false, error: e.message }
  end

  def self.discard_working(path, slug: nil)
    return { ok: false, error: 'git not available' } unless ensure_repo!

    rel = resolve_relative_target(slug: slug, path: path)
    return { ok: false, error: 'invalid path' } unless rel

    _out, err, st = run_git('checkout', 'HEAD', '--', rel)
    if st.exitstatus == 0
      { ok: true, discarded: rel }
    else
      { ok: false, error: err.strip }
    end
  rescue StandardError => e
    { ok: false, error: e.message }
  end

  def self.diff(hash, slug: nil, path: nil)
    return { ok: false, error: 'git not available' } unless ensure_repo!

    clean_hash = hash.to_s.strip
    return { ok: false, error: 'invalid hash' } unless clean_hash =~ /\A[a-f0-9]{4,40}\z/i

    stat_args = ['show', '--stat', '--oneline', clean_hash]
    patch_args = ['show', '-p', clean_hash]
    rel = resolve_relative_target(slug: slug, path: path)
    if rel && rel != '.'
      stat_args += ['--', rel]
      patch_args += ['--', rel]
    end

    stat_out, _err, _st = run_git(*stat_args)
    patch_out, err, st = run_git(*patch_args)

    if st.exitstatus == 0
      { ok: true, hash: clean_hash, stat: stat_out, diff: patch_out }
    else
      { ok: false, error: err.strip }
    end
  rescue StandardError => e
    { ok: false, error: e.message }
  end

  def self.show_file(hash, path, slug: nil)
    return { ok: false, error: 'git not available' } unless ensure_repo!

    clean_hash = hash.to_s.strip
    return { ok: false, error: 'invalid hash' } unless clean_hash =~ /\A[a-f0-9]{4,40}\z/i

    rel = resolve_relative_target(slug: slug, path: path)
    return { ok: false, error: 'invalid path' } unless rel && rel != '.'

    out, err, status = run_git('show', "#{clean_hash}:#{rel}")
    if status.exitstatus == 0
      { ok: true, content: out, hash: clean_hash, path: rel }
    else
      { ok: false, error: err.strip }
    end
  rescue StandardError => e
    { ok: false, error: e.message }
  end

  def self.restore_file(hash, path, slug: nil, message: nil)
    return { ok: false, error: 'git not available' } unless ensure_repo!

    clean_hash = hash.to_s.strip
    return { ok: false, error: 'invalid hash' } unless clean_hash =~ /\A[a-f0-9]{4,40}\z/i

    rel = resolve_relative_target(slug: slug, path: path)
    return { ok: false, error: 'invalid path' } unless rel

    _out, err, status = run_git('checkout', clean_hash, '--', rel)
    if status.exitstatus == 0
      msg = message || "Restore #{rel == '.' ? 'repository' : rel} from #{clean_hash[0..7]}"
      commit(msg, files: (rel == '.' ? nil : [rel]))
      { ok: true, restored: rel, hash: clean_hash }
    else
      { ok: false, error: err.strip }
    end
  rescue StandardError => e
    { ok: false, error: e.message }
  end

  def self.status(slug: nil)
    if defined?(WalkthroughGitService)
      st = WalkthroughGitService.status(slug)
      return st unless st[:ok]
      items = Array(st[:changes]).map do |c|
        { code: c[:code], file: c[:file] }
      end
      return {
        ok: true,
        repo: st[:repo],
        repo_name: st[:repo_name],
        repositories: st[:repositories],
        slug: slug,
        clean: items.empty?,
        items: items,
        branch: st[:branch],
        remote: st[:remote],
        remote_linked: st[:remote_linked],
        ahead: st[:ahead],
        behind: st[:behind],
        last_commit: st[:last_commit]
      }
    end

    return { ok: false, error: 'git not available' } unless ensure_repo!

    out, err, st = run_git('status', '--porcelain')
    if st.exitstatus == 0
      items = out.lines.map do |line|
        code = line[0..1]
        file = line[3..].strip
        { code: code, file: file }
      end
      { ok: true, clean: items.empty?, items: items }
    else
      { ok: false, error: err.strip }
    end
  rescue StandardError => e
    { ok: false, error: e.message }
  end

  def self.relative_path(path)
    p = path.to_s.strip
    return nil if p.empty?
    return '.' if p == '.'
    rdir = root_dir
    p = p.sub(%r{\A#{Regexp.escape(rdir)}/?}, '')
    p = p.sub(%r{\A#{Regexp.escape(ROOT)}/?}, '')
    p = Pathname.new(p).cleanpath.to_s
    return nil if p.start_with?('..')
    p
  end

  def self.run_git(*args)
    cmd = ['git', '-C', root_dir] + args
    Open3.capture3(*cmd)
  end
end
