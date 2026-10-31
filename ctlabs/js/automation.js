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
    const res = await fetch('/automation/repositories');
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
  document.querySelectorAll(".ans-tab").forEach(tab => tab.style.display = "none");
      
  document.querySelectorAll(".ans-tablink").forEach(btn => {
    btn.classList.remove("w3-text-blue");
    btn.style.backgroundColor = "transparent";
    btn.style.borderBottom = "none";
          
    if (btn.getAttribute("data-target-tab") === tabId) {
      btn.classList.add("w3-text-blue");
      btn.style.backgroundColor = "#1e293b";
      btn.style.borderBottom = "2px solid #38bdf8";
    }
  });
      
  const activeTab = document.getElementById(tabId);
  if (activeTab) activeTab.style.display = "block";

  const deleteBtn = document.getElementById('ans-delete-file-btn');
  if (deleteBtn) deleteBtn.style.display = (tabId === 'AnsSettings' || tabId === 'AnsPlayProfiles' || tabId === 'AnsSetupProfiles' || tabId === 'AnsPlaySetup') ? 'none' : 'inline-block';

  const taId = 'editor-' + tabId;
  if (window.cmEditors[taId]) {
    setTimeout(() => window.cmEditors[taId].refresh(), 50);
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
      div.innerHTML = `<textarea id="editor-${tabId}"></textarea>`;
      
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

  window.openAnsibleEditor = async function(labName, base) {
    window.automationBase = base || null;
    window.currentEditLab = labName;
    // Update labels for controller vs lab context. The modal renders both the
    // lab (automation/lab/) and controller (automation/ctl/) file paths into
    // data-lab-label / data-ctl-label; pick the one matching this context.
    window.setProfileFileLabel('#AnsSetupProfiles', window.automationBase === '/controller');
    window.setProfileFileLabel('#AnsPlayProfiles',  window.automationBase === '/controller');
    // --- READ MEMORY FIRST! ---
    const savedActiveTab = localStorage.getItem('ans_active_tab_' + window.currentEditLab);

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
        
        const book = play.book || 'main.yml';
        let defaultInv = play.inv;
        if (!defaultInv) {
            // Controller scope passes 'controller' (no .yml), labs pass e.g.
            // 'labs/net01.yml'. Always normalize to a .ini inventory filename.
            defaultInv = window.currentEditLab.split('/').pop().replace(/\.ya?ml$/i, '.ini');
        }
        if (defaultInv && !defaultInv.includes('/')) {
            if (window.automationBase === '/controller' && !defaultInv.startsWith('controller')) {
                defaultInv = 'controller';
            }
            if (!defaultInv.endsWith('.ini')) defaultInv += '.ini';
        }
        const customInv = play.custom_inv || '';
        document.getElementById('edit-ansible-book').value = book;
        if (document.getElementById('edit-ansible-root-dir')) {
            document.getElementById('edit-ansible-root-dir').value = play.root_dir || '';
        }
        window.loadAvailableRepositories && window.loadAvailableRepositories();
        document.getElementById('edit-ansible-inv').value = defaultInv;
        document.getElementById('edit-ansible-custom-inv').value = customInv;
        document.getElementById('edit-ansible-tags').value = (play.tags || []).join(', ');
        document.getElementById('edit-ansible-env').value = (play.env || []).join('\n');
        
        const playSetupEd = window.initCodeEditor('editor-AnsPlaySetup', 'yaml');
        playSetupEd.setValue(data.json.setup_yaml || '');
        
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
          await window.fetchAnsibleFile(defaultInv.includes('/') ? defaultInv : `inventories/${defaultInv}`);
          if (customInv !== '') {
            await window.fetchAnsibleFile(customInv.includes('/') ? customInv : `inventories/${customInv}`);
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
    } catch (err) { alert("Error: " + err.message); }
};

  window.saveAnsibleConfig = async function() {
      const resultDiv = document.getElementById('ansible-editor-result');
      const filesData = {};
      document.querySelectorAll('.ans-tab[data-filepath]').forEach(tab => {
          const filepath = tab.getAttribute('data-filepath');
          const taId = tab.querySelector('textarea').id;
          filesData[filepath] = window.cmEditors[taId].getValue();
      });

      const playProf  = window.cmEditors['editor-AnsPlayProfiles']  ? window.cmEditors['editor-AnsPlayProfiles'].getValue()  : '';
      const setupProf = window.cmEditors['editor-AnsSetupProfiles'] ? window.cmEditors['editor-AnsSetupProfiles'].getValue() : '';
      const playSetup = window.cmEditors['editor-AnsPlaySetup']     ? window.cmEditors['editor-AnsPlaySetup'].getValue()     : '';

      const formData = new URLSearchParams({
          root_dir: (document.getElementById('edit-ansible-root-dir')?.value || '').trim(),
          book: document.getElementById('edit-ansible-book').value,
          inv: document.getElementById('edit-ansible-inv').value,
          custom_inv: document.getElementById('edit-ansible-custom-inv').value,
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
              resultDiv.textContent = '✅ All files saved successfully.';
              setTimeout(() => location.reload(), 800);
          } else {
              // Safely handle HTML vs JSON error responses
              const errText = await res.text();
              let errMsg = errText;
              try { errMsg = JSON.parse(errText).error; } catch(e) {} // Fallback to raw text if not JSON
              throw new Error(errMsg);
          }
      } catch (err) {
          resultDiv.style.cssText = 'background-color: rgba(239, 68, 68, 0.2); color: #ef4444; border: 1px solid #ef4444; display: block; margin-top: 15px; padding: 8px; max-height: 200px; overflow-y: auto;';
          resultDiv.innerHTML = '❌ ' + err.message; // Will render Sinatra's HTML error directly in the box!
          if (saveBtn) { saveBtn.disabled = false; saveBtn.innerHTML = saveBtnHtml; }
      }
  };
  
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

  window.runAnsiblePlaybook = async function(event, labName) {
      const btn = event.currentTarget;
      btn.disabled = true;
      btn.innerHTML = '<i class="fas fa-spinner fa-spin"></i> Starting...';
      btn.classList.replace('w3-green', 'w3-grey');

      const safeLab = (labName || '').replace(/\.ya?ml$/i, '').split('/').map(encodeURIComponent).join('/');
      try {
          const res = await fetch(`${window.ansScope(labName)}/playbook`, { method: 'POST' });
          if (res.ok) {
              const data = await res.json().catch(() => ({}));
              window.location.href = data.log_url || '/logs/current';
          }
          else {
              const data = await res.json();
              alert("Error: " + (data.error || 'Failed to start playbook'));
              btn.disabled = false;
              btn.innerHTML = '<i class="fas fa-play"></i> Run Playbook';
              btn.classList.replace('w3-grey', 'w3-green');
          }
      } catch (err) {
          alert("Error: " + err.message);
          btn.disabled = false;
          btn.innerHTML = '<i class="fas fa-play"></i> Run Playbook';
          btn.classList.replace('w3-grey', 'w3-green');
      }
  };


window.stopAnsiblePlaybook = async function(event, labName) {
      const btn = event.currentTarget;

      const safeLab = (labName || '').replace(/\.ya?ml$/i, '').split('/').map(encodeURIComponent).join('/');
      try {
          btn.disabled = true;
          btn.innerHTML = '<i class="fas fa-spinner fa-spin"></i> Stopping...';
          const res = await fetch(`${window.ansScope(labName)}/playbook/stop`, { method: 'POST' });
          const data = await res.json().catch(() => ({}));
          if (!res.ok) throw new Error(data.message || data.error || 'Stop failed');
          window.location.reload();
      } catch (err) {
          btn.disabled = false;
          btn.innerHTML = '<i class="fas fa-exclamation-triangle"></i> Stop failed';
          btn.title = err.message;
      }
  };


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
          credInput.value = `credentials/${fn}`;
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
