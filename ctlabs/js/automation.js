/*
 -----------------------------------------------------------------------------
 File        : ctlabs/public/js/automation.js
 License     : MIT License
 -----------------------------------------------------------------------------
 */

// ----------------------------------------------------------------------------
// --- EDITOR SCOPE (lab vs control-plane) ---
// The Ansible/Terraform editor modals are shared between a lab and the global
// control plane. `window.automationBase` is null for lab scope (default) and
// '/controller' when a control-plane editor is open; every fetch uses ansScope()
// so the SAME modal/JS drives both. Lab-scoped calls that receive an explicit
// labName (Run/Stop/Destroy) pass it through so they still target the right lab
// even when no editor is open.
// ----------------------------------------------------------------------------
window.automationBase = null;

// Scope precedence:
//   1. explicit labName  -> /labs/<lab>  (lab Run/Stop/Destroy buttons)
//   2. automationBase    -> '/controller' (control-plane editor / runs)
//   3. currentEditLab    -> /labs/<lab>  (open editor fetches)
window.ansScope = function(labName) {
  if (labName) {
    const lab = labName.replace(/\.ya?ml$/i, '').split('/').map(encodeURIComponent).join('/');
    return '/labs/' + lab;
  }
  if (window.automationBase) return window.automationBase;
  const lab = (window.currentEditLab || '')
    .replace(/\.ya?ml$/i, '').split('/').map(encodeURIComponent).join('/');
  return '/labs/' + lab;
};

// Point an editor info-bar's <code> at the correct profile file for the current
// context. The modal is server-rendered with both variants in data-lab-label /
// data-ctl-label (see views/modals/*_editor.erb), so the label stays accurate
// even when a box-local override is active.
window.setProfileFileLabel = function(containerSelector, isController) {
  const code = document.querySelector(containerSelector + ' code');
  if (!code) return;
  const label = isController ? code.dataset.ctlLabel : code.dataset.labLabel;
  if (label) code.textContent = label;
};

window.loadAvailableRepositories = async function() {
  try {
    const scope = (typeof window.ansScope === 'function') ? window.ansScope() : '';
    const url = scope ? `${scope}/repositories?t=${Date.now()}` : `/automation/repositories?t=${Date.now()}`;
    const res = await fetch(url);
    if (!res.ok) return;
    const repos = await res.json();
    const ansList = document.getElementById('available-ansible-repos');
    if (ansList && repos.ansible) {
      ansList.innerHTML = repos.ansible.map(r => `<option value="${r}"></option>`).join('');
    }
    const tfList = document.getElementById('available-terraform-repos');
    if (tfList && repos.terraform) {
      tfList.innerHTML = repos.terraform.map(r => `<option value="${r}"></option>`).join('');
    }
  } catch (e) {
    console.warn("Could not load available repositories", e);
  }
};

// ----------------------------------------------------------------------------
// --- ANSIBLE ---
// ----------------------------------------------------------------------------
window.openAnsTab = function(tabId) {
  window.currentAnsibleTab = tabId;
  document.querySelectorAll(".ans-tab").forEach(tab => tab.style.display = "none");
      
  document.querySelectorAll(".ans-tablink").forEach(btn => {
    btn.classList.remove("w3-text-blue", "w3-text-teal");
    btn.style.backgroundColor = "transparent";
    btn.style.borderBottom = "none";
          
    if (btn.getAttribute("data-target-tab") === tabId) {
      if (tabId === 'AnsCommands') {
        btn.classList.add("w3-text-teal");
        btn.style.borderBottom = "2px solid #14b8a6";
      } else {
        btn.classList.add("w3-text-blue");
        btn.style.borderBottom = "2px solid #38bdf8";
      }
      btn.style.backgroundColor = "#1e293b";
    }
  });
      
  const activeTab = document.getElementById(tabId);
  if (activeTab) {
    if (tabId === 'AnsSettings') {
      activeTab.style.display = "block";
    } else {
      activeTab.style.display = "flex";
      activeTab.style.flexDirection = "column";
    }
  }

  if (tabId === 'AnsSettings') {
    const envEl = document.getElementById('edit-ansible-env');
    if (envEl) {
      setTimeout(() => {
        envEl.style.height = 'auto';
        envEl.style.height = Math.max(envEl.scrollHeight + 4, 90) + 'px';
      }, 0);
    }
  }

  const deleteBtn = document.getElementById('ans-delete-file-btn');
  const isProtectedTab = ['AnsSettings', 'AnsCommands', 'AnsPlayProfiles', 'AnsSetupProfiles', 'AnsPlaySetup'].includes(tabId);
  if (deleteBtn) deleteBtn.style.display = isProtectedTab ? 'none' : 'inline-block';

  const taId = (tabId === 'AnsCommands') ? 'edit-ansible-commands' : 'editor-' + tabId;
  if (window.cmEditors[taId]) {
    setTimeout(() => window.cmEditors[taId].refresh(), 50);
  }

  if (tabId === 'AnsCommands' && window.initAnsibleAdhocResizer) {
    setTimeout(() => window.initAnsibleAdhocResizer(), 20);
  }

  if (window.updateAnsibleVimStatus) {
    window.updateAnsibleVimStatus();
  }
      
  // --- NEW: Remember the actively clicked tab! ---
  if (window.currentEditLab) {
    localStorage.setItem('ans_active_tab_' + window.currentEditLab, tabId);
  }
};

  // INNER FILE BROWSER LOGIC
  window.openAnsibleFileBrowser = async function() {
      const safeLab = window.currentEditLab.replace(/\.ya?ml$/i, '').split('/').map(encodeURIComponent).join('/');
      try {
          const res = await fetch(`${window.ansScope()}/ansible/tree?t=${Date.now()}`);
          if (res.ok) {
              const files = await res.json();
              const datalist = document.getElementById('ans-files-datalist');
              datalist.innerHTML = '';
              files.forEach(f => {
                  const opt = document.createElement('option');
                  opt.value = f;
                  datalist.appendChild(opt);
              });
          }
      } catch (e) { console.error("Failed to load file tree", e); }

      document.getElementById('ans-file-browser-input').value = '';
      document.getElementById('ans-file-browser-modal').style.display = 'block';
  };

  window.confirmAnsibleFileBrowser = function() {
      const val = document.getElementById('ans-file-browser-input').value.trim();
      if (val) {
          window.fetchAnsibleFile(val);
          document.getElementById('ans-file-browser-modal').style.display = 'none';
      }
  };

  window.fetchAnsibleFile = async function(filepath) {
      const resultDiv = document.getElementById('ansible-editor-result');
      try {
          const rootDir = (document.getElementById('edit-ansible-root-dir')?.value || '').trim();
          let url = `${window.ansScope()}/ansible/file?path=${encodeURIComponent(filepath)}`;
          if (rootDir) url += `&root_dir=${encodeURIComponent(rootDir)}`;
          const res = await fetch(url);
          if (!res.ok) throw new Error((await res.json()).error);
          
          const data = await res.json();
          window.addAnsibleFileTab(filepath, data.content);
      } catch (err) {
          resultDiv.style.cssText = 'background-color: rgba(239, 68, 68, 0.2); color: #ef4444; border: 1px solid #ef4444; display: block; margin-top: 15px; padding: 8px;';
          resultDiv.innerHTML = '❌ ' + err.message;
      }
  };

  window.promptAndLoadAnsibleFile = function() {
      const filepath = prompt("Enter file path to open/create (e.g., playbooks/main.yml, inventories/hosts.ini):");
      if (filepath && filepath.trim() !== "") {
          window.fetchAnsibleFile(filepath.trim());
      }
  };

  window.loadActiveInventory = function() {
      let inv = document.getElementById('edit-ansible-inv').value.trim();
      
      // If blank, calculate the default auto-generated inventory name!
      if (!inv) { 
          const basename = window.currentEditLab.split('/').pop().replace('.yml', '.ini');
          inv = basename;
      }
      
      const finalPath = inv.includes('/') ? inv : `inventories/${inv}`;
      window.fetchAnsibleFile(finalPath);
  };

  // Add the loadActivePlaybook logic (updated to assume playbooks/ folder)
  window.loadActivePlaybook = function() {
      const book = document.getElementById('edit-ansible-book').value.trim();
      if (!book) { alert("Please enter a playbook filename first."); return; }
      const finalPath = book.includes('/') ? book : `playbooks/${book}`;
      window.fetchAnsibleFile(finalPath);
  };

  window.addAnsibleFileTab = function(filepath, content = "") {
      const tabId = 'ans-tab-' + filepath.replace(/[^a-zA-Z0-9_-]/g, '-');
      if (document.getElementById(tabId)) {
          window.openAnsTab(tabId);
          return;
      }

      const basename = filepath.split('/').pop();
      const btn = document.createElement('button');
      btn.className = "w3-bar-item w3-button ans-tablink";
      btn.title = filepath;
      btn.style.display = "flex";
      btn.style.alignItems = "center";
      btn.style.gap = "8px";
      
      // Inject the data-target-tab attribute!
      btn.setAttribute("data-target-tab", tabId);
      btn.setAttribute("onclick", `window.openAnsTab('${tabId}')`);
      
      btn.innerHTML = `
        <span><i class="fas fa-file-code"></i> ${basename}</span>
        <i class="fas fa-times w3-text-gray w3-hover-text-red" onclick="window.closeAnsibleTab(event, '${tabId}')" style="font-size: 1.1em; margin-top: 1px;"></i>
      `;
      
      const tabBar = document.getElementById('ans-tab-bar');
      tabBar.insertBefore(btn, tabBar.lastElementChild);

      const div = document.createElement('div');
      div.id = tabId;
      div.className = "ans-tab";
      div.style.display = "none";
      div.style.height = "100%";
      div.setAttribute('data-filepath', filepath);
      div.innerHTML = `<div style="flex: 1; min-height: 0; height: 100%; position: relative;"><textarea id="editor-${tabId}"></textarea></div>`;
      
      const container = document.getElementById('ans-editors-container');
      container.insertBefore(div, document.getElementById('ansible-editor-result'));

      let mode = 'yaml';
      if (filepath.endsWith('.ini') || filepath.endsWith('hosts')) mode = 'properties';
      else if (filepath.endsWith('.json')) mode = 'javascript';
      else if (filepath.endsWith('.sh')) mode = 'shell';
      else if (filepath.endsWith('.py')) mode = 'python';
      else if (filepath.endsWith('.j2')) mode = 'jinja2';

      const editor = window.initCodeEditor(`editor-${tabId}`, mode);
      editor.setValue(content);
      
      window.openAnsTab(tabId); // Open and highlight instantly
      window.updateAnsibleOpenTabs();
  };

