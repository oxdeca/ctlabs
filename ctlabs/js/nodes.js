/*
 -----------------------------------------------------------------------------
 File        : ctlabs/public/js/nodes.js
 License     : MIT License
 -----------------------------------------------------------------------------
*/

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
    
    // Smart clear: Handle both the old select box or the new datalist input
    const kindEl = document.getElementById('add-node-kind');
    if (kindEl.tagName === 'SELECT') {
        kindEl.innerHTML = '<option value="" disabled selected>-- Select Profile --</option>';
    } else {
        kindEl.value = ''; 
        const dList = document.getElementById('add-node-kind-list');
        if (dList) dList.innerHTML = ''; 
    }
    
    document.getElementById('add-node-result').style.display = 'none';
    
    // Reset the smart form to standard view on open
    if(typeof window.updateNodeFormFields === 'function') window.updateNodeFormFields('');
    
    document.getElementById('add-node-modal').style.display = 'block';
};

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

window.updateKindOptions = function(type, targetId) {
    const map = window.getImagesMap ? window.getImagesMap() : window.getLabData('images-map');
    const targetElement = document.getElementById(targetId);
    if (!targetElement) return;
    
    // If the target is an Input with a Datalist attached
    if (targetElement.tagName === 'INPUT') {
        const dataList = document.getElementById(targetElement.getAttribute('list'));
        if (!dataList) return;
        dataList.innerHTML = ''; // Clear old options
        
        if (type === 'external' || type === 'rhost') {
            dataList.innerHTML += `<option value="remote">remote</option>`;
            targetElement.value = 'remote'; // Auto-select for remotes
        } else {
            targetElement.value = ''; // Clear current selection
            const kinds = map[type] || [];
            kinds.forEach(k => { dataList.innerHTML += `<option value="${k}">${k}</option>`; });
        }
    } else {
        // Legacy Select Fallback
        targetElement.innerHTML = '<option value="remote" disabled selected>-- Select Profile --</option>';
        if (type === 'external' || type === 'rhost') {
            targetElement.innerHTML += `<option value="remote" selected>Remote Server</option>`;
            return;
        }
        const kinds = map[type] || [];
        kinds.forEach(k => { targetElement.innerHTML += `<option value="${k}">${k}</option>`; });
    }
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
        const editRes = await fetch(`/labs/${safeLab}/node_edit/${encodeURIComponent(nodeName)}`, {
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
// Real-time filter for Active Nodes
window.filterNodes = function() {
    const input = document.getElementById('node-filter-input');
    if (!input) return;
    
    const filter = input.value.toUpperCase();
    const rows = document.getElementById('active-nodes-table')?.getElementsByClassName('node-row') || [];
    
    for (let i = 0; i < rows.length; i++) {
        rows[i].style.display = rows[i].innerText.toUpperCase().indexOf(filter) > -1 ? "" : "none";
    }
};

// Real-time filter for Node Profiles
window.filterNodeProfiles = function() {
    const input = document.getElementById('profile-filter-input');
    if (!input) return;
    
    const filter = input.value.toUpperCase();
    const rows = document.getElementById('node-profiles-table')?.getElementsByClassName('profile-row') || [];
    
    for (let i = 0; i < rows.length; i++) {
        rows[i].style.display = rows[i].innerText.toUpperCase().indexOf(filter) > -1 ? "" : "none";
    }
};

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
