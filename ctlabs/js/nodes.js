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

        targetElement.value = '';
        const kinds = map[type] || [];
        kinds.forEach(k => { dataList.innerHTML += `<option value="${k}">${k}</option>`; });
    }
};

//
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

    // Set the gateway if found, otherwise clear it to avoid stale values
    if (gwMap && gwMap[switchName]) {
        gwInput.value = gwMap[switchName];
    } else {
        gwInput.value = '';
    }
};

//
window.updateNodeFormFields = function(nodeType, nodePlane) {
    const switchSelect   = document.getElementById('edit-switch');
    const ipInput        = document.getElementById('edit-ip');
    const gwInput        = document.getElementById('edit-gw');
    const planeSelect    = document.getElementById('edit-plane');
    const providerSelect = document.getElementById('edit-provider');

    if (!switchSelect || !ipInput || !gwInput) return;

    if (!nodePlane) {
        nodePlane = planeSelect ? planeSelect.value : 'data';
    }

    const provider = providerSelect ? providerSelect.value : 'local';

    const switchContainer = switchSelect.closest('.w3-col');
    const ipContainer     = ipInput.closest('.w3-col');
    const gwContainer     = gwInput.closest('.w3-col');

    const switchLabel = switchContainer ? switchContainer.querySelector('label') : null;
    const ipLabel     = ipContainer ? ipContainer.querySelector('label') : null;
    const gwLabel     = gwContainer ? gwContainer.querySelector('label') : null;

    let primaryNic = 'eth1';
    if (nodeType === 'controller' || nodePlane === 'mgmt') primaryNic = 'eth0';
    if (provider !== 'local') primaryNic = 'tun0';

    let targetType = 'switches';
    let labelText = `Connect to Switch (${primaryNic})`;
    let showIpGw = true;
    let ipLabelText = 'Data IP / Public IP Address';
    let gwLabelText = 'Gateway (gw)';

    if (nodeType === 'switch') {
        targetType = 'routers';
        labelText = `Connect to Router (${primaryNic})`;
        showIpGw = false;
    } 
    
    // Cloud / External Overrides
    if (provider !== 'local') {
        targetType = 'routers';
        labelText = `Connect to Router (${primaryNic})`;
        showIpGw = true;
        ipLabelText = `Tunnel / Data IP (${primaryNic})`;
        gwLabelText = 'Public Mgmt IP (for SSH)';
    }

    if (switchLabel) switchLabel.innerHTML = labelText;
    if (ipLabel) ipLabel.innerHTML = ipLabelText;
    if (gwLabel) gwLabel.innerHTML = gwLabelText;

    if (ipContainer) ipContainer.style.display = showIpGw ? 'block' : 'none';
    if (gwContainer) gwContainer.style.display = showIpGw ? 'block' : 'none';

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
        if (opt === window.currentEditNode) return;

        if (nodePlane === 'mgmt') {
            if (targetType === 'routers') {
                if (opt === 'ro0') switchSelect.innerHTML += `<option value="${opt}">${opt}</option>`;
            } else {
                if (opt === 'sw0' || opt === 'ro0') switchSelect.innerHTML += `<option value="${opt}">${opt}</option>`;
            }
        } else {
            if (opt !== 'sw0' && opt !== 'ro0') {
                switchSelect.innerHTML += `<option value="${opt}">${opt}</option>`;
            }
        }
    });
};

window.updateDynamicLabels = function() {
    const typeEl = document.getElementById('edit-type');
    const providerEl = document.getElementById('edit-provider');
    if (!typeEl || !providerEl) return;

    const type = typeEl.value;
    const provider = providerEl.value;

    const isVPN = (type === 'tunnel') && ['openvpn', 'wireguard', 'ipsec'].includes(provider);
    
    // Consolidated into a single, clean declaration
    const isCloud = ['gcp', 'aws', 'azure', 'external'].includes(provider);

    // Toggle the Terraform Tab visibility
    const tfTabBtn = document.getElementById('tab-btn-terraform');
    if (tfTabBtn) {
        tfTabBtn.style.display = isCloud ? 'block' : 'none';
    }

    // Toggle visibility using W3CSS column classes
    document.querySelectorAll('.std-field').forEach(el => {
        el.style.display = isVPN ? 'none' : 'block';
    });
    document.querySelectorAll('.vpn-field').forEach(el => {
        el.style.display = isVPN ? 'block' : 'none';
    });

    if (isVPN) return;

    const divEth0 = document.getElementById('div-eth0');
    const divGw   = document.getElementById('div-gw');

    if (divEth0) {
        divEth0.style.display = (type === 'router' && provider === 'local') ? 'none' : 'block';
    }

    if (divGw) {
        divGw.style.display = isCloud ? 'none' : 'block';
    }

    const profileList = document.getElementById('node-profiles-list');
    if (profileList && window.rawProfilesData) {
        profileList.innerHTML = '';
        const filteredProfiles = window.rawProfilesData.filter(p => p.provider === provider || (!p.provider && provider === 'local'));

        const uniqueKinds = [...new Set(filteredProfiles.map(p => p.kind))].sort();
        uniqueKinds.forEach(k => {
            if (k) profileList.innerHTML += `<option value="${k}">${k}</option>`;
        });
    }
};