window.loadAnsProfiles = async function() {
      const resultDiv = document.getElementById('ansible-editor-result');
      try {
          const safeLab = window.currentEditLab.replace(/\.ya?ml$/i, '').split('/').map(encodeURIComponent).join('/');
          const res = await fetch(`${window.ansScope()}/ansible/profiles?t=${Date.now()}`);
          if (!res.ok) throw new Error((await res.json()).error);
          
          const data = await res.json();
          
          const playProf  = window.initCodeEditor('editor-AnsPlayProfiles',  'yaml');
          const setupProf = window.initCodeEditor('editor-AnsSetupProfiles', 'yaml');
          if (window.automationBase === '/controller') {
            if (data['play_profiles_ctl.yml'])   playProf.setValue(data['play_profiles_ctl.yml']);
            if (data['setup_profiles_ctl.yml'])  setupProf.setValue(data['setup_profiles_ctl.yml']);
            if (!data['play_profiles_ctl.yml'] && data['play_profiles.yml'])   playProf.setValue(data['play_profiles.yml']);
            if (!data['setup_profiles_ctl.yml'] && data['setup_profiles.yml'])  setupProf.setValue(data['setup_profiles.yml']);
          } else {
            if (data['play_profiles.yml'])   playProf.setValue(data['play_profiles.yml']);
            if (data['setup_profiles.yml'])  setupProf.setValue(data['setup_profiles.yml']);
          }
      } catch (err) {
          resultDiv.style.cssText = 'background-color: rgba(239, 68, 68, 0.2); color: #ef4444; border: 1px solid #ef4444; display: block; margin-top: 15px; padding: 8px;';
          resultDiv.innerHTML = '❌ ' + err.message;
      }
  };

  // --- ANSIBLE WORKSPACE PROFILES STATE & HELPERS ---
  window.ansibleWorkspaces = {};
  window.currentAnsibleWorkspace = 'default';

  window.renderAnsibleWorkspaceSelect = function() {
    const select = document.getElementById('edit-ansible-workspace');
    if (!select) return;
    select.innerHTML = '';
    const names = Object.keys(window.ansibleWorkspaces || {});
    if (!names.includes('default')) names.unshift('default');
    names.forEach(name => {
      const opt = document.createElement('option');
      opt.value = name;
      opt.textContent = name;
      if (name === window.currentAnsibleWorkspace) opt.selected = true;
      select.appendChild(opt);
    });
    const badge = document.getElementById('ans-active-workspace-badge');
    if (badge) badge.textContent = window.currentAnsibleWorkspace;
  };

  window.snapshotActiveAnsibleWorkspace = function() {
    const ws = window.currentAnsibleWorkspace || 'default';
    if (!window.ansibleWorkspaces) window.ansibleWorkspaces = {};
    if (!window.ansibleWorkspaces[ws]) window.ansibleWorkspaces[ws] = {};

    const setupVal = window.cmEditors['editor-AnsPlaySetup'] ? window.cmEditors['editor-AnsPlaySetup'].getValue() : '';
    const cmdVal = window.cmEditors['edit-ansible-commands'] ? window.cmEditors['edit-ansible-commands'].getValue() : '';

    const tagsRaw = (document.getElementById('edit-ansible-tags')?.value || '').trim();
    const tagsArr = tagsRaw ? tagsRaw.split(',').map(s => s.trim()).filter(Boolean) : [];

    const envRaw = (document.getElementById('edit-ansible-env')?.value || '').trim();
    const envArr = envRaw ? envRaw.split('\n').map(s => s.trim()).filter(Boolean) : [];

    const adhocInv = (document.getElementById('edit-ansible-adhoc-inv')?.value || '').trim();
    let invVal = (document.getElementById('edit-ansible-inv')?.value || '').trim();
    if (window.currentAnsibleTab === 'AnsCommands' && adhocInv) invVal = adhocInv;
    else if (!invVal && adhocInv) invVal = adhocInv;

    window.ansibleWorkspaces[ws] = {
      ...window.ansibleWorkspaces[ws],
      root_dir: (document.getElementById('edit-ansible-root-dir')?.value || '').trim(),
      book: (document.getElementById('edit-ansible-book')?.value || '').trim(),
      inv: invVal,
      limit: (document.getElementById('edit-ansible-limit')?.value || '').trim(),
      extra_args: (document.getElementById('edit-ansible-extra-args')?.value || '').trim(),
      tags: tagsArr,
      env: envArr,
      commands: cmdVal,
      setup_yaml: setupVal
    };
  };

  window.applyAnsibleWorkspace = function(wsName) {
    if (!window.ansibleWorkspaces || !window.ansibleWorkspaces[wsName]) return;
    window.currentAnsibleWorkspace = wsName;
    const cfg = window.ansibleWorkspaces[wsName];

    const select = document.getElementById('edit-ansible-workspace');
    if (select) select.value = wsName;
    const badge = document.getElementById('ans-active-workspace-badge');
    if (badge) badge.textContent = wsName;

    if (document.getElementById('edit-ansible-root-dir')) {
      document.getElementById('edit-ansible-root-dir').value = cfg.root_dir || '';
    }
    if (document.getElementById('edit-ansible-book')) {
      document.getElementById('edit-ansible-book').value = cfg.book || 'main.yml';
    }
    if (document.getElementById('edit-ansible-inv')) {
      let invVal = cfg.inv || '';
      if (Array.isArray(invVal)) invVal = invVal.join(', ');
      if (!invVal) {
        invVal = (window.automationBase === '/controller')
          ? 'controller.ini'
          : (window.currentEditLab ? window.currentEditLab.split('/').pop().replace(/\.ya?ml$/i, '.ini') : 'default.ini');
      }
      document.getElementById('edit-ansible-inv').value = invVal;
      if (document.getElementById('edit-ansible-adhoc-inv')) {
        document.getElementById('edit-ansible-adhoc-inv').value = invVal;
      }
    }
    if (document.getElementById('edit-ansible-limit')) {
      document.getElementById('edit-ansible-limit').value = cfg.limit || cfg.hosts || '';
    }
    if (document.getElementById('edit-ansible-extra-args')) {
      document.getElementById('edit-ansible-extra-args').value = cfg.extra_args || '';
    }
    if (document.getElementById('edit-ansible-tags')) {
      let tagsVal = cfg.tags || '';
      if (Array.isArray(tagsVal)) tagsVal = tagsVal.join(', ');
      document.getElementById('edit-ansible-tags').value = tagsVal;
    }
    const envEl = document.getElementById('edit-ansible-env');
    if (envEl) {
      let envVal = cfg.env || '';
      if (Array.isArray(envVal)) envVal = envVal.join('\n');
      envEl.value = envVal;
      setTimeout(() => {
        envEl.style.height = 'auto';
        envEl.style.height = Math.max(envEl.scrollHeight + 4, 90) + 'px';
      }, 0);
    }

    // Update Execution Script CodeMirror
    if (window.cmEditors['edit-ansible-commands']) {
      window.cmEditors['edit-ansible-commands'].setValue(cfg.commands || '');
    }

    // Update Play Setup CodeMirror
    if (window.cmEditors['editor-AnsPlaySetup']) {
      let setupStr = cfg.setup_yaml;
      if (typeof setupStr !== 'string') {
        if (typeof cfg.setup === 'string') {
          setupStr = cfg.setup;
        } else if (cfg.setup && typeof cfg.setup === 'object') {
          try {
            setupStr = (window.jsyaml && window.jsyaml.dump) ? window.jsyaml.dump(cfg.setup) : JSON.stringify(cfg.setup, null, 2);
          } catch(e) { setupStr = ''; }
        } else {
          setupStr = '';
        }
      }
      window.cmEditors['editor-AnsPlaySetup'].setValue(setupStr || '');
    }

    // Delete button state (disable deletion of default)
    const delBtn = document.getElementById('ans-delete-ws-btn');
    if (delBtn) delBtn.disabled = (wsName === 'default');

    // Trigger Git status check for the new root_dir
    if (window.fetchAnsibleGitStatus) {
      window.fetchAnsibleGitStatus();
    }
  };

  window.onAnsibleWorkspaceChange = function(newWs) {
    window.snapshotActiveAnsibleWorkspace();
    window.applyAnsibleWorkspace(newWs);
  };

  window.promptNewAnsibleWorkspace = function() {
    const name = prompt("Enter new workspace profile name (e.g. adhoc, setup, staging):");
    if (!name) return;
    const cleanName = name.trim().toLowerCase().replace(/[^a-z0-9_\-]/g, '_');
    if (!cleanName) { alert("Invalid profile name."); return; }
    if (window.ansibleWorkspaces[cleanName]) { alert(`Workspace '${cleanName}' already exists.`); return; }

    window.snapshotActiveAnsibleWorkspace();
    const current = window.ansibleWorkspaces[window.currentAnsibleWorkspace] || {};
    window.ansibleWorkspaces[cleanName] = JSON.parse(JSON.stringify(current));
    window.renderAnsibleWorkspaceSelect();
    window.applyAnsibleWorkspace(cleanName);
  };

  window.promptCloneAnsibleWorkspace = function() {
    const name = prompt(`Clone '${window.currentAnsibleWorkspace}' as:`, `${window.currentAnsibleWorkspace}_copy`);
    if (!name) return;
    const cleanName = name.trim().toLowerCase().replace(/[^a-z0-9_\-]/g, '_');
    if (!cleanName) { alert("Invalid profile name."); return; }
    if (window.ansibleWorkspaces[cleanName]) { alert(`Workspace '${cleanName}' already exists.`); return; }

    window.snapshotActiveAnsibleWorkspace();
    const current = window.ansibleWorkspaces[window.currentAnsibleWorkspace] || {};
    window.ansibleWorkspaces[cleanName] = JSON.parse(JSON.stringify(current));
    window.renderAnsibleWorkspaceSelect();
    window.applyAnsibleWorkspace(cleanName);
  };

  window.promptDeleteAnsibleWorkspace = function() {
    const ws = window.currentAnsibleWorkspace;
    if (ws === 'default') {
      alert("Cannot delete default workspace profile.");
      return;
    }
    if (!confirm(`Are you sure you want to delete workspace profile '${ws}'?`)) return;

    delete window.ansibleWorkspaces[ws];
    window.currentAnsibleWorkspace = 'default';
    window.renderAnsibleWorkspaceSelect();
    window.applyAnsibleWorkspace('default');
  };

  window.openAnsibleEditor = async function(labName, base, initialTab) {
    window.automationBase = base || null;
    window.currentEditLab = labName;
    if (window.refreshAnsibleToolbar) window.refreshAnsibleToolbar();
    window.setProfileFileLabel('#AnsSetupProfiles', window.automationBase === '/controller');
    window.setProfileFileLabel('#AnsPlayProfiles',  window.automationBase === '/controller');
    const savedActiveTab = initialTab || localStorage.getItem('ans_active_tab_' + window.currentEditLab);

    const resultDiv = document.getElementById('ansible-editor-result');
    if (resultDiv) resultDiv.style.display = 'none';
    document.querySelector('.ans-tablink').click();
    try {
        const safeLab = labName.replace(/\.ya?ml$/i, '').split('/').map(encodeURIComponent).join('/');
        const res = await fetch(`${window.ansScope()}/ansible/config?t=${Date.now()}`);
        if (!res.ok) throw new Error("Could not fetch ansible node configuration");
        
        const data = await res.json();
        let play = data.json.play || {};
        if (typeof play === 'string') play = { book: play };

        // Populate available topology hosts datalist for limit targeting
        const hostsList = data.hosts || data.json?.hosts || [];
        const hostsDatalist = document.getElementById('available-ansible-hosts');
        if (hostsDatalist && Array.isArray(hostsList)) {
          hostsDatalist.innerHTML = '';
          hostsList.forEach(h => {
            const opt = document.createElement('option');
            opt.value = h;
            hostsDatalist.appendChild(opt);
          });
        }
        
        const book = play.book || 'main.yml';
        let invVal = play.inv;
        if (Array.isArray(invVal)) {
            invVal = invVal.join(', ');
        } else if (typeof invVal === 'string') {
            invVal = invVal.trim();
        } else {
            invVal = '';
        }
        if (!invVal) {
            invVal = (window.automationBase === '/controller')
                ? 'controller.ini'
                : window.currentEditLab.split('/').pop().replace(/\.ya?ml$/i, '.ini');
        }
        if (invVal && !invVal.includes('/') && !invVal.includes(',')) {
            if (window.automationBase === '/controller' && !invVal.startsWith('controller')) {
                invVal = 'controller.ini';
            }
            if (!invVal.endsWith('.ini')) invVal += '.ini';
        }
        if (play.custom_inv && !invVal.includes(play.custom_inv)) {
            invVal += `, ${play.custom_inv}`;
        }
        const customInv = play.custom_inv || '';

        // Workspace Profiles Setup
        window.ansibleWorkspaces = {};
        if (play.workspaces && typeof play.workspaces === 'object' && Object.keys(play.workspaces).length > 0) {
          window.ansibleWorkspaces = JSON.parse(JSON.stringify(play.workspaces));
        }

        // Initialize default workspace if not present
        if (!window.ansibleWorkspaces['default']) {
          window.ansibleWorkspaces['default'] = {
            root_dir: play.root_dir || '',
            book: book,
            inv: invVal,
            custom_inv: customInv,
            limit: play.limit || play.hosts || '',
            extra_args: play.extra_args || '',
            tags: play.tags || [],
            env: play.env || [],
            commands: play.commands || '',
            setup_yaml: data.json.setup_yaml || ''
          };
        }

        // Active workspace
        window.currentAnsibleWorkspace = play.workspace || 'default';
        if (!window.ansibleWorkspaces[window.currentAnsibleWorkspace]) {
          window.currentAnsibleWorkspace = Object.keys(window.ansibleWorkspaces)[0] || 'default';
        }

        document.getElementById('edit-ansible-book').value = book;
        if (document.getElementById('edit-ansible-root-dir')) {
            document.getElementById('edit-ansible-root-dir').value = play.root_dir || '';
        }
        window.loadAvailableRepositories && window.loadAvailableRepositories();

        const invInput = document.getElementById('edit-ansible-inv');
        if (invInput) invInput.value = invVal;
        const adhocInvInput = document.getElementById('edit-ansible-adhoc-inv');
        if (adhocInvInput) adhocInvInput.value = invVal;
        if (document.getElementById('edit-ansible-custom-inv')) {
            document.getElementById('edit-ansible-custom-inv').value = customInv;
        }
        if (document.getElementById('edit-ansible-limit')) {
            document.getElementById('edit-ansible-limit').value = play.limit || play.hosts || '';
        }
        if (document.getElementById('edit-ansible-extra-args')) {
            document.getElementById('edit-ansible-extra-args').value = play.extra_args || '';
        }
        const tagsStr = (play.tags || []).join(', ');
        document.getElementById('edit-ansible-tags').value = tagsStr;
        if (document.getElementById('edit-ansible-adhoc-tags')) {
            document.getElementById('edit-ansible-adhoc-tags').value = tagsStr;
        }
        
        const envEl = document.getElementById('edit-ansible-env');
        if (envEl) {
            envEl.value = (play.env || []).join('\n');
            setTimeout(() => {
                envEl.style.height = 'auto';
                envEl.style.height = Math.max(envEl.scrollHeight + 4, 90) + 'px';
            }, 0);
        }
        
        // Initialize CodeMirror editor for custom commands / execution script
        if (!window.cmEditors['edit-ansible-commands']) {
          window.cmEditors['edit-ansible-commands'] = window.initCodeEditor('edit-ansible-commands', 'shell');
        }
        window.cmEditors['edit-ansible-commands'].setValue(play.commands || '');

        // Initialize Play Setup editor
        const playSetupEd = window.initCodeEditor('editor-AnsPlaySetup', 'yaml');
        playSetupEd.setValue(data.json.setup_yaml || '');

        // Render Workspaces dropdown and apply active profile
        window.renderAnsibleWorkspaceSelect();
        window.applyAnsibleWorkspace(window.currentAnsibleWorkspace);
        
        await window.loadAnsProfiles();
        
        document.getElementById('ansible-editor-modal').style.display = 'block';
        document.querySelectorAll('.ans-tablink:not([data-pinned]):not(:first-child):not(:last-child)').forEach(e => e.remove());
        document.querySelectorAll('.ans-tab[data-filepath]').forEach(e => {
            const taId = e.querySelector('textarea')?.id;
            if (taId && window.cmEditors[taId]) delete window.cmEditors[taId];
            e.remove();
        });
        
        // 🔥 RESTORE TABS FROM MEMORY 🔥
        const savedTabsStr = localStorage.getItem('ansible_tabs_' + window.currentEditLab);
        let savedTabs = savedTabsStr ? JSON.parse(savedTabsStr) : null;

        if (savedTabs && savedTabs.length > 0) {
          for (const filepath of savedTabs) {
            await window.fetchAnsibleFile(filepath);
          }
        } else {
          // Only load defaults if no tabs were saved
          await window.fetchAnsibleFile(book.includes('/') ? book : `playbooks/${book}`);
          const invList = invVal.split(/[,\n]+/).map(s => s.trim()).filter(Boolean);
          for (const inv of invList) {
            await window.fetchAnsibleFile(inv.includes('/') ? inv : `inventories/${inv}`);
          }
        }

        // --- NEW: Restore the exact active tab, or fallback to the right-most tab ---
        if (savedActiveTab && document.getElementById(savedActiveTab)) {
              window.openAnsTab(savedActiveTab);
        } else {
          const fileTabs = document.querySelectorAll('.ans-tablink:not([data-pinned]):not(:first-child):not(:last-child)');
          if (fileTabs.length > 0) {
            fileTabs[fileTabs.length - 1].click();
          }
        }

        // Initialize Ad-hoc Resizer
        if (window.initAnsibleAdhocResizer) {
          window.initAnsibleAdhocResizer();
        }

        // Fetch Git status for Ansible repository
        if (window.fetchAnsibleGitStatus) {
          window.fetchAnsibleGitStatus();
        }
    } catch (err) { alert("Error: " + err.message); }
};

  window.saveAnsibleConfig = async function() {
      const resultDiv = document.getElementById('ansible-editor-result');
      if (window.snapshotActiveAnsibleWorkspace) {
        window.snapshotActiveAnsibleWorkspace();
      }

      const filesData = {};
      document.querySelectorAll('.ans-tab[data-filepath]').forEach(tab => {
          const filepath = tab.getAttribute('data-filepath');
          const taId = tab.querySelector('textarea').id;
          filesData[filepath] = window.cmEditors[taId].getValue();
      });

      const playProf  = window.cmEditors['editor-AnsPlayProfiles']  ? window.cmEditors['editor-AnsPlayProfiles'].getValue()  : '';
      const setupProf = window.cmEditors['editor-AnsSetupProfiles'] ? window.cmEditors['editor-AnsSetupProfiles'].getValue() : '';
      const playSetup = window.cmEditors['editor-AnsPlaySetup']     ? window.cmEditors['editor-AnsPlaySetup'].getValue()     : '';
      const commands  = window.cmEditors['edit-ansible-commands']   ? window.cmEditors['edit-ansible-commands'].getValue()   : '';

      const invVal = (document.getElementById('edit-ansible-inv')?.value || '').trim();
      const customInvVal = (document.getElementById('edit-ansible-custom-inv')?.value || '').trim();
      const limitVal = (document.getElementById('edit-ansible-limit')?.value || '').trim();
      const extraArgsVal = (document.getElementById('edit-ansible-extra-args')?.value || '').trim();

      const formData = new URLSearchParams({
          workspace: window.currentAnsibleWorkspace || 'default',
          workspaces: JSON.stringify(window.ansibleWorkspaces || {}),
          root_dir: (document.getElementById('edit-ansible-root-dir')?.value || '').trim(),
          book: document.getElementById('edit-ansible-book').value,
          inv: invVal,
          custom_inv: customInvVal,
          limit: limitVal,
          extra_args: extraArgsVal,
          commands: commands,
          tags: document.getElementById('edit-ansible-tags').value,
          env: document.getElementById('edit-ansible-env').value,
          setup: playSetup,
          ans_files: JSON.stringify(filesData),
          play_profiles: playProf,
          setup_profiles: setupProf
      });

      resultDiv.style.cssText = 'background-color: rgba(245, 158, 11, 0.2); color: #f59e0b; border: 1px solid #f59e0b; display: block; margin-top: 15px; padding: 8px;';
      resultDiv.innerHTML = '<i class="fas fa-spinner fa-spin"></i> Saving configuration and files...';

      // Disable while the request is in flight so a second click can't fire a
      // duplicate save (the two POSTs would race the reload below).
      const saveBtn = document.getElementById('ans-save-btn');
      const saveBtnHtml = saveBtn ? saveBtn.innerHTML : null;
      if (saveBtn) {
          saveBtn.disabled = true;
          saveBtn.innerHTML = '<i class="fas fa-spinner fa-spin"></i> Saving...';
      }

      const safeLab = window.currentEditLab.replace(/\.ya?ml$/i, '').split('/').map(encodeURIComponent).join('/');
      try {
          const res = await fetch(`${window.ansScope()}/ansible/edit`, {
              method: 'POST',
              headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
              body: formData.toString()
          });
          
          if (res.ok) {
              resultDiv.style.cssText = 'background-color: rgba(16, 185, 129, 0.2); color: #10b981; border: 1px solid #10b981; display: block; margin-top: 15px; padding: 8px;';
              resultDiv.textContent = '✅ All files and workspace profiles saved successfully.';
              setTimeout(() => location.reload(), 800);
              return true;
          } else {
              // Safely handle HTML vs JSON error responses
              const errText = await res.text();
              let errMsg = errText;
              try { errMsg = JSON.parse(errText).error; } catch(e) {}
              throw new Error(errMsg);
          }
      } catch (err) {
          resultDiv.style.cssText = 'background-color: rgba(239, 68, 68, 0.2); color: #ef4444; border: 1px solid #ef4444; display: block; margin-top: 15px; padding: 8px; max-height: 200px; overflow-y: auto;';
          resultDiv.innerHTML = '❌ ' + err.message;
          if (saveBtn) { saveBtn.disabled = false; saveBtn.innerHTML = saveBtnHtml; }
          return false;
      }
  };

  window.clearAnsibleModalOutput = function() {
    const out = document.getElementById('ans-modal-adhoc-output');
    if (out) out.innerHTML = '';
  };

  window.runAnsibleAdhocModal = async function() {
    const runBtn = document.getElementById('ans-modal-run-adhoc-btn');
    const stopBtn = document.getElementById('ans-modal-stop-adhoc-btn');
    const statusBadge = document.getElementById('ans-modal-adhoc-status');
    const outPre = document.getElementById('ans-modal-adhoc-output');

    if (runBtn) {
      runBtn.disabled = true;
      runBtn.innerHTML = '<i class="fas fa-spinner fa-spin"></i> Running...';
    }
    if (outPre) {
      outPre.innerHTML = '<i style="color: #64748b;">Starting ad-hoc execution...</i>\n';
    }

    try {
      const activeWs = window.currentAnsibleWorkspace || 'default';
      const wsCfg = (window.ansibleWorkspaces && window.ansibleWorkspaces[activeWs]) || {};
      const invVal = (document.getElementById('edit-ansible-adhoc-inv')?.value || document.getElementById('edit-ansible-inv')?.value || wsCfg.inv || '').trim();
      const limitVal = (document.getElementById('edit-ansible-limit')?.value || wsCfg.limit || '').trim();
      const adhocTagsEl = document.getElementById('edit-ansible-adhoc-tags');
      const tagsVal = adhocTagsEl ? adhocTagsEl.value.trim() : (document.getElementById('edit-ansible-tags')?.value || (Array.isArray(wsCfg.tags) ? wsCfg.tags.join(',') : '')).trim();
      const extraArgsVal = (document.getElementById('edit-ansible-extra-args')?.value || wsCfg.extra_args || '').trim();
      const commandsVal = window.cmEditors['edit-ansible-commands'] ? window.cmEditors['edit-ansible-commands'].getValue() : '';

      const payload = new URLSearchParams({
        workspace: activeWs,
        inv: invVal,
        limit: limitVal,
        tags: tagsVal,
        book: wsCfg.book || (document.getElementById('edit-ansible-book')?.value || '').trim(),
        commands: commandsVal,
        extra_args: extraArgsVal
      });

      const res = await fetch(`${window.ansScope()}/playbook`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
        body: payload.toString()
      });
      const data = await res.json().catch(() => ({}));
      if (res.ok) {
        if (outPre && typeof window.streamAnsibleOutput === 'function') {
          window.streamAnsibleOutput({
            logId: data.log_id,
            initialOffset: typeof data.offset === 'number' ? data.offset : 0,
            scope: window.ansScope(),
            preEl: 'ans-modal-adhoc-output',
            statusBadgeEl: 'ans-modal-adhoc-status',
            scrollStatusEl: 'ans-modal-scroll-status',
            stopBtnEl: 'ans-modal-stop-adhoc-btn',
            runBtnEl: runBtn,
            runBtnOriginalHtml: '<i class="fas fa-play"></i> Run Ad-Hoc',
            fullLogLinkEl: 'ans-modal-full-log-link',
            pollerKey: 'modal'
          });
        } else {
          window.location.href = data.log_url || '/logs/current';
        }
      } else {
        alert("Error starting ad-hoc execution: " + (data.error || 'Failed to start'));
        if (runBtn) {
          runBtn.disabled = false;
          runBtn.innerHTML = '<i class="fas fa-play"></i> Run Ad-Hoc';
        }
      }
    } catch(err) {
      alert("Error starting ad-hoc execution: " + err.message);
      if (runBtn) {
        runBtn.disabled = false;
        runBtn.innerHTML = '<i class="fas fa-play"></i> Run Ad-Hoc';
      }
    }
  };

  window.stopAnsiblePlaybookModal = async function() {
    const stopBtn = document.getElementById('ans-modal-stop-adhoc-btn');
    if (stopBtn) {
      stopBtn.disabled = true;
      stopBtn.innerHTML = '<i class="fas fa-spinner fa-spin"></i> Stopping...';
    }
    try {
      await fetch(`${window.ansScope()}/playbook/stop`, { method: 'POST' });
    } catch(e) {
      console.warn("Modal stop failed:", e);
    }
  };

  window.saveAndRunAnsible = async function() {
    const runBtn = document.getElementById('ans-run-btn');
    const runBtnHtml = runBtn ? runBtn.innerHTML : null;
    if (runBtn) {
      runBtn.disabled = true;
      runBtn.innerHTML = '<i class="fas fa-spinner fa-spin"></i> Running...';
    }

    const saved = await window.saveAnsibleConfig();
    if (!saved) {
      if (runBtn) { runBtn.disabled = false; runBtn.innerHTML = runBtnHtml; }
      return;
    }

    // Switch to Ad-Hoc / Runner tab so the user sees live streaming output
    if (typeof window.openAnsTab === 'function') {
      window.openAnsTab('AnsCommands');
    }

    const outPre = document.getElementById('ans-modal-adhoc-output');
    if (outPre) outPre.innerHTML = '<i style="color: #64748b;">Starting execution...</i>\n';

    try {
      const activeWs = window.currentAnsibleWorkspace || 'default';
      const wsCfg = (window.ansibleWorkspaces && window.ansibleWorkspaces[activeWs]) || {};
      const invVal = (document.getElementById('edit-ansible-adhoc-inv')?.value || document.getElementById('edit-ansible-inv')?.value || wsCfg.inv || '').trim();
      const limitVal = (document.getElementById('edit-ansible-limit')?.value || wsCfg.limit || '').trim();
      const adhocTagsEl = document.getElementById('edit-ansible-adhoc-tags');
      const tagsVal = adhocTagsEl ? adhocTagsEl.value.trim() : (document.getElementById('edit-ansible-tags')?.value || (Array.isArray(wsCfg.tags) ? wsCfg.tags.join(',') : '')).trim();
      const extraArgsVal = (document.getElementById('edit-ansible-extra-args')?.value || wsCfg.extra_args || '').trim();
      const commandsVal = window.cmEditors['edit-ansible-commands'] ? window.cmEditors['edit-ansible-commands'].getValue() : '';

      const payload = new URLSearchParams({
        workspace: activeWs,
        inv: invVal,
        limit: limitVal,
        tags: tagsVal,
        book: wsCfg.book || (document.getElementById('edit-ansible-book')?.value || '').trim(),
        commands: commandsVal,
        extra_args: extraArgsVal
      });

      const res = await fetch(`${window.ansScope()}/playbook`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
        body: payload.toString()
      });
      const data = await res.json().catch(() => ({}));
      if (res.ok) {
        if (outPre && typeof window.streamAnsibleOutput === 'function') {
          window.streamAnsibleOutput({
            logId: data.log_id,
            initialOffset: typeof data.offset === 'number' ? data.offset : 0,
            scope: window.ansScope(),
            preEl: 'ans-modal-adhoc-output',
            statusBadgeEl: 'ans-modal-adhoc-status',
            scrollStatusEl: 'ans-modal-scroll-status',
            stopBtnEl: 'ans-modal-stop-adhoc-btn',
            runBtnEl: runBtn,
            runBtnOriginalHtml: '<i class="fas fa-play"></i> Run Now',
            fullLogLinkEl: 'ans-modal-full-log-link',
            pollerKey: 'modal'
          });
        } else {
          window.location.href = data.log_url || '/logs/current';
        }
      } else {
        alert("Error starting playbook: " + (data.error || 'Failed to start'));
        if (runBtn) { runBtn.disabled = false; runBtn.innerHTML = runBtnHtml; }
      }
    } catch(err) {
      alert("Error starting playbook: " + err.message);
      if (runBtn) { runBtn.disabled = false; runBtn.innerHTML = runBtnHtml; }
    }
  };

  // --- GIT SUPPORT FOR ANSIBLE REPOSITORY ---
  window.toggleAnsibleGitMenu = function(e) {
    if (e) e.stopPropagation();
    const menu = document.getElementById('ans-git-menu');
    if (!menu) return;
    const isHidden = menu.style.display === 'none' || !menu.style.display;
    menu.style.display = isHidden ? 'block' : 'none';
    if (isHidden) {
      window.fetchAnsibleGitStatus();
    }
  };

  window.getAnsibleRootDir = function() {
    return (document.getElementById('edit-ansible-root-dir')?.value || '').trim();
  };

  window.fetchAnsibleGitStatus = async function(manual) {
    try {
      const rootDir = window.getAnsibleRootDir();
      const query = rootDir ? `?root_dir=${encodeURIComponent(rootDir)}` : '';
      const res = await fetch(`${window.ansScope()}/ansible/git/status${query}`);
      if (!res.ok) return;
      const data = await res.json();
      if (!data.git_repo) {
        const btn = document.getElementById('ans-git-btn');
        if (btn) btn.style.display = 'none';
        return;
      }
      const btn = document.getElementById('ans-git-btn');
      if (btn) btn.style.display = 'inline-flex';

      const branchLabel = document.getElementById('ans-git-branch-label');
      if (branchLabel) branchLabel.textContent = data.branch || 'main';

      const dirtyDot = document.getElementById('ans-git-dirty-badge');
      const summarySpan = document.getElementById('ans-git-status-summary');
      const countBadge = document.getElementById('ans-git-commit-count');

      if (data.clean) {
        if (dirtyDot) dirtyDot.style.display = 'none';
        if (summarySpan) { summarySpan.textContent = 'clean'; summarySpan.style.color = '#38bdf8'; }
        if (countBadge) countBadge.style.display = 'none';
      } else {
        const count = (data.modified?.length || 0) + (data.untracked?.length || 0);
        if (dirtyDot) dirtyDot.style.display = 'inline-block';
        if (summarySpan) { summarySpan.textContent = `modified (${count})`; summarySpan.style.color = '#f59e0b'; }
        if (countBadge) { countBadge.textContent = count; countBadge.style.display = 'inline-block'; }
      }
      if (manual) {
        alert(`Git repository is on branch '${data.branch}'. Status: ${data.clean ? 'clean' : 'modified (' + ((data.modified?.length || 0) + (data.untracked?.length || 0)) + ' files)'}`);
      }
      window.currentAnsibleGitStatus = data;
    } catch (err) {
      console.error("fetchAnsibleGitStatus error:", err);
    }
  };

  window.openAnsibleGitCommitModal = async function() {
    const menu = document.getElementById('ans-git-menu');
    if (menu) menu.style.display = 'none';
    const preview = document.getElementById('ans-git-commit-status-preview');
    if (preview) preview.innerHTML = 'Checking status...';
    document.getElementById('ans-git-commit-modal').style.display = 'block';

    await window.fetchAnsibleGitStatus();
    const status = window.currentAnsibleGitStatus || {};
    if (preview) {
      if (status.clean) {
        preview.innerHTML = '<span style="color: #38bdf8;">Working tree clean, nothing to commit.</span>';
      } else {
        let html = '';
        if (status.modified && status.modified.length > 0) {
          html += '<div style="color: #f59e0b; margin-bottom: 4px;">Modified files:</div>';
          status.modified.forEach(f => { html += `<div>&nbsp;&nbsp;M ${f}</div>`; });
        }
        if (status.untracked && status.untracked.length > 0) {
          html += '<div style="color: #22c55e; margin-top: 4px; margin-bottom: 4px;">Untracked files:</div>';
          status.untracked.forEach(f => { html += `<div>&nbsp;&nbsp;? ${f}</div>`; });
        }
        preview.innerHTML = html;
      }
    }
  };

  window.confirmAnsibleGitCommit = async function() {
    const msgInput = document.getElementById('ans-git-commit-message');
    const msg = (msgInput?.value || '').trim();
    if (!msg) { alert("Please enter a commit message."); return; }

    const submitBtn = document.getElementById('ans-git-commit-submit-btn');
    if (submitBtn) { submitBtn.disabled = true; submitBtn.innerHTML = '<i class="fas fa-spinner fa-spin"></i> Committing...'; }

    try {
      const rootDir = window.getAnsibleRootDir();
      const payload = new URLSearchParams({ message: msg, root_dir: rootDir });
      const res = await fetch(`${window.ansScope()}/ansible/git/commit`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
        body: payload.toString()
      });
      const data = await res.json().catch(() => ({}));
      if (res.ok && data.success) {
        alert("Changes committed successfully!");
        document.getElementById('ans-git-commit-modal').style.display = 'none';
        if (msgInput) msgInput.value = '';
        window.fetchAnsibleGitStatus();
      } else {
        alert("Commit failed: " + (data.error || 'Unknown error'));
      }
    } catch (err) {
      alert("Commit error: " + err.message);
    } finally {
      if (submitBtn) { submitBtn.disabled = false; submitBtn.innerHTML = '<i class="fas fa-check"></i> Commit'; }
    }
  };

  window.ansibleGitPull = async function() {
    const menu = document.getElementById('ans-git-menu');
    if (menu) menu.style.display = 'none';
    if (!confirm("Pull latest changes from remote (git pull --rebase)?")) return;

    try {
      const rootDir = window.getAnsibleRootDir();
      const payload = new URLSearchParams({ root_dir: rootDir });
      const res = await fetch(`${window.ansScope()}/ansible/git/pull`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
        body: payload.toString()
      });
      const data = await res.json().catch(() => ({}));
      if (res.ok && data.success) {
        alert("Pull successful:\n" + (data.output || 'Up to date'));
        window.fetchAnsibleGitStatus();
      } else {
        alert("Pull failed: " + (data.error || 'Unknown error'));
      }
    } catch (err) {
      alert("Pull error: " + err.message);
    }
  };

  window.ansibleGitPush = async function() {
    const menu = document.getElementById('ans-git-menu');
    if (menu) menu.style.display = 'none';
    if (!confirm("Push commits to remote (git push)?")) return;

    try {
      const rootDir = window.getAnsibleRootDir();
      const payload = new URLSearchParams({ root_dir: rootDir });
      const res = await fetch(`${window.ansScope()}/ansible/git/push`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
        body: payload.toString()
      });
      const data = await res.json().catch(() => ({}));
      if (res.ok && data.success) {
        alert("Push successful:\n" + (data.output || 'Pushed to remote'));
        window.fetchAnsibleGitStatus();
      } else {
        alert("Push failed: " + (data.error || 'Unknown error'));
      }
    } catch (err) {
      alert("Push error: " + err.message);
    }
  };

  window.ansibleGitCommits = [];
  window.ansibleGitSelectedHash = null;

  window.escapeAnsHtml = function(str) {
    if (!str) return '';
    return String(str)
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;')
      .replace(/'/g, '&#039;');
  };

  window.formatAnsibleGitDiff = function(diffText) {
    if (!diffText) return '';
    const lines = diffText.split('\n');
    return lines.map(line => {
      let bg = 'transparent';
      let fg = '#cbd5e1';
      let weight = '400';

      if (line.startsWith('+++') || line.startsWith('---')) {
        fg = '#94a3b8';
        weight = '600';
      } else if (line.startsWith('+')) {
        bg = 'rgba(16, 185, 129, 0.2)';
        fg = '#86efac';
      } else if (line.startsWith('-')) {
        bg = 'rgba(239, 68, 68, 0.2)';
        fg = '#fca5a5';
      } else if (line.startsWith('@@')) {
        bg = 'rgba(56, 189, 248, 0.12)';
        fg = '#38bdf8';
        weight = '600';
      } else if (line.startsWith('diff --git') || line.startsWith('index ')) {
        fg = '#64748b';
        weight = '600';
      } else if (line.startsWith('commit ')) {
        fg = '#38bdf8';
        weight = '600';
      } else if (line.startsWith('Author:') || line.startsWith('Date:')) {
        fg = '#94a3b8';
      }

      const escaped = window.escapeAnsHtml(line);
      const text = escaped.length > 0 ? escaped : '&nbsp;';
      return `<div style="background: ${bg}; color: ${fg}; font-weight: ${weight}; padding: 0 4px; border-radius: 2px; min-height: 1.45em; margin: 0; box-sizing: border-box;">${text}</div>`;
    }).join('');
  };

  window.openAnsibleGitHistoryModal = function() {
    const menu = document.getElementById('ans-git-menu');
    if (menu) menu.style.display = 'none';
    document.getElementById('ans-git-history-modal').style.display = 'block';
    window.loadAnsibleGitHistory();
  };

  window.loadAnsibleGitHistory = async function() {
    const listEl = document.getElementById('ans-git-history-list');
    const diffEl = document.getElementById('ans-git-diff-body');
    const titleEl = document.getElementById('ans-git-diff-title');
    const metaEl = document.getElementById('ans-git-diff-meta');
    const branchBadge = document.getElementById('ans-git-history-branch-badge');
    const workingBadge = document.getElementById('ans-git-history-working-badge');
    const countBadge = document.getElementById('ans-git-commits-count');
    const repoLabel = document.getElementById('ans-git-history-repo-label');

    const rootDir = window.getAnsibleRootDir();
    if (repoLabel) repoLabel.textContent = rootDir || '/root/ctlabs-ansible';

    if (listEl) listEl.innerHTML = '<div style="color: #64748b; font-size: 0.85em; text-align: center; padding: 20px;"><i class="fas fa-spinner fa-spin"></i> Loading revisions...</div>';
    if (diffEl) diffEl.innerHTML = '<span style="color: #64748b;">Select a commit from the list on the left to inspect file changes and unified diffs.</span>';
    if (titleEl) titleEl.textContent = 'Select a revision to view diff';
    if (metaEl) metaEl.textContent = '';
    window.ansibleGitSelectedHash = null;

    try {
      // 1. Fetch Git status
      const statusRes = await fetch(`${window.ansScope()}/ansible/git/status${rootDir ? '?root_dir=' + encodeURIComponent(rootDir) : ''}`);
      let statusData = {};
      if (statusRes.ok) {
        statusData = await statusRes.json();
      }

      if (branchBadge) {
        branchBadge.textContent = `branch: ${statusData.branch || 'main'}`;
      }
      const hasWorkingChanges = !statusData.clean;
      if (workingBadge) {
        workingBadge.style.display = hasWorkingChanges ? 'inline-flex' : 'none';
      }

      // 2. Fetch commits log
      const query = rootDir ? `?root_dir=${encodeURIComponent(rootDir)}&limit=50` : '?limit=50';
      const res = await fetch(`${window.ansScope()}/ansible/git/history${query}`);
      if (!res.ok) throw new Error("Failed to fetch history");
      const data = await res.json();
      window.ansibleGitCommits = data.commits || [];

      if (countBadge) {
        countBadge.textContent = `${window.ansibleGitCommits.length} commits`;
      }

      // Render cards
      window.renderAnsibleGitHistoryList(hasWorkingChanges, statusData);

      // Auto-select working tree if modified, else top commit
      if (hasWorkingChanges) {
        window.showAnsibleGitDiff('working');
      } else if (window.ansibleGitCommits.length > 0) {
        window.showAnsibleGitDiff(window.ansibleGitCommits[0].hash);
      } else {
        if (listEl) listEl.innerHTML = '<div style="color: #94a3b8; font-size: 0.85em; text-align: center; padding: 20px;">No revisions found yet.</div>';
      }
    } catch (err) {
      if (listEl) listEl.innerHTML = `<div style="color: #ef4444; padding: 15px;">Error: ${err.message}</div>`;
    }
  };

  window.renderAnsibleGitHistoryList = function(hasWorkingChanges, statusData) {
    const listEl = document.getElementById('ans-git-history-list');
    if (!listEl) return;
    listEl.innerHTML = '';

    // Render Working Tree card if there are uncommitted changes
    if (hasWorkingChanges) {
      const isSelected = (window.ansibleGitSelectedHash === 'working');
      const item = document.createElement('div');
      item.className = 'ans-git-commit-card';
      item.dataset.hash = 'working';
      item.style.cssText = `padding: 10px 12px; border-radius: 6px; background: ${isSelected ? '#1e293b' : '#131d31'}; border: 1px solid ${isSelected ? '#f59e0b' : '#78350f'}; cursor: pointer; transition: all 0.15s ease;`;

      const modCount = (statusData.modified?.length || 0) + (statusData.untracked?.length || 0);
      item.innerHTML = `
        <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 4px;">
          <span style="font-size: 0.78em; color: #f59e0b; font-weight: 700; display: inline-flex; align-items: center; gap: 4px;">
            <i class="fas fa-pencil-alt"></i> Working Tree
          </span>
          <span style="font-size: 0.72em; color: #fde68a; background: #78350f; padding: 1px 6px; border-radius: 3px;">Uncommitted</span>
        </div>
        <div style="font-size: 0.84em; color: #f8fafc; font-weight: 500; margin-bottom: 4px;">
          Uncommitted changes (${modCount} file${modCount === 1 ? '' : 's'})
        </div>
        <div style="font-size: 0.72em; color: #94a3b8;">
          Click to inspect diff and pending changes
        </div>
      `;
      item.addEventListener('click', () => window.showAnsibleGitDiff('working'));
      listEl.appendChild(item);
    }

    // Render commit cards
    window.ansibleGitCommits.forEach(c => {
      const isSelected = (c.hash === window.ansibleGitSelectedHash);
      const item = document.createElement('div');
      item.className = 'ans-git-commit-card';
      item.dataset.hash = c.hash;
      item.style.cssText = `padding: 10px 12px; border-radius: 6px; background: ${isSelected ? '#1e293b' : '#131d31'}; border: 1px solid ${isSelected ? '#0284c7' : '#334155'}; cursor: pointer; transition: all 0.15s ease;`;

      item.innerHTML = `
        <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 4px;">
          <span style="font-family: ui-monospace, monospace; font-size: 0.78em; color: #38bdf8; font-weight: 700;">${c.hash}</span>
          <span style="font-size: 0.72em; color: #94a3b8;">${c.date}</span>
        </div>
        <div style="font-size: 0.84em; color: #f8fafc; font-weight: 500; margin-bottom: 4px; word-break: break-word; line-height: 1.35;">${window.escapeAnsHtml(c.message)}</div>
        <div style="font-size: 0.72em; color: #64748b;"><i class="fas fa-user" style="font-size: 0.85em;"></i> ${window.escapeAnsHtml(c.author)}</div>
      `;
      item.addEventListener('click', () => window.showAnsibleGitDiff(c.hash));
      listEl.appendChild(item);
    });
  };

  window.showAnsibleGitDiff = async function(hash) {
    window.ansibleGitSelectedHash = hash;
    const listEl = document.getElementById('ans-git-history-list');
    const diffEl = document.getElementById('ans-git-diff-body');
    const titleEl = document.getElementById('ans-git-diff-title');
    const metaEl = document.getElementById('ans-git-diff-meta');

    // Highlight selected item in list
    if (listEl) {
      listEl.querySelectorAll('.ans-git-commit-card').forEach(card => {
        const isSel = (card.dataset.hash === hash);
        if (card.dataset.hash === 'working') {
          card.style.background = isSel ? '#1e293b' : '#131d31';
          card.style.borderColor = isSel ? '#f59e0b' : '#78350f';
        } else {
          card.style.background = isSel ? '#1e293b' : '#131d31';
          card.style.borderColor = isSel ? '#0284c7' : '#334155';
        }
      });
    }

    if (diffEl) diffEl.innerHTML = '<span style="color: #64748b;"><i class="fas fa-spinner fa-spin"></i> Loading diff...</span>';

    const rootDir = window.getAnsibleRootDir();
    const query = rootDir ? `?root_dir=${encodeURIComponent(rootDir)}` : '';

    if (hash === 'working') {
      if (titleEl) titleEl.textContent = 'Uncommitted Changes (Working Tree vs HEAD)';
      if (metaEl) metaEl.textContent = 'Active working tree modifications';

      try {
        const res = await fetch(`${window.ansScope()}/ansible/git/diff/working${query}`);
        const data = await res.json();
        if (!data.ok) throw new Error(data.error || 'Failed to inspect working tree diff');

        const diffText = (data.diff && data.diff.trim()) ? data.diff : (data.stat && data.stat.trim() ? data.stat : '');
        if (!diffText) {
          if (diffEl) diffEl.innerHTML = '<span style="color: #10b981;"><i class="fas fa-check-circle"></i> Working tree is clean. No uncommitted modifications.</span>';
        } else {
          if (diffEl) diffEl.innerHTML = window.formatAnsibleGitDiff(diffText);
        }
      } catch (err) {
        if (diffEl) diffEl.innerHTML = `<span style="color: #ef4444;">Error loading working tree diff: ${window.escapeAnsHtml(err.message)}</span>`;
      }
      return;
    }

    const commit = (window.ansibleGitCommits || []).find(c => c.hash === hash);
    if (titleEl) titleEl.textContent = commit ? commit.message : `Commit ${hash}`;
    if (metaEl) {
      metaEl.textContent = commit ? `Commit ${commit.hash} by ${commit.author} (${commit.date})` : '';
    }

    try {
      const res = await fetch(`${window.ansScope()}/ansible/git/diff/${encodeURIComponent(hash)}${query}`);
      const data = await res.json();
      if (!data.ok) throw new Error(data.error || 'Failed to load diff');

      const diffText = (data.diff && data.diff.trim()) ? data.diff : (data.stat && data.stat.trim() ? data.stat : '');
      if (!diffText) {
        if (diffEl) diffEl.innerHTML = '<span style="color: #64748b;">(No text changes in this commit)</span>';
      } else {
        if (diffEl) diffEl.innerHTML = window.formatAnsibleGitDiff(diffText);
      }
    } catch (err) {
      if (diffEl) diffEl.innerHTML = `<span style="color: #ef4444;">Error loading diff: ${window.escapeAnsHtml(err.message)}</span>`;
    }
  };

  window.openAnsibleGitBranchModal = async function() {
    const menu = document.getElementById('ans-git-menu');
    if (menu) menu.style.display = 'none';
    const select = document.getElementById('ans-git-branch-select');
    select.innerHTML = '<option>Loading branches...</option>';
    document.getElementById('ans-git-branch-modal').style.display = 'block';

    try {
      const rootDir = window.getAnsibleRootDir();
      const query = rootDir ? `?root_dir=${encodeURIComponent(rootDir)}` : '';
      const res = await fetch(`${window.ansScope()}/ansible/git/branches${query}`);
      if (!res.ok) throw new Error("Failed to fetch branches");
      const data = await res.json();
      select.innerHTML = '';
      const branches = data.branches || [];
      branches.forEach(b => {
        const opt = document.createElement('option');
        opt.value = b.name;
        opt.textContent = b.name + (b.current ? ' (current)' : '');
        if (b.current) opt.selected = true;
        select.appendChild(opt);
      });
    } catch (err) {
      select.innerHTML = `<option>Error: ${err.message}</option>`;
    }
  };

  window.confirmAnsibleGitBranch = async function() {
    const select = document.getElementById('ans-git-branch-select');
    const newNameInput = document.getElementById('ans-git-new-branch-name');
    const newBranch = (newNameInput?.value || '').trim();
    const targetBranch = newBranch || select.value;

    if (!targetBranch) { alert("Please select or enter a branch."); return; }

    try {
      const rootDir = window.getAnsibleRootDir();
      const payload = new URLSearchParams({
        branch: targetBranch,
        create: !!newBranch,
        root_dir: rootDir
      });
      const res = await fetch(`${window.ansScope()}/ansible/git/branch`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
        body: payload.toString()
      });
      const data = await res.json().catch(() => ({}));
      if (res.ok && data.success) {
        alert(`Switched to branch '${targetBranch}'`);
        document.getElementById('ans-git-branch-modal').style.display = 'none';
        if (newNameInput) newNameInput.value = '';
        window.fetchAnsibleGitStatus();
      } else {
        alert("Branch checkout failed: " + (data.error || 'Unknown error'));
      }
    } catch (err) {
      alert("Branch checkout error: " + err.message);
    }
  };

  // Close Git menu when clicking outside
  document.addEventListener('click', function(e) {
    const menu = document.getElementById('ans-git-menu');
    const btn = document.getElementById('ans-git-btn');
    if (menu && menu.style.display !== 'none' && !menu.contains(e.target) && (!btn || !btn.contains(e.target))) {
      menu.style.display = 'none';
    }
  });
  
  window.updateAnsibleOpenTabs = function() {
      if (!window.currentEditLab) return;
      const tabs = [];
      document.querySelectorAll('.ans-tab[data-filepath]').forEach(tab => {
          tabs.push(tab.getAttribute('data-filepath'));
      });
      localStorage.setItem('ansible_tabs_' + window.currentEditLab, JSON.stringify(tabs));
  };

  window.closeAnsibleTab = function(e, tabId) {
      e.stopPropagation();
      const tabBtn = e.currentTarget.closest('button');
      if (tabBtn) tabBtn.remove();
      
      const tabDiv = document.getElementById(tabId);
      if (tabDiv) {
          const taId = tabDiv.querySelector('textarea')?.id;
          if (taId && window.cmEditors[taId]) delete window.cmEditors[taId];
          tabDiv.remove();
      }
      document.querySelector('.ans-tablink').click();
      window.updateAnsibleOpenTabs(); // Update memory!
  };

  window.deleteActiveAnsibleFile = async function() {
      const activeTab = document.querySelector('.ans-tab[style*="display: block"]');
      if (!activeTab || activeTab.id === 'AnsSettings') return;
      const filepath = activeTab.getAttribute('data-filepath');
      if (!filepath) return;

      if (!confirm(`WARNING: Are you sure you want to permanently delete '${filepath}' from disk?`)) return;

      const safeLab = window.currentEditLab.replace(/\.ya?ml$/i, '').split('/').map(encodeURIComponent).join('/');
      try {
          const rootDir = (document.getElementById('edit-ansible-root-dir')?.value || '').trim();
          const bodyData = { filepath: filepath };
          if (rootDir) bodyData.root_dir = rootDir;
          const res = await fetch(`${window.ansScope()}/ansible/file/delete`, {
              method: 'POST',
              headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
              body: new URLSearchParams(bodyData).toString()
          });
          
          if (res.ok) {
              const tabBtn = document.querySelector(`button[onclick*="openAnsTab(event, '${activeTab.id}')"]`);
              if (tabBtn) tabBtn.remove();
              const taId = activeTab.querySelector('textarea')?.id;
              if (taId && window.cmEditors[taId]) delete window.cmEditors[taId];
              activeTab.remove();
              
              document.querySelector('.ans-tablink').click();
              window.updateAnsibleOpenTabs(); // Update memory!
          } else throw new Error((await res.json()).error);
      } catch (err) { alert("Failed to delete file: " + err.message); }
  };

