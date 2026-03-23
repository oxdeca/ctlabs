/*
 -----------------------------------------------------------------------------
 File        : ctlabs/public/js/nodes.js
 License     : MIT License
 -----------------------------------------------------------------------------
*/

window.updateKindOptions = function(type, targetId) {
    const map = window.getImagesMap ? window.getImagesMap() : (typeof window.getLabData === 'function' ? window.getLabData('images-map') : {});
    const targetElement = document.getElementById(targetId);
    if (!targetElement) return;
    
    if (targetElement.tagName === 'INPUT') {
        const dataList = document.getElementById(targetElement.getAttribute('list'));
        if (!dataList) return;
        dataList.innerHTML = ''; 
        
        if (type === 'external' || type === 'rhost') {
            dataList.innerHTML += `<option value="remote">remote</option>`;
            targetElement.value = 'remote'; 
        } else {
            targetElement.value = ''; 
            const kinds = map[type] || [];
            kinds.forEach(k => { dataList.innerHTML += `<option value="${k}">${k}</option>`; });
        }
    }
};

window.updateGatewayForSwitch = function(switchName) {
    const gwInput = document.getElementById('edit-gw');
    if (!gwInput) return;
    
    if (!switchName) {
        gwInput.value = ''; 
        return;
    }

    let gwMap = {};
    if (typeof window.getLabData === 'function') {
        gwMap = window.getLabData('switch-gws') || {};
    }

    if (gwMap && gwMap[switchName]) {
        gwInput.value = gwMap[switchName];
    }
};

window.updateNodeFormFields = function(nodeType, nodePlane) {
    const switchSelect = document.getElementById('edit-switch');
    const ipInput = document.getElementById('edit-ip');
    const gwInput = document.getElementById('edit-gw');
    const planeSelect = document.getElementById('edit-plane');
    
    if (!switchSelect || !ipInput || !gwInput) return;

    if (!nodePlane) {
        nodePlane = planeSelect ? planeSelect.value : 'data';
    }

    const switchContainer = switchSelect.closest('.w3-col');
    const ipContainer = ipInput.closest('.w3-col');
    const gwContainer = gwInput.closest('.w3-col');
    const switchLabel = switchContainer ? switchContainer.querySelector('label') : null;

    let primaryNic = (nodeType === 'controller') ? 'eth0' : 'eth1';
    let targetType = 'switches';
    let labelText = `Connect to Switch (${primaryNic})`;
    let showIpGw = true;

    if (nodeType === 'switch') {
        targetType = 'routers';
        labelText = `Connect to Router (${primaryNic})`;
        showIpGw = false;
    } else if (nodeType === 'rhost' || nodeType === 'external') {
        targetType = 'switches';
        labelText = 'Connect to Switch (Optional)';
        showIpGw = true; 
    }

    if (switchLabel) switchLabel.innerHTML = labelText;
    if (ipContainer) ipContainer.style.display = showIpGw ? 'block' : 'none';
    if (gwContainer) gwContainer.style.display = (showIpGw && nodeType !== 'external') ? 'block' : 'none';

    if (!showIpGw) {
        ipInput.value = '';
        gwInput.value = '';
    }

    switchSelect.innerHTML = '<option value="" selected>-- None (Mgmt Only) --</option>';
    let optionsList = [];
    if (typeof window.getLabData === 'function') {
        optionsList = window.getLabData(targetType) || [];
    }

    optionsList.forEach(opt => {
        // PREVENT SELF-CONNECTION BUG: A node can never connect to itself
        if (opt === window.currentEditNode) return;

        if (nodePlane === 'mgmt') {
            // FIX: If we need a router in Mgmt Plane, ONLY show ro0 (not sw0)
            if (targetType === 'routers') {
                if (opt === 'ro0') switchSelect.innerHTML += `<option value="${opt}">${opt}</option>`;
            } else {
                // If we need a switch in Mgmt plane, show sw0 or ro0
                if (opt === 'sw0' || opt === 'ro0') switchSelect.innerHTML += `<option value="${opt}">${opt}</option>`;
            }
        } else {
            // Data/Edge Plane: Hide sw0 and ro0
            if (opt !== 'sw0' && opt !== 'ro0') {
                switchSelect.innerHTML += `<option value="${opt}">${opt}</option>`;
            }
        }
    });
};

