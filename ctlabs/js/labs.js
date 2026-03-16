/*
 -----------------------------------------------------------------------------
 File        : ctlabs/public/js/labs.js
 License     : MIT License
 -----------------------------------------------------------------------------
*/

  // --- GLOBAL CODEMIRROR REGISTRY ---
  window.cmEditors = {};

  // --- CUSTOM TERRAFORM HIGHLIGHTER ---
  if (typeof CodeMirror.defineSimpleMode === 'function') {
    CodeMirror.defineSimpleMode("terraform", {
      start: [
        // Core Terraform Blocks & Keywords
        {regex: /(?:resource|data|provider|variable|output|module|locals|terraform|backend)\b/, token: "keyword"},
        // Built-in functions and types
        {regex: /(?:string|number|bool|list|map|any|object|tuple)\b/, token: "builtin"},
        // Booleans & Null
        {regex: /true|false|null\b/, token: "atom"},
        // Double-quoted Strings (supports escaped quotes)
        {regex: /"(?:[^\\]|\\.)*?(?:"|$)/, token: "string"},
        // Multi-line Strings / Heredoc (<<EOF)
        {regex: /<<-?\s*[A-Za-z0-9_]+/, token: "string", next: "heredoc"},
        // Numbers
        {regex: /0x[a-f\d]+|[-+]?(?:\.\d+|\d+\.?\d*)(?:e[-+]?\d+)?/i, token: "number"},
        // Comments (Hash, Double Slash, and Multi-line)
        {regex: /\#.*/, token: "comment"},
        {regex: /\/\/.*/, token: "comment"},
        {regex: /\/\*/, token: "comment", next: "comment"},
        // Operators
        {regex: /[-+\/*=<>!]+/, token: "operator"},
        // Brackets
        {regex: /[\{\}\[\]\(\)]/, token: "bracket"},
        // Variables and Properties
        {regex: /[a-zA-Z_][a-zA-Z0-9_\-]*\b/, token: "variable-2"}
      ],
      comment: [
        {regex: /.*?\*\//, token: "comment", next: "start"},
        {regex: /.*/, token: "comment"}
      ],
      heredoc: [
        // Safely end heredoc blocks (simple approximation)
        {regex: /^[A-Za-z0-9_]+$/, token: "string", next: "start"},
        {regex: /.*/, token: "string"}
      ],
      meta: {
        lineComment: "#",
        blockCommentStart: "/*",
        blockCommentEnd: "*/"
      }
    });
  }

  // --- UNIVERSAL EDITOR FACTORY ---
  window.initCodeEditor = function(textAreaId, langMode) {
      // If it already exists, just return it!
      if (window.cmEditors[textAreaId]) {
          setTimeout(() => window.cmEditors[textAreaId].refresh(), 50);
          return window.cmEditors[textAreaId];
      }

      const ta = document.getElementById(textAreaId);
      if (!ta) return null;

      // Build the new editor dynamically
      const editor = CodeMirror.fromTextArea(ta, {
          mode: langMode,
          theme: 'material-ocean',
          lineNumbers: true,
          tabSize: 2,
          viewportMargin: Infinity
      });
      
      editor.setSize("100%", "auto");
      editor.getWrapperElement().style.minHeight = "400px";
      
      window.cmEditors[textAreaId] = editor;
      
      // Refresh to fix the hidden-div glitch
      setTimeout(() => editor.refresh(), 50);
      return editor;
  };

  // JavaScript to handle Tab Switching in the Sidebar
  function openLabTab(evt, tabId) {
    localStorage.setItem('ctlabs_active_tab', tabId);

    const contents = document.getElementsByClassName("lab-tab-content");
    for (let i = 0; i < contents.length; i++) contents[i].style.display = "none";
          
    const btns = document.getElementsByClassName("lab-tab-btn");
    for (let i = 0; i < btns.length; i++) {
      btns[i].style.backgroundColor = "transparent";
      btns[i].style.color = "#cbd5e1";
      btns[i].style.fontWeight = "normal";
    }
    
    // CRITICAL FIX: Use flex instead of block so CSS constraints work!
    document.getElementById(tabId).style.display = "flex";
    
    evt.currentTarget.style.backgroundColor = "#38bdf8";
    evt.currentTarget.style.color = "#0f172a";
    evt.currentTarget.style.fontWeight = "bold";
  }

  // --- PERFECT LAYOUT RESIZER ---
  window.autoResizeLayout = function() {
      const wrapper = document.getElementById('lab-layout-wrapper');
      if (wrapper) {
          const rect = wrapper.getBoundingClientRect();
          // Increased to 60px to fully clear the bottom padding of the w3-panels
          const newHeight = window.innerHeight - rect.top - 60;
          wrapper.style.height = Math.max(400, newHeight) + 'px';
      }
  };
  window.addEventListener('resize', window.autoResizeLayout);

  // --- EDIT LAB ATTRIBUTES ---
  window.openEditLabModal = async function(labPath) {
      const pathInput = document.getElementById('edit-lab-path');
      const modal = document.getElementById('edit-lab-modal');
      
      if (!pathInput || !modal) {
          alert("Error: The Edit Lab modal HTML is missing from the page! Please make sure it was pasted into views/labs.erb");
          return;
      }

      pathInput.value = labPath;
      const resultDiv = document.getElementById('edit-lab-result');
      if (resultDiv) resultDiv.style.display = 'none';

      try {
          const safeLab = labPath.split('/').map(encodeURIComponent).join('/');
          const res = await fetch(`/labs/${safeLab}/meta`);
          if (!res.ok) throw new Error("Failed to load lab data from backend.");
          const data = await res.json();

          document.getElementById('edit-lab-name').value = data.name || '';
          document.getElementById('edit-lab-desc').value = data.desc || '';
          document.getElementById('edit-lab-vm-name').value = data.vm_name || '';
          document.getElementById('edit-lab-vm-dns').value = data.vm_dns || '';
          document.getElementById('edit-lab-mgmt-vrfid').value = data.mgmt_vrfid || '';
          document.getElementById('edit-lab-mgmt-dns').value = data.mgmt_dns || '';
          document.getElementById('edit-lab-mgmt-net').value = data.mgmt_net || '';
          document.getElementById('edit-lab-mgmt-gw').value = data.mgmt_gw || '';

          modal.style.display = 'block';
      } catch (err) {
          alert("Error: " + err.message);
      }
  };

  window.submitEditLab = async function(e) {
      e.preventDefault();
      const form = e.target;
      const formData = new FormData(form);
      const labPath = formData.get('lab_path');
      const safeLab = labPath.split('/').map(encodeURIComponent).join('/');
      
      const btn = form.querySelector('button[type="submit"]');
      const origText = btn.innerHTML;
      btn.innerHTML = '<i class="fas fa-spinner fa-spin"></i> Saving...';
      btn.disabled = true;

      const resultDiv = document.getElementById('edit-lab-result');

      try {
          const res = await fetch(`/labs/${safeLab}/edit_meta`, {
              method: 'POST',
              headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
              body: new URLSearchParams(formData).toString()
          });

          if (!res.ok) throw new Error((await res.json()).error || "Failed to save configuration.");

          resultDiv.style.cssText = 'background-color: rgba(16, 185, 129, 0.2); color: #10b981; border: 1px solid #10b981; display: block; margin-top: 10px; padding: 8px;';
          resultDiv.textContent = '✅ Lab updated successfully! Reloading...';
          setTimeout(() => location.reload(), 800);
      } catch (err) {
          resultDiv.style.cssText = 'background-color: rgba(239, 68, 68, 0.2); color: #ef4444; border: 1px solid #ef4444; display: block; margin-top: 10px; padding: 8px;';
          resultDiv.textContent = '❌ ' + err.message;
          btn.innerHTML = origText;
          btn.disabled = false;
      }
  };

  // Helper to dynamically read data from the DOM after an AJAX load
  window.getLabData = function(key) {
      const dataDiv = document.getElementById('lab-dynamic-data');
      if (!dataDiv) return (key === 'images-map') ? {} : [];
      try { return JSON.parse(dataDiv.getAttribute('data-' + key) || (key === 'images-map' ? '{}' : '[]')); } 
      catch(e) { return (key === 'images-map') ? {} : []; }
  };

  // Old helper mapped to new helper to prevent breaking existing code
  function getImagesMap() { return window.getLabData('images-map'); }

  // Auto-fills the Gateway IP based on the Switch selected
  window.updateGatewayForSwitch = function(switchName) {
      const gwInput = document.querySelector('input[name="gw"]');
      if (!gwInput) return;

      const gwMap = window.getLabData('switch-gws');
      if (switchName && gwMap && gwMap[switchName]) {
          gwInput.value = gwMap[switchName];
      } else {
          // Optional: You can remove this else-block if you don't want 
          // the field to automatically clear itself when "None" is selected
          gwInput.value = ''; 
      }
  };

  // --- SMART ADD NODE LOGIC ---
  window.updateNodeFormFields = function(nodeType) {
      const connectLabel = document.getElementById('add-node-connect-label');
      const connectSelect = document.getElementById('add-node-connect-select');
      const ipContainer = document.getElementById('add-node-ip-container');
      const gwContainer = document.getElementById('add-node-gw-container');

      if (!connectSelect) return;

      // Default layout for Host/Router/Controller
      let targetType = 'switches';
      let labelText = 'Connect to Switch (eth1)';
      let showIpGw = true;

      // Smart Layouts
      if (nodeType === 'switch') {
          targetType = 'routers';
          labelText = 'Connect to Router (eth1)';
          showIpGw = false; // Switches are L2, no IP needed!
      } else if (nodeType === 'rhost') {
          targetType = 'switches';
          labelText = 'Connect to Switch (Optional)';
          showIpGw = true; 
      }

      connectLabel.innerHTML = labelText;
      
      // Toggle IP visibility
      ipContainer.style.display = showIpGw ? 'block' : 'none';
      
      // Hide Gateway for Switches AND External nodes
      gwContainer.style.display = (showIpGw && nodeType !== 'external') ? 'block' : 'none';
      
      if (!showIpGw) {
          ipContainer.querySelector('input').value = '';
          gwContainer.querySelector('input').value = '';
      }

      connectSelect.innerHTML = '<option value="" selected>-- None (Mgmt Only) --</option>';
      const optionsList = window.getLabData(targetType);
      optionsList.forEach(opt => {
          connectSelect.innerHTML += `<option value="${opt}">${opt}</option>`;
      });
      window.updateGatewayForSwitch('');
  };

  // --- UNIFIED ADD NODE ---
  window.openAddNodeModal = function(labPath) {
      document.getElementById('add-node-lab-name').value = labPath;
      document.getElementById('add-node-form').reset();
      document.getElementById('add-node-kind').innerHTML = '<option value="" disabled selected>-- Select Kind --</option>';
      document.getElementById('add-node-result').style.display = 'none';
      
      // Reset the smart form to standard view on open
      if(typeof window.updateNodeFormFields === 'function') window.updateNodeFormFields('');
      
      document.getElementById('add-node-modal').style.display = 'block';
  };

  window.updateKindOptions = function(type, targetId) {
      const map = window.getImagesMap ? window.getImagesMap() : window.getLabData('images-map');
      const kindSelect = document.getElementById(targetId);
      if (!kindSelect) return;

      kindSelect.innerHTML = '<option value="remote" disabled selected>-- Select Kind --</option>';
      
      // Inject a fake "kind" for external nodes since they don't use containers!
      if (type === 'external' || type === 'rhost') {
          kindSelect.innerHTML += `<option value="remote" selected>Remote Server</option>`;
          return;
      }

      const kinds = map[type] || [];
      kinds.forEach(k => { kindSelect.innerHTML += `<option value="${k}">${k}</option>`; });
  };

  window.submitCombinedNode = async function(e) {
      e.preventDefault();
      const form = e.target;
      const formData = new FormData(form);
      const safeLab = formData.get('lab_name').split('/').map(encodeURIComponent).join('/');
      const nodeName = formData.get('node_name');

      const isRunning = document.getElementById('lab-running-state').getAttribute('data-is-running') === 'true';
      const resultDiv = document.getElementById('add-node-result');
      const btn = form.querySelector('button[type="submit"]');
      const originalBtnHTML = btn ? btn.innerHTML : 'Save Node';

      if (btn) { btn.disabled = true; btn.innerHTML = '<i class="fas fa-spinner fa-spin"></i> Saving...'; }

      try {
          const createUrl = isRunning ? `/labs/${safeLab}/node` : `/labs/${safeLab}/node/new`;
          const createRes = await fetch(createUrl, {
              method: 'POST',
              headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
              body: new URLSearchParams(formData).toString()
          });

          // SAFELY HANDLE RAW TEXT OR JSON ERRORS
          if (!createRes.ok) {
              let errText = await createRes.text();
              try { errText = JSON.parse(errText).error || errText; } catch(e) {}
              throw new Error(errText || 'Failed to create node');
          }

          let finalNics = formData.get('nics') || '';
          const ipField = formData.get('ip');
          const typeField = formData.get('type');

          // 1. ALWAYS assign the IP to eth1 if nics is currently empty (for both Hosts and External nodes)
          if (!finalNics.trim() && ipField) {
              finalNics = `eth1=${ipField}`;
              formData.set('nics', finalNics);
          }

          // 2. Add the SSH terminal override specifically for External nodes
          if (typeField === 'rhost' && ipField) {
              const ipOnly = ipField.split('/')[0];
              formData.set('term', `ssh://root@${ipOnly}`);
          }
          
          formData.append('format', 'form');

          const editRes = await fetch(`/labs/${safeLab}/node/${encodeURIComponent(nodeName)}/edit`, {
              method: 'POST',
              headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
              body: new URLSearchParams(formData).toString()
          });

          // SAFELY HANDLE RAW TEXT OR JSON ERRORS
          if (!editRes.ok) {
              let errText = await editRes.text();
              try { errText = JSON.parse(errText).error || errText; } catch(e) {}
              throw new Error('Node created, but failed to save advanced settings: ' + errText);
          }

          resultDiv.style.cssText = 'background-color: rgba(16, 185, 129, 0.2); color: #10b981; border: 1px solid #10b981; display: block; margin-top: 10px; padding: 8px;';
          resultDiv.textContent = '✅ Node saved successfully! (Reloading...)';
          setTimeout(() => location.reload(), 800);

      } catch (err) {
          resultDiv.style.cssText = 'background-color: rgba(239, 68, 68, 0.2); color: #ef4444; border: 1px solid #ef4444; display: block; margin-top: 10px; padding: 8px;';
          resultDiv.textContent = '❌ ' + err.message;
          if (btn) { btn.disabled = false; btn.innerHTML = originalBtnHTML; }
      }
  };

  window.openEditorTab = function(evt, tabName) {
    let i, x, tablinks;
    x = document.getElementsByClassName("editor-tab");
    for (i = 0; i < x.length; i++) x[i].style.display = "none";
    
    tablinks = document.getElementsByClassName("editor-tablink");
    for (i = 0; i < tablinks.length; i++) tablinks[i].className = tablinks[i].className.replace(" w3-text-blue", "");
    
    document.getElementById(tabName).style.display = "block";
    evt.currentTarget.className += " w3-text-blue";

    // --- CODEMIRROR INITIALIZATION FOR YAML ---
    if (tabName === 'YamlEdit') {
        window.initCodeEditor('node-yaml-editor', 'yaml');
    }
  };

  // --- NODES ---
  window.editNodeConfig = async function(labName, nodeName) {
      window.currentEditLab = labName;
      window.currentEditNode = nodeName;
      document.getElementById('editor-node-name').textContent = nodeName;
      document.getElementById('node-editor-result').style.display = 'none';

      try {
          const safeLab = labName.split('/').map(encodeURIComponent).join('/');
          const res     = await fetch(`/labs/${safeLab}/node/${encodeURIComponent(nodeName)}`);
          if (!res.ok) throw new Error("HTTP Status " + res.status);
          const data = await res.json();

          document.getElementById('node-yaml-editor').value = data.yaml;
          if (window.cmEditors['node-yaml-editor']) {
            window.cmEditors['node-yaml-editor'].setValue(data.yaml);
          }
          //if (window.nodeYamlEditorInstance) {
          //  window.nodeYamlEditorInstance.setValue(data.yaml);
          // }

          if (data.json) {
              document.getElementById('edit-type').value = data.json.type || 'host';
              document.getElementById('edit-kind').value = data.json.kind || '';
              document.getElementById('edit-gw').value   = data.json.gw   || '';
              document.getElementById('edit-info').value = data.json.info || '';
              document.getElementById('edit-term').value = data.json.term || '';

              let nicsStr = '';
              if (data.json.nics) {
                  for (const [key, value] of Object.entries(data.json.nics)) {
                      nicsStr += `${key}=${value}\n`;
                  }
              }
              document.getElementById('edit-nics').value = nicsStr.trim();

              let urlStr = '';
              if (data.json.urls && typeof data.json.urls === 'object') {
                  for (const [title, link] of Object.entries(data.json.urls)) {
                      urlStr += `${title}|${link}\n`;
                  }
              }
              document.getElementById('edit-urls').value = urlStr.trim();
          }

          document.getElementById('defaultTab').click();
          document.getElementById('node-editor-modal').style.display = 'block';
      } catch (err) {
          alert("Failed to load node configuration. " + err.message);
      }
  };

  window.saveNodeConfig = async function() {
      const resultDiv = document.getElementById('node-editor-result');
      const formData  = new URLSearchParams();
      const isYaml    = document.getElementById('YamlEdit').style.display === 'block';

      if (isYaml) {
          formData.append('format', 'yaml');
          // USE CODEMIRROR VALUE IF IT EXISTS
          const yamlValue = window.cmEditors['node-yaml-editor'] ? window.cmEditors['node-yaml-editor'].getValue() : document.getElementById('node-yaml-editor').value;
          formData.append('yaml_data', yamlValue);
      } else {
          formData.append('format', 'form');
          formData.append('type', document.getElementById('edit-type').value);
          formData.append('kind', document.getElementById('edit-kind').value);
          formData.append('gw', document.getElementById('edit-gw').value);
          formData.append('nics', document.getElementById('edit-nics').value);
          formData.append('info', document.getElementById('edit-info').value);
          formData.append('urls_text', document.getElementById('edit-urls').value);
          formData.append('term', document.getElementById('edit-term').value);
      }

      const safeLab = window.currentEditLab.split('/').map(encodeURIComponent).join('/');
      try {
          const res = await fetch(`/labs/${safeLab}/node_edit/${encodeURIComponent(window.currentEditNode)}`, {
              method: 'POST',
              headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
              body: formData.toString()
          });
          const data = await res.json();
          if (res.ok) {
              resultDiv.style.cssText = 'background-color: rgba(16, 185, 129, 0.2); color: #10b981; border: 1px solid #10b981; display: block; margin-top: 10px; padding: 8px;';
              resultDiv.textContent = '✅ ' + data.message + ' (Reloading...)';
              setTimeout(() => location.reload(), 800);
          } else {
              throw new Error(data.error || 'Failed to save configuration');
          }
      } catch (err) {
          resultDiv.style.cssText = 'background-color: rgba(239, 68, 68, 0.2); color: #ef4444; border: 1px solid #ef4444; display: block; margin-top: 10px; padding: 8px;';
          resultDiv.textContent = '❌ ' + err.message;
      }
  };

  window.submitAdhocDnat = async function(e) {
      e.preventDefault();
      const formData = new FormData(e.target);
      const safeLab = formData.get('lab_name').split('/').map(encodeURIComponent).join('/');
      const resultDiv = document.getElementById('adhoc-dnat-result');

      try {
          const res = await fetch(`/labs/${safeLab}/dnat`, {
              method: 'POST',
              headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
              body: new URLSearchParams(formData).toString()
          });
          const data = await res.json();
          if (res.ok) {
              resultDiv.style.cssText = 'background-color: rgba(16, 185, 129, 0.2); color: #10b981; border: 1px solid #10b981; display: block; margin-top: 10px; padding: 8px;';
              resultDiv.textContent = '✅ ' + data.message;
              setTimeout(() => location.reload(), 800);
          } else throw new Error(data.error);
      } catch (err) {
          resultDiv.style.cssText = 'background-color: rgba(239, 68, 68, 0.2); color: #ef4444; border: 1px solid #ef4444; display: block; margin-top: 10px; padding: 8px;';
          resultDiv.textContent = '❌ ' + err.message;
      }
  };

  // --- DELETE ROUTINES ---
  window.deleteItem = async function(labName, endpointPath) {
      if (!confirm("Are you sure you want to delete this item?")) return;
      const safeLab = labName.split('/').map(encodeURIComponent).join('/');
      try {
          const res = await fetch(`/labs/${safeLab}/${endpointPath}/delete`, { method: 'POST' });
          if (res.ok) setTimeout(() => location.reload(), 300);
          else alert("Failed to delete item.");
      } catch (err) { alert("Error: " + err.message); }
  };

  window.deleteDnat = async function(labName, node, ext, int, proto) {
      if (!confirm("Delete this port forwarding rule?")) return;
      const safeLab = labName.split('/').map(encodeURIComponent).join('/');
      try {
          const res = await fetch(`/labs/${safeLab}/dnat/delete`, {
              method: 'POST',
              headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
              body: new URLSearchParams({ node, ext, int, proto }).toString()
          });
          if (res.ok) setTimeout(() => location.reload(), 300);
          else alert("Failed to delete DNAT rule.");
      } catch (err) { alert("Error: " + err.message); }
  };

  window.deleteLink = async function(labName, ep1, ep2) {
      if (!confirm("Delete this link?")) return;
      const safeLab = labName.split('/').map(encodeURIComponent).join('/');
      try {
          const res = await fetch(`/labs/${safeLab}/link/delete`, {
              method: 'POST',
              headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
              body: new URLSearchParams({ ep1, ep2 }).toString()
          });
          if (res.ok) setTimeout(() => location.reload(), 300);
          else alert("Failed to delete link.");
      } catch (err) { alert("Error: " + err.message); }
  };

  // --- IMAGES ---
  window.openImageEditor = function(labName) {
      window.currentEditLab = labName;
      document.getElementById('image-editor-result').style.display = 'none';
      document.getElementById('edit-img-type').value = 'host';
      document.getElementById('edit-img-kind').value = '';
      document.getElementById('edit-img-ref').value = '';
      document.getElementById('edit-img-caps').value = '';
      document.getElementById('edit-img-env').value = '';
      document.getElementById('edit-img-extras').value = '';
      document.getElementById('image-editor-modal').style.display = 'block';
  };

  window.editImageConfig = function(labPath, type, kind, image, caps, env, extras) {
      window.currentEditLab = labPath; 
      
      const typeSelect = document.getElementById('edit-img-type');
      const imgInput = document.getElementById('edit-img-ref'); // Now an input again!
      
      const safeType = type || '';
      const safeImg = image ? decodeURIComponent(image) : '';

      // SMART GUARDRAIL: If the profile has a custom Node Type not in the list, inject it dynamically!
      if (safeType && !Array.from(typeSelect.options).some(opt => opt.value === safeType)) {
          const newOpt = document.createElement('option');
          newOpt.value = safeType;
          newOpt.text = safeType + ' (Custom)';
          typeSelect.appendChild(newOpt);
      }
      typeSelect.value = safeType;

      // The datalist input natively accepts any value, so we just set it!
      imgInput.value = safeImg;

      document.getElementById('edit-img-kind').value = kind || '';
      document.getElementById('edit-img-caps').value = caps ? decodeURIComponent(caps) : '';
      document.getElementById('edit-img-env').value = env ? decodeURIComponent(env) : '';
      document.getElementById('edit-img-extras').value = extras ? decodeURIComponent(extras) : '';
      
      const resDiv = document.getElementById('image-editor-result');
      if (resDiv) resDiv.style.display = 'none';
      
      document.getElementById('image-editor-modal').style.display = 'block';
  };

  window.saveImageConfig = async function() {
      const resDiv = document.getElementById('image-editor-result');
      
      if (!window.currentEditLab) {
          resDiv.style.cssText = 'background-color: rgba(239, 68, 68, 0.2); color: #ef4444; border: 1px solid #ef4444; display: block; padding: 8px;';
          resDiv.innerHTML = '❌ Error: Lab path is missing from memory. Please close and re-open the modal.';
          return;
      }

      const formData = new URLSearchParams({
          type: document.getElementById('edit-img-type').value.trim(),
          kind: document.getElementById('edit-img-kind').value.trim(),
          image: document.getElementById('edit-img-ref').value.trim(),
          caps: document.getElementById('edit-img-caps').value.trim(),
          env: document.getElementById('edit-img-env').value.trim(),
          extras: document.getElementById('edit-img-extras').value.trim()
      });

      resDiv.style.cssText = 'background-color: rgba(245, 158, 11, 0.2); color: #f59e0b; border: 1px solid #f59e0b; display: block; padding: 8px;';
      resDiv.innerHTML = '<i class="fas fa-spinner fa-spin"></i> Saving profile...';

      const safeLab = window.currentEditLab.split('/').map(encodeURIComponent).join('/');
      try {
          // Send to the unified Edit/Add endpoint
          const res = await fetch(`/labs/${safeLab}/image/edit`, {
              method: 'POST',
              headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
              body: formData.toString()
          });

          if (res.ok) {
              resDiv.style.cssText = 'background-color: rgba(16, 185, 129, 0.2); color: #10b981; border: 1px solid #10b981; display: block; padding: 8px;';
              resDiv.textContent = '✅ Profile saved successfully.';
              setTimeout(() => location.reload(), 800);
          } else {
              // Safely handle HTML vs JSON error responses
              const errText = await res.text();
              let errMsg = errText;
              try { errMsg = JSON.parse(errText).error; } catch(e) {} 
              throw new Error(errMsg);
          }
      } catch (err) {
          resDiv.style.cssText = 'background-color: rgba(239, 68, 68, 0.2); color: #ef4444; border: 1px solid #ef4444; display: block; padding: 8px; max-height: 200px; overflow-y: auto;';
          resDiv.innerHTML = '❌ ' + err.message;
      }
  };

  // --- CONTAINER IMAGES FILTER ---
  window.filterContainerImages = function() {
    const input = document.getElementById('image-filter-input');
    if (!input) return;

    const filter = input.value.toUpperCase();
    const table = document.getElementById('container-images-table');
    if (!table) return;
    
    // Get all rows with class 'image-row'
    const trs = table.getElementsByClassName('image-row');

    for (let i = 0; i < trs.length; i++) {
      let tds = trs[i].getElementsByTagName('td');
      let textValue = "";
      // Grab text from the first 4 columns (Name, Category, OS, Version)
      for (let j = 0; j < 4; j++) {
        if (tds[j]) textValue += (tds[j].textContent || tds[j].innerText) + " ";
      }
      
      if (textValue.toUpperCase().indexOf(filter) > -1) {
        trs[i].style.display = "";
      } else {
        trs[i].style.display = "none";
      }
    }
  };

  // --- CODEMIRROR RAW IMAGE EDITOR ---
  window.openBuildModal = async function(imageEnc) {
      const decodedImg = decodeURIComponent(imageEnc);
      document.getElementById('build-img-name').textContent       = decodedImg;
      document.getElementById('build-img-ref').value              = decodedImg;
      document.getElementById('build-img-version').value          = "Loading...";
      document.getElementById('build-image-result').style.display = 'none';
      document.getElementById('build-dockerfile').value           = "Loading...";
      document.getElementById('build-image-modal').style.display  = 'block';

      try {
          const res = await fetch(`/images/dockerfile?image=${encodeURIComponent(decodedImg)}`);
          let data;
          try { data = await res.json(); } 
          catch (e) { throw new Error("Backend did not return valid JSON. Dockerfile missing?"); }

          if (res.ok) {
              document.getElementById('build-dockerfile').value  = data.dockerfile;
              document.getElementById('build-img-version').value = data.version || "latest";
              
              // --- UNIVERSAL CODEMIRROR INJECTION ---
              const editor = window.initCodeEditor('build-dockerfile', 'dockerfile');
              editor.setValue(data.dockerfile);

          } else {
              const errText = `# Error: ${data.error}`;
              document.getElementById('build-dockerfile').value = errText;
              if (window.cmEditors['build-dockerfile']) window.cmEditors['build-dockerfile'].setValue(errText);
          }
      } catch (err) {
          const errText = `# Fetch Error:\n# ${err.message}`;
          document.getElementById('build-dockerfile').value = errText;
          if (window.cmEditors['build-dockerfile']) window.cmEditors['build-dockerfile'].setValue(errText);
      }
  };

  window.saveDockerfileOnly = async function() {
      const resultDiv = document.getElementById('build-image-result');
      
      // USE CODEMIRROR VALUE IF IT EXISTS
      const dockerfileText = window.cmEditors['build-dockerfile'] ? window.cmEditors['build-dockerfile'].getValue() : document.getElementById('build-dockerfile').value;

      const formData = new URLSearchParams({
          image: document.getElementById('build-img-ref').value,
          version: document.getElementById('build-img-version').value,
          dockerfile: dockerfileText
      });

      resultDiv.style.cssText = 'background-color: rgba(56, 189, 248, 0.2); color: #38bdf8; border: 1px solid #38bdf8; display: block; margin-top: 10px; padding: 8px;';
      resultDiv.innerHTML = '<i class="fas fa-spinner fa-spin"></i> Saving...';

      try {
          const res = await fetch(`/images/save`, { method: 'POST', body: formData });
          if (res.ok) {
              resultDiv.style.cssText = 'background-color: rgba(16, 185, 129, 0.2); color: #10b981; border: 1px solid #10b981; display: block; margin-top: 10px; padding: 8px;';
              resultDiv.innerHTML = `✅ Saved successfully.`;
          } else throw new Error((await res.json()).error);
      } catch (err) {
          resultDiv.style.cssText = 'background-color: rgba(239, 68, 68, 0.2); color: #ef4444; border: 1px solid #ef4444; display: block; margin-top: 10px; padding: 8px;';
          resultDiv.innerHTML = '❌ ' + err.message;
      }
  };

  window.triggerImageBuild = async function(event) {
      const resultDiv = document.getElementById('build-image-result');
      
      // USE CODEMIRROR VALUE IF IT EXISTS
      const dockerfileText = window.cmEditors['build-dockerfile'] ? window.cmEditors['build-dockerfile'].getValue() : document.getElementById('build-dockerfile').value;

      const formData = new URLSearchParams({
          image: document.getElementById('build-img-ref').value,
          version: document.getElementById('build-img-version').value,
          dockerfile: dockerfileText
      });

      const btn = event ? event.currentTarget : document.querySelector("button[onclick='window.triggerImageBuild()']");
      const originalHtml = btn ? btn.innerHTML : '';
      if (btn) {
          btn.disabled = true;
          btn.innerHTML = '<i class="fas fa-spinner fa-spin"></i> Starting...';
      }

      resultDiv.style.cssText = 'background-color: rgba(245, 158, 11, 0.2); color: #f59e0b; border: 1px solid #f59e0b; display: block; margin-top: 10px; padding: 8px;';
      resultDiv.innerHTML = '<i class="fas fa-spinner fa-spin"></i> Triggering build...';

      try {
          const res = await fetch(`/images/build`, { method: 'POST', body: formData });
          const data = await res.json();
          
          if (res.ok) {
              document.getElementById('build-image-modal').style.display = 'none';
              window.location.href = `/logs?file=${encodeURIComponent(data.log_path)}&lab=ImageBuilder&action=build`;
          } else {
              throw new Error(data.error);
          }
      } catch (err) {
          resultDiv.style.cssText = 'background-color: rgba(239, 68, 68, 0.2); color: #ef4444; border: 1px solid #ef4444; display: block; margin-top: 10px; padding: 8px;';
          resultDiv.innerHTML = '❌ ' + err.message;
          if (btn) {
              btn.innerHTML = originalHtml;
              btn.disabled = false;
          }
      }
  };

  // --- NEW IMAGE MANAGEMENT ACTIONS ---

  // Open the Container Manage Images Modal
  window.openManageImagesModal = function() {
      document.getElementById('manage-images-modal').style.display = 'block';
  };

  // Unload Image from Local Registry (Eject Icon)
  window.unloadImage = async function(imageEnc) {
      const decodedImg = decodeURIComponent(imageEnc);
      if (!confirm(`Are you sure you want to unload ${decodedImg} from the container registry? (This does not delete your source files.)`)) return;
      
      try {
          const res = await fetch(`/images/unload`, { 
              method: 'POST', 
              headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
              body: new URLSearchParams({ image: decodedImg }).toString() 
          });
          if (res.ok) location.reload();
          else alert((await res.json()).error);
      } catch(err) { alert("Failed to unload image: " + err.message); }
  };

  // Add Image (Plus Icon)
  window.openAddLocalImageModal = function() {
      document.getElementById('add-local-image-modal').style.display = 'block';
  };

  window.submitNewLocalImage = async function(e) {
      e.preventDefault();
      const formData = new FormData(e.target);
      try {
          const res = await fetch(`/images/create`, { 
              method: 'POST', 
              body: new URLSearchParams(formData).toString() 
          });
          if (res.ok) location.reload();
          else alert((await res.json()).error);
      } catch(err) { alert(err.message); }
  };

  // Delete Image (Trash Icon)
  window.deleteLocalImage = async function(imageEnc) {
      const decodedImg = decodeURIComponent(imageEnc);
      if (!confirm(`WARNING: Are you absolutely sure you want to permanently delete the ${decodedImg} directory and all files inside it?`)) return;
      
      try {
          const res = await fetch(`/images/delete`, { 
              method: 'POST', 
              headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
              body: new URLSearchParams({ image: decodedImg }).toString() 
          });
          if (res.ok) location.reload();
          else alert((await res.json()).error);
      } catch(err) { alert(err.message); }
  };

  // Pull External Image from Docker Hub / Registry
  window.submitPullImage = async function(e) {
      e.preventDefault();
      const formData = new FormData(e.target);
      const btn = e.target.querySelector('button[type="submit"]');
      const origText = btn.innerHTML;
      
      btn.innerHTML = '<i class="fas fa-spinner fa-spin"></i> Pulling...';
      btn.disabled = true;

      try {
          const res = await fetch(`/images/pull`, { 
              method: 'POST', 
              headers: { 'Content-Type': 'application/x-www-form-urlencoded' }, 
              body: new URLSearchParams(formData).toString() 
          });
          if (res.ok) location.reload();
          else { 
              alert((await res.json()).error); 
              btn.innerHTML = origText; 
              btn.disabled = false; 
          }
      } catch(err) { alert(err.message); btn.innerHTML = origText; btn.disabled = false; }
  };

  // Remove an imported image directly by its full registry tag
  window.removeImportedImage = async function(imageTagEnc) {
      const tag = decodeURIComponent(imageTagEnc);
      if (!confirm(`Remove external image '${tag}' from the registry?`)) return;
      
      try {
          const res = await fetch(`/images/remove_imported`, { 
              method: 'POST', 
              headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
              body: new URLSearchParams({ image: tag }).toString() 
          });
          if (res.ok) location.reload();
          else alert((await res.json()).error);
      } catch(err) { alert("Failed to remove image: " + err.message); }
  };

  // --- LINKS ---
  window.openLinkEditor = function(labName) {
      window.currentEditLab = labName;
      document.getElementById('edit-link-old-ep1').value = '';
      document.getElementById('edit-link-old-ep2').value = '';
      document.getElementById('edit-link-node-a').value = '';
      document.getElementById('edit-link-int-a').value = '';
      document.getElementById('edit-link-node-b').value = '';
      document.getElementById('edit-link-int-b').value = '';
      document.getElementById('link-editor-modal').style.display = 'block';
  };

  window.editLinkConfig = function(labName, nodeA, intA, nodeB, intB, oldEp1, oldEp2) {
      window.currentEditLab = labName;
      document.getElementById('edit-link-old-ep1').value = oldEp1;
      document.getElementById('edit-link-old-ep2').value = oldEp2;
      document.getElementById('edit-link-node-a').value = nodeA;
      document.getElementById('edit-link-int-a').value = intA;
      document.getElementById('edit-link-node-b').value = nodeB;
      document.getElementById('edit-link-int-b').value = intB;
      document.getElementById('link-editor-modal').style.display = 'block';
  };

  window.saveLinkConfig = async function() {
      const safeLab = window.currentEditLab.split('/').map(encodeURIComponent).join('/');
      const formData = new URLSearchParams({
          old_ep1: document.getElementById('edit-link-old-ep1').value,
          old_ep2: document.getElementById('edit-link-old-ep2').value,
          node_a: document.getElementById('edit-link-node-a').value,
          int_a: document.getElementById('edit-link-int-a').value,
          node_b: document.getElementById('edit-link-node-b').value,
          int_b: document.getElementById('edit-link-int-b').value
      });

      try {
          const res = await fetch(`/labs/${safeLab}/link/save`, {
              method: 'POST',
              headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
              body: formData.toString()
          });
          if (res.ok) setTimeout(() => location.reload(), 300);
          else { const data = await res.json(); alert(data.error); }
      } catch (err) { alert("Error: " + err.message); }
  };

  // --- UNIFIED FILE BROWSER ---
  window.openUnifiedBrowser = async function(mode) {
      window.currentBrowserMode = mode; // 'ansible' or 'terraform'
      const searchInput = document.getElementById('unified-file-search');
      const listDiv = document.getElementById('unified-file-list');
      const pathInput = document.getElementById('unified-file-input');
      
      searchInput.value = '';
      pathInput.value = '';
      listDiv.innerHTML = '<div style="padding: 16px; text-align: center; color: #94a3b8;"><i class="fas fa-spinner fa-spin"></i> Loading workspace...</div>';
      document.getElementById('unified-file-browser-modal').style.display = 'block';

      try {
          const safeLab = window.currentEditLab.split('/').map(encodeURIComponent).join('/');
          const res = await fetch(`/labs/${safeLab}/${mode}/tree?t=${Date.now()}`);
          if (res.ok) {
              const files = await res.json();
              listDiv.innerHTML = '';
              
              if (files.length === 0) {
                  listDiv.innerHTML = '<div style="padding: 16px; text-align: center; color: #64748b;">Workspace is empty.</div>';
              } else {
                  files.forEach(filepath => {
                      const item = document.createElement('div');
                      item.className = 'file-list-item';
                      
                      // Assign an icon based on extension
          let icon = 'fa-file-alt';
          if (filepath.endsWith('.yml') || filepath.endsWith('.yaml')) icon = 'fa-file-code w3-text-red';
          else if (filepath.endsWith('.tf')) icon = 'fa-cubes w3-text-purple';
          else if (filepath.endsWith('.py')) icon = 'fa-brands fa-python w3-text-blue';
          else if (filepath.endsWith('.sh')) icon = 'fa-terminal w3-text-green';
                      
                      item.innerHTML = `<i class="fas ${icon}" style="width: 16px; text-align: center;"></i> <span>${filepath}</span>`;
                      item.onclick = function() {
                          // Highlight selection
                          document.querySelectorAll('.file-list-item').forEach(el => el.classList.remove('selected'));
                          item.classList.add('selected');
                          pathInput.value = filepath;
                      };
                      listDiv.appendChild(item);
                  });
              }
          }
      } catch (e) {
          listDiv.innerHTML = `<div style="padding: 16px; color: #ef4444;">❌ Failed to load tree: ${e.message}</div>`;
      }
  };

  window.filterUnifiedFileBrowser = function() {
      const filter = document.getElementById('unified-file-search').value.toLowerCase();
      const items = document.querySelectorAll('.file-list-item');
      items.forEach(item => {
          const text = item.innerText.toLowerCase();
          item.style.display = text.includes(filter) ? 'flex' : 'none';
      });
  };

  window.confirmUnifiedFileBrowser = function() {
      const path = document.getElementById('unified-file-input').value.trim();
      if (!path) return;

      document.getElementById('unified-file-browser-modal').style.display = 'none';
      
      if (window.currentBrowserMode === 'ansible') {
          window.fetchAnsibleFile(path);
      } else {
          window.fetchTerraformFile(path);
      }
  };

  // --- ANSIBLE ---
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

  // --- SAVE ACTIVE LAB ---
  window.saveActiveLab = async function() {
      const labSelector = document.getElementById('lab-selector');
      if (!labSelector || !labSelector.value) {
          alert("No lab selected.");
          return;
      }

      const labPath = labSelector.value;

      // Find the button and show a loading state
      const btn = document.querySelector('button[onclick="window.saveActiveLab()"]');
      const origHTML = btn ? btn.innerHTML : '';
      if (btn) {
          btn.disabled = true;
          btn.innerHTML = '<i class="fas fa-spinner fa-spin"></i> Saving...';
      }

      try {
          const safeLab = labPath.split('/').map(encodeURIComponent).join('/');
          
          // Send the save command to the backend
          const res = await fetch(`/labs/${safeLab}/save`, { method: 'POST' });
          
          if (!res.ok) {
              let errText = await res.text();
              try { errText = JSON.parse(errText).error || errText; } catch(e) {}
              
              // If the backend sends an HTML error page (like a 404 or 500)
              if (errText.trim().startsWith("<!DOCTYPE") || errText.trim().startsWith("<html")) {
                  throw new Error(`HTTP ${res.status}: Backend route missing or crashed. Check the terminal!`);
              }
              throw new Error(errText || "Failed to save lab configuration.");
          }

          // Create a nice temporary success notification
          const infoSection = document.getElementById('lab-info-section');
          const successDiv = document.createElement('div');
          successDiv.className = 'w3-panel w3-green w3-round';
          successDiv.innerHTML = '<h4><i class="fas fa-check-circle"></i> Saved!</h4><p>Runtime changes permanently saved to base YAML.</p>';
          infoSection.prepend(successDiv);
          
          setTimeout(() => location.reload(), 1500);

      } catch (err) {
          alert("Error: " + err.message);
          if (btn) {
              btn.disabled = false;
              btn.innerHTML = origHTML;
          }
      }
  };

  window.submitSaveAs = async function(e) {
      e.preventDefault();
      const form = e.target;
      const formData = new FormData(form);
      const labSelector = document.getElementById('lab-selector');
      if (!labSelector || !labSelector.value) return;

      const safeLab = labSelector.value.split('/').map(encodeURIComponent).join('/');
      const btn = form.querySelector('button[type="submit"]');
      const originalBtnHTML = btn.innerHTML;
      btn.disabled = true; 
      btn.innerHTML = '<i class="fas fa-spinner fa-spin"></i> Saving...';

      try {
        const res = await fetch(`/labs/${safeLab}/save_as`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
          body: new URLSearchParams(formData).toString()
        });
        const data = await res.json();
        
        if (res.ok) {
          // Tell the browser to select the NEW lab on reload
          localStorage.setItem('ctlabs_last_selected_lab', data.new_lab);
          // Reload the page completely so the dropdown population updates
          window.location.href = window.location.pathname; 
        } else {
          throw new Error(data.error);
        }
      } catch (err) {
        alert("Error: " + err.message);
        btn.disabled = false; 
        btn.innerHTML = originalBtnHTML;
      }
    };

  document.addEventListener('DOMContentLoaded', () => {
    const selectElement = document.getElementById('lab-selector');
    const infoSection = document.getElementById('lab-info-section');

    // Function to fetch and update the card (Manual / Dropdown Change Only)
    const fetchLabInfo = (selectedLab) => {
      
      // Show the loading spinner
      infoSection.innerHTML = '<div class="w3-panel w3-flat-midnight-blue w3-round"><p><i class="fas fa-spinner fa-spin"></i> Loading lab info...</p></div>';

      // We always pass ?init=true now, because every fetch is an intentional user action!
      fetch(`/labs/${encodeURIComponent(selectedLab)}/info_card?init=true`)
        .then(response => {
            if (!response.ok) throw new Error(`HTTP error! status: ${response.status}`);
            return response.text(); 
        })
        .then(htmlFragment => {
            infoSection.innerHTML = htmlFragment;
            
            // Auto-click the remembered tab
            const activeTab = localStorage.getItem('ctlabs_active_tab') || 'tab-overview';
            const tabBtn = document.querySelector(`button[onclick*="${activeTab}"]`);
            if (tabBtn) tabBtn.click();

            // Trigger the perfect height calculator!
            setTimeout(window.autoResizeLayout, 50);
        })
        .catch(error => {
            console.error('Error fetching lab info card:', error);
            infoSection.innerHTML = '<div class="w3-panel w3-red w3-round"><h4><i class="fas fa-exclamation-triangle"></i> Error</h4><p>Could not load lab info.</p></div>';
        });
    };

    if (selectElement) {
      // 1. Recover the last selected lab from local storage
      const savedLab = localStorage.getItem('ctlabs_last_selected_lab');
      
      if (savedLab && !selectElement.disabled) {
        const exists = Array.from(selectElement.options).some(opt => opt.value === savedLab);
        if (exists) selectElement.value = savedLab;
      }

      // 2. Setup the Dropdown Change Event
      selectElement.addEventListener('change', function() {
        const selectedLab = this.value;
        if (selectedLab) {
          localStorage.setItem('ctlabs_last_selected_lab', selectedLab);
          
          // Fetch once when the dropdown changes
          fetchLabInfo(selectedLab);
        }
      });

      // 3. Fire the change event immediately on page load
      if (selectElement.value) {
        selectElement.dispatchEvent(new Event('change'));
      }
    }
  });