// --- ANSIBLE IN-VIEW LIVE OUTPUT STREAMING & AD-HOC SPLITTER ---
window.initAnsibleAdhocResizer = function() {
  const resizer = document.getElementById('ans-adhoc-drag-resizer');
  const scriptContainer = document.getElementById('ans-adhoc-script-container');
  const consoleContainer = document.getElementById('ans-adhoc-console-container');
  if (!resizer || !scriptContainer || !consoleContainer) return;
  if (resizer.__resizerInitialized) return;
  resizer.__resizerInitialized = true;

  // Restore saved console height from localStorage
  try {
    const savedH = localStorage.getItem('ctlabs_ans_adhoc_console_h');
    if (savedH && parseInt(savedH, 10) >= 80) {
      consoleContainer.style.height = parseInt(savedH, 10) + 'px';
    }
  } catch(e) {}

  let isDragging = false;
  let startY = 0;
  let startConsoleH = 0;

  resizer.addEventListener('mousedown', function(e) {
    e.preventDefault();
    isDragging = true;
    startY = e.clientY;
    startConsoleH = consoleContainer.offsetHeight;

    resizer.style.backgroundColor = '#14b8a6';
    document.body.style.cursor = 'row-resize';
    document.body.style.userSelect = 'none';

    const onMouseMove = function(moveEvent) {
      if (!isDragging) return;
      const deltaY = moveEvent.clientY - startY;
      // Dragging UP grows console; dragging DOWN shrinks console
      const newConsoleH = Math.max(70, Math.min(650, startConsoleH - deltaY));
      consoleContainer.style.height = newConsoleH + 'px';

      if (window.cmEditors['edit-ansible-commands']) {
        window.cmEditors['edit-ansible-commands'].refresh();
      }
    };

    const onMouseUp = function() {
      if (!isDragging) return;
      isDragging = false;
      resizer.style.backgroundColor = '#1e293b';
      document.body.style.cursor = '';
      document.body.style.userSelect = '';
      window.removeEventListener('mousemove', onMouseMove);
      window.removeEventListener('mouseup', onMouseUp);

      try {
        localStorage.setItem('ctlabs_ans_adhoc_console_h', consoleContainer.offsetHeight);
      } catch(e) {}

      if (window.cmEditors['edit-ansible-commands']) {
        window.cmEditors['edit-ansible-commands'].refresh();
      }
    };

    window.addEventListener('mousemove', onMouseMove);
    window.addEventListener('mouseup', onMouseUp);
  });
};

