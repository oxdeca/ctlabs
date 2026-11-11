# frozen_string_literal: true

# -----------------------------------------------------------------------------
# File        : ctlabs/services/recording_git_service.rb
# Description : Git versioning service for walkthrough sets, markdown notes,
#               graphviz diagrams, terminal recordings (.cast), and export zips.
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
    # Video files (casts / screen captures) - not stored in git
    *.webm
    *.mp4
    *.mkv
    *.mov
    *.avi
    *.flv
    *.wmv

    # Temporary files & swap
    *.tmp
    temp_*
    .DS_Store
  GITIGNORE

  def self.git_available?
    @git_available ||= system('git --version > /dev/null 2>&1')
  end

  def self.repo_initialized?
    File.directory?(File.join(ROOT, '.git'))
  end

  def self.ensure_repo!
    return false unless git_available?

    FileUtils.mkdir_p(ROOT) unless File.directory?(ROOT)

    unless repo_initialized?
      run_git('init')
      run_git('config', 'user.name', 'ctlabs')
      run_git('config', 'user.email', 'ctlabs@localhost')
    end

    gitignore_path = File.join(ROOT, '.gitignore')
    unless File.exist?(gitignore_path)
      File.write(gitignore_path, GITIGNORE_CONTENT)
    end

    # Initial commit if no commits exist yet
    _out, _err, status = run_git('rev-parse', '--verify', 'HEAD')
    if status.exitstatus != 0
      run_git('add', '-A')
      run_git('commit', '-m', 'Initialize recordings repository (walkthroughs, notes, diagrams, casts, zips)')
    end

    true
  rescue StandardError => e
    warn "RecordingGitService.ensure_repo! error: #{e.message}"
    false
  end

  def self.commit(message, author: nil, files: nil)
    return { ok: false, error: 'git not available' } unless ensure_repo!

    msg = message.to_s.strip
    msg = 'Update walkthrough / recordings' if msg.empty?

    if files && !files.empty?
      Array(files).each do |f|
        rel = relative_path(f)
        run_git('add', rel) if rel
      end
    else
      run_git('add', '-A')
    end

    # Check if there is anything to commit
    _out, _err, status = run_git('diff', '--cached', '--quiet')
    if status.exitstatus == 0
      # Clean working tree, nothing to commit
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
    args = ['log', "-n#{lim}", '--pretty=format:%H|%h|%an|%ae|%ad|%s', '--date=iso']

    if path && !path.strip.empty?
      clean_path = path.strip
      if slug && !slug.strip.empty? && slug != 'default' && !clean_path.start_with?("#{slug.strip}/")
        clean_path = File.join(slug.strip, clean_path)
      end
      rel = relative_path(clean_path)
      args += ['--', rel] if rel && rel != '.'
    elsif slug && !slug.strip.empty? && slug != 'default'
      args += ['--', slug]
    end

    out, _err, status = run_git(*args)
    return [] unless status.exitstatus == 0

    commits = out.lines.map do |line|
      parts = line.strip.split('|', 6)
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
    end.compact

    # Enrich with changed files
    commits.each do |c|
      fout, _ferr, fstatus = run_git('diff-tree', '--no-commit-id', '--name-status', '-r', c[:hash])
      if fstatus.exitstatus == 0
        c[:files] = fout.lines.map do |fl|
          status_char, filepath = fl.strip.split(/\s+/, 2)
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
    if path && !path.strip.empty?
      clean_path = path.strip
      if slug && !slug.strip.empty? && slug != 'default' && !clean_path.start_with?("#{slug.strip}/")
        clean_path = File.join(slug.strip, clean_path)
      end
      rel = relative_path(clean_path)
      if rel && rel != '.'
        args += ['--', rel]
        stat_args += ['--', rel]
      end
    elsif slug && !slug.strip.empty? && slug != 'default'
      args += ['--', slug.strip]
      stat_args += ['--', slug.strip]
    end

    stat_out, _err, _st = run_git(*stat_args)
    patch_out, err, st = run_git(*args)
    if st.exitstatus == 0
      { ok: true, hash: 'working', stat: stat_out, diff: patch_out }
    else
      { ok: false, error: err.strip }
    end
  rescue StandardError => e
    { ok: false, error: e.message }
  end

  def self.discard_working(path, slug: nil)
    return { ok: false, error: 'git not available' } unless ensure_repo!

    clean_path = path.to_s.strip
    if slug && !slug.strip.empty? && slug != 'default' && !clean_path.start_with?("#{slug.strip}/")
      clean_path = File.join(slug.strip, clean_path)
    end
    rel = relative_path(clean_path)
    return { ok: false, error: 'invalid path' } unless rel && rel != '.'

    _out, err, st = run_git('checkout', 'HEAD', '--', rel)
    if st.exitstatus == 0
      { ok: true, discarded: rel }
    else
      { ok: false, error: err.strip }
    end
  rescue StandardError => e
    { ok: false, error: e.message }
  end

  def self.diff(hash)
    return { ok: false, error: 'git not available' } unless ensure_repo!

    clean_hash = hash.to_s.strip
    return { ok: false, error: 'invalid hash' } unless clean_hash =~ /\A[a-f0-9]{4,40}\z/i

    stat_out, _err, _st = run_git('show', '--stat', '--oneline', clean_hash)
    patch_out, err, st = run_git('show', '-p', clean_hash)

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

    clean_path = path.to_s.strip
    if slug && !slug.strip.empty? && slug != 'default' && !clean_path.start_with?("#{slug.strip}/")
      clean_path = File.join(slug.strip, clean_path)
    end
    rel = relative_path(clean_path)
    return { ok: false, error: 'invalid path' } unless rel

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

    clean_path = path.to_s.strip
    if clean_path.empty? && slug && !slug.strip.empty? && slug != 'default'
      clean_path = slug.strip
    elsif slug && !slug.strip.empty? && slug != 'default' && clean_path != '.' && !clean_path.start_with?("#{slug.strip}/")
      clean_path = File.join(slug.strip, clean_path)
    end

    rel = relative_path(clean_path)
    return { ok: false, error: 'invalid path' } unless rel

    _out, err, status = run_git('checkout', clean_hash, '--', rel)
    if status.exitstatus == 0
      msg = message || "Restore #{rel} from #{clean_hash[0..7]}"
      commit(msg, files: (rel == '.' ? nil : [rel]))
      { ok: true, restored: rel, hash: clean_hash }
    else
      { ok: false, error: err.strip }
    end
  rescue StandardError => e
    { ok: false, error: e.message }
  end

  def self.status
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
    p = p.sub(%r{\A#{Regexp.escape(ROOT)}/?}, '')
    # Prevent traversal
    p = Pathname.new(p).cleanpath.to_s
    return nil if p.start_with?('..')
    p
  end

  def self.run_git(*args)
    cmd = ['git', '-C', ROOT] + args
    Open3.capture3(*cmd)
  end
end