window.toggleVpnFields = function() {
    const typeEl = document.getElementById('edit-type');
    const providerEl = document.getElementById('edit-provider');
    if (!typeEl || !providerEl) return;

    const type = typeEl.value;
    const provider = providerEl.value;
    const isVPN = (type === 'tunnel') && ['openvpn', 'wireguard', 'ipsec'].includes(provider);

    const standardFields = document.getElementById('standard-network-fields');
    const vpnFields = document.getElementById('vpn-peer-fields');

    if (standardFields) standardFields.style.display = isVPN ? 'none' : 'block';
    if (vpnFields) vpnFields.style.display = isVPN ? 'block' : 'none';
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
        const res = await fetch(`/labs/${safeLab}/node/${encodeURIComponent(nodeName)}?t=${Date.now()}`);
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
            const nodeProvider = nodeObj.provider || 'local';

            document.getElementById('edit-type').value = nodeType;
            const providerEl = document.getElementById('edit-provider');
            if (providerEl) providerEl.value = nodeProvider;
            const planeEl = document.getElementById('edit-plane');
            if(planeEl) planeEl.value = nodePlane;

            // Trigger the UI Context safely
            if (typeof window.updateDynamicLabels === 'function') {
                window.updateDynamicLabels();
            }

            // Load the peers safely
            if (nodeObj.peers) {
                const pLocal = nodeObj.peers.local || {};
                const pRemote = nodeObj.peers.remote || {};
                document.getElementById('edit-peer-local-node').value = pLocal.node || '';
                document.getElementById('edit-peer-local-nic').value  = pLocal.nic || 'tun0';
                document.getElementById('edit-peer-remote-node').value = pRemote.node || '';
                document.getElementById('edit-peer-remote-nic').value = pRemote.nic || 'tun0';
            } else {
                document.getElementById('edit-peer-local-node').value = '';
                document.getElementById('edit-peer-local-nic').value = 'tun0';
                document.getElementById('edit-peer-remote-node').value = '';
                document.getElementById('edit-peer-remote-nic').value = 'tun0';
            }

            try {
                if (typeof window.updateNodeFormFields === 'function') window.updateNodeFormFields(nodeType, nodePlane);
                if (typeof window.updateKindOptions === 'function') window.updateKindOptions(nodeType, 'edit-kind');
            } catch (e) { console.error("UI Setup Error:", e); }

            document.getElementById('edit-info').value = nodeObj.info || '';
            document.getElementById('edit-term').value = nodeObj.term || '';

            const needsLinuxFallback = ['host', 'controller', 'switch', 'router', 'gateway'].includes(nodeType) && nodeProvider === 'local';
            document.getElementById('edit-kind').value = nodeObj.profile || nodeObj.kind || (needsLinuxFallback ? 'linux' : '');

            // --- NIC EXTRACTION LOGIC ---
            let nicsStr = '';
            let eth0Ip = '';
            let eth1Ip = '';

            if (nodeObj.nics && typeof nodeObj.nics === 'object') {
                for (const [key, value] of Object.entries(nodeObj.nics)) {
                    const cleanKey = String(key).replace(/['"]/g, '').trim();
                    if (cleanKey === 'eth0') eth0Ip = value;
                    else if (cleanKey === 'eth1') eth1Ip = value;
                    else nicsStr += `${cleanKey}=${value}\n`;
                }
            }

            document.getElementById('edit-eth0').value = eth0Ip;
            document.getElementById('edit-eth1').value = eth1Ip;
            document.getElementById('edit-nics').value = nicsStr.trim();
            // --------------------------------

            let connectedSwitch = '';
            try {
                const switchNic = (nodePlane === 'mgmt' || nodeType === 'controller') ? 'eth0' : 'eth1';
                const linkRows = document.querySelectorAll('#network-links-table .link-row');
                for (const row of linkRows) {
                    const cols = row.querySelectorAll('td');
                    if (cols.length >= 2) {
                        const nodeA = cols[0].querySelector('strong')?.innerText.trim();
                        const nodeB = cols[1].querySelector('strong')?.innerText.trim();
                        const spanA = Array.from(cols[0].querySelectorAll('span')).find(s => s.innerText.includes('['));
                        const spanB = Array.from(cols[1].querySelectorAll('span')).find(s => s.innerText.includes('['));

                        const intA = spanA ? spanA.innerText.replace(/\[|\]/g, '').trim() : '';
                        const intB = spanB ? spanB.innerText.replace(/\[|\]/g, '').trim() : '';

                        if (nodeA && intA && nodeB && intB) {
                            const sideA = `${nodeA}:${intA}`;
                            const sideB = `${nodeB}:${intB}`;
                            const targetSearch = `${nodeName}:${switchNic}`;

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

            // --- LOAD CLOUD VM YAML ---
            if (data.cloud_vm_yaml) {
                document.getElementById('node-cloud-vm-editor').value = data.cloud_vm_yaml;
                if (window.cmEditors && window.cmEditors['node-cloud-vm-editor']) {
                    window.cmEditors['node-cloud-vm-editor'].setValue(data.cloud_vm_yaml);
                }
            } else {
                // Provide a helpful default skeleton if it's a new cloud node
                const defaultVmYaml = `- name: ${nodeName}\n  domain: gcp.ctlabs.internal\n  type: e2-micro\n  zone: us-east1-c\n  image: debian-12-bookworm-v20260310\n  network: net1-sub1\n  nat: true\n`;
                document.getElementById('node-cloud-vm-editor').value = defaultVmYaml;
                if (window.cmEditors && window.cmEditors['node-cloud-vm-editor']) {
                    window.cmEditors['node-cloud-vm-editor'].setValue(defaultVmYaml);
                }
            }
            
            // Trigger auto-resize for the new textareas
            setTimeout(() => {
                document.querySelectorAll('#TerraformEdit textarea').forEach(ta => {
                   ta.style.height = '56px';
                   ta.style.height = Math.max(ta.scrollHeight, 56) + 'px';
                });
            }, 10);
            // -----------------------------
        }

        const defaultTabBtn = document.getElementById('defaultTab');
        if (defaultTabBtn) defaultTabBtn.click();
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

    ['edit-node-name','edit-type','edit-kind','edit-switch','edit-eth1','edit-gw','edit-nics','edit-vols','edit-env','edit-devs','edit-info','edit-term','edit-urls', 'edit-plane', 'edit-node-tf-dir', 'edit-node-tf-workspace', 'edit-node-tf-cmds', 'edit-node-tf-vars', 'edit-node-tf-vault-project', 'edit-node-tf-vault-roleset'].forEach(id => {
        const el = document.getElementById(id);
        if (el) el.value = '';
    });

    const planeEl = document.getElementById('edit-plane');
    if (planeEl) planeEl.value = 'data';
    
    const providerEl = document.getElementById('edit-provider');
    if (providerEl) providerEl.value = 'local';

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
    const yamlEditTab = document.getElementById('YamlEdit');
    const isYaml = yamlEditTab && yamlEditTab.style.display === 'block';

    let typeField = document.getElementById('edit-type').value;
    let providerField = document.getElementById('edit-provider').value;
    let planeEl = document.getElementById('edit-plane');
    let planeField = planeEl ? planeEl.value : 'data';

    let eth0Field = document.getElementById('edit-eth0').value.trim();
    let eth1Field = document.getElementById('edit-eth1').value.trim();
    let advancedNics = document.getElementById('edit-nics').value.trim();
    let gwField   = document.getElementById('edit-gw').value.trim();
    let finalTerm = document.getElementById('edit-term').value.trim();

    if (providerField !== 'local' && !finalTerm && eth0Field) {
        const ipOnly = eth0Field.split('/')[0];
        finalTerm = `ssh://ansible@${ipOnly}`;
    }

    let nicsArray = advancedNics ? advancedNics.split('\n').map(n => n.trim()).filter(n => n !== '') : [];
    nicsArray = nicsArray.filter(n => !n.startsWith('eth0=') && !n.startsWith('eth1='));

    if (eth1Field) nicsArray.unshift(`eth1=${eth1Field}`);
    if (eth0Field) nicsArray.unshift(`eth0=${eth0Field}`);

    let finalNics = nicsArray.join('\n');

    if (isAdding) {
        formData.append('node_name', nodeName);
        formData.append('switch', document.getElementById('edit-switch').value);
        formData.append('ip', eth1Field || eth0Field);
    } else {
        formData.append('switch', document.getElementById('edit-switch').value);
    }

    const isVPN = (typeField === 'tunnel') && ['openvpn', 'wireguard', 'ipsec'].includes(providerField);
    const isCloudProvider = ['gcp', 'aws', 'azure'].includes(providerField);

    if (isYaml && !isAdding) {
        formData.append('format', 'yaml');
        const yamlValue = window.cmEditors && window.cmEditors['node-yaml-editor'] ? window.cmEditors['node-yaml-editor'].getValue() : document.getElementById('node-yaml-editor').value;
        formData.append('yaml_data', yamlValue);
    } else {
        formData.append('format', 'form');
        formData.append('type', typeField);
        formData.append('provider', providerField);
        formData.append('plane', planeField);

        // ALWAYS append these safe defaults
        formData.append('profile', document.getElementById('edit-kind').value);
        formData.append('gw',    gwField);
        formData.append('nics', finalNics);

        // --- VPN PAYLOAD ---
        if (isVPN) {
            const peersObj = {
                local: {
                    node: document.getElementById('edit-peer-local-node').value.trim(),
                    nic: document.getElementById('edit-peer-local-nic').value.trim() || 'tun0'
                },
                remote: {
                    node: document.getElementById('edit-peer-remote-node').value.trim(),
                    nic: document.getElementById('edit-peer-remote-nic').value.trim() || 'tun0'
                }
            };
            formData.append('peers', JSON.stringify(peersObj));
        }

        // --- CLOUD VM PAYLOAD ---
        if (isCloudProvider) {
            const cloudYaml = window.cmEditors && window.cmEditors['node-cloud-vm-editor'] ? window.cmEditors['node-cloud-vm-editor'].getValue() : document.getElementById('node-cloud-vm-editor').value;
            console.log("[DIAGNOSTIC - FRONTEND] Cloud YAML Payload:\n", cloudYaml);
            formData.append('cloud_vm_yaml', cloudYaml);
        }

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
            resultDiv.innerHTML = '<i class="fas fa-check-circle w3-text-green"></i> Node saved successfully! (Reloading...)';
            setTimeout(() => location.reload(), 800);
        } else {
            throw new Error(data.error || "Failed to save node.");
        }
    } catch (err) {
        resultDiv.style.cssText = 'background-color: rgba(239, 68, 68, 0.2); color: #ef4444; display: block; padding: 8px;';
        resultDiv.innerHTML = '<i class="fas fa-times-circle w3-text-red"></i> ' + err.message;
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
    if (tabName === 'TerraformEdit') {
        window.initCodeEditor('node-cloud-vm-editor', 'yaml');
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

// ===================================================
// REMOTE HOST LIVENESS WATCHER
// ===================================================
window.checkRemoteHosts = async function() {
    // Only target icons that are still spinning (unprocessed)
    const icons = document.querySelectorAll('.rhost-status-icon.fa-spin');
    if (icons.length === 0) return; // Nothing new to check

    console.log(`[Ping] Found ${icons.length} unprocessed remote hosts.`);

    for (let el of icons) {
        const rawLab = el.getAttribute('data-lab');
        if (!rawLab) continue;

        const safeLab = rawLab.split('/').map(encodeURIComponent).join('/');
        const node = encodeURIComponent(el.getAttribute('data-node'));

        // Instantly remove the spin class so we don't check it twice next loop
        el.classList.remove('fa-circle-notch', 'fa-spin', 'w3-text-gray');
        el.classList.add('fa-circle');

        console.log(`[Ping] Sending request to backend for node: ${decodeURIComponent(node)}...`);

        try {
            const res = await fetch(`/labs/${safeLab}/node/${node}/ping`);
            const data = await res.json();

            if (res.ok && data.alive) {
                console.log(`[Ping] ${decodeURIComponent(node)} is ALIVE!`);
                el.style.color = '#10b981'; // Green
                el.title = "Reachable via SSH";
            } else {
                console.warn(`[Ping] ${decodeURIComponent(node)} is OFFLINE:`, data.error || "Timeout");
                el.style.color = '#ef4444'; // Red
                el.title = data.error ? `Error: ${data.error}` : "Unreachable (Timeout)";
            }
        } catch (e) {
            console.error(`[Ping] Network/Fetch error for ${decodeURIComponent(node)}:`, e);
            el.style.color = '#ef4444';
            el.title = "Network error checking status";
        }
    }
};

// Start a background watcher that runs every 2 seconds.
// Whenever the dashboard dynamically reloads the nodes.erb card, this will instantly catch it!
setInterval(window.checkRemoteHosts, 2000);