window.editNodeConfig = async function(labName, nodeName) {
    window.currentEditLab = labName;
    window.currentEditNode = nodeName; 
    
    document.getElementById('node-modal-icon').className = 'fas fa-edit';
    document.getElementById('node-modal-title').innerText = 'Configure Node: ';
    document.getElementById('editor-node-name').innerText = nodeName;
    document.getElementById('node-modal-save-text').innerText = 'Save Override';
    document.getElementById('edit-node-name').value = nodeName;
    document.getElementById('edit-node-name').disabled = true; 
    document.getElementById('node-editor-result').style.display = 'none';
    
    try {
        const safeLab = labName.split('/').map(encodeURIComponent).join('/');
        const res = await fetch(`/labs/${safeLab}/node/${encodeURIComponent(nodeName)}`);
        if (!res.ok) throw new Error("HTTP Status " + res.status);
        const data = await res.json();
        
        document.getElementById('node-yaml-editor').value = data.yaml || '';
        if (window.cmEditors && window.cmEditors['node-yaml-editor']) {
          window.cmEditors['node-yaml-editor'].setValue(data.yaml || '');
        }

        if (data.json) {
            const nodeObj = data.json[nodeName] || data.json || {};
            const nodeType = nodeObj.type || 'host';
            const nodePlane = nodeObj.plane || 'data';
            const primaryNic = (nodeType === 'controller') ? 'eth0' : 'eth1';

            try {
                window.updateNodeFormFields(nodeType, nodePlane);
                if (typeof window.updateKindOptions === 'function') window.updateKindOptions(nodeType, 'edit-kind');
            } catch (e) { console.error("UI Setup Error:", e); }

            document.getElementById('edit-type').value = nodeType;
            
            const planeEl = document.getElementById('edit-plane');
            if(planeEl) planeEl.value = nodePlane;
            
            document.getElementById('edit-info').value = nodeObj.info || '';
            document.getElementById('edit-term').value = nodeObj.term || '';
            
            // FIX: Gracefully default switches, routers, gateways to 'linux' if missing.
            const needsLinuxFallback = ['host', 'controller', 'switch', 'router', 'gateway'].includes(nodeType);
            document.getElementById('edit-kind').value = nodeObj.kind || (needsLinuxFallback ? 'linux' : '');
            
            let nicsStr = '';
            let dataIp = '';
            if (nodeObj.nics && typeof nodeObj.nics === 'object') {
                for (const [key, value] of Object.entries(nodeObj.nics)) { 
                    const cleanKey = String(key).replace(/['"]/g, '').trim();
                    if (cleanKey === primaryNic) dataIp = value;
                    else nicsStr += `${cleanKey}=${value}\n`; 
                }
            }
            document.getElementById('edit-ip').value = dataIp;
            document.getElementById('edit-nics').value = nicsStr.trim();
            
            let connectedSwitch = '';
            try {
                const linkRows = document.querySelectorAll('#network-links-table .link-row');
                for (const row of linkRows) {
                    const cols = row.querySelectorAll('td');
                    if (cols.length >= 2) {
                        const nodeA = cols[0].querySelector('strong')?.innerText.trim();
                        const nodeB = cols[1].querySelector('strong')?.innerText.trim();
                        const spanA = Array.from(cols[0].querySelectorAll('span')).find(s => s.innerText.includes('['));
                        const spanB = Array.from(cols[1].querySelectorAll('span')).find(s => s.innerText.includes('['));
                        
                        const intA = spanA ? spanA.innerText.replace(/[[\]]/g, '').trim() : '';
                        const intB = spanB ? spanB.innerText.replace(/[[\]]/g, '').trim() : '';

                        if (nodeA && intA && nodeB && intB) {
                            const sideA = `${nodeA}:${intA}`;
                            const sideB = `${nodeB}:${intB}`;
                            const targetSearch = `${nodeName}:${primaryNic}`;

                            if (sideA === targetSearch) {
                                connectedSwitch = nodeB; break;
                            } else if (sideB === targetSearch) {
                                connectedSwitch = nodeA; break;
                            }
                        }
                    }
                }
            } catch (e) { console.error("DOM Link Scraper Error:", e); }

            if (!connectedSwitch && nodePlane === 'mgmt') {
                connectedSwitch = (nodeType === 'switch') ? 'ro0' : 'sw0';
            }
            
            if (connectedSwitch) {
                const switchSelect = document.getElementById('edit-switch');
                if (switchSelect) {
                    // Force inject if not present, to ensure the UI successfully reflects reality
                    const exists = Array.from(switchSelect.options).some(o => o.value === connectedSwitch);
                    if (!exists) switchSelect.innerHTML += `<option value="${connectedSwitch}">${connectedSwitch}</option>`;
                    switchSelect.value = connectedSwitch;
                }
            }
            
            document.getElementById('edit-gw').value = nodeObj.gw || '';
            if (!nodeObj.gw && connectedSwitch && typeof window.updateGatewayForSwitch === 'function') {
                try { window.updateGatewayForSwitch(connectedSwitch); } catch(e) {}
            }
            
            try {
                let urlStr = '';
                if (nodeObj.urls && typeof nodeObj.urls === 'object') {
                    for (const [title, link] of Object.entries(nodeObj.urls)) urlStr += `${title}|${link}\n`;
                }
                document.getElementById('edit-urls').value = urlStr.trim();
                document.getElementById('edit-vols').value = Array.isArray(nodeObj.vols) ? nodeObj.vols.join('\n') : (nodeObj.vols || '');
                document.getElementById('edit-env').value  = Array.isArray(nodeObj.env)  ? nodeObj.env.join('\n')  : (nodeObj.env || '');
                document.getElementById('edit-devs').value = Array.isArray(nodeObj.devs) ? nodeObj.devs.join('\n') : (nodeObj.devs || '');
                
                setTimeout(() => {
                    document.querySelectorAll('#AdvancedEdit textarea').forEach(ta => {
                       ta.style.height = '56px'; 
                       ta.style.height = Math.max(ta.scrollHeight, 56) + 'px'; 
                    });
                }, 10);
            } catch (e) { console.error("Advanced Fields Error:", e); }
        }
        
        document.getElementById('defaultTab').click();
        document.getElementById('node-editor-modal').style.display = 'block';
    } catch (err) {
        alert("Failed to load node configuration. " + err.message);
    }
};

window.openAddNodeModal = function(labPath) {
    window.currentEditLab = labPath;
    window.currentEditNode = null; 

    document.getElementById('node-modal-icon').className = 'fas fa-plus-circle';
    document.getElementById('node-modal-title').innerText = 'Add Node';
    document.getElementById('editor-node-name').innerText = '';
    document.getElementById('node-modal-save-text').innerText = 'Add Node';

    ['edit-node-name','edit-type','edit-kind','edit-switch','edit-ip','edit-gw','edit-nics','edit-vols','edit-env','edit-devs','edit-info','edit-term','edit-urls', 'edit-plane'].forEach(id => {
        const el = document.getElementById(id);
        if (el) el.value = '';
    });
    
    const planeEl = document.getElementById('edit-plane');
    if (planeEl) planeEl.value = 'data';

    document.getElementById('node-yaml-editor').value = '';
    if (window.cmEditors && window.cmEditors['node-yaml-editor']) {
        window.cmEditors['node-yaml-editor'].setValue('');
    }

    document.getElementById('edit-node-name').disabled = false;
    document.getElementById('node-editor-result').style.display = 'none';
    
    window.updateNodeFormFields('', 'data');
    document.getElementById('defaultTab').click();
    document.getElementById('node-editor-modal').style.display = 'block';
};

window.saveNodeConfig = async function() {
    const resultDiv = document.getElementById('node-editor-result');
    const btn = document.getElementById('node-modal-save-btn');
    const origBtnHtml = btn.innerHTML;
    
    const isAdding = !window.currentEditNode;
    const nodeName = isAdding ? document.getElementById('edit-node-name').value.trim() : window.currentEditNode;
    
    if (!nodeName) return alert("Node Name is required.");
    
    btn.disabled = true;
    btn.innerHTML = '<i class="fas fa-spinner fa-spin"></i> Saving...';
    
    const formData  = new URLSearchParams();
    const isYaml    = document.getElementById('YamlEdit').style.display === 'block';
    
    let typeField = document.getElementById('edit-type').value;
    let planeEl = document.getElementById('edit-plane');
    let planeField = planeEl ? planeEl.value : 'data';
    
    let primaryNic = (typeField === 'controller') ? 'eth0' : 'eth1';
    let ipField   = document.getElementById('edit-ip').value.trim();
    let finalNics = document.getElementById('edit-nics').value.trim();
    let finalTerm = document.getElementById('edit-term').value.trim();

    let nicsArray = finalNics ? finalNics.split('\n') : [];
    if (ipField) {
        nicsArray = nicsArray.filter(n => !n.startsWith(`${primaryNic}=`));
        nicsArray.unshift(`${primaryNic}=${ipField}`); 
    }
    finalNics = nicsArray.join('\n');

    if (isAdding) {
        formData.append('node_name', nodeName);
        formData.append('switch', document.getElementById('edit-switch').value);
        formData.append('ip', ipField);
        
        if (typeField === 'rhost' && ipField && !finalTerm) {
            const ipOnly = ipField.split('/')[0];
            finalTerm = `ssh://root@${ipOnly}`;
        }
    } else {
        formData.append('switch', document.getElementById('edit-switch').value);
    }

    if (isYaml && !isAdding) {
        formData.append('format', 'yaml');
        const yamlValue = window.cmEditors && window.cmEditors['node-yaml-editor'] ? window.cmEditors['node-yaml-editor'].getValue() : document.getElementById('node-yaml-editor').value;
        formData.append('yaml_data', yamlValue);
    } else {
        formData.append('format', 'form');
        formData.append('type', typeField);
        formData.append('plane', planeField);
        formData.append('kind', document.getElementById('edit-kind').value);
        formData.append('gw',   document.getElementById('edit-gw').value);
        formData.append('nics', finalNics);
        formData.append('info', document.getElementById('edit-info').value);
        formData.append('urls_text', document.getElementById('edit-urls').value);
        formData.append('term', finalTerm);
        formData.append('vols', document.getElementById('edit-vols').value);
        formData.append('env',  document.getElementById('edit-env').value);
        formData.append('devs', document.getElementById('edit-devs').value);
    }
    
    const safeLab = window.currentEditLab.split('/').map(encodeURIComponent).join('/');
    
    try {
        if (isAdding) {
            const labStateEl = document.getElementById('lab-running-state');
            const isRunning = labStateEl && labStateEl.getAttribute('data-is-running') === 'true';
            const createUrl = isRunning ? `/labs/${safeLab}/node` : `/labs/${safeLab}/node/new`;
            
            const createRes = await fetch(createUrl, {
                method: 'POST',
                headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
                body: formData.toString()
            });
            
            if (!createRes.ok) throw new Error(await createRes.text());
        }
        
        const editRes = await fetch(`/labs/${safeLab}/node_edit/${encodeURIComponent(nodeName)}`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
            body: formData.toString()
        });
        const data = await editRes.json();
        
        if (editRes.ok) {
            resultDiv.style.cssText = 'background-color: rgba(16, 185, 129, 0.2); color: #10b981; display: block; padding: 8px;';
            // FIX: Safe HTML injected icon, immune to encoding corruption!
            resultDiv.innerHTML = '<i class="w3-text-green fas fa-check-circle"></i> Node saved successfully! (Reloading...)';
            setTimeout(() => location.reload(), 800);
        } else {
            throw new Error(data.error);
        }
    } catch (err) {
        resultDiv.style.cssText = 'background-color: rgba(239, 68, 68, 0.2); color: #ef4444; display: block; padding: 8px;';
        resultDiv.innerHTML = '<i class="w3-text-red fas fa-times-circle"></i> ' + err.message;
        btn.disabled = false;
        btn.innerHTML = origBtnHtml;
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
    
    if (tabName === 'YamlEdit') {
        window.initCodeEditor('node-yaml-editor', 'yaml');
        
        if (!window.currentEditNode && window.cmEditors && window.cmEditors['node-yaml-editor']) {
            const cm = window.cmEditors['node-yaml-editor'];
            if (cm.getValue().trim() === '') {
                cm.setValue("# Note: The Form and Raw YAML tabs do not sync in real-time.\n# Whichever tab you are viewing when you click 'Save Node'\n# is the data that will be saved to your lab.");
            }
        }
    }
};

window.filterNodes = function() {
    const input = document.getElementById('node-filter-input');
    if (!input) return;
    const filter = input.value.toUpperCase();
    const rows = document.getElementById('active-nodes-table')?.getElementsByClassName('node-row') || [];
    for (let i = 0; i < rows.length; i++) {
        rows[i].style.display = rows[i].innerText.toUpperCase().indexOf(filter) > -1 ? "" : "none";
    }
};

window.filterNodeProfiles = function() {
    const input = document.getElementById('profile-filter-input');
    if (!input) return;
    const filter = input.value.toUpperCase();
    const rows = document.getElementById('node-profiles-table')?.getElementsByClassName('profile-row') || [];
    for (let i = 0; i < rows.length; i++) {
        rows[i].style.display = rows[i].innerText.toUpperCase().indexOf(filter) > -1 ? "" : "none";
    }
};