window.clearAnsibleCardOutput = function() {
  const out = document.getElementById('card-ans-output');
  if (out) out.innerHTML = '';
};

window.toggleAnsibleCardOutputSize = function() {
  const out = document.getElementById('card-ans-output');
  const btn = document.getElementById('card-ans-expand-btn');
  if (!out) return;
  const isExpanded = out.style.height === '480px';
  out.style.height = isExpanded ? '220px' : '480px';
  out.style.maxHeight = isExpanded ? '400px' : '650px';
  if (btn) {
    btn.innerHTML = isExpanded ? '<i class="fas fa-expand-alt"></i>' : '<i class="fas fa-compress-alt"></i>';
  }
};

window.activeAnsibleStreamPollers = window.activeAnsibleStreamPollers || {};

window.streamAnsibleOutput = function(options) {
  const pollerKey = options.pollerKey || 'default';
  if (window.activeAnsibleStreamPollers[pollerKey]) {
    clearTimeout(window.activeAnsibleStreamPollers[pollerKey]);
    delete window.activeAnsibleStreamPollers[pollerKey];
  }

  const preEl = typeof options.preEl === 'string' ? document.getElementById(options.preEl) : options.preEl;
  if (!preEl) return;

  const statusBadgeEl = typeof options.statusBadgeEl === 'string' ? document.getElementById(options.statusBadgeEl) : options.statusBadgeEl;
  const scrollStatusEl = typeof options.scrollStatusEl === 'string' ? document.getElementById(options.scrollStatusEl) : options.scrollStatusEl;
  const stopBtnEl = typeof options.stopBtnEl === 'string' ? document.getElementById(options.stopBtnEl) : options.stopBtnEl;
  const runBtnEl = typeof options.runBtnEl === 'string' ? document.getElementById(options.runBtnEl) : options.runBtnEl;
  const fullLogLinkEl = typeof options.fullLogLinkEl === 'string' ? document.getElementById(options.fullLogLinkEl) : options.fullLogLinkEl;

  if (statusBadgeEl) {
    statusBadgeEl.className = 'w3-badge w3-tiny w3-round w3-teal';
    statusBadgeEl.innerHTML = '<i class="fas fa-spinner fa-spin"></i> Running...';
  }
  if (stopBtnEl) stopBtnEl.style.display = 'inline-block';
  if (fullLogLinkEl && options.logId) {
    fullLogLinkEl.href = `/logs?id=${encodeURIComponent(options.logId)}`;
  }

  let isAutoScroll = true;
  preEl.onscroll = () => {
    const atBottom = preEl.scrollHeight - preEl.scrollTop <= preEl.clientHeight + 30;
    isAutoScroll = atBottom;
    if (scrollStatusEl) {
      scrollStatusEl.textContent = isAutoScroll ? '' : '⏸ Paused';
    }
  };

  let currentOffset = typeof options.initialOffset === 'number' ? options.initialOffset : 0;
  let isFetching = false;
  let nonRunningChecks = 0;
  let pollAttempts = 0;
  let hasSeenRunning = false;

  async function poll() {
    if (isFetching) return;
    isFetching = true;
    pollAttempts++;

    try {
      // 1. Fetch streaming log content
      if (options.logId) {
        const url = `/logs/content?id=${encodeURIComponent(options.logId)}&offset=${currentOffset}&format=json&t=${Date.now()}`;
        const res = await fetch(url, { cache: 'no-store' });
        if (res.ok) {
          const data = await res.json();
          currentOffset = data.offset;
          if (data.content && data.content.trim() !== '') {
            if (preEl.innerHTML.includes('Starting ad-hoc execution') ||
                preEl.innerHTML.includes('Starting execution') ||
                preEl.innerHTML.includes('Starting playbook execution') ||
                preEl.innerHTML.includes('Waiting for log output...')) {
              preEl.innerHTML = '';
            }
            preEl.insertAdjacentHTML('beforeend', data.content);
            if (isAutoScroll) preEl.scrollTop = preEl.scrollHeight;
          }
        }
      }

      // 2. Query status endpoint
      const scopeUrl = options.scope || (typeof window.ansScope === 'function' ? window.ansScope() : '');
      const statusRes = await fetch(`${scopeUrl}/playbook/status?t=${Date.now()}`);
      let isRunning = false;
      if (statusRes.ok) {
        const statusData = await statusRes.json();
        isRunning = Boolean(statusData.running);
        if (!options.logId && statusData.log_id) {
          options.logId = statusData.log_id;
          if (fullLogLinkEl) fullLogLinkEl.href = `/logs?id=${encodeURIComponent(options.logId)}`;
        }
      }

      if (isRunning) {
        hasSeenRunning = true;
        nonRunningChecks = 0;
      } else {
        if (hasSeenRunning || pollAttempts >= 5) {
          nonRunningChecks++;
        }
      }

      const logText = preEl.textContent || '';
      const hasCompletedMarker = logText.includes('--- Playbook execution completed ---') ||
                                 logText.includes('Playbook execution completed') ||
                                 logText.includes('PLAY RECAP') ||
                                 logText.includes('Playbook failed:') ||
                                 logText.includes('stopped by user');

      const isFinished = (hasSeenRunning && nonRunningChecks >= 2) ||
                         (hasCompletedMarker && !isRunning) ||
                         (nonRunningChecks >= 3 && pollAttempts >= 8);

      // After confirmation that run is completed, do final flush and finish
      if (isFinished && pollAttempts > 1) {
        if (options.logId) {
          try {
            const finalRes = await fetch(`/logs/content?id=${encodeURIComponent(options.logId)}&offset=${currentOffset}&format=json&t=${Date.now()}`, { cache: 'no-store' });
            if (finalRes.ok) {
              const finalData = await finalRes.json();
              if (finalData.content && finalData.content.trim() !== '') {
                preEl.insertAdjacentHTML('beforeend', finalData.content);
                if (isAutoScroll) preEl.scrollTop = preEl.scrollHeight;
              }
            }
          } catch(e) {}
        }

        const finalLogText = preEl.textContent || '';
        const hasStopped = finalLogText.includes('stopped by user');
        const hasFailed = finalLogText.includes('Playbook execution failed') || finalLogText.includes('Playbook failed') || (finalLogText.includes('failed=') && !finalLogText.includes('failed=0'));

        if (statusBadgeEl) {
          if (hasStopped) {
            statusBadgeEl.className = 'w3-badge w3-tiny w3-round w3-orange';
            statusBadgeEl.innerHTML = '<i class="fas fa-stop"></i> Stopped';
          } else if (hasFailed) {
            statusBadgeEl.className = 'w3-badge w3-tiny w3-round w3-red';
            statusBadgeEl.innerHTML = '<i class="fas fa-times"></i> Failed';
          } else {
            statusBadgeEl.className = 'w3-badge w3-tiny w3-round w3-green';
            statusBadgeEl.innerHTML = '<i class="fas fa-check"></i> Completed';
          }
        }

        if (stopBtnEl) stopBtnEl.style.display = 'none';
        if (runBtnEl) {
          runBtnEl.disabled = false;
          if (options.runBtnOriginalHtml) runBtnEl.innerHTML = options.runBtnOriginalHtml;
        }

        const pbRunBtn = document.getElementById('card-ans-run-playbook-btn');
        if (pbRunBtn) {
          pbRunBtn.disabled = false;
          pbRunBtn.innerHTML = '<i class="fas fa-play"></i> Run Playbook';
          pbRunBtn.classList.replace('w3-grey', 'w3-green');
        }
        const pbStopBtn = document.getElementById('card-ans-stop-playbook-btn');
        if (pbStopBtn) pbStopBtn.style.display = 'none';

        delete window.activeAnsibleStreamPollers[pollerKey];
        return;
      }
    } catch(err) {
      console.warn("streamAnsibleOutput error:", err);
    } finally {
      isFetching = false;
      window.activeAnsibleStreamPollers[pollerKey] = setTimeout(poll, 1000);
    }
  }

  poll();
};

