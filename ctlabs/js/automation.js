/*
 -----------------------------------------------------------------------------
 File        : ctlabs/public/js/automation.js
 License     : MIT License
 -----------------------------------------------------------------------------
*/

// ----------------------------------------------------------------------------
// --- ANSIBLE ---
// ----------------------------------------------------------------------------
  window.openAnsTab = function(tabId) {
      document.querySelectorAll(".ans-tab").forEach(tab => tab.style.display = "none");
      
      document.querySelectorAll(".ans-tablink").forEach(btn => {
          btn.classList.remove("w3-text-blue");
          btn.style.backgroundColor = "transparent";
          btn.style.borderBottom = "none";
          
          // Highlight the matching tab button instantly
          if (btn.getAttribute("data-target-tab") === tabId) {
              btn.classList.add("w3-text-blue");
              btn.style.backgroundColor = "#1e293b";
              btn.style.borderBottom = "2px solid #38bdf8";
          }
      });
      
      const activeTab = document.getElementById(tabId);
      if (activeTab) activeTab.style.display = "block";

      const deleteBtn = document.getElementById('ans-delete-file-btn');
      if (deleteBtn) deleteBtn.style.display = (tabId === 'AnsSettings') ? 'none' : 'inline-block';

      const taId = 'editor-' + tabId;
      if (window.cmEditors[taId]) {
          setTimeout(() => window.cmEditors[taId].refresh(), 50);
      }
  };

  // INNER FILE BROWSER LOGIC
  window.openAnsibleFileBrowser = async function() {
      const safeLab = window.currentEditLab.split('/').map(encodeURIComponent).join('/');
      try {
          const res = await fetch(`/labs/${safeLab}/ansible/tree?t=${Date.now()}`);
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
          const safeLab = window.currentEditLab.split('/').map(encodeURIComponent).join('/');
          const res = await fetch(`/labs/${safeLab}/ansible/file?path=${encodeURIComponent(filepath)}`);
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

  window.openAnsibleEditor = async function(labName) {
      window.currentEditLab = labName;
      const resultDiv = document.getElementById('ansible-editor-result');
      if (resultDiv) resultDiv.style.display = 'none';

      document.querySelector('.ans-tablink').click();

      try {
          const safeLab = labName.split('/').map(encodeURIComponent).join('/');
          const res = await fetch(`/labs/${safeLab}/ansible/config?t=${Date.now()}`);
          if (!res.ok) throw new Error("Could not fetch ansible node configuration");
          
          const data = await res.json();
          let play = data.json.play || {};
          if (typeof play === 'string') play = { book: play };
          
          const book = play.book || 'main.yml';
          const defaultInv = play.inv || window.currentEditLab.split('/').pop().replace('.yml', '.ini');
          const customInv = play.custom_inv || '';

          document.getElementById('edit-ansible-book').value = book;
          document.getElementById('edit-ansible-inv').value = defaultInv;
          document.getElementById('edit-ansible-custom-inv').value = customInv;
          document.getElementById('edit-ansible-tags').value = (play.tags || []).join(', ');
          document.getElementById('edit-ansible-env').value = (play.env || []).join('\n');
          
          document.getElementById('ansible-editor-modal').style.display = 'block';

          document.querySelectorAll('.ans-tablink:not(:first-child):not(:last-child)').forEach(e => e.remove());
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

          // Focus the last opened file tab, or fallback to Settings
          const fileTabs = document.querySelectorAll('.ans-tablink:not(:first-child):not(:last-child)');
          if (fileTabs.length > 0) {
              fileTabs[fileTabs.length - 1].click();
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

      const formData = new URLSearchParams({
          book: document.getElementById('edit-ansible-book').value,
          inv: document.getElementById('edit-ansible-inv').value,
          custom_inv: document.getElementById('edit-ansible-custom-inv').value,
          tags: document.getElementById('edit-ansible-tags').value,
          env: document.getElementById('edit-ansible-env').value,
          ans_files: JSON.stringify(filesData)
      });

      resultDiv.style.cssText = 'background-color: rgba(245, 158, 11, 0.2); color: #f59e0b; border: 1px solid #f59e0b; display: block; margin-top: 15px; padding: 8px;';
      resultDiv.innerHTML = '<i class="fas fa-spinner fa-spin"></i> Saving configuration and files...';

      const safeLab = window.currentEditLab.split('/').map(encodeURIComponent).join('/');
      try {
          const res = await fetch(`/labs/${safeLab}/ansible/edit`, {
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

      const safeLab = window.currentEditLab.split('/').map(encodeURIComponent).join('/');
      try {
          const res = await fetch(`/labs/${safeLab}/ansible/file/delete`, {
              method: 'POST',
              headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
              body: new URLSearchParams({ filepath: filepath }).toString()
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

      const safeLab = labName.split('/').map(encodeURIComponent).join('/');
      try {
          const res = await fetch(`/labs/${safeLab}/playbook`, { method: 'POST' });
          if (res.ok) window.location.href = '/logs/current';
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


// ----------------------------------------------------------------------------
// --- TERRAFORM ---
// ----------------------------------------------------------------------------

  window.openTfTab = function(tabId) {
      document.querySelectorAll(".tf-tab").forEach(tab => tab.style.display = "none");
      
      document.querySelectorAll(".tf-tablink").forEach(btn => {
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

      const deleteBtn = document.getElementById('tf-delete-file-btn');
      if (deleteBtn) deleteBtn.style.display = (tabId === 'TfSettings') ? 'none' : 'inline-block';

      const taId = 'editor-' + tabId;
      if (window.cmEditors[taId]) {
          setTimeout(() => window.cmEditors[taId].refresh(), 50);
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

  window.openTerraformEditor = async function(labName) {
      window.currentEditLab = labName;
      const resultDiv = document.getElementById('terraform-editor-result');
      if (resultDiv) resultDiv.style.display = 'none';

      document.querySelector('.tf-tablink').click();

      try {
          const safeLab = labName.split('/').map(encodeURIComponent).join('/');
          const res = await fetch(`/labs/${safeLab}/terraform/config?t=${Date.now()}`);
          if (!res.ok) throw new Error("Could not fetch terraform node configuration");
          
          const data = await res.json();
          let tf = data.json.tf || {};
          
          document.getElementById('edit-terraform-workdir').value = tf.work_dir || '';
          document.getElementById('edit-terraform-workspace').value = tf.workspace || '';
          document.getElementById('edit-terraform-vars').value = (tf.vars || []).join('\n');
          
          document.getElementById('terraform-editor-modal').style.display = 'block';

          // Safely clear old tabs
          document.querySelectorAll('.tf-tablink:not(:first-child):not(:last-child)').forEach(e => e.remove());
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
              const fileTabs = document.querySelectorAll('.tf-tablink:not(:first-child):not(:last-child)');
              if (fileTabs.length > 0) {
                  fileTabs[fileTabs.length - 1].click();
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
          const safeLab = window.currentEditLab.split('/').map(encodeURIComponent).join('/');
          const res = await fetch(`/labs/${safeLab}/terraform/files?work_dir=${encodeURIComponent(workDir)}`);
          if (!res.ok) throw new Error((await res.json()).error);
          const data = await res.json();

          // Safely clear old tabs
          document.querySelectorAll('.tf-tablink:not(:first-child):not(:last-child)').forEach(e => e.remove());
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
              const firstFileBtn = document.querySelectorAll('.tf-tablink')[1];
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

      const formData = new URLSearchParams({
          work_dir: workDir,
          workspace: document.getElementById('edit-terraform-workspace').value,
          vars: document.getElementById('edit-terraform-vars').value,
          tf_files: JSON.stringify(filesData)
      });

      resultDiv.style.cssText = 'background-color: rgba(245, 158, 11, 0.2); color: #f59e0b; border: 1px solid #f59e0b; display: block; margin-top: 15px; padding: 8px;';
      resultDiv.innerHTML = '<i class="fas fa-spinner fa-spin"></i> Saving files...';

      const safeLab = window.currentEditLab.split('/').map(encodeURIComponent).join('/');
      try {
          const res = await fetch(`/labs/${safeLab}/terraform/edit`, {
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
          const safeLab = window.currentEditLab.split('/').map(encodeURIComponent).join('/');
          const res = await fetch(`/labs/${safeLab}/terraform/file?path=${encodeURIComponent(filepath)}`);
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

      const safeLab = window.currentEditLab.split('/').map(encodeURIComponent).join('/');
      try {
          const res = await fetch(`/labs/${safeLab}/terraform/file/delete`, {
              method: 'POST',
              headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
              body: new URLSearchParams({ filepath: filepath }).toString()
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

  window.runTerraform = async function(event, labName) {
      const btn = event.currentTarget;
      btn.disabled = true;
      btn.innerHTML = '<i class="fas fa-spinner fa-spin"></i> Starting...';
      btn.classList.replace('w3-green', 'w3-grey');

      const safeLab = labName.split('/').map(encodeURIComponent).join('/');
      try {
          const res = await fetch(`/labs/${safeLab}/terraform`, { method: 'POST' });
          if (res.ok) window.location.href = '/logs/current';
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
