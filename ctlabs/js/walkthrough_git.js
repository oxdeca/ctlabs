/*
 -----------------------------------------------------------------------------
 File        : ctlabs/js/walkthrough_git.js
 Description : Walkthrough Repository & Git Sync Modal controller
 License     : MIT License
 -----------------------------------------------------------------------------
*/

(function() {
  'use strict';

  let currentSlug = '';
  let currentStatus = null;
  let busy = false;

  function byId(id) {
    return document.getElementById(id);
  }

  function valueOf(id) {
    const el = byId(id);
    return el ? String(el.value || '').trim() : '';
  }

  function setBusy(next) {
    busy = !!next;
    const modal = byId('wg-modal');
    if (!modal) return;
    modal.style.cursor = busy ? 'progress' : '';
    modal.querySelectorAll('button, select').forEach((el) => {
      el.disabled = busy;
      el.style.opacity = busy ? '0.6' : '';
    });
  }

  function showLog(text, isError) {
    const wrap = byId('wg-log-wrap');
    const pre = byId('wg-log');
    if (!wrap || !pre) return;
    wrap.style.display = 'block';
    pre.textContent = text == null ? '' : String(text);
    pre.style.color = isError ? '#fca5a5' : '#cbd5e1';
  }

  async function api(path, options) {
    const opts = Object.assign({ credentials: 'same-origin' }, options || {});
    const headers = Object.assign({ Accept: 'application/json' }, opts.headers || {});
    if (opts.body) headers['Content-Type'] = 'application/json';
    opts.headers = headers;

    const response = await fetch(path, opts);
    let data = null;
    try {
      data = await response.json();
    } catch (e) {
      data = null;
    }
    if (!data || typeof data !== 'object') {
      data = { ok: false, error: 'HTTP ' + response.status };
    }
    if (data.ok === undefined) data.ok = response.ok;
    if (!response.ok && !data.error) data.error = 'HTTP ' + response.status;
    return data;
  }

  function post(action, body) {
    const target = currentSlug || 'default';
    return api('/walkthroughs/' + encodeURIComponent(target) + '/git/' + action, {
      method: 'POST',
      body: JSON.stringify(body || {})
    });
  }

  function branchValue() {
    return valueOf('wg-branch');
  }

  function renderRepositories(status) {
    const repos = Array.isArray(status.repositories) ? status.repositories : [];
    const activeRepo = status.repo || 'default';
    const repoSelect = byId('wg-repo-select');
    if (repoSelect && repos.length > 0) {
      repoSelect.innerHTML = '';
      repos.forEach((r) => {
        const opt = document.createElement('option');
        opt.value = r.slug;
        opt.selected = (r.slug === activeRepo || !!r.active);
        const setCount = Number(r.set_count || 0);
        const remoteTag = r.remote ? ' · ' + r.remote : ' · local';
        opt.textContent = (r.name || r.slug) + ' (' + setCount + ' set' + (setCount === 1 ? '' : 's') + ')' + remoteTag;
        repoSelect.appendChild(opt);
      });
    }

    const sidebarRepoSelect = byId('repo-select');
    if (sidebarRepoSelect && repos.length > 0) {
      sidebarRepoSelect.innerHTML = '';
      repos.forEach((r) => {
        const opt = document.createElement('option');
        opt.value = r.slug;
        opt.selected = (r.slug === activeRepo || !!r.active);
        const setCount = Number(r.set_count || 0);
        opt.textContent = (r.name || r.slug) + ' (' + setCount + ' set' + (setCount === 1 ? '' : 's') + ')';
        sidebarRepoSelect.appendChild(opt);
      });
    }

    const deleteRepoBtn = byId('wg-delete-repo-btn');
    if (deleteRepoBtn) {
      deleteRepoBtn.style.display = (activeRepo && activeRepo !== 'default') ? 'inline-block' : 'none';
    }
  }

  function render() {
    const status = currentStatus || {};
    const gitMissing = status.git_available === false;

    renderRepositories(status);

    const badge = byId('wg-slug-badge');
    if (badge) {
      const repoLabel = status.repo_name || status.repo || 'Local Workspace';
      badge.textContent = 'Repo: ' + repoLabel;
    }

    const missing = byId('wg-git-missing');
    if (missing) missing.style.display = gitMissing ? 'block' : 'none';

    const cloneSection = byId('wg-clone-section');
    if (cloneSection) cloneSection.style.display = gitMissing ? 'none' : 'block';

    const statusCard = byId('wg-status-card');
    const linkedActions = byId('wg-linked-actions');
    const remoteHint = byId('wg-remote-hint');
    const initialized = !!(status.initialized || status.linked);
    const hasRemote = !!(status.remote_linked || (status.remote && String(status.remote).trim()));

    if (statusCard) statusCard.style.display = initialized ? 'block' : 'none';
    if (linkedActions) linkedActions.style.display = initialized ? 'block' : 'none';
    if (remoteHint) {
      remoteHint.style.display = hasRemote ? 'none' : 'block';
      remoteHint.textContent = initialized
        ? 'Local Git history is active for this repository. Enter a remote URL below to link it for Fetch / Pull / Push.'
        : 'This repository is not linked to a remote yet. Enter a remote URL to publish it.';
    }

    ['wg-fetch-btn', 'wg-pull-btn', 'wg-push-btn', 'wg-unlink-btn'].forEach((btnId) => {
      const btn = byId(btnId);
      if (!btn) return;
      btn.disabled = busy || !hasRemote;
      btn.style.opacity = (!busy && !hasRemote) ? '0.45' : (busy ? '0.6' : '');
      btn.title = hasRemote ? '' : 'Configure a Remote URL above first';
    });

    const stateEl = byId('wg-state');
    const remoteEl = byId('wg-remote');
    const branchEl = byId('wg-branch-display');
    const lastEl = byId('wg-last-commit');
    const syncEl = byId('wg-sync');
    const changesEl = byId('wg-changes');
    const changesList = byId('wg-changes-list');
    const branchInput = byId('wg-branch');

    if (!initialized) {
      if (stateEl) stateEl.textContent = 'Not initialized';
      if (remoteEl) remoteEl.textContent = '-';
      if (branchEl) branchEl.textContent = '-';
      if (lastEl) lastEl.textContent = '-';
      if (syncEl) syncEl.textContent = '-';
      if (changesEl) changesEl.textContent = '-';
      if (changesList) changesList.style.display = 'none';
      if (branchInput) branchInput.value = '';
      return;
    }

    if (branchInput && !branchInput.value) branchInput.value = status.branch || '';
    if (stateEl) {
      const prefix = hasRemote ? 'Linked to remote' : 'Local repository';
      stateEl.textContent = status.clean ? (prefix + ' — working tree clean') : (prefix + ' — uncommitted changes');
    }
    if (remoteEl) remoteEl.textContent = status.remote || '(no remote configured — local only)';
    if (branchEl) branchEl.textContent = status.branch || (status.detached ? '(detached HEAD)' : '-');

    const commit = status.last_commit;
    if (lastEl) {
      lastEl.textContent = commit
        ? commit.short_hash + ' — ' + commit.message + ' (' + commit.author + ', ' + commit.date + ')'
        : '(no commits yet)';
    }

    const ahead = Number(status.ahead || 0);
    const behind = Number(status.behind || 0);
    if (syncEl) {
      if (!hasRemote) {
        syncEl.textContent = 'Local only (link a Remote URL above to sync)';
      } else if (status.detached) {
        syncEl.textContent = 'Detached HEAD';
      } else if (ahead === 0 && behind === 0) {
        syncEl.textContent = 'Up to date with upstream';
      } else {
        syncEl.textContent = ahead + ' ahead, ' + behind + ' behind';
      }
    }

    const changes = Array.isArray(status.changes) ? status.changes : [];
    if (changesEl) changesEl.textContent = changes.length === 0 ? 'None' : changes.length + ' file(s) with local changes';
    if (changesList) {
      if (changes.length === 0) {
        changesList.style.display = 'none';
        changesList.textContent = '';
      } else {
        changesList.style.display = 'block';
        changesList.textContent = changes.map((item) => item.code + ' ' + item.file).join('\n');
      }
    }
  }

  async function refresh() {
    const target = currentSlug || 'default';
    try {
      const data = await api('/walkthroughs/' + encodeURIComponent(target) + '/git/status');
      currentStatus = data;
      render();
    } catch (e) {
      showLog('Could not load git status: ' + e.message, true);
    }
  }

  async function simpleAction(action, label, body) {
    if (busy) return { ok: false, error: 'busy' };
    setBusy(true);
    try {
      const result = await post(action, body);
      if (!result || !result.ok) {
        showLog((result && result.error) || (label + ' failed.'), true);
        return result || { ok: false, error: label + ' failed' };
      }
      showLog(result.output ? result.output : (label + ': ok.'), false);
      return result;
    } catch (e) {
      showLog(label + ' failed: ' + e.message, true);
      return { ok: false, error: e.message };
    } finally {
      setBusy(false);
    }
  }

  async function switchRepo(repoSlug) {
    if (busy || !repoSlug) return;
    setBusy(true);
    try {
      const result = await api('/repositories/switch', {
        method: 'POST',
        body: JSON.stringify({ repo: repoSlug })
      });
      if (!result || !result.ok) {
        showLog((result && result.error) || 'Failed to switch repository.', true);
        return;
      }
      showLog("Switched active repository to '" + (result.repo_name || result.repo) + "'. Loading sets...", false);
      window.location.href = '/demo?walkthrough=' + encodeURIComponent(result.walkthrough || '');
    } finally {
      setBusy(false);
    }
  }

  async function createRepo() {
    if (busy) return;
    const name = valueOf('wg-create-repo-name');
    const url = valueOf('wg-create-repo-url');
    if (!name) {
      showLog('Enter a name for the new repository.', true);
      return;
    }
    setBusy(true);
    try {
      const result = await api('/repositories/create', {
        method: 'POST',
        body: JSON.stringify({ name: name, url: url })
      });
      if (!result || !result.ok) {
        showLog((result && result.error) || 'Failed to create repository.', true);
        return;
      }
      showLog("Created repository '" + (result.repo_name || result.repo) + "'. Switching...", false);
      window.location.href = '/demo?walkthrough=' + encodeURIComponent(result.walkthrough || '');
    } finally {
      setBusy(false);
    }
  }

  async function renameRepo() {
    if (busy || !currentStatus) return;
    const activeRepo = currentStatus.repo || 'default';
    const currentName = currentStatus.repo_name || activeRepo;
    const nextName = window.prompt('New display name for repository:', currentName);
    if (nextName === null || !nextName.trim()) return;

    setBusy(true);
    try {
      const result = await api('/repositories/' + encodeURIComponent(activeRepo) + '/rename', {
        method: 'POST',
        body: JSON.stringify({ name: nextName.trim() })
      });
      if (!result || !result.ok) {
        showLog((result && result.error) || 'Failed to rename repository.', true);
        return;
      }
      showLog("Renamed repository to '" + result.repo_name + "'.", false);
      await refresh();
    } finally {
      setBusy(false);
    }
  }

  async function deleteRepo() {
    if (busy || !currentStatus) return;
    const activeRepo = currentStatus.repo || 'default';
    if (activeRepo === 'default') return;
    const repoLabel = currentStatus.repo_name || activeRepo;
    if (!window.confirm("Delete repository '" + repoLabel + "' and all walkthrough sets inside it?\n\nThis will switch you back to Local Workspace.")) {
      return;
    }

    setBusy(true);
    try {
      const result = await api('/repositories/' + encodeURIComponent(activeRepo) + '/delete', {
        method: 'POST',
        body: JSON.stringify({})
      });
      if (!result || !result.ok) {
        showLog((result && result.error) || 'Failed to delete repository.', true);
        return;
      }
      window.location.href = '/demo';
    } finally {
      setBusy(false);
    }
  }

  async function doFetch() {
    const result = await simpleAction('fetch', 'Fetch');
    if (result && result.ok) await refresh();
  }

  async function doPull() {
    const result = await simpleAction('pull', 'Pull', { branch: branchValue() });
    if (result && result.ok) {
      await refresh();
      if (result.updated) {
        showLog((result.output ? result.output + '\n' : '') + 'Repository updated from remote. Reloading view...', false);
        setTimeout(function() {
          window.location.href = '/demo?walkthrough=' + encodeURIComponent(currentSlug);
        }, 800);
      }
    }
  }

  async function doPush() {
    const message = valueOf('wg-message');
    const result = await simpleAction('push', 'Push', { message: message, branch: branchValue() });
    if (result && result.ok) {
      const msgEl = byId('wg-message');
      if (msgEl) msgEl.value = '';
      await refresh();
    }
  }

  async function doCommit() {
    const message = valueOf('wg-message');
    const result = await simpleAction('commit', 'Commit', { message: message });
    if (result && result.ok) {
      const msgEl = byId('wg-message');
      if (msgEl) msgEl.value = '';
      await refresh();
    }
  }

  function openHistory() {
    const slug = currentSlug || window.activeWalkthrough || '';
    close();
    if (typeof window.openGitHistoryModal === 'function') {
      window.openGitHistoryModal(slug);
    }
  }

  async function doUnlink() {
    if (busy) return;
    if (!window.confirm('Remove the remote URL link from this repository? Local walkthrough sets and commit history will be kept.')) return;
    const result = await simpleAction('unlink', 'Unlink');
    if (result && result.ok) await refresh();
  }

  async function saveRemote() {
    if (busy) return;
    const url = valueOf('wg-url');
    const branch = branchValue();
    const linked = !!(currentStatus && currentStatus.linked);
    if (!linked && !url) {
      showLog('Enter a remote URL to link this repository.', true);
      return;
    }

    const result = await simpleAction('remote', 'Save remote', { url: url, branch: branch });
    if (result && result.ok) {
      const urlInput = byId('wg-url');
      if (urlInput) urlInput.value = '';
      showLog(result.remote_linked ? 'Remote saved. You can now Fetch, Pull, and Push.' : 'Branch updated.', false);
      await refresh();
    }
  }

  async function doClone() {
    if (busy) return;
    const url = valueOf('wg-clone-url');
    if (!url) {
      showLog('Enter a repository URL to clone.', true);
      return;
    }

    setBusy(true);
    try {
      const result = await api('/walkthroughs/git/clone', {
        method: 'POST',
        body: JSON.stringify({
          url: url,
          branch: valueOf('wg-clone-branch'),
          name: valueOf('wg-clone-name')
        })
      });
      if (!result || !result.ok) {
        showLog((result && result.error) || 'Clone failed.', true);
        return;
      }
      showLog("Cloned repository '" + (result.repo_name || result.repo) + "' (branch " + result.branch + '). Switching to repository...', false);
      window.location.href = '/demo?walkthrough=' + encodeURIComponent(result.slug || '');
    } catch (e) {
      showLog('Clone failed: ' + e.message, true);
    } finally {
      setBusy(false);
    }
  }

  function open(slug, expandNewRepo) {
    currentSlug = String(slug || window.activeWalkthrough || 'default').trim();
    currentStatus = null;

    ['wg-url', 'wg-branch', 'wg-message', 'wg-clone-url', 'wg-clone-branch', 'wg-clone-name', 'wg-create-repo-name', 'wg-create-repo-url'].forEach((id) => {
      const el = byId(id);
      if (el) el.value = '';
    });
    const logWrap = byId('wg-log-wrap');
    if (logWrap) logWrap.style.display = 'none';

    const cloneDetails = byId('wg-clone-section');
    if (cloneDetails) {
      cloneDetails.open = !!expandNewRepo;
    }

    const modal = byId('wg-modal');
    if (modal) modal.style.display = 'block';

    render();
    refresh();
  }

  function close() {
    if (busy) return;
    const modal = byId('wg-modal');
    if (modal) modal.style.display = 'none';
  }

  window.addEventListener('keydown', (event) => {
    if (event.key !== 'Escape') return;
    const modal = byId('wg-modal');
    if (modal && modal.style.display === 'block') close();
  });

  window.WalkthroughGit = {
    open: open,
    close: close,
    refresh: refresh,
    switchRepo: switchRepo,
    createRepo: createRepo,
    renameRepo: renameRepo,
    deleteRepo: deleteRepo,
    saveRemote: saveRemote,
    fetch: doFetch,
    pull: doPull,
    push: doPush,
    commit: doCommit,
    openHistory: openHistory,
    unlink: doUnlink,
    clone: doClone
  };
})();