window.runAnsiblePlaybook = async function(event, labName) {
  const btn = event.currentTarget;
  const originalHtml = btn.innerHTML;
  btn.disabled = true;
  btn.innerHTML = '<i class="fas fa-spinner fa-spin"></i> Starting...';
  btn.classList.replace('w3-green', 'w3-grey');

  const outContainer = document.getElementById('card-ans-output-container');
  const outPre = document.getElementById('card-ans-output');
  const outTitle = document.getElementById('card-ans-output-title');
  if (outContainer) outContainer.style.display = 'block';
  if (outTitle) outTitle.textContent = 'Ansible Output';
  if (outPre) outPre.innerHTML = '<i style="color: #64748b;">Starting playbook execution...</i>\n';

  try {
    const res = await fetch(`${window.ansScope(labName)}/playbook`, { method: 'POST' });
    const data = await res.json().catch(() => ({}));
    if (res.ok) {
      if (outPre) {
        window.streamAnsibleOutput({
          logId: data.log_id,
          initialOffset: typeof data.offset === 'number' ? data.offset : 0,
          scope: window.ansScope(labName),
          preEl: 'card-ans-output',
          statusBadgeEl: 'card-ans-status-badge',
          scrollStatusEl: 'card-ans-scroll-status',
          stopBtnEl: 'card-ans-stop-playbook-btn',
          runBtnEl: btn,
          runBtnOriginalHtml: '<i class="fas fa-play"></i> Run Playbook',
          fullLogLinkEl: 'card-ans-full-log-link',
          pollerKey: 'card'
        });
      } else {
        window.location.href = data.log_url || '/logs/current';
      }
    } else {
      alert("Error: " + (data.error || 'Failed to start playbook'));
      btn.disabled = false;
      btn.innerHTML = originalHtml;
      btn.classList.replace('w3-grey', 'w3-green');
    }
  } catch (err) {
    alert("Error: " + err.message);
    btn.disabled = false;
    btn.innerHTML = originalHtml;
    btn.classList.replace('w3-grey', 'w3-green');
  }
};

window.runAnsibleAdhocCard = function(event, labName) {
  return window.runAnsiblePlaybook(event, labName);
};

window.stopAnsiblePlaybook = async function(event, labName) {
  const btn = event.currentTarget;
  try {
    btn.disabled = true;
    btn.innerHTML = '<i class="fas fa-spinner fa-spin"></i> Stopping...';
    const res = await fetch(`${window.ansScope(labName)}/playbook/stop`, { method: 'POST' });
    const data = await res.json().catch(() => ({}));
    if (!res.ok) throw new Error(data.message || data.error || 'Stop failed');
    if (!document.getElementById('card-ans-output')) {
      window.location.reload();
    }
  } catch (err) {
    btn.disabled = false;
    btn.innerHTML = '<i class="fas fa-exclamation-triangle"></i> Stop failed';
    btn.title = err.message;
  }
};

document.addEventListener('DOMContentLoaded', () => {
  const cardOut = document.getElementById('card-ans-output');
  const cardContainer = document.getElementById('card-ans-output-container');
  const badge = document.getElementById('card-ans-status-badge');
  if (cardOut && cardContainer && badge && badge.textContent.includes('Running')) {
    window.streamAnsibleOutput({
      preEl: 'card-ans-output',
      statusBadgeEl: 'card-ans-status-badge',
      scrollStatusEl: 'card-ans-scroll-status',
      stopBtnEl: 'card-ans-stop-playbook-btn',
      runBtnEl: 'card-ans-run-playbook-btn',
      fullLogLinkEl: 'card-ans-full-log-link',
      pollerKey: 'card'
    });
  }
});


// ----------------------------------------------------------------------------
// --- TERRAFORM ---
// ----------------------------------------------------------------------------

