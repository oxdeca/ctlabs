/*
 -----------------------------------------------------------------------------
 File        : ctlabs/js/walkthrough_git.js
 Description : Walkthrough Repository & Git Sync Modal controller
               (hierarchical authentication, 2-tab workflow, multi-repo management)
 License     : MIT License
 -----------------------------------------------------------------------------
*/

(function() {
  'use strict';

  let currentSlug = '';
  let currentStatus = null;
  let busy = false;
  let generatedCloneKeyPath = null;
  let generatedRemoteKeyPath = null;
  let userEditedRemoteAuth = false;

  let activeTab = 'sync'; // 'sync' | 'add'
  let remoteProto = 'none'; // 'none' | 'https' | 'ssh'
  let remoteMethod = 'token'; // 'token' | 'user_pass' | 'key'
  let cloneProto = 'none'; // 'none' | 'https' | 'ssh'
  let cloneMethod = 'token'; // 'token' | 'user_pass' | 'key'

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

  // ---------------------------------------------------------------------------
  // Tabs Navigation
  // ---------------------------------------------------------------------------

  function switchTab(tabId) {
    activeTab = (tabId === 'add') ? 'add' : 'sync';

    const tabSync = byId('wg-tab-sync');
    const tabAdd = byId('wg-tab-add');
    const btnSync = byId('wg-tab-btn-sync');
    const btnAdd = byId('wg-tab-btn-add');

    if (tabSync) tabSync.style.display = (activeTab === 'sync') ? 'block' : 'none';
    if (tabAdd) tabAdd.style.display = (activeTab === 'add') ? 'block' : 'none';

    if (btnSync) {
      if (activeTab === 'sync') btnSync.classList.add('active');
      else btnSync.classList.remove('active');
    }
    if (btnAdd) {
      if (activeTab === 'add') btnAdd.classList.add('active');
      else btnAdd.classList.remove('active');
    }
  }

  // ---------------------------------------------------------------------------
  // Authentication Hierarchical Switchers
  // ---------------------------------------------------------------------------

  function setRemoteProto(proto, userAction) {
    remoteProto = ['none', 'https', 'ssh'].includes(proto) ? proto : 'none';
    if (userAction) userEditedRemoteAuth = true;

    // Default method when switching protocols
    if (remoteProto === 'https' && remoteMethod !== 'token' && remoteMethod !== 'user_pass') {
      remoteMethod = 'token';
    } else if (remoteProto === 'ssh' && remoteMethod !== 'key' && remoteMethod !== 'user_pass') {
      remoteMethod = 'key';
    }

    // Update pill buttons
    ['none', 'https', 'ssh'].forEach((p) => {
      const btn = byId('wg-remote-proto-' + p);
      if (btn) {
        if (p === remoteProto) btn.classList.add('active');
        else btn.classList.remove('active');
      }
    });

    // Update subpanels
    const panelNone = byId('wg-remote-panel-none');
    const panelHttps = byId('wg-remote-panel-https');
    const panelSsh = byId('wg-remote-panel-ssh');

    if (panelNone) panelNone.style.display = (remoteProto === 'none') ? 'block' : 'none';
    if (panelHttps) panelHttps.style.display = (remoteProto === 'https') ? 'block' : 'none';
    if (panelSsh) panelSsh.style.display = (remoteProto === 'ssh') ? 'block' : 'none';

    // Render active method views
    if (remoteProto === 'https') {
      setRemoteMethod(remoteMethod, userAction);
    } else if (remoteProto === 'ssh') {
      setRemoteMethod(remoteMethod, userAction);
    }
  }

  function setRemoteMethod(method, userAction) {
    if (userAction) userEditedRemoteAuth = true;

    if (remoteProto === 'https') {
      remoteMethod = (method === 'user_pass') ? 'user_pass' : 'token';
      const btnToken = byId('wg-remote-https-btn-token');
      const btnUserPass = byId('wg-remote-https-btn-userpass');
      const viewToken = byId('wg-remote-https-view-token');
      const viewUserPass = byId('wg-remote-https-view-userpass');

      if (btnToken) btnToken.classList.toggle('active', remoteMethod === 'token');
      if (btnUserPass) btnUserPass.classList.toggle('active', remoteMethod === 'user_pass');
      if (viewToken) viewToken.style.display = (remoteMethod === 'token') ? 'block' : 'none';
      if (viewUserPass) viewUserPass.style.display = (remoteMethod === 'user_pass') ? 'block' : 'none';
    } else if (remoteProto === 'ssh') {
      remoteMethod = (method === 'user_pass') ? 'user_pass' : 'key';
      const btnKey = byId('wg-remote-ssh-btn-key');
      const btnUserPass = byId('wg-remote-ssh-btn-userpass');
      const viewKey = byId('wg-remote-ssh-view-key');
      const viewUserPass = byId('wg-remote-ssh-view-userpass');

      if (btnKey) btnKey.classList.toggle('active', remoteMethod === 'key');
      if (btnUserPass) btnUserPass.classList.toggle('active', remoteMethod === 'user_pass');
      if (viewKey) viewKey.style.display = (remoteMethod === 'key') ? 'block' : 'none';
      if (viewUserPass) viewUserPass.style.display = (remoteMethod === 'user_pass') ? 'block' : 'none';
    }
  }

  function setCloneProto(proto) {
    cloneProto = ['none', 'https', 'ssh'].includes(proto) ? proto : 'none';

    if (cloneProto === 'https' && cloneMethod !== 'token' && cloneMethod !== 'user_pass') {
      cloneMethod = 'token';
    } else if (cloneProto === 'ssh' && cloneMethod !== 'key' && cloneMethod !== 'user_pass') {
      cloneMethod = 'key';
    }

    ['none', 'https', 'ssh'].forEach((p) => {
      const btn = byId('wg-clone-proto-' + p);
      if (btn) {
        if (p === cloneProto) btn.classList.add('active');
        else btn.classList.remove('active');
      }
    });

    const panelNone = byId('wg-clone-panel-none');
    const panelHttps = byId('wg-clone-panel-https');
    const panelSsh = byId('wg-clone-panel-ssh');

    if (panelNone) panelNone.style.display = (cloneProto === 'none') ? 'block' : 'none';
    if (panelHttps) panelHttps.style.display = (cloneProto === 'https') ? 'block' : 'none';
    if (panelSsh) panelSsh.style.display = (cloneProto === 'ssh') ? 'block' : 'none';

    if (cloneProto === 'https') {
      setCloneMethod(cloneMethod);
    } else if (cloneProto === 'ssh') {
      setCloneMethod(cloneMethod);
    }
  }

  function setCloneMethod(method) {
    if (cloneProto === 'https') {
      cloneMethod = (method === 'user_pass') ? 'user_pass' : 'token';
      const btnToken = byId('wg-clone-https-btn-token');
      const btnUserPass = byId('wg-clone-https-btn-userpass');
      const viewToken = byId('wg-clone-https-view-token');
      const viewUserPass = byId('wg-clone-https-view-userpass');

      if (btnToken) btnToken.classList.toggle('active', cloneMethod === 'token');
      if (btnUserPass) btnUserPass.classList.toggle('active', cloneMethod === 'user_pass');
      if (viewToken) viewToken.style.display = (cloneMethod === 'token') ? 'block' : 'none';
      if (viewUserPass) viewUserPass.style.display = (cloneMethod === 'user_pass') ? 'block' : 'none';
    } else if (cloneProto === 'ssh') {
      cloneMethod = (method === 'user_pass') ? 'user_pass' : 'key';
      const btnKey = byId('wg-clone-ssh-btn-key');
      const btnUserPass = byId('wg-clone-ssh-btn-userpass');
      const viewKey = byId('wg-clone-ssh-view-key');
      const viewUserPass = byId('wg-clone-ssh-view-userpass');

      if (btnKey) btnKey.classList.toggle('active', cloneMethod === 'key');
      if (btnUserPass) btnUserPass.classList.toggle('active', cloneMethod === 'user_pass');
      if (viewKey) viewKey.style.display = (cloneMethod === 'key') ? 'block' : 'none';
      if (viewUserPass) viewUserPass.style.display = (cloneMethod === 'user_pass') ? 'block' : 'none';
    }
  }

  // ---------------------------------------------------------------------------
  // SSH Key Generation & Public Key Copy
  // ---------------------------------------------------------------------------

  async function generateKey(context) {
    if (busy) return;
    setBusy(true);
    try {
      const targetSlug = (context === 'clone')
        ? (valueOf('wg-clone-name') || 'clone_key')
        : (currentStatus && (currentStatus.repo || currentStatus.slug) || 'repo_key');

      const result = await api('/walkthroughs/git/key/generate', {
        method: 'POST',
        body: JSON.stringify({ slug: targetSlug })
      });

      if (!result || !result.ok) {
        showLog((result && result.error) || 'Failed to generate SSH key.', true);
        return;
      }

      if (context === 'clone') {
        generatedCloneKeyPath = result.key_path;
        const info = byId('wg-clone-ssh-info');
        if (info) info.textContent = 'Generated Key: ' + result.key_name;
        const pubWrap = byId('wg-clone-pubkey-wrap');
        const pubPre = byId('wg-clone-pubkey');
        if (pubWrap && pubPre) {
          pubWrap.style.display = 'block';
          pubPre.textContent = result.public_key || '';
        }
        const keyArea = byId('wg-clone-ssh-key');
        if (keyArea) keyArea.value = '';
      } else {
        generatedRemoteKeyPath = result.key_path;
        const info = byId('wg-remote-ssh-info');
        if (info) info.textContent = 'Generated Key: ' + result.key_name;
        const pubWrap = byId('wg-remote-pubkey-wrap');
        const pubPre = byId('wg-remote-pubkey');
        if (pubWrap && pubPre) {
          pubWrap.style.display = 'block';
          pubPre.textContent = result.public_key || '';
        }
        const keyArea = byId('wg-remote-ssh-key');
        if (keyArea) keyArea.value = '';
      }

      showLog('Generated SSH key pair: ' + result.key_name + '. Copy the public key and add it to your Git host Deploy Keys.', false);
    } catch (e) {
      showLog('Key generation failed: ' + e.message, true);
    } finally {
      setBusy(false);
    }
  }

  function copyPubkey(preId) {
    const el = byId(preId);
    if (!el) return;
    const text = (el.textContent || '').trim();
    if (!text) return;

    if (navigator.clipboard && navigator.clipboard.writeText) {
      navigator.clipboard.writeText(text).then(function() {
        showLog('Copied public key to clipboard.', false);
      }).catch(function() {
        window.prompt('Copy public key:', text);
      });
    } else {
      window.prompt('Copy public key:', text);
    }
  }

  // ---------------------------------------------------------------------------
  // Render & UI State
  // ---------------------------------------------------------------------------

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

    const initialized = !!(status.initialized || status.linked);
    const hasRemote = !!(status.remote_linked || (status.remote && String(status.remote).trim()));

    // Status Badges
    const branchText = byId('wg-branch-text');
    const remoteUrlText = byId('wg-remote-url-text');
    const syncText = byId('wg-sync-text');
    const workingTreeText = byId('wg-working-tree-text');

    if (branchText) {
      branchText.textContent = status.branch || (status.detached ? '(detached)' : '-');
    }
    if (remoteUrlText) {
      const rem = status.remote || 'None';
      remoteUrlText.textContent = rem;
      remoteUrlText.title = rem;
    }
    if (syncText) {
      if (!hasRemote) {
        syncText.textContent = 'Local only';
        syncText.style.color = '#94a3b8';
      } else if (status.detached) {
        syncText.textContent = 'Detached HEAD';
        syncText.style.color = '#fbbf24';
      } else {
        const ahead = Number(status.ahead || 0);
        const behind = Number(status.behind || 0);
        if (ahead === 0 && behind === 0) {
          syncText.textContent = 'Up to date';
          syncText.style.color = '#10b981';
        } else {
          syncText.textContent = ahead + ' ahead, ' + behind + ' behind';
          syncText.style.color = '#38bdf8';
        }
      }
    }
    if (workingTreeText) {
      const changes = Array.isArray(status.changes) ? status.changes : [];
      if (changes.length === 0) {
        workingTreeText.textContent = 'Clean';
        workingTreeText.style.color = '#10b981';
      } else {
        workingTreeText.textContent = changes.length + ' uncommitted';
        workingTreeText.style.color = '#f59e0b';
      }
    }

    // Branch input pre-population
    const branchInput = byId('wg-branch');
    if (branchInput && !branchInput.value && status.branch) {
      branchInput.value = status.branch;
    }

    // Remote link status badge & unlink button
    const savedBadge = byId('wg-remote-saved-badge');
    if (savedBadge) {
      if (hasRemote) {
        savedBadge.textContent = 'Linked: ' + (status.branch || 'main');
        savedBadge.style.color = '#38bdf8';
        savedBadge.style.background = '#0c4a6e';
        savedBadge.style.borderColor = '#0284c7';
      } else {
        savedBadge.textContent = 'Not linked';
        savedBadge.style.color = '#94a3b8';
        savedBadge.style.background = '#1e293b';
        savedBadge.style.borderColor = '#334155';
      }
    }

    const unlinkBtn = byId('wg-unlink-btn');
    if (unlinkBtn) {
      unlinkBtn.style.display = hasRemote ? 'inline-block' : 'none';
    }

    // Sync Action Buttons
    ['wg-fetch-btn', 'wg-pull-btn', 'wg-push-btn'].forEach((btnId) => {
      const btn = byId(btnId);
      if (!btn) return;
      btn.disabled = busy || !hasRemote;
      btn.style.opacity = (!busy && !hasRemote) ? '0.45' : (busy ? '0.6' : '');
      btn.title = hasRemote ? '' : 'Configure and save a Remote URL above first';
    });

    // Populate credentials from status.auth if user hasn't modified settings
    if (!userEditedRemoteAuth) {
      const auth = status.auth || { type: 'none', protocol: 'none', auth_method: 'none' };
      let proto = auth.protocol || 'none';
      if (proto === 'none' && (auth.type === 'basic' || auth.type === 'http')) proto = 'https';
      if (proto === 'none' && (auth.type === 'ssh_key' || auth.type === 'ssh_password')) proto = 'ssh';

      let method = auth.auth_method || 'token';
      if (proto === 'ssh' && (auth.type === 'ssh_key' || method === 'key')) method = 'key';
      if (proto === 'ssh' && (auth.type === 'ssh_password' || method === 'user_pass')) method = 'user_pass';
      if (proto === 'https' && method !== 'user_pass') method = 'token';

      setRemoteProto(proto, false);
      setRemoteMethod(method, false);

      if (proto === 'https') {
        if (method === 'token') {
          const userEl = byId('wg-remote-token-user');
          const tokenEl = byId('wg-remote-token');
          if (userEl) userEl.value = auth.username || '';
          if (tokenEl) tokenEl.placeholder = auth.has_password ? '(unchanged - token configured)' : 'PAT (ghp_..., glpat-..., or token)';
        } else {
          const userEl = byId('wg-remote-user');
          const passEl = byId('wg-remote-pass');
          if (userEl) userEl.value = auth.username || '';
          if (passEl) passEl.placeholder = auth.has_password ? '(unchanged - password configured)' : 'Password';
        }
      } else if (proto === 'ssh') {
        if (method === 'key') {
          const info = byId('wg-remote-ssh-info');
          if (info) info.textContent = auth.key_name ? ('Active Key: ' + auth.key_name) : 'Private Key';
          const pubWrap = byId('wg-remote-pubkey-wrap');
          const pubPre = byId('wg-remote-pubkey');
          if (pubWrap && pubPre) {
            if (auth.public_key) {
              pubWrap.style.display = 'block';
              pubPre.textContent = auth.public_key;
            } else {
              pubWrap.style.display = 'none';
            }
          }
        } else {
          const userEl = byId('wg-remote-sshpass-user');
          const passEl = byId('wg-remote-sshpass-pass');
          if (userEl) userEl.value = auth.username || '';
          if (passEl) passEl.placeholder = auth.has_password ? '(unchanged - password configured)' : 'SSH user password';
        }
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

  // ---------------------------------------------------------------------------
  // Repository Management Actions
  // ---------------------------------------------------------------------------

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

  // ---------------------------------------------------------------------------
  // Remote & Sync Actions
  // ---------------------------------------------------------------------------

  async function saveRemote() {
    if (busy) return;
    const url = valueOf('wg-url');
    const branch = branchValue();
    const hasRemote = !!(currentStatus && currentStatus.remote_linked);

    if (!hasRemote && !url && remoteProto === 'none') {
      showLog('Enter a Remote Git URL to link this repository.', true);
      return;
    }

    let authData = { type: 'none' };
    if (remoteProto === 'https') {
      if (remoteMethod === 'token') {
        authData = {
          type: 'http',
          auth_method: 'token',
          username: valueOf('wg-remote-token-user'),
          password: valueOf('wg-remote-token')
        };
      } else {
        authData = {
          type: 'http',
          auth_method: 'user_pass',
          username: valueOf('wg-remote-user'),
          password: valueOf('wg-remote-pass')
        };
      }
    } else if (remoteProto === 'ssh') {
      if (remoteMethod === 'key') {
        authData = {
          type: 'ssh_key',
          auth_method: 'key',
          key_content: valueOf('wg-remote-ssh-key'),
          passphrase: valueOf('wg-remote-ssh-passphrase')
        };
        if (generatedRemoteKeyPath) {
          authData.key_path = generatedRemoteKeyPath;
        }
      } else {
        authData = {
          type: 'ssh_password',
          auth_method: 'user_pass',
          username: valueOf('wg-remote-sshpass-user'),
          password: valueOf('wg-remote-sshpass-pass')
        };
      }
    }

    const result = await simpleAction('remote', 'Save remote', { url: url, branch: branch, auth: authData });
    if (result && result.ok) {
      const urlInput = byId('wg-url');
      if (urlInput) urlInput.value = '';
      const tokenInput = byId('wg-remote-token');
      if (tokenInput) tokenInput.value = '';
      const passInput = byId('wg-remote-pass');
      if (passInput) passInput.value = '';
      const sshPassInput = byId('wg-remote-sshpass-pass');
      if (sshPassInput) sshPassInput.value = '';
      const sshKeyInput = byId('wg-remote-ssh-key');
      if (sshKeyInput) sshKeyInput.value = '';
      const sshPassphraseInput = byId('wg-remote-ssh-passphrase');
      if (sshPassphraseInput) sshPassphraseInput.value = '';
      generatedRemoteKeyPath = null;
      userEditedRemoteAuth = false;

      showLog(result.remote_linked ? 'Remote repository and credentials saved successfully.' : 'Remote settings updated.', false);
      await refresh();
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
    const result = await simpleAction('push', 'Push', { branch: branchValue() });
    if (result && result.ok) {
      await refresh();
    }
  }

  async function doUnlink() {
    if (busy) return;
    if (!window.confirm('Remove the remote URL link from this repository? Local walkthrough sets and commit history will be kept.')) return;
    const result = await simpleAction('unlink', 'Unlink');
    if (result && result.ok) await refresh();
  }

  function openHistory() {
    const slug = currentSlug || window.activeWalkthrough || '';
    close();
    if (typeof window.openGitHistoryModal === 'function') {
      window.openGitHistoryModal(slug);
    }
  }

  // ---------------------------------------------------------------------------
  // Clone Action
  // ---------------------------------------------------------------------------

  async function doClone() {
    if (busy) return;
    const url = valueOf('wg-clone-url');
    if (!url) {
      showLog('Enter a repository URL to clone.', true);
      return;
    }

    let authData = { type: 'none' };
    if (cloneProto === 'https') {
      if (cloneMethod === 'token') {
        authData = {
          type: 'http',
          auth_method: 'token',
          username: valueOf('wg-clone-token-user'),
          password: valueOf('wg-clone-token')
        };
      } else {
        authData = {
          type: 'http',
          auth_method: 'user_pass',
          username: valueOf('wg-clone-auth-user'),
          password: valueOf('wg-clone-auth-pass')
        };
      }
    } else if (cloneProto === 'ssh') {
      if (cloneMethod === 'key') {
        authData = {
          type: 'ssh_key',
          auth_method: 'key',
          key_content: valueOf('wg-clone-ssh-key'),
          passphrase: valueOf('wg-clone-ssh-passphrase')
        };
        if (generatedCloneKeyPath) {
          authData.key_path = generatedCloneKeyPath;
        }
      } else {
        authData = {
          type: 'ssh_password',
          auth_method: 'user_pass',
          username: valueOf('wg-clone-sshpass-user'),
          password: valueOf('wg-clone-sshpass-pass')
        };
      }
    }

    setBusy(true);
    try {
      const result = await api('/walkthroughs/git/clone', {
        method: 'POST',
        body: JSON.stringify({
          url: url,
          branch: valueOf('wg-clone-branch'),
          name: valueOf('wg-clone-name'),
          auth: authData
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

  // ---------------------------------------------------------------------------
  // Modal Open & Close
  // ---------------------------------------------------------------------------

  function open(slug, openAddTab) {
    currentSlug = String(slug || window.activeWalkthrough || 'default').trim();
    currentStatus = null;
    generatedCloneKeyPath = null;
    generatedRemoteKeyPath = null;
    userEditedRemoteAuth = false;

    // Reset inputs
    ['wg-url', 'wg-branch', 'wg-clone-url', 'wg-clone-branch', 'wg-clone-name', 'wg-create-repo-name', 'wg-create-repo-url',
     'wg-clone-token', 'wg-clone-token-user', 'wg-clone-auth-user', 'wg-clone-auth-pass',
     'wg-clone-sshpass-user', 'wg-clone-sshpass-pass', 'wg-clone-ssh-key', 'wg-clone-ssh-passphrase',
     'wg-remote-token', 'wg-remote-token-user', 'wg-remote-user', 'wg-remote-pass',
     'wg-remote-sshpass-user', 'wg-remote-sshpass-pass', 'wg-remote-ssh-key', 'wg-remote-ssh-passphrase'].forEach((id) => {
      const el = byId(id);
      if (el) el.value = '';
    });

    const clonePubWrap = byId('wg-clone-pubkey-wrap');
    if (clonePubWrap) clonePubWrap.style.display = 'none';
    const cloneSshInfo = byId('wg-clone-ssh-info');
    if (cloneSshInfo) cloneSshInfo.textContent = 'Private Key';

    const logWrap = byId('wg-log-wrap');
    if (logWrap) logWrap.style.display = 'none';

    // Reset clone auth controls
    setCloneProto('none');
    setCloneMethod('token');

    // Switch tab according to request
    switchTab(openAddTab ? 'add' : 'sync');

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
    switchTab: switchTab,
    setRemoteProto: function(p) { setRemoteProto(p, true); },
    setRemoteMethod: function(m) { setRemoteMethod(m, true); },
    setCloneProto: setCloneProto,
    setCloneMethod: setCloneMethod,
    refresh: refresh,
    switchRepo: switchRepo,
    createRepo: createRepo,
    renameRepo: renameRepo,
    deleteRepo: deleteRepo,
    saveRemote: saveRemote,
    fetch: doFetch,
    pull: doPull,
    push: doPush,
    unlink: doUnlink,
    openHistory: openHistory,
    clone: doClone,
    generateKey: generateKey,
    copyPubkey: copyPubkey
  };
})();
