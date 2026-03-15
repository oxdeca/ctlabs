/*
 -----------------------------------------------------------------------------
 File        : ctlabs/public/js/labs.js
 License     : MIT License
 -----------------------------------------------------------------------------
*/


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
      if (type === 'external') {
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
  };

  // --- NODES ---
  window.editNodeConfig = async function(labName, nodeName) {
      window.currentEditLab = labName;
      window.currentEditNode = nodeName;
      document.getElementById('editor-node-name').textContent = nodeName;
      document.getElementById('node-editor-result').style.display = 'none';

      try {
          const safeLab = labName.split('/').map(encodeURIComponent).join('/');
          const res = await fetch(`/labs/${safeLab}/node/${encodeURIComponent(nodeName)}`);
          if (!res.ok) throw new Error("HTTP Status " + res.status);
          const data = await res.json();

          document.getElementById('node-yaml-editor').value = data.yaml;

          if (data.json) {
              document.getElementById('edit-type').value = data.json.type || 'host';
              document.getElementById('edit-kind').value = data.json.kind || '';
              document.getElementById('edit-gw').value = data.json.gw || '';
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
      const formData = new URLSearchParams();
      const isYaml = document.getElementById('YamlEdit').style.display === 'block';

      if (isYaml) {
          formData.append('format', 'yaml');
          formData.append('yaml_data', document.getElementById('node-yaml-editor').value);
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
          const res = await fetch(`/labs/${safeLab}/node/${encodeURIComponent(window.currentEditNode)}/edit`, {
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

  window.editImageConfig = function(type, kind, imageEnc, capsEnc, envEnc, extrasEnc) {
      document.getElementById('edit-img-type').value = type;
      document.getElementById('edit-img-kind').value = kind;
      const decodedImg = decodeURIComponent(imageEnc);
      document.getElementById('edit-img-ref').value = decodedImg === 'N/A' ? '' : decodedImg;
      document.getElementById('edit-img-caps').value = decodeURIComponent(capsEnc);
      document.getElementById('edit-img-env').value = decodeURIComponent(envEnc);
      document.getElementById('edit-img-extras').value = decodeURIComponent(extrasEnc);
      document.getElementById('image-editor-result').style.display = 'none';
      document.getElementById('image-editor-modal').style.display = 'block';
  };

  window.saveImageConfig = async function() {
      const resultDiv = document.getElementById('image-editor-result');
      const formData = new URLSearchParams({
          type: document.getElementById('edit-img-type').value,
          kind: document.getElementById('edit-img-kind').value,
          image: document.getElementById('edit-img-ref').value,
          caps: document.getElementById('edit-img-caps').value,
          env: document.getElementById('edit-img-env').value,
          extra_attrs: document.getElementById('edit-img-extras').value
      });

      const safeLab = window.currentEditLab.split('/').map(encodeURIComponent).join('/');
      try {
          const res = await fetch(`/labs/${safeLab}/image/edit`, {
              method: 'POST',
              headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
              body: formData.toString()
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

  // --- BULLETPROOF RAW IMAGE EDITOR ---
  window.openBuildModal = async function(imageEnc) {
      const decodedImg = decodeURIComponent(imageEnc);
      document.getElementById('build-img-name').textContent = decodedImg;
      document.getElementById('build-img-ref').value = decodedImg;
      document.getElementById('build-img-version').value = "Loading...";
      document.getElementById('build-image-result').style.display = 'none';
      document.getElementById('build-dockerfile').value = "Loading...";
      document.getElementById('build-image-modal').style.display = 'block';

      try {
          const res = await fetch(`/images/dockerfile?image=${encodeURIComponent(decodedImg)}`);
          let data;
          try { data = await res.json(); } 
          catch (e) { throw new Error("Backend did not return valid JSON. Dockerfile missing?"); }

          if (res.ok) {
              document.getElementById('build-dockerfile').value = data.dockerfile;
              document.getElementById('build-img-version').value = data.version || "latest";
          } else {
              document.getElementById('build-dockerfile').value = `# Error: ${data.error}`;
          }
      } catch (err) {
          document.getElementById('build-dockerfile').value = `# Fetch Error:\n# ${err.message}`;
      }
      window.updateDockerHighlight();
  };

  window.saveDockerfileOnly = async function() {
      const resultDiv = document.getElementById('build-image-result');
      const formData = new URLSearchParams({
          image: document.getElementById('build-img-ref').value,
          version: document.getElementById('build-img-version').value,
          dockerfile: document.getElementById('build-dockerfile').value
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
      const formData = new URLSearchParams({
          image: document.getElementById('build-img-ref').value,
          version: document.getElementById('build-img-version').value,
          dockerfile: document.getElementById('build-dockerfile').value
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

  // Real-time Syntax Highlighting Sync
  window.updateDockerHighlight = function() {
      let text = document.getElementById('build-dockerfile').value;
      if (text.endsWith("\n")) text += " "; 
      
      try {
          const highlighted = hljs.highlight(text, { language: 'dockerfile', ignoreIllegals: true }).value;
          document.getElementById('raw-highlight').innerHTML = highlighted;
      } catch (e) {
          document.getElementById('raw-highlight').textContent = text;
      }
      
      // Trigger the vertical stretch every time the user types!
      window.autoResizeGlassEditor();
  };

  // Synchronizes horizontal scrolling between layers
  window.syncDockerScroll = function(element) {
      const bgLayer = document.getElementById('raw-highlight-pre');
      bgLayer.scrollLeft = element.scrollLeft; // We only need horizontal sync now!
  };

  // Perfectly stretches the container, textarea, and background layer vertically
  window.autoResizeGlassEditor = function() {
      const ta = document.getElementById('build-dockerfile');
      const pre = document.getElementById('raw-highlight-pre');
      const container = document.querySelector('.editor-container');

      // Briefly collapse to calculate true required height
      ta.style.height = '450px'; 
      
      // Calculate height based on content (minimum 450px)
      const newHeight = Math.max(450, ta.scrollHeight) + 'px';

      // Apply exact height to all 3 layers so they lock together
      ta.style.height = newHeight;
      pre.style.height = newHeight;
      container.style.height = newHeight;
  };

  // --- NEW IMAGE MANAGEMENT ACTIONS ---

  // Open the Global Manage Images Modal
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
              headers: { 'Content-Type': 'application/x-www-form-urlencoded' }, // <-- THIS WAS MISSING!
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

  // --- ANSIBLE ---
  window.openAnsibleEditor = async function(labName) {
      window.currentEditLab = labName;
      document.getElementById('ansible-editor-result').style.display = 'none';

      try {
          const safeLab = labName.split('/').map(encodeURIComponent).join('/');
          const res = await fetch(`/labs/${safeLab}/node/ansible`);
          if (!res.ok) throw new Error("Could not fetch ansible node configuration");
          const data = await res.json();

          let play = data.json.play || {};
          if (typeof play === 'string') {
              document.getElementById('edit-ansible-book').value = play;
              document.getElementById('edit-ansible-tags').value = '';
              document.getElementById('edit-ansible-env').value = '';
          } else {
              document.getElementById('edit-ansible-book').value = play.book || '';
              document.getElementById('edit-ansible-tags').value = (play.tags || []).join(', ');
              document.getElementById('edit-ansible-env').value = (play.env || []).join('\n');
          }
          document.getElementById('ansible-editor-modal').style.display = 'block';
      } catch (err) { alert("Error: " + err.message); }
  };

  window.saveAnsibleConfig = async function() {
      const resultDiv = document.getElementById('ansible-editor-result');
      const formData = new URLSearchParams({
          book: document.getElementById('edit-ansible-book').value,
          tags: document.getElementById('edit-ansible-tags').value,
          env: document.getElementById('edit-ansible-env').value
      });

      const safeLab = window.currentEditLab.split('/').map(encodeURIComponent).join('/');
      try {
          const res = await fetch(`/labs/${safeLab}/ansible/edit`, {
              method: 'POST',
              headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
              body: formData.toString()
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