window.openTfTab = function(tabId) {
      document.querySelectorAll(".tf-tab").forEach(tab => tab.style.display = "none");
      
      document.querySelectorAll(".tf-tablink").forEach(btn => {
          btn.classList.remove("w3-text-blue", "w3-text-purple");
          btn.style.backgroundColor = "transparent";
          btn.style.borderBottom = "none";
          
          if (btn.getAttribute("data-target-tab") === tabId) {
              // Give the Execution Script tab a cool purple highlight, others blue
              const highlightColor = tabId === 'TfCommands' ? 'purple' : 'blue';
              const hexColor = tabId === 'TfCommands' ? '#a855f7' : '#38bdf8';
              
              btn.classList.add(`w3-text-${highlightColor}`);
              btn.style.backgroundColor = "#1e293b";
              btn.style.borderBottom = `2px solid ${hexColor}`;
          }
      });
      
      const activeTab = document.getElementById(tabId);
      if (activeTab) {
          // FIX: Only apply flex to the Commands tab so we don't destroy the Settings layout!
          if (tabId === 'TfCommands') {
              activeTab.style.display = "flex";
          } else {
              activeTab.style.display = "block";
          }
      }

      const deleteBtn = document.getElementById('tf-delete-file-btn');
      // Hide the delete button for pinned tabs (Settings/Commands/Auth Profiles), only file tabs are deletable
      const activeBtn = document.querySelector(`.tf-tablink[data-target-tab="${tabId}"]`);
      if (deleteBtn) deleteBtn.style.display = (activeBtn && activeBtn.hasAttribute('data-pinned')) ? 'none' : 'inline-block';

      // Refresh the CodeMirror instance
      const taId = (tabId === 'TfCommands') ? 'edit-terraform-commands' : 'editor-' + tabId;
      if (window.cmEditors[taId]) {
          setTimeout(() => window.cmEditors[taId].refresh(), 50);
      }
      
      if (window.currentEditLab) {
          localStorage.setItem('tf_active_tab_' + window.currentEditLab, tabId);
      }
};


  window.addTerraformFileTab = function(filepath, content = "") {
      const tabId = 'tf-tab-' + filepath.replace(/[^a-zA-Z0-9_-]/g, '-');
      if (document.getElementById(tabId)) {
          window.openTfTab(tabId);
          return;
      }

      const basename = filepath.split('/').pop();
      const btn = document.createElement('button');
      btn.className = "w3-bar-item w3-button tf-tablink";
      btn.title = filepath;
      btn.style.display = "flex";
      btn.style.alignItems = "center";
      btn.style.gap = "8px";
      
      btn.setAttribute("data-target-tab", tabId);
      btn.setAttribute("onclick", `window.openTfTab('${tabId}')`);
      
      btn.innerHTML = `
        <span><i class="fas fa-file-code"></i> ${basename}</span>
        <i class="fas fa-times w3-text-gray w3-hover-text-red" onclick="window.closeTerraformTab(event, '${tabId}')" style="font-size: 1.1em; margin-top: 1px;"></i>
      `;
      
      const tabBar = document.getElementById('tf-tab-bar');
      tabBar.insertBefore(btn, tabBar.lastElementChild);

      const div = document.createElement('div');
      div.id = tabId;
      div.className = "tf-tab";
      div.style.display = "none";
      div.style.height = "100%";
      div.setAttribute('data-filepath', filepath);
      div.innerHTML = `<textarea id="editor-${tabId}"></textarea>`;
      
      const container = document.getElementById('tf-editors-container');
      container.insertBefore(div, document.getElementById('terraform-editor-result'));

      let mode = 'terraform';
      if (filepath.endsWith('.yml') || filepath.endsWith('.yaml')) mode = 'yaml';
      else if (filepath.endsWith('.json')) mode = 'javascript';
      else if (filepath.endsWith('.sh')) mode = 'shell';

      const editor = window.initCodeEditor(`editor-${tabId}`, mode);
      editor.setValue(content);

      window.openTfTab(tabId);
      window.updateTerraformOpenTabs();
  };

  window.updateTfAuthMethodUI = function() {
      const method = document.getElementById('edit-terraform-auth-method').value;
      const envFields = document.getElementById('tf-auth-env-fields');
      if (envFields) envFields.style.display = (method === 'env') ? 'block' : 'none';
      document.getElementById('tf-auth-vault-fields').style.display = (method === 'vault') ? 'block' : 'none';
      document.getElementById('tf-auth-wif-fields').style.display = (method === 'wif') ? 'block' : 'none';
      document.getElementById('tf-auth-profile-fields').style.display = (method === 'profile') ? 'block' : 'none';
      if (method === 'env') {
          window.checkTerminalStagedCreds();
      }
  };

  window.checkTerminalStagedCreds = function() {
      const hintDiv = document.getElementById('tf-auth-terminal-env-hint');
      if (!hintDiv) return;

      let foundCreds = null;
      let foundNode = null;

      for (let i = 0; i < localStorage.length; i++) {
          const key = localStorage.key(i);
          if (key && key.startsWith('ctlabs_env_files_')) {
              try {
                  const files = JSON.parse(localStorage.getItem(key));
                  if (Array.isArray(files)) {
                      const match = files.find(f => f.env_var === 'GOOGLE_APPLICATION_CREDENTIALS');
                      if (match) {
                          foundCreds = match;
                          foundNode = key.replace('ctlabs_env_files_', '');
                          break;
                      }
                  }
              } catch (e) {}
          }
      }

      if (foundCreds) {
          window.lastFoundTerminalCreds = foundCreds;
          hintDiv.style.display = 'block';
          const escNode = (foundNode || '').replace(/</g, '&lt;').replace(/>/g, '&gt;');
          const escFn = (foundCreds.filename || '').replace(/</g, '&lt;').replace(/>/g, '&gt;');
          hintDiv.innerHTML = `
              <div style="background: rgba(14, 165, 233, 0.1); border: 1px solid #0284c7; border-radius: 6px; padding: 8px 12px; margin-top: 8px; font-size: 0.85em; display: flex; align-items: center; justify-content: space-between; flex-wrap: wrap; gap: 8px;">
                  <div>
                      <i class="fas fa-magic" style="color: #38bdf8;"></i>
                      <span style="color: #e2e8f0;"> Terminal Environment File detected on <b>${escNode}</b>:</span>
                      <code style="color: #f59e0b; background: #0f172a; padding: 1px 6px; border-radius: 3px; margin-left: 4px;">${escFn}</code>
                  </div>
                  <div style="display: flex; gap: 6px;">
                      <button type="button" class="w3-button w3-tiny w3-teal w3-round" onclick="window.useTerminalStagedCreds()">
                          <i class="fas fa-check"></i> Use Path
                      </button>
                      <button type="button" class="w3-button w3-tiny w3-blue w3-round" onclick="window.importTerminalStagedCredsToRepo()">
                          <i class="fas fa-file-import"></i> Stage in Workspace
                      </button>
                  </div>
              </div>
          `;
      } else {
          hintDiv.style.display = 'none';
      }
  };

  window.useTerminalStagedCreds = function() {
      if (!window.lastFoundTerminalCreds) return;
      const fn = window.lastFoundTerminalCreds.filename;
      const credInput = document.getElementById('edit-terraform-env-credentials');
      if (credInput) {
          const envDir = window.CTLABS_ENV_DIR_NAME || '.ctlabs_env';
          credInput.value = `~/${envDir}/${fn}`;
      }
  };

  window.importTerminalStagedCredsToRepo = async function() {
      if (!window.lastFoundTerminalCreds) return;
      const creds = window.lastFoundTerminalCreds;
      const filePath = `credentials/${creds.filename}`;
      let content = '';
      try {
          const rawB64 = (creds.content_base64 || '').replace(/^data:[^;]+;base64,/, '');
          content = atob(rawB64);
      } catch (e) {
          alert("Could not decode credentials content: " + e.message);
          return;
      }

      window.createTerraformFileTab(filePath, content);
      const credInput = document.getElementById('edit-terraform-env-credentials');
      if (credInput) {
          credInput.value = filePath;
      }
      alert(`Staged ${filePath} into Terraform editor! Click 'Save All Files' to persist to repository.`);
  };

  window.loadTfAuthProfiles = async function() {
      const resultDiv = document.getElementById('terraform-editor-result');
      try {
          const safeLab = window.currentEditLab.replace(/\.ya?ml$/i, '').split('/').map(encodeURIComponent).join('/');
          const res = await fetch(`${window.ansScope()}/terraform/profiles?t=${Date.now()}`);
          if (!res.ok) throw new Error((await res.json()).error);

          const data = await res.json();
          const authProf = window.initCodeEditor('editor-TfAuthProfiles', 'yaml');
          if (window.automationBase === '/controller') {
            if (data['terraform_profiles_ctl.yml']) authProf.setValue(data['terraform_profiles_ctl.yml']);
            else if (data['terraform_profiles.yml']) authProf.setValue(data['terraform_profiles.yml']);
          } else {
            if (data['terraform_profiles.yml']) authProf.setValue(data['terraform_profiles.yml']);
          }
      } catch (err) {
          resultDiv.style.cssText = 'background-color: rgba(239, 68, 68, 0.2); color: #ef4444; border: 1px solid #ef4444; display: block; margin-top: 15px; padding: 8px;';
          resultDiv.innerHTML = '❌ ' + err.message;
      }
  };

  window.openTerraformEditor = async function(labName, base) {
      window.automationBase = base || null;
      window.currentEditLab = labName;
      // See openAnsibleEditor - swap between the lab and controller file paths.
      window.setProfileFileLabel('#TfAuthProfiles', window.automationBase === '/controller');
      // --- READ MEMORY FIRST! Before any clicks overwrite it! ---
      const savedActiveTab = localStorage.getItem('tf_active_tab_' + window.currentEditLab);

      const resultDiv = document.getElementById('terraform-editor-result');
      if (resultDiv) resultDiv.style.display = 'none';

      document.querySelector('.tf-tablink').click();

      try {
          const safeLab = labName.replace(/\.ya?ml$/i, '').split('/').map(encodeURIComponent).join('/');
          const res = await fetch(`${window.ansScope()}/terraform/config?t=${Date.now()}`);
          if (!res.ok) throw new Error("Could not fetch terraform node configuration");
          
          const data = await res.json();
          let tf = data.json.tf || {};
          
          document.getElementById('edit-terraform-workdir').value = tf.work_dir || '';
          if (document.getElementById('edit-terraform-root-dir')) {
              document.getElementById('edit-terraform-root-dir').value = tf.root_dir || '';
          }
          window.loadAvailableRepositories && window.loadAvailableRepositories();
          document.getElementById('edit-terraform-workspace').value = tf.workspace || '';
          document.getElementById('edit-terraform-vars').value = (tf.vars || []).join('\n');

          // --- NEW: Initialize CodeMirror for the Custom Script Tab ---
          if (!window.cmEditors['edit-terraform-commands']) {
              window.cmEditors['edit-terraform-commands'] = window.initCodeEditor('edit-terraform-commands', 'shell');
          }
          window.cmEditors['edit-terraform-commands'].setValue(tf.commands || '');

          // --- LOAD GCP AUTH FIELDS INTO UI (auth.method / profile, with legacy `vault` fallback) ---
          const auth = tf.auth || (tf.vault ? Object.assign({ method: 'vault' }, tf.vault) : {});
          const authMethod = tf.profile ? 'profile' : (auth.method || '');

          document.getElementById('edit-terraform-auth-method').value = authMethod;
          const envCredsEl = document.getElementById('edit-terraform-env-credentials');
          if (envCredsEl) envCredsEl.value = auth.credentials_file || '';
          const envProjEl = document.getElementById('edit-terraform-env-project');
          if (envProjEl) envProjEl.value = auth.project || '';
          const envExtraEl = document.getElementById('edit-terraform-env-extra');
          if (envExtraEl) envExtraEl.value = (Array.isArray(auth.extra_vars) ? auth.extra_vars.join('\n') : (auth.extra_vars || ''));
          document.getElementById('edit-terraform-vault-project').value = auth.project || '';
          document.getElementById('edit-terraform-vault-roleset').value = auth.roleset || '';
          document.getElementById('edit-terraform-wif-vault-role').value = auth.vault_role || '';
          document.getElementById('edit-terraform-wif-audience').value = auth.audience || '';
          document.getElementById('edit-terraform-wif-service-account').value = auth.service_account || '';
          document.getElementById('edit-terraform-wif-scopes').value = (auth.scopes || []).join('\n');
          document.getElementById('edit-terraform-auth-profile').value = tf.profile || '';
          window.updateTfAuthMethodUI();

          await window.loadTfAuthProfiles();

          document.getElementById('terraform-editor-modal').style.display = 'block';

          // Safely clear old tabs, strictly ignoring our pinned tabs! ---
          document.querySelectorAll('.tf-tablink:not([data-pinned])').forEach(e => e.remove());
          document.querySelectorAll('.tf-tab[data-filepath]').forEach(e => {
              const taId = e.querySelector('textarea')?.id;
              if (taId && window.cmEditors[taId]) delete window.cmEditors[taId];
              e.remove();
          });

         // 🔥 RESTORE TABS FROM MEMORY 🔥
          const savedTabsStr = localStorage.getItem('terraform_tabs_' + window.currentEditLab);
          let savedTabs = savedTabsStr ? JSON.parse(savedTabsStr) : null;

          if (savedTabs && savedTabs.length > 0) {
              for (const filepath of savedTabs) {
                  await window.fetchTerraformFile(filepath);
              }
              
              if (savedActiveTab && document.getElementById(savedActiveTab)) {
                  window.openTfTab(savedActiveTab);
              } else {
                  const fileTabs = document.querySelectorAll('.tf-tablink:not([data-pinned])');
                  if (fileTabs.length > 0) {
                      fileTabs[fileTabs.length - 1].click();
                  }
              }
          } else if (tf.work_dir && tf.work_dir.trim() !== '') {
              window.loadTerraformFiles();
          }

      } catch (err) { alert("Error: " + err.message); }
  };

  window.loadTerraformFiles = async function() {
      const workDir = document.getElementById('edit-terraform-workdir').value.trim();
      const resultDiv = document.getElementById('terraform-editor-result');
      if (!workDir) { alert("Please enter a Working Directory."); return; }

      resultDiv.style.cssText = 'background-color: rgba(56, 189, 248, 0.2); color: #38bdf8; border: 1px solid #38bdf8; display: block; margin-top: 15px; padding: 8px;';
      resultDiv.innerHTML = '<i class="fas fa-spinner fa-spin"></i> Discovering and loading files...';

      try {
          const rootDir = (document.getElementById('edit-terraform-root-dir')?.value || '').trim();
          let url = `${window.ansScope()}/terraform/files?work_dir=${encodeURIComponent(workDir)}`;
          if (rootDir) url += `&root_dir=${encodeURIComponent(rootDir)}`;
          const res = await fetch(url);
          if (!res.ok) throw new Error((await res.json()).error);
          const data = await res.json();

          // Safely clear old tabs
          document.querySelectorAll('.tf-tablink:not([data-pinned])').forEach(e => e.remove());
          document.querySelectorAll('.tf-tab[data-filepath]').forEach(e => {
              const taId = e.querySelector('textarea')?.id;
              if (taId && window.cmEditors[taId]) delete window.cmEditors[taId];
              e.remove();
          });

          const defaults = ['config.yml', 'main.tf', 'provider.tf', 'variables.tf', 'outputs.tf'];
          let loadedCount = 0;
          
          for (const [filename, content] of Object.entries(data)) {
              if (defaults.includes(filename)) {
                  // Format as a path so the tab saves correctly!
                  const fullPath = workDir === '.' || workDir === '' ? filename : `${workDir}/${filename}`;
                  window.addTerraformFileTab(fullPath, content);
                  loadedCount++;
              }
          }
          
          if (loadedCount > 0) {
              const pinnedCount = document.querySelectorAll('.tf-tablink[data-pinned]').length;
              const firstFileBtn = document.querySelectorAll('.tf-tablink')[pinnedCount];
              if (firstFileBtn) firstFileBtn.querySelector('span').click();
          }

          resultDiv.style.display = 'none';
      } catch (err) {
          resultDiv.style.cssText = 'background-color: rgba(239, 68, 68, 0.2); color: #ef4444; border: 1px solid #ef4444; display: block; margin-top: 15px; padding: 8px;';
          resultDiv.innerHTML = '❌ ' + err.message;
      }
  };

  window.saveTerraformConfig = async function() {
      const resultDiv = document.getElementById('terraform-editor-result');
      const workDir = document.getElementById('edit-terraform-workdir').value.trim();
      
      const filesData = {};
      document.querySelectorAll('.tf-tab[data-filepath]').forEach(tab => {
          const filepath = tab.getAttribute('data-filepath');
          const taId = tab.querySelector('textarea').id;
          filesData[filepath] = window.cmEditors[taId].getValue();
      });

      // --- EXTRACT GCP AUTH CONFIG ---
      const authMethod     = document.getElementById('edit-terraform-auth-method').value;
      const envCreds       = (document.getElementById('edit-terraform-env-credentials')?.value || '').trim();
      const envProject     = (document.getElementById('edit-terraform-env-project')?.value || '').trim();
      const envExtra       = document.getElementById('edit-terraform-env-extra')?.value || '';
      const vProject       = document.getElementById('edit-terraform-vault-project').value.trim();
      const vRoleset       = document.getElementById('edit-terraform-vault-roleset').value.trim();
      const wifVaultRole   = document.getElementById('edit-terraform-wif-vault-role').value.trim();
      const wifAudience    = document.getElementById('edit-terraform-wif-audience').value.trim();
      const wifServiceAcct = document.getElementById('edit-terraform-wif-service-account').value.trim();
      const wifScopes      = document.getElementById('edit-terraform-wif-scopes').value;
      const authProfile    = document.getElementById('edit-terraform-auth-profile').value.trim();
      const authProfilesYaml = window.cmEditors['editor-TfAuthProfiles'] ? window.cmEditors['editor-TfAuthProfiles'].getValue() : '';
      const customCommands = window.cmEditors['edit-terraform-commands'] ? window.cmEditors['edit-terraform-commands'].getValue() : '';

      const formData = new URLSearchParams({
          root_dir: (document.getElementById('edit-terraform-root-dir')?.value || '').trim(),
          work_dir: workDir,
          workspace: document.getElementById('edit-terraform-workspace').value,
          vars: document.getElementById('edit-terraform-vars').value,
          commands: customCommands, // <-- Add it to the form payload!
          auth_method: authMethod,
          env_credentials: envCreds,
          env_project: envProject,
          env_extra: envExtra,
          vault_project: vProject,
          vault_roleset: vProject ? (vRoleset || 'terraform-runner') : '',
          wif_vault_role: wifVaultRole,
          wif_audience: wifAudience,
          wif_service_account: wifServiceAcct,
          wif_scopes: wifScopes,
          auth_profile: authProfile,
          tf_auth_profiles: authProfilesYaml,
          tf_files: JSON.stringify(filesData)
      });

      resultDiv.style.cssText = 'background-color: rgba(245, 158, 11, 0.2); color: #f59e0b; border: 1px solid #f59e0b; display: block; margin-top: 15px; padding: 8px;';
      resultDiv.innerHTML = '<i class="fas fa-spinner fa-spin"></i> Saving files...';

      // Disable while the request is in flight so a second click can't fire a
      // duplicate save (the two POSTs would race the reload below).
      const saveBtn = document.getElementById('tf-save-btn');
      const saveBtnHtml = saveBtn ? saveBtn.innerHTML : null;
      if (saveBtn) {
          saveBtn.disabled = true;
          saveBtn.innerHTML = '<i class="fas fa-spinner fa-spin"></i> Saving...';
      }

      const safeLab = window.currentEditLab.replace(/\.ya?ml$/i, '').split('/').map(encodeURIComponent).join('/');
      try {
          const res = await fetch(`${window.ansScope()}/terraform/edit`, {
              method: 'POST',
              headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
              body: formData.toString()
          });
          if (res.ok) {
              resultDiv.style.cssText = 'background-color: rgba(16, 185, 129, 0.2); color: #10b981; border: 1px solid #10b981; display: block; margin-top: 15px; padding: 8px;';
              resultDiv.textContent = '✅ All files saved successfully.';
              setTimeout(() => location.reload(), 800);
          } else {
              const errText = await res.text();
              let errMsg = errText;
              try { errMsg = JSON.parse(errText).error; } catch(e) {}
              throw new Error(errMsg);
          }
      } catch (err) {
          resultDiv.style.cssText = 'background-color: rgba(239, 68, 68, 0.2); color: #ef4444; border: 1px solid #ef4444; display: block; margin-top: 15px; padding: 8px; max-height: 200px; overflow-y: auto;';
          resultDiv.innerHTML = '❌ ' + err.message;
          if (saveBtn) { saveBtn.disabled = false; saveBtn.innerHTML = saveBtnHtml; }
      }
  };

  window.updateTerraformOpenTabs = function() {
      if (!window.currentEditLab) return;
      const tabs = [];
      // Harvest using data-filepath!
      document.querySelectorAll('.tf-tab[data-filepath]').forEach(tab => {
          tabs.push(tab.getAttribute('data-filepath'));
      });
      localStorage.setItem('terraform_tabs_' + window.currentEditLab, JSON.stringify(tabs));
  };

  window.closeTerraformTab = function(e, tabId) {
      e.stopPropagation();
      const tabBtn = e.currentTarget.closest('button');
      if (tabBtn) tabBtn.remove();
      
      const tabDiv = document.getElementById(tabId);
      if (tabDiv) {
          const taId = tabDiv.querySelector('textarea')?.id;
          if (taId && window.cmEditors[taId]) delete window.cmEditors[taId];
          tabDiv.remove();
      }
      document.querySelector('.tf-tablink').click();
      window.updateTerraformOpenTabs(); // Save state
  };

  window.fetchTerraformFile = async function(filepath) {
      const resultDiv = document.getElementById('terraform-editor-result');
      try {
          const rootDir = (document.getElementById('edit-terraform-root-dir')?.value || '').trim();
          let url = `${window.ansScope()}/terraform/file?path=${encodeURIComponent(filepath)}`;
          if (rootDir) url += `&root_dir=${encodeURIComponent(rootDir)}`;
          const res = await fetch(url);
          if (!res.ok) throw new Error((await res.json()).error);
          
          const data = await res.json();
          window.addTerraformFileTab(filepath, data.content);
      } catch (err) {
          resultDiv.style.cssText = 'background-color: rgba(239, 68, 68, 0.2); color: #ef4444; border: 1px solid #ef4444; display: block; margin-top: 15px; padding: 8px;';
          resultDiv.innerHTML = '❌ ' + err.message;
      }
  };

  window.deleteActiveTerraformFile = async function() {
      const activeTab = document.querySelector('.tf-tab[style*="display: block"]');
      if (!activeTab || activeTab.id === 'TfSettings') return;
      
      // Look up using data-filepath
      const filepath = activeTab.getAttribute('data-filepath');
      if (!filepath) return;

      if (!confirm(`WARNING: Are you sure you want to permanently delete '${filepath}' from disk?`)) return;

      const safeLab = window.currentEditLab.replace(/\.ya?ml$/i, '').split('/').map(encodeURIComponent).join('/');
      try {
          const rootDir = (document.getElementById('edit-terraform-root-dir')?.value || '').trim();
          const bodyData = { filepath: filepath };
          if (rootDir) bodyData.root_dir = rootDir;
          const res = await fetch(`${window.ansScope()}/terraform/file/delete`, {
              method: 'POST',
              headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
              body: new URLSearchParams(bodyData).toString()
          });
          
          if (res.ok) {
              const tabBtn = document.querySelector(`button[onclick*="openTfTab(event, '${activeTab.id}')"]`);
              if (tabBtn) tabBtn.remove();
              activeTab.remove();
              document.querySelector('.tf-tablink').click();
              window.updateTerraformOpenTabs(); // Save state
          } else throw new Error((await res.json()).error);
      } catch (err) { alert("Failed to delete file: " + err.message); }
  };

  window.destroyTerraform = async function(event, labName) {
      if (!confirm("⚠️ WARNING: This will destroy all Terraform resources managed by this configuration. Are you absolutely sure?")) {
          return;
      }

      const btn = event.currentTarget;
      btn.disabled = true;
      btn.innerHTML = '<i class="fas fa-spinner fa-spin"></i> Destroying...';
      btn.classList.replace('w3-red', 'w3-grey');

      const safeLab = (labName || '').replace(/\.ya?ml$/i, '').split('/').map(encodeURIComponent).join('/');
      try {
          // We will pass an explicit 'action=destroy' flag to the backend
          const res = await fetch(`${window.ansScope(labName)}/terraform?action=destroy`, { method: 'POST' });
          if (res.ok) {
              const data = await res.json().catch(() => ({}));
              window.location.href = data.log_url || '/logs/current';
          }
          else {
              const data = await res.json();
              alert("Error: " + (data.error || 'Failed to start Terraform Destroy'));
              btn.disabled = false;
              btn.innerHTML = '<i class="fas fa-trash-alt"></i> Destroy';
              btn.classList.replace('w3-grey', 'w3-red');
          }
      } catch (err) {
          alert("Error: " + err.message);
          btn.disabled = false;
          btn.innerHTML = '<i class="fas fa-trash-alt"></i> Destroy';
          btn.classList.replace('w3-grey', 'w3-red');
      }
  };

  window.runTerraform = async function(event, labName) {
      const btn = event.currentTarget;
      btn.disabled = true;
      btn.innerHTML = '<i class="fas fa-spinner fa-spin"></i> Starting...';
      btn.classList.replace('w3-green', 'w3-grey');

      const safeLab = (labName || '').replace(/\.ya?ml$/i, '').split('/').map(encodeURIComponent).join('/');
      try {
          const res = await fetch(`${window.ansScope(labName)}/terraform`, { method: 'POST' });
          if (res.ok) {
              const data = await res.json().catch(() => ({}));
              window.location.href = data.log_url || '/logs/current';
          }
          else {
              const data = await res.json();
              alert("Error: " + (data.error || 'Failed to start Terraform'));
              btn.disabled = false;
              btn.innerHTML = '<i class="fas fa-play"></i> Apply Terraform';
              btn.classList.replace('w3-grey', 'w3-green');
          }
      } catch (err) {
          alert("Error: " + err.message);
          btn.disabled = false;
          btn.innerHTML = '<i class="fas fa-play"></i> Apply Terraform';
          btn.classList.replace('w3-grey', 'w3-green');
      }
  };

  // ----------------------------------------------------------------------------
  // --- ROOT REPOSITORY / DIRECTORY BROWSER MODAL ---
  // ----------------------------------------------------------------------------
  window.dirBrowserTargetInputId = null;
  window.dirBrowserMode = 'ansible';
  window.dirBrowserCurrentPath = '/root';
  window.dirBrowserSelectedPath = '/root';

  window.openDirBrowser = async function(targetInputId, options = {}) {
    window.dirBrowserTargetInputId = targetInputId;
    window.dirBrowserMode = options.mode || 'ansible';

    const modalTitle = document.getElementById('dir-browser-title');
    if (modalTitle) {
      modalTitle.textContent = (window.dirBrowserMode === 'terraform')
        ? 'Select Terraform Repository / Directory'
        : 'Select Ansible Repository / Directory';
    }

    const currentVal = (document.getElementById(targetInputId)?.value || '').trim();
    const startPath = currentVal || '/root';
    window.dirBrowserSelectedPath = startPath;

    const modal = document.getElementById('unified-dir-browser-modal');
    if (modal) modal.style.display = 'block';

    await window.navigateToDir(startPath);
  };

  window.browseAnsibleRootDir = function() {
    window.openDirBrowser('edit-ansible-root-dir', { mode: 'ansible' });
  };

  window.browseTerraformRootDir = function() {
    window.openDirBrowser('edit-terraform-root-dir', { mode: 'terraform' });
  };

  window.navigateToDir = async function(path) {
    const listDiv = document.getElementById('dir-browser-items-list');
    const selectedInput = document.getElementById('dir-browser-selected-input');
    const breadcrumbsDiv = document.getElementById('dir-browser-breadcrumbs');
    const quickpicksDiv = document.getElementById('dir-browser-quickpicks');

    if (listDiv) {
      listDiv.innerHTML = '<div style="color: #64748b; font-style: italic; font-size: 0.85em; text-align: center; padding: 24px;"><i class="fas fa-spinner fa-spin"></i> Loading directory...</div>';
    }

    try {
      const scope = (typeof window.ansScope === 'function') ? window.ansScope() : '';
      const url = scope ? `${scope}/directories?path=${encodeURIComponent(path || '/root')}` : `/automation/directories?path=${encodeURIComponent(path || '/root')}`;
      const res = await fetch(url);
      if (!res.ok) throw new Error(`HTTP ${res.status}`);
      const data = await res.json();
      if (!data.success) throw new Error(data.error || 'Failed to list directory');

      window.dirBrowserCurrentPath = data.current;
      window.dirBrowserSelectedPath = data.current;
      if (selectedInput) selectedInput.value = data.current;

      // Render quick picks
      if (quickpicksDiv && data.repositories) {
        const repos = (window.dirBrowserMode === 'terraform')
          ? (data.repositories.terraform || [])
          : (data.repositories.ansible || []);

        if (repos.length > 0) {
          quickpicksDiv.innerHTML = repos.map(r => {
            const isSelected = (r === data.current);
            const activeStyle = isSelected ? 'background-color: #2563eb; color: #fff; border-color: #38bdf8;' : '';
            return `<button type="button" class="repo-chip" style="${activeStyle}" onclick="window.selectQuickPickRepo('${window.escapeHtml(r)}')"><i class="fas fa-folder"></i> ${window.escapeHtml(r)}</button>`;
          }).join('');
          const qContainer = document.getElementById('dir-browser-quickpicks-container');
          if (qContainer) qContainer.style.display = 'block';
        } else {
          const qContainer = document.getElementById('dir-browser-quickpicks-container');
          if (qContainer) qContainer.style.display = 'none';
        }
      }

      // Render breadcrumbs
      if (breadcrumbsDiv) {
        const parts = data.current.split('/').filter(Boolean);
        let bcHtml = `<button type="button" class="dir-breadcrumb-btn" onclick="window.navigateToDir('/')"><i class="fas fa-hdd"></i> /</button>`;
        let built = '';
        for (const part of parts) {
          built += '/' + part;
          const target = built;
          bcHtml += `<span style="color: #64748b; font-size: 0.8em;">/</span><button type="button" class="dir-breadcrumb-btn" onclick="window.navigateToDir('${window.escapeHtml(target)}')">${window.escapeHtml(part)}</button>`;
        }
        breadcrumbsDiv.innerHTML = bcHtml;
      }

      // Render directories list
      if (listDiv) {
        let itemsHtml = '';

        // Parent directory row
        if (data.parent) {
          itemsHtml += `
            <div class="dir-browser-item-row" onclick="window.navigateToDir('${window.escapeHtml(data.parent)}')">
              <span style="display: flex; align-items: center; gap: 8px; color: #94a3b8;">
                <i class="fas fa-level-up-alt" style="color: #64748b;"></i>
                <span>.. (parent directory)</span>
              </span>
              <span class="w3-text-gray" style="font-size: 0.8em;"><i class="fas fa-arrow-up"></i> Up</span>
            </div>
          `;
        }

        if (data.directories && data.directories.length > 0) {
          data.directories.forEach(dir => {
            const isSelected = (dir.path === window.dirBrowserSelectedPath);
            let badges = '';
            if (dir.has_ansible) {
              badges += `<span class="repo-badge w3-green w3-text-white">Ansible</span>`;
            }
            if (dir.has_terraform) {
              badges += `<span class="repo-badge w3-purple w3-text-white">Terraform</span>`;
            }
            if (dir.has_git) {
              badges += `<span class="repo-badge w3-teal w3-text-white"><i class="fab fa-git-alt"></i> Git</span>`;
            }

            itemsHtml += `
              <div class="dir-browser-item-row ${isSelected ? 'selected' : ''}" 
                   onclick="window.selectDirBrowserItem('${window.escapeHtml(dir.path)}')" 
                   ondblclick="window.navigateToDir('${window.escapeHtml(dir.path)}')">
                <span style="display: flex; align-items: center; gap: 8px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap;">
                  <i class="fas fa-folder" style="color: #f59e0b; flex-shrink: 0;"></i>
                  <span style="font-weight: 500;">${window.escapeHtml(dir.name)}</span>
                  ${badges}
                </span>
                <button type="button" class="w3-button w3-tiny w3-round w3-blue-gray" onclick="event.stopPropagation(); window.navigateToDir('${window.escapeHtml(dir.path)}')" title="Open folder" style="padding: 2px 7px;">
                  <i class="fas fa-chevron-right"></i>
                </button>
              </div>
            `;
          });
        } else {
          itemsHtml += `<div style="padding: 24px; color: #64748b; text-align: center; font-style: italic;">No subdirectories found</div>`;
        }

        listDiv.innerHTML = itemsHtml;
      }
    } catch (err) {
      if (listDiv) {
        listDiv.innerHTML = `<div style="padding: 20px; color: #ef4444; text-align: center;"><i class="fas fa-exclamation-triangle"></i> Error loading directory: ${window.escapeHtml(err.message)}</div>`;
      }
    }
  };

  window.selectQuickPickRepo = function(path) {
    window.dirBrowserSelectedPath = path;
    const selectedInput = document.getElementById('dir-browser-selected-input');
    if (selectedInput) selectedInput.value = path;
    window.navigateToDir(path);
  };

  window.selectDirBrowserItem = function(path) {
    window.dirBrowserSelectedPath = path;
    const selectedInput = document.getElementById('dir-browser-selected-input');
    if (selectedInput) selectedInput.value = path;

    document.querySelectorAll('.dir-browser-item-row').forEach(row => {
      row.classList.remove('selected');
    });
    if (window.event && window.event.currentTarget) {
      window.event.currentTarget.classList.add('selected');
    }
  };

  window.refreshDirBrowser = function() {
    window.navigateToDir(window.dirBrowserCurrentPath || '/root');
  };

  window.confirmDirBrowserSelection = function() {
    const selectedInput = document.getElementById('dir-browser-selected-input');
    const path = (selectedInput?.value || window.dirBrowserSelectedPath || '').trim();

    if (window.dirBrowserTargetInputId) {
      const targetInput = document.getElementById(window.dirBrowserTargetInputId);
      if (targetInput) {
        targetInput.value = path;
        targetInput.dispatchEvent(new Event('input', { bubbles: true }));
        targetInput.dispatchEvent(new Event('change', { bubbles: true }));
      }
    }

    const modal = document.getElementById('unified-dir-browser-modal');
    if (modal) modal.style.display = 'none';
  };

// --- DIRECTORY BROWSER ---
  window.tfBrowserTree = [];
  window.tfBrowserCurrentDir = '';
  window.tfBrowserSelectedPath = '';
  window.tfBrowserTargetInputId = 'edit-terraform-workdir';
  window.tfBrowserMode = 'folder'; // 'folder' | 'file' | 'any'

  window.escapeHtml = window.escapeHtml || function(str) {
      if (!str) return '';
      return String(str).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;').replace(/'/g, '&#039;');
  };

  window.openTerraformDirBrowser = async function(targetInputId = 'edit-terraform-workdir', options = {}) {
      window.tfBrowserTargetInputId = targetInputId;
      window.tfBrowserMode = options.mode || (targetInputId === 'edit-terraform-env-credentials' ? 'file' : 'folder');

      const modalTitle = document.getElementById('tf-dir-browser-title');
      if (modalTitle) {
          modalTitle.textContent = options.title || (window.tfBrowserMode === 'file' ? 'Select Credentials File' : 'Select Terraform Folder');
      }

      const confirmLabel = document.getElementById('tf-dir-confirm-label');
      if (confirmLabel) {
          confirmLabel.textContent = window.tfBrowserMode === 'file' ? 'Select File' : (targetInputId === 'edit-terraform-workdir' ? 'Select & Load' : 'Select Folder');
      }

      const selectCurrFolderBtn = document.getElementById('tf-dir-select-curr-folder-btn');
      if (selectCurrFolderBtn) {
          selectCurrFolderBtn.style.display = (window.tfBrowserMode === 'file') ? 'none' : 'inline-block';
      }

      // Initial browsed path from current input value if present
      const currVal = (document.getElementById(targetInputId)?.value || '').trim();
      let initDir = '';
      if (currVal && currVal !== '(root)' && currVal !== '.') {
          if (window.tfBrowserMode === 'file' && currVal.includes('/')) {
              const p = currVal.split('/');
              p.pop();
              initDir = p.join('/');
          } else if (window.tfBrowserMode !== 'file') {
              initDir = currVal;
          }
      }
      window.tfBrowserCurrentDir = initDir;
      window.tfBrowserSelectedPath = currVal;

      const searchInput = document.getElementById('tf-dir-search-input');
      if (searchInput) searchInput.value = '';

      const container = document.getElementById('tf-dir-items-container');
      if (container) {
          container.innerHTML = '<div style="color: #64748b; font-style: italic; font-size: 0.85em; text-align: center; padding: 24px;"><i class="fas fa-spinner fa-spin"></i> Loading workspace tree...</div>';
      }

      document.getElementById('tf-dir-browser-modal').style.display = 'block';

      try {
          const rootDir = (document.getElementById('edit-terraform-root-dir')?.value || '').trim();
          let url = `${window.ansScope()}/terraform/tree?t=${Date.now()}`;
          if (rootDir) url += `&root_dir=${encodeURIComponent(rootDir)}`;
          const res = await fetch(url);
          if (res.ok) {
              window.tfBrowserTree = await res.json();
          } else {
              window.tfBrowserTree = [];
          }
      } catch (e) {
          console.error("Failed to load Terraform directory tree", e);
          window.tfBrowserTree = [];
      }

      window.renderTerraformDirBrowser();
  };

  window.navigateToTfDir = function(dir) {
      window.tfBrowserCurrentDir = (dir || '').trim().replace(/^\/+|\/+$/g, '');
      if (window.tfBrowserMode === 'folder') {
          window.tfBrowserSelectedPath = window.tfBrowserCurrentDir;
      }
      const searchInput = document.getElementById('tf-dir-search-input');
      if (searchInput) searchInput.value = '';
      window.renderTerraformDirBrowser();
  };

  window.selectTfBrowserItem = function(path, type, autoConfirm = false) {
      window.tfBrowserSelectedPath = path;
      const selCode = document.getElementById('tf-dir-browser-selected');
      if (selCode) {
          selCode.textContent = path ? path : '(root)';
      }

      // Update selection styling
      document.querySelectorAll('.tf-browser-row').forEach(row => {
          if (row.getAttribute('data-path') === path) {
              row.classList.add('selected');
          } else {
              row.classList.remove('selected');
          }
      });

      if (autoConfirm) {
          window.confirmTerraformDirBrowser();
      }
  };

  window.selectCurrentTfBrowserFolder = function() {
      window.tfBrowserSelectedPath = window.tfBrowserCurrentDir;
      window.confirmTerraformDirBrowser();
  };

  window.filterTerraformBrowserItems = function() {
      window.renderTerraformDirBrowser();
  };

  window.getTfContentsAtDir = function(files, dir) {
      const normDir = dir ? dir.replace(/^\/+|\/+$/g, '') : '';
      const prefix = normDir ? normDir + '/' : '';
      const folders = new Map();
      const fileItems = [];

      files.forEach(f => {
          const isExplicitDir = f.endsWith('/');
          const cleanPath = isExplicitDir ? f.slice(0, -1) : f;
          if (normDir && !cleanPath.startsWith(prefix)) return;
          const rel = normDir ? cleanPath.slice(prefix.length) : cleanPath;
          if (!rel) return;
          const parts = rel.split('/');
          if (parts.length === 1) {
              if (isExplicitDir) {
                  if (!folders.has(parts[0])) folders.set(parts[0], 0);
              } else {
                  fileItems.push({ name: parts[0], path: cleanPath });
              }
          } else {
              const folderName = parts[0];
              folders.set(folderName, (folders.get(folderName) || 0) + (isExplicitDir ? 0 : 1));
          }
      });

      const folderItems = Array.from(folders.entries()).map(([name, count]) => ({
          name,
          path: normDir ? `${normDir}/${name}` : name,
          count
      })).sort((a, b) => a.name.localeCompare(b.name));

      fileItems.sort((a, b) => a.name.localeCompare(b.name));
      return { folders: folderItems, files: fileItems };
  };

  window.renderTerraformDirBrowser = function() {
      const container = document.getElementById('tf-dir-items-container');
      const breadcrumbs = document.getElementById('tf-dir-breadcrumbs');
      const selCode = document.getElementById('tf-dir-browser-selected');
      const searchInput = document.getElementById('tf-dir-search-input');
      const filterQuery = (searchInput ? searchInput.value : '').trim().toLowerCase();

      if (selCode) {
          selCode.textContent = window.tfBrowserSelectedPath ? window.tfBrowserSelectedPath : '(root)';
      }

      const currDir = window.tfBrowserCurrentDir;

      // 1. Render Breadcrumbs
      if (breadcrumbs) {
          breadcrumbs.innerHTML = '';
          const rootBtn = document.createElement('button');
          rootBtn.type = 'button';
          rootBtn.className = 'tf-crumb-btn' + (currDir === '' ? ' active' : '');
          rootBtn.innerHTML = '<i class="fas fa-hdd"></i> root';
          rootBtn.onclick = () => window.navigateToTfDir('');
          breadcrumbs.appendChild(rootBtn);

          if (currDir !== '') {
              const parts = currDir.split('/');
              let acc = '';
              parts.forEach((p, idx) => {
                  acc = acc ? `${acc}/${p}` : p;
                  const sep = document.createElement('span');
                  sep.style.cssText = 'color: #64748b; font-size: 0.85em; user-select: none;';
                  sep.textContent = '/';
                  breadcrumbs.appendChild(sep);

                  const crumbBtn = document.createElement('button');
                  crumbBtn.type = 'button';
                  crumbBtn.className = 'tf-crumb-btn' + (idx === parts.length - 1 ? ' active' : '');
                  crumbBtn.textContent = p;
                  const targetDir = acc;
                  crumbBtn.onclick = () => window.navigateToTfDir(targetDir);
                  breadcrumbs.appendChild(crumbBtn);
              });
          }
      }

      // 2. Extract contents at current directory
      if (!container) return;
      container.innerHTML = '';

      const { folders, files } = window.getTfContentsAtDir(window.tfBrowserTree || [], currDir);

      // Parent Directory row (..)
      if (currDir !== '') {
          const parentDir = currDir.includes('/') ? currDir.replace(/\/[^\/]+$/, '') : '';
          const parentRow = document.createElement('div');
          parentRow.className = 'tf-browser-row';
          parentRow.style.color = '#94a3b8';
          parentRow.innerHTML = `
              <div style="display: flex; align-items: center; gap: 8px;">
                  <i class="fas fa-level-up-alt" style="color: #94a3b8; font-size: 0.9em; width: 18px; text-align: center;"></i>
                  <span style="font-family: monospace; font-weight: 500;">.. (parent directory)</span>
              </div>
          `;
          parentRow.onclick = () => window.navigateToTfDir(parentDir);
          container.appendChild(parentRow);
      }

      const filteredFolders = folders.filter(f => !filterQuery || f.name.toLowerCase().includes(filterQuery));
      const filteredFiles = files.filter(f => !filterQuery || f.name.toLowerCase().includes(filterQuery));

      if (filteredFolders.length === 0 && filteredFiles.length === 0) {
          const empty = document.createElement('div');
          empty.style.cssText = 'color: #64748b; font-style: italic; font-size: 0.85em; text-align: center; padding: 20px;';
          empty.textContent = filterQuery ? `No items match "${filterQuery}"` : 'Directory is empty';
          container.appendChild(empty);
          return;
      }

      // Render Folders
      filteredFolders.forEach(folder => {
          const row = document.createElement('div');
          row.className = 'tf-browser-row' + (window.tfBrowserSelectedPath === folder.path ? ' selected' : '');
          row.setAttribute('data-path', folder.path);

          row.innerHTML = `
              <div style="display: flex; align-items: center; gap: 8px; flex: 1; min-width: 0; overflow: hidden;">
                  <i class="fas fa-folder" style="color: #f59e0b; font-size: 1em; width: 18px; text-align: center; flex-shrink: 0;"></i>
                  <span style="font-family: monospace; color: #f8fafc; font-weight: 500; white-space: nowrap; overflow: hidden; text-overflow: ellipsis;">${window.escapeHtml(folder.name)}/</span>
                  <span style="color: #64748b; font-size: 0.78em; margin-left: 4px; white-space: nowrap;">(${folder.count} ${folder.count === 1 ? 'item' : 'items'})</span>
              </div>
              <div style="display: flex; align-items: center; gap: 6px; margin-left: 8px; flex-shrink: 0;">
                  <button type="button" class="w3-button w3-tiny w3-round" style="background: #334155; color: #cbd5e1; padding: 2px 8px;" title="Open folder">
                      <i class="fas fa-folder-open"></i> Open
                  </button>
                  <button type="button" class="w3-button w3-tiny w3-blue w3-round" style="padding: 2px 8px;" title="Select folder">
                      <i class="fas fa-check"></i> Select
                  </button>
              </div>
          `;

          // Single-click selects row
          row.onclick = () => window.selectTfBrowserItem(folder.path, 'folder', false);

          // Double-click navigates into folder
          row.ondblclick = (e) => {
              e.preventDefault();
              window.navigateToTfDir(folder.path);
          };

          // "Open" button navigates into folder
          const openBtn = row.querySelectorAll('button')[0];
          if (openBtn) {
              openBtn.onclick = (e) => {
                  e.stopPropagation();
                  window.navigateToTfDir(folder.path);
              };
          }

          // "Select" button selects and confirms
          const selectBtn = row.querySelectorAll('button')[1];
          if (selectBtn) {
              selectBtn.onclick = (e) => {
                  e.stopPropagation();
                  window.selectTfBrowserItem(folder.path, 'folder', true);
              };
          }

          container.appendChild(row);
      });

      // Render Files
      filteredFiles.forEach(file => {
          const row = document.createElement('div');
          row.className = 'tf-browser-row' + (window.tfBrowserSelectedPath === file.path ? ' selected' : '');
          row.setAttribute('data-path', file.path);

          let iconHtml = '<i class="fas fa-file-alt" style="color: #94a3b8; width: 18px; text-align: center; flex-shrink: 0;"></i>';
          if (file.name.endsWith('.tf') || file.name.endsWith('.tfvars')) {
              iconHtml = '<i class="fas fa-cubes" style="color: #a855f7; width: 18px; text-align: center; flex-shrink: 0;"></i>';
          } else if (/\.(json|ya?ml|conf|cfg|ini)$/i.test(file.name)) {
              iconHtml = '<i class="fas fa-file-code" style="color: #38bdf8; width: 18px; text-align: center; flex-shrink: 0;"></i>';
          } else if (/\.(sh|bash)$/i.test(file.name)) {
              iconHtml = '<i class="fas fa-terminal" style="color: #2dd4bf; width: 18px; text-align: center; flex-shrink: 0;"></i>';
          } else if (/\.(key|pem|pub)$/i.test(file.name) || file.name.startsWith('id_')) {
              iconHtml = '<i class="fas fa-key" style="color: #eab308; width: 18px; text-align: center; flex-shrink: 0;"></i>';
          }

          row.innerHTML = `
              <div style="display: flex; align-items: center; gap: 8px; flex: 1; min-width: 0; overflow: hidden;">
                  ${iconHtml}
                  <span style="font-family: monospace; color: #cbd5e1; white-space: nowrap; overflow: hidden; text-overflow: ellipsis;">${window.escapeHtml(file.name)}</span>
              </div>
              <div style="display: flex; align-items: center; gap: 6px; margin-left: 8px; flex-shrink: 0;">
                  <button type="button" class="w3-button w3-tiny w3-teal w3-round" style="padding: 2px 8px;" title="Select file">
                      <i class="fas fa-check"></i> Select
                  </button>
              </div>
          `;

          row.onclick = () => window.selectTfBrowserItem(file.path, 'file', false);
          row.ondblclick = (e) => {
              e.preventDefault();
              window.selectTfBrowserItem(file.path, 'file', true);
          };

          const selectBtn = row.querySelector('button');
          if (selectBtn) {
              selectBtn.onclick = (e) => {
                  e.stopPropagation();
                  window.selectTfBrowserItem(file.path, 'file', true);
              };
          }

          container.appendChild(row);
      });
  };

  window.confirmTerraformDirBrowser = function() {
      let val = (window.tfBrowserSelectedPath || '').trim();
      if (val === '(root)' || val === '.') val = '';

      const targetId = window.tfBrowserTargetInputId || 'edit-terraform-workdir';
      const targetField = document.getElementById(targetId);
      if (targetField) {
          targetField.value = val;
      }

      document.getElementById('tf-dir-browser-modal').style.display = 'none';

      // Auto-load files only if the working directory input called this
      if (targetId === 'edit-terraform-workdir' && typeof window.loadTerraformFiles === 'function') {
          window.loadTerraformFiles();
      }
  };
  
// ----------------------------------------------------------------------------
// --- CONTROL-PLANE WRAPPERS ---
// The control-plane cards live on the lab details page but must hit the
// global /controller/* endpoints instead of /labs/<lab>/*. They set
// automationBase for the editor scope, then reuse the shared lab runners with
// an empty labName (ansScope treats an explicit labName as an absolute lab
// target, so an empty string falls through to automationBase).
// ----------------------------------------------------------------------------
window.openControllerAnsibleEditor = function() {
    window.openAnsibleEditor('controller', '/controller');
};

window.openControllerTerraformEditor = function() {
    window.openTerraformEditor('controller', '/controller');
};

window.runControllerAnsible = function(event) {
    window.automationBase = '/controller';
    return window.runAnsiblePlaybook(event, '');
};

window.stopControllerAnsible = function(event) {
    window.automationBase = '/controller';
    return window.stopAnsiblePlaybook(event, '');
};

window.runControllerTerraform = function(event) {
    window.automationBase = '/controller';
    return window.runTerraform(event, '');
};

window.destroyControllerTerraform = function(event) {
    window.automationBase = '/controller';
    return window.destroyTerraform(event, '');
};

// ----------------------------------------------------------------------------
// --- SSH AGENT MANAGEMENT ---
// In-memory ssh-agent key management for Controller and Lab automation nodes.
// ----------------------------------------------------------------------------
window.sshAgentContext = { scope: 'controller', labName: '' };
window.sshAgentMode = 'local';
window.uploadedSshKeyContent = '';

window.switchSshAgentMode = function(mode) {
  window.sshAgentMode = mode;
  const btnLocal = document.getElementById('ssh-mode-btn-local');
  const btnRemote = document.getElementById('ssh-mode-btn-remote');
  const paneLocal = document.getElementById('ssh-agent-pane-local');
  const paneRemote = document.getElementById('ssh-agent-pane-remote');

  if (mode === 'local') {
    if (btnLocal) {
      btnLocal.classList.add('w3-text-teal');
      btnLocal.style.fontWeight = '600';
      btnLocal.style.borderBottom = '2px solid #14b8a6';
      btnLocal.style.color = '';
    }
    if (btnRemote) {
      btnRemote.classList.remove('w3-text-teal');
      btnRemote.style.fontWeight = '500';
      btnRemote.style.borderBottom = 'none';
      btnRemote.style.color = '#94a3b8';
    }
    if (paneLocal) paneLocal.style.display = 'block';
    if (paneRemote) paneRemote.style.display = 'none';
  } else {
    if (btnRemote) {
      btnRemote.classList.add('w3-text-teal');
      btnRemote.style.fontWeight = '600';
      btnRemote.style.borderBottom = '2px solid #14b8a6';
      btnRemote.style.color = '';
    }
    if (btnLocal) {
      btnLocal.classList.remove('w3-text-teal');
      btnLocal.style.fontWeight = '500';
      btnLocal.style.borderBottom = 'none';
      btnLocal.style.color = '#94a3b8';
    }
    if (paneLocal) paneLocal.style.display = 'none';
    if (paneRemote) paneRemote.style.display = 'block';
  }
};

window.handleSshKeyFileSelect = function(event) {
  const file = event.target.files && event.target.files[0];
  if (!file) return;

  const reader = new FileReader();
  reader.onload = function(e) {
    window.uploadedSshKeyContent = e.target.result;
    const nameInput = document.getElementById('ssh-agent-key-name');
    if (nameInput) {
      nameInput.value = file.name.replace(/\.(pem|key)$/i, '');
    }
    const label = document.getElementById('ssh-agent-selected-file-label');
    if (label) {
      label.textContent = `Selected: ${file.name} (${file.size} bytes)`;
      label.style.display = 'inline-block';
    }
    const pasteBox = document.getElementById('ssh-agent-paste-box');
    if (pasteBox) pasteBox.style.display = 'none';
  };
  reader.readAsText(file);
};

window.toggleSshPasteMode = function() {
  const pasteBox = document.getElementById('ssh-agent-paste-box');
  const toggleLink = document.getElementById('ssh-agent-paste-toggle-link');
  if (!pasteBox) return;

  if (pasteBox.style.display === 'none' || !pasteBox.style.display) {
    pasteBox.style.display = 'block';
    if (toggleLink) toggleLink.innerHTML = '<i class="fas fa-file-upload"></i> Switch to file upload';
  } else {
    pasteBox.style.display = 'none';
    if (toggleLink) toggleLink.innerHTML = '<i class="fas fa-keyboard"></i> Or paste key text directly';
  }
};

window.handleSshPasteInput = function() {
  const pasteContent = document.getElementById('ssh-agent-paste-content');
  if (pasteContent && pasteContent.value.trim().length > 0) {
    window.uploadedSshKeyContent = '';
    const label = document.getElementById('ssh-agent-selected-file-label');
    if (label) label.style.display = 'none';

    const nameInput = document.getElementById('ssh-agent-key-name');
    if (nameInput && !nameInput.value) {
      nameInput.value = 'id_rsa';
    }
  }
};

window.initSshDropzone = function() {
  const dropzone = document.getElementById('ssh-agent-dropzone');
  if (!dropzone || dropzone.dataset.initialized) return;
  dropzone.dataset.initialized = 'true';

  dropzone.addEventListener('dragover', (e) => {
    e.preventDefault();
    dropzone.style.borderColor = '#14b8a6';
    dropzone.style.backgroundColor = '#132338';
  });
  dropzone.addEventListener('dragleave', (e) => {
    e.preventDefault();
    dropzone.style.borderColor = '#475569';
    dropzone.style.backgroundColor = '#0b1120';
  });
  dropzone.addEventListener('drop', (e) => {
    e.preventDefault();
    dropzone.style.borderColor = '#475569';
    dropzone.style.backgroundColor = '#0b1120';
    if (e.dataTransfer && e.dataTransfer.files && e.dataTransfer.files[0]) {
      const file = e.dataTransfer.files[0];
      window.handleSshKeyFileSelect({ target: { files: [file] } });
    }
  });
};

window.openSshAgentModal = function(scope, labName) {
  window.sshAgentContext = {
    scope: scope || 'controller',
    labName: labName || ''
  };

  const badge = document.getElementById('ssh-agent-target-badge');
  if (badge) {
    if (window.sshAgentContext.scope === 'controller') {
      badge.textContent = 'ctl-ctrl (root)';
      badge.className = 'w3-badge w3-small w3-round w3-indigo';
    } else {
      badge.textContent = labName || 'Lab Controller';
      badge.className = 'w3-badge w3-small w3-round w3-teal';
    }
  }

  const alertEl = document.getElementById('ssh-agent-alert');
  if (alertEl) {
    alertEl.style.display = 'none';
    alertEl.innerHTML = '';
  }

  // Reset inputs
  window.uploadedSshKeyContent = '';
  const filePicker = document.getElementById('ssh-agent-file-picker');
  if (filePicker) filePicker.value = '';
  const label = document.getElementById('ssh-agent-selected-file-label');
  if (label) {
    label.textContent = '';
    label.style.display = 'none';
  }
  const pasteBox = document.getElementById('ssh-agent-paste-box');
  if (pasteBox) pasteBox.style.display = 'none';
  const pasteContent = document.getElementById('ssh-agent-paste-content');
  if (pasteContent) pasteContent.value = '';
  const toggleLink = document.getElementById('ssh-agent-paste-toggle-link');
  if (toggleLink) toggleLink.innerHTML = '<i class="fas fa-keyboard"></i> Or paste key text directly';

  const nameInput = document.getElementById('ssh-agent-key-name');
  if (nameInput) nameInput.value = '';

  const passInput = document.getElementById('ssh-agent-passphrase');
  if (passInput) {
    passInput.value = '';
    passInput.type = 'password';
  }
  const passIcon = document.getElementById('ssh-agent-pass-icon');
  if (passIcon && passIcon.parentElement) {
    passIcon.parentElement.innerHTML = '<i id="ssh-agent-pass-icon" class="fas fa-eye"></i> Show';
  }

  window.switchSshAgentMode('local');

  const modal = document.getElementById('ssh-agent-modal');
  if (modal) {
    modal.style.display = 'block';
  }

  window.initSshDropzone();
  window.loadSshAgentStatus();
};

window.getSshAgentEndpoint = function(subpath) {
  const base = (window.sshAgentContext.scope === 'controller')
    ? '/controller'
    : window.ansScope(window.sshAgentContext.labName);
  return `${base}/ssh_agent${subpath || ''}`;
};

window.renderIdentitiesHtml = function(identities) {
  if (!identities || identities.length === 0) {
    return '';
  }
  let html = `
    <table class="w3-table w3-small" style="background-color: #0b1120; border-radius: 6px; border: 1px solid #1e293b;">
      <thead>
        <tr style="border-bottom: 1px solid #334155; color: #94a3b8; font-size: 11px;">
          <th style="padding: 4px 6px;">Type</th>
          <th style="padding: 4px 6px;">Fingerprint</th>
          <th style="padding: 4px 6px;">Identifier / Comment</th>
        </tr>
      </thead>
      <tbody>
  `;
  identities.forEach(id => {
    html += `
      <tr style="border-bottom: 1px solid #1e293b;">
        <td style="padding: 4px 6px;"><span class="w3-badge w3-tiny w3-round w3-dark-grey" style="font-family: monospace;">${window.escapeHtml(id.type || 'RSA')}</span></td>
        <td style="padding: 4px 6px;"><code style="color: #38bdf8; font-size: 11px;">${window.escapeHtml(id.fingerprint || '')}</code></td>
        <td style="padding: 4px 6px; color: #e2e8f0; font-family: monospace;">${window.escapeHtml(id.comment || id.raw || '')}</td>
      </tr>
    `;
  });
  html += `</tbody></table>`;
  return html;
};

window.updateCardIdentities = function(scope, identities) {
  const cardScope = (scope === 'controller') ? 'controller' : 'lab';
  const container = document.getElementById(`card-identities-container-${cardScope}-ssh-agent`);
  const countEl = document.getElementById(`card-count-${cardScope}-ssh-agent`);

  if (countEl) {
    const size = (identities || []).length;
    countEl.textContent = `${size} ${size === 1 ? 'identity' : 'identities'} loaded`;
  }

  if (container) {
    if (!identities || identities.length === 0) {
      container.innerHTML = `
        <div style="color: #64748b; font-style: italic; padding: 4px 0;">
          No keys currently loaded in agent. Click <a href="javascript:void(0)" onclick="window.openSshAgentModal('${cardScope}')" style="color: #38bdf8; font-weight: 600; text-decoration: underline;">Load Key</a> to add a key from your computer or container.
        </div>
      `;
    } else {
      container.innerHTML = window.renderIdentitiesHtml(identities);
    }
  }
};

window.loadSshAgentStatus = async function() {
  const loadingEl = document.getElementById('ssh-agent-loading-identities');
  const emptyEl = document.getElementById('ssh-agent-empty-msg');
  const tableEl = document.getElementById('ssh-agent-identities-table');
  const tbodyEl = document.getElementById('ssh-agent-identities-tbody');
  const clearBtn = document.getElementById('ssh-agent-clear-btn');
  const datalist = document.getElementById('ssh-agent-candidate-keys');
  const keyInput = document.getElementById('ssh-agent-key-path');

  if (loadingEl) loadingEl.style.display = 'block';
  if (emptyEl) emptyEl.style.display = 'none';
  if (tableEl) tableEl.style.display = 'none';
  if (clearBtn) clearBtn.style.display = 'none';

  try {
    const url = window.getSshAgentEndpoint(`?t=${Date.now()}`);
    const res = await fetch(url);
    if (!res.ok) {
      const errData = await res.json().catch(() => ({}));
      throw new Error(errData.error || `HTTP ${res.status}`);
    }
    const data = await res.json();

    if (loadingEl) loadingEl.style.display = 'none';

    const identities = Array.isArray(data.identities) ? data.identities : [];
    if (identities.length > 0) {
      if (tbodyEl) {
        tbodyEl.innerHTML = '';
        identities.forEach(id => {
          const tr = document.createElement('tr');
          tr.style.borderBottom = '1px solid #334155';

          const tdType = document.createElement('td');
          tdType.style.padding = '6px';
          tdType.innerHTML = `<span class="w3-badge w3-tiny w3-round w3-dark-grey" style="font-family: monospace;">${window.escapeHtml(id.type || 'RSA')}</span>`;

          const tdFp = document.createElement('td');
          tdFp.style.padding = '6px';
          tdFp.innerHTML = `<code style="color: #38bdf8; font-size: 11px;">${window.escapeHtml(id.fingerprint || '')}</code>`;

          const tdComment = document.createElement('td');
          tdComment.style.padding = '6px';
          tdComment.style.color = '#e2e8f0';
          tdComment.style.fontFamily = 'monospace';
          tdComment.textContent = id.comment || id.raw || '';

          tr.appendChild(tdType);
          tr.appendChild(tdFp);
          tr.appendChild(tdComment);
          tbodyEl.appendChild(tr);
        });
      }
      if (tableEl) tableEl.style.display = 'table';
      if (clearBtn) clearBtn.style.display = 'inline-block';
    } else {
      if (emptyEl) emptyEl.style.display = 'block';
    }

    if (datalist && Array.isArray(data.candidate_keys)) {
      datalist.innerHTML = data.candidate_keys.map(k => `<option value="${window.escapeHtml(k)}"></option>`).join('');
      if (keyInput && !keyInput.value && data.candidate_keys.length > 0) {
        keyInput.value = data.candidate_keys[0];
      }
    }

    // Synchronize card identities view
    window.updateCardIdentities(window.sshAgentContext.scope, identities);

  } catch (err) {
    if (loadingEl) loadingEl.style.display = 'none';
    const alertEl = document.getElementById('ssh-agent-alert');
    if (alertEl) {
      alertEl.className = 'w3-panel w3-round w3-red';
      alertEl.innerHTML = `<i class="fas fa-exclamation-triangle"></i> Error checking SSH Agent: ${window.escapeHtml(err.message)}`;
      alertEl.style.display = 'block';
    }
  }
};

window.submitSshAgentAddKey = async function(event) {
  if (event) event.preventDefault();
  const submitBtn = document.getElementById('ssh-agent-submit-btn');
  const alertEl = document.getElementById('ssh-agent-alert');
  const passInput = document.getElementById('ssh-agent-passphrase');
  const passphrase = passInput ? passInput.value : '';

  let payload = {};

  if (window.sshAgentMode === 'local') {
    const pasteBox = document.getElementById('ssh-agent-paste-content');
    const keyContent = window.uploadedSshKeyContent || (pasteBox ? pasteBox.value : '');
    const nameInput = document.getElementById('ssh-agent-key-name');
    const keyName = nameInput ? nameInput.value.trim() : '';
    const saveCheck = document.getElementById('ssh-agent-save-disk');
    const saveToDisk = saveCheck ? saveCheck.checked : true;

    if (!keyContent.trim()) {
      if (alertEl) {
        alertEl.className = 'w3-panel w3-round w3-red';
        alertEl.innerHTML = '<i class="fas fa-exclamation-triangle"></i> Please select a private key file or paste key content.';
        alertEl.style.display = 'block';
      }
      return;
    }

    const lifeInput = document.getElementById('ssh-agent-lifetime');
    const lifetime = lifeInput ? lifeInput.value.trim() : '';

    payload = {
      key_content: keyContent,
      key_name: keyName,
      passphrase: passphrase,
      save_to_disk: saveToDisk
    };
    if (lifetime) payload.lifetime = lifetime;
  } else {
    const keyInput = document.getElementById('ssh-agent-key-path');
    const keyPath = (keyInput ? keyInput.value : '').trim();
    const lifeInput = document.getElementById('ssh-agent-lifetime');
    const lifetime = lifeInput ? lifeInput.value.trim() : '';

    if (!keyPath) {
      if (alertEl) {
        alertEl.className = 'w3-panel w3-round w3-red';
        alertEl.innerHTML = '<i class="fas fa-exclamation-triangle"></i> Please provide a key path.';
        alertEl.style.display = 'block';
      }
      return;
    }

    payload = {
      key_path: keyPath,
      passphrase: passphrase
    };
    if (lifetime) payload.lifetime = lifetime;
  }

  let originalHtml = '';
  if (submitBtn) {
    originalHtml = submitBtn.innerHTML;
    submitBtn.disabled = true;
    submitBtn.innerHTML = '<i class="fas fa-spinner fa-spin"></i> Validating & Loading...';
  }

  try {
    const url = window.getSshAgentEndpoint('/add');
    const res = await fetch(url, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(payload)
    });
    const data = await res.json().catch(() => ({}));

    if (res.ok && data.success) {
      if (alertEl) {
        alertEl.className = 'w3-panel w3-round w3-green';
        alertEl.innerHTML = `<i class="fas fa-check-circle"></i> ${window.escapeHtml(data.message || 'Key successfully loaded into SSH Agent.')}`;
        alertEl.style.display = 'block';
      }
      if (passInput) passInput.value = '';
      window.uploadedSshKeyContent = '';
      const picker = document.getElementById('ssh-agent-file-picker');
      if (picker) picker.value = '';
      const pasteBox = document.getElementById('ssh-agent-paste-content');
      if (pasteBox) pasteBox.value = '';
      const label = document.getElementById('ssh-agent-selected-file-label');
      if (label) label.style.display = 'none';

      window.loadSshAgentStatus();
    } else {
      if (alertEl) {
        alertEl.className = 'w3-panel w3-round w3-red';
        alertEl.innerHTML = `<i class="fas fa-exclamation-triangle"></i> ${window.escapeHtml(data.error || 'Failed to add key.')}`;
        alertEl.style.display = 'block';
      }
    }
  } catch (err) {
    if (alertEl) {
      alertEl.className = 'w3-panel w3-round w3-red';
      alertEl.innerHTML = `<i class="fas fa-exclamation-triangle"></i> Network error: ${window.escapeHtml(err.message)}`;
      alertEl.style.display = 'block';
    }
  } finally {
    if (submitBtn) {
      submitBtn.disabled = false;
      submitBtn.innerHTML = originalHtml;
    }
  }
};

window.clearSshAgentKeys = async function(scope, labName) {
  if (scope) {
    window.sshAgentContext = {
      scope: scope,
      labName: labName || ''
    };
  }

  if (!confirm('Are you sure you want to remove all keys from the SSH Agent?')) {
    return;
  }

  const clearBtn = document.getElementById('ssh-agent-clear-btn');
  const alertEl = document.getElementById('ssh-agent-alert');
  let origText = '';
  if (clearBtn) {
    origText = clearBtn.innerHTML;
    clearBtn.disabled = true;
    clearBtn.innerHTML = '<i class="fas fa-spinner fa-spin"></i> Clearing...';
  }

  try {
    const url = window.getSshAgentEndpoint('/clear');
    const res = await fetch(url, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' }
    });
    const data = await res.json().catch(() => ({}));

    if (res.ok && data.success) {
      if (alertEl) {
        alertEl.className = 'w3-panel w3-round w3-blue';
        alertEl.innerHTML = `<i class="fas fa-info-circle"></i> ${window.escapeHtml(data.message || 'All identities removed from agent.')}`;
        alertEl.style.display = 'block';
      }
      window.loadSshAgentStatus();
    } else {
      if (alertEl) {
        alertEl.className = 'w3-panel w3-round w3-red';
        alertEl.innerHTML = `<i class="fas fa-exclamation-triangle"></i> ${window.escapeHtml(data.error || 'Failed to clear identities.')}`;
        alertEl.style.display = 'block';
      }
    }
  } catch (err) {
    if (alertEl) {
      alertEl.className = 'w3-panel w3-round w3-red';
      alertEl.innerHTML = `<i class="fas fa-exclamation-triangle"></i> Network error: ${window.escapeHtml(err.message)}`;
      alertEl.style.display = 'block';
    }
  } finally {
    if (clearBtn) {
      clearBtn.disabled = false;
      clearBtn.innerHTML = origText;
    }
  }
};

window.toggleSshAgentPassVisibility = function() {
  const passInput = document.getElementById('ssh-agent-passphrase');
  const passIcon = document.getElementById('ssh-agent-pass-icon');
  if (!passInput) return;
  if (passInput.type === 'password') {
    passInput.type = 'text';
    if (passIcon && passIcon.parentElement) {
      passIcon.parentElement.innerHTML = '<i id="ssh-agent-pass-icon" class="fas fa-eye-slash"></i> Hide';
    }
  } else {
    passInput.type = 'password';
    if (passIcon && passIcon.parentElement) {
      passIcon.parentElement.innerHTML = '<i id="ssh-agent-pass-icon" class="fas fa-eye"></i> Show';
    }
  }
};
