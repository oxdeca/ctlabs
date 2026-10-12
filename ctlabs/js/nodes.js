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

// Determine the current node's editor context (type/provider/plane).
window.nicSwitchContext = function() {
    const typeEl = document.getElementById('edit-type');
    const providerEl = document.getElementById('edit-provider');
    const planeEl = document.getElementById('edit-plane');
    const type = typeEl ? typeEl.value : 'host';
    const provider = providerEl ? providerEl.value : 'local';
    const plane = planeEl ? planeEl.value : 'data';

    return { type, provider, plane };
};

// Plane-aware target pool offered by the switch <select>s. A node may only peer
// with switches/routers in its own plane class: management-plane nodes see the
// mgmt plane (e.g. sw0/ro0), everything else sees the non-mgmt plane (sw1..,
// ro1..). Routers additionally get any wired SNAT gateway (natgw).
window.nicSwitchPool = function(ctx) {
    ctx = ctx || window.nicSwitchContext();
    const g = window.getLabData ? window.getLabData.bind(window) : null;
    const switches = g ? (g('switches') || []) : [];
    const routers  = g ? (g('routers')  || []) : [];
    const planes   = g ? (g('node-planes') || {}) : {};
    const natgws   = g ? (g('natgws')   || []) : [];

    const self = window.currentEditNode;
    const selfPlane = (self && planes[self]) || ctx.plane || 'data';
    const isMgmt = (ctx.type === 'controller' || selfPlane === 'mgmt');

    const pool = [];
    switches.concat(routers).forEach(name => {
        if (name === self) return;
        const nameIsMgmt = (planes[name] || 'data') === 'mgmt';
        if (isMgmt === nameIsMgmt) pool.push(name);
    });

    if (ctx.type === 'router') {
        natgws.forEach(n => { if (n !== self && !pool.includes(n)) pool.push(n); });
    }
    return pool;
};

// Is the given profile a qemu/kvm one? Those are the only nodes where a NIC
// can be kept at the container level (not passed into the guest).
window.isQemuKind = function(kind) {
    if (!kind) return false;
    if (/qemu/i.test(kind)) return true;
    const profs = window.rawProfilesData || [];
    const p = profs.find(x => x.kind === kind);
    return !!(p && (/qemu/i.test(p.image || '') || /(^|\n)\s*kvm:\s*true/.test(p.extras || '')));
};

// Show/hide the "Container only" column based on the selected profile.
window.refreshNicContainerMode = function() {
    const kindEl = document.getElementById('edit-kind');
    window.nicContainerMode = window.isQemuKind(kindEl ? kindEl.value : '');

    const display = window.nicContainerMode ? 'flex' : 'none';
    document.querySelectorAll('.nic-container-col').forEach(el => { el.style.display = display; });
};

// (Re)fill every uplink <select> (primary NIC + extra NIC rows), preserving the
// current selection. Uses the plane-aware pool from nicSwitchPool().
window.populateNicSwitchOptions = function() {
    const pool = window.nicSwitchPool();

    const fill = (sel) => {
        if (!sel || sel.tagName !== 'SELECT') return;
        const want = sel.dataset.pending || sel.value;
        let html = '<option value="">-- None --</option>';
        pool.forEach(name => { html += `<option value="${name}">${name}</option>`; });
        if (want && !pool.includes(want)) html += `<option value="${want}">${want}</option>`;
        sel.innerHTML = html;
        sel.value = want || '';
        delete sel.dataset.pending;
    };

    document.querySelectorAll('#extra-nics-rows .nic-switch').forEach(fill);
    fill(document.getElementById('edit-switch'));
};

// Append a new additional-interface row to the node editor.
window.addNicRow = function(name, ip, sw, gw, container) {
    const wrap = document.getElementById('extra-nics-rows');
    if (!wrap) return;

    if (!name) {
        const existing = new Set();
        document.querySelectorAll('#extra-nics-rows .nic-name').forEach(el => existing.add(el.value.trim()));
        const primary = document.getElementById('primary-nic-name');
        if (primary) existing.add(primary.innerText.trim());
        let n = 2;
        while (existing.has(`eth${n}`)) n++;
        name = `eth${n}`;
    }

    const row = document.createElement('div');
    row.className = 'nic-row';
    row.style.cssText = 'display:flex; gap:6px; align-items:center; margin-top:6px;';
    row.innerHTML = `
        <input type="text" class="w3-input w3-small w3-round nic-name" value="${name}" placeholder="eth2" style="flex:0 0 110px; background-color:#0f172a; color:#e2e8f0; border:1px solid #475569; height:32px;">
        <input type="text" class="w3-input w3-small w3-round nic-ip" value="${ip || ''}" placeholder="10.0.1.1/24" style="flex:1 1 auto; background-color:#0f172a; color:#e2e8f0; border:1px solid #475569; height:32px;">
        <input type="text" class="w3-input w3-small w3-round nic-gw" value="${gw || ''}" placeholder="optional" list="edit-gw-options" style="flex:1 1 auto; background-color:#0f172a; color:#e2e8f0; border:1px solid #475569; height:32px;">
        <select class="w3-select w3-small w3-round nic-switch" style="flex:0 0 150px; background-color:#0f172a; color:#e2e8f0; border:1px solid #475569; height:32px;"><option value="">-- None --</option></select>
        <div class="nic-container-col" title="pass-through: send this NIC into the guest &middot; container: keep it at the container level" style="flex:0 0 120px; display:flex; align-items:center; margin:0;">
          <select class="w3-select w3-small w3-round nic-mode" style="background-color:#0f172a; color:#e2e8f0; border:1px solid #475569; height:32px; width:100%;">
            <option value="pass-through">pass-through</option>
            <option value="container">container</option>
          </select>
        </div>
        <button type="button" class="w3-button w3-tiny w3-round w3-red" onclick="window.removeNicRow(this)" title="Remove" style="flex:0 0 28px; padding:2px 8px;">&times;</button>`;

    if (container) row.querySelector('.nic-mode').value = 'container';
    if (!window.nicContainerMode) row.querySelector('.nic-container-col').style.display = 'none';

    wrap.appendChild(row);
    if (sw) row.querySelector('.nic-switch').dataset.pending = sw;
    window.populateNicSwitchOptions();
};

window.removeNicRow = function(btn) {
    const row = btn.closest('.nic-row');
    if (row) row.remove();
};

window.clearNicRows = function() {
    const wrap = document.getElementById('extra-nics-rows');
    if (wrap) wrap.innerHTML = '';
};

// Read the repeater rows back into a structured list.
window.collectNicRows = function() {
    const rows = [];
    document.querySelectorAll('#extra-nics-rows .nic-row').forEach(r => {
        const nameEl = r.querySelector('.nic-name');
        const ipEl   = r.querySelector('.nic-ip');
        const gwEl   = r.querySelector('.nic-gw');
        const swEl   = r.querySelector('.nic-switch');
        const modeEl = r.querySelector('.nic-mode');
        const name = nameEl ? nameEl.value.trim() : '';
        const ip   = ipEl ? ipEl.value.trim() : '';
        const gw   = gwEl ? gwEl.value.trim() : '';
        const sw   = swEl ? swEl.value : '';
        const container = !!(modeEl && modeEl.value === 'container');
        if (name && ip) rows.push({ name, ip, gw, sw, container });
    });
    return rows;
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

    if (window.populateNicSwitchOptions) window.populateNicSwitchOptions();
};

window.updateDynamicLabels = function() {
    const typeEl = document.getElementById('edit-type');
    const providerEl = document.getElementById('edit-provider');
    const planeEl = document.getElementById('edit-plane');
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

    if (divEth0) {
        // eth0 gets its own field only when it isn't the node's primary
        // interface: cloud / external nodes keep a public mgmt IP there. Local
        // nodes (data or controller) show eth0 in the primary NIC row (or get
        // it auto-generated), so the standalone mgmt field is hidden.
        divEth0.style.display = (provider !== 'local') ? 'block' : 'none';
    }

    // Keep the primary NIC row label in sync (mirrors Lab.primary_nic_for).
    const pnm = document.getElementById('primary-nic-name');
    if (pnm) {
        const planeVal = planeEl ? planeEl.value : 'data';
        pnm.innerText = (provider !== 'local') ? 'tun0'
                      : (type === 'controller' || planeVal === 'mgmt') ? 'eth0'
                      : 'eth1';
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

    if (window.populateNicSwitchOptions) window.populateNicSwitchOptions();
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
            // The "primary" NIC mirrors Lab.primary_nic_for: tun0 for remote /
            // cloud, eth0 for controllers / mgmt plane, eth1 otherwise. The
            // primary lives in the first NIC row; eth0 (when it isn't the
            // primary) has its own field; everything else becomes a repeater row.
            const primaryName = (nodeProvider !== 'local') ? 'tun0'
                              : (nodeType === 'controller' || nodePlane === 'mgmt') ? 'eth0'
                              : 'eth1';

            const cleanNics = {};
            if (nodeObj.nics && typeof nodeObj.nics === 'object') {
                for (const [key, value] of Object.entries(nodeObj.nics)) {
                    cleanNics[String(key).replace(/['"]/g, '').trim()] = value;
                }
            }

            const primaryIpEl = document.getElementById('edit-primary-ip');
            if (primaryIpEl) primaryIpEl.value = cleanNics[primaryName] || '';
            document.getElementById('edit-eth0').value = (primaryName !== 'eth0') ? (cleanNics['eth0'] || '') : '';

            const extraNics = [];
            for (const [name, ip] of Object.entries(cleanNics)) {
                if (name === primaryName) continue;
                if (name === 'eth0' && primaryName !== 'eth0') continue;
                extraNics.push({ name, ip });
            }

            // Map each interface of this node -> connected switch, from the links table
            const nicSwitchMap = {};
            try {
                document.querySelectorAll('#network-links-table .link-row').forEach(row => {
                    const cols = row.querySelectorAll('td');
                    if (cols.length < 2) return;
                    [[0, 1], [1, 0]].forEach(pair => {
                        const a = pair[0], b = pair[1];
                        const nodeA = cols[a].querySelector('strong') ? cols[a].querySelector('strong').innerText.trim() : '';
                        const spanA = Array.from(cols[a].querySelectorAll('span')).find(s => s.innerText.includes('['));
                        const intA  = spanA ? spanA.innerText.replace(/[\[\]]/g, '').trim() : '';
                        const nodeB = cols[b].querySelector('strong') ? cols[b].querySelector('strong').innerText.trim() : '';
                        if (nodeA === nodeName && intA) nicSwitchMap[intA] = nodeB;
                    });
                });
            } catch (e) { console.error("NIC/switch scrape error:", e); }

            // Per-NIC gateways (primary gateway is the node-level 'gw')
            const nicGwsMap = (nodeObj.nic_gws && typeof nodeObj.nic_gws === 'object') ? nodeObj.nic_gws : {};

            // Per-NIC "keep in container" flags (qemu nodes)
            const nicContainerMap = (nodeObj.nic_container && typeof nodeObj.nic_container === 'object') ? nodeObj.nic_container : {};

            // Primary interface label (auto): eth1 data, eth0 mgmt, tun0 remote
            const pnm = document.getElementById('primary-nic-name');
            if (pnm) pnm.innerText = primaryName;

            // Populate the additional-interfaces repeater
            if (window.refreshNicContainerMode) window.refreshNicContainerMode();
            window.clearNicRows();
            extraNics.forEach(n => window.addNicRow(
                n.name, n.ip, nicSwitchMap[n.name] || '', nicGwsMap[n.name] || '',
                !!(nicContainerMap[n.name] === true || nicContainerMap[n.name] === 'true')
            ));
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
            const cloudEditor = document.getElementById('node-cloud-vm-editor');
            if (cloudEditor) {
                if (data.cloud_vm_yaml) {
                    cloudEditor.value = data.cloud_vm_yaml;
                    if (window.cmEditors && window.cmEditors['node-cloud-vm-editor']) {
                        window.cmEditors['node-cloud-vm-editor'].setValue(data.cloud_vm_yaml);
                    }
                } else {
                    // Provide a helpful default skeleton if it's a new cloud node
                    const defaultVmYaml = `- name: ${nodeName}\n  domain: gcp.ctlabs.internal\n  type: e2-micro\n  zone: us-east1-c\n  image: debian-12-bookworm-v20260310\n  network: net1-sub1\n  nat: true\n`;
                    cloudEditor.value = defaultVmYaml;
                    if (window.cmEditors && window.cmEditors['node-cloud-vm-editor']) {
                        window.cmEditors['node-cloud-vm-editor'].setValue(defaultVmYaml);
                    }
                }
            }
            
            // Trigger auto-resize for the new textareas
            setTimeout(() => {
                const tfEdit = document.getElementById('TerraformEdit');
                if (tfEdit) {
                    tfEdit.querySelectorAll('textarea').forEach(ta => {
                       ta.style.height = '56px';
                       ta.style.height = Math.max(ta.scrollHeight, 56) + 'px';
                    });
                }
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

    ['edit-node-name','edit-type','edit-kind','edit-switch','edit-eth0','edit-primary-ip','edit-gw','edit-vols','edit-env','edit-devs','edit-info','edit-term','edit-urls', 'edit-plane', 'edit-node-tf-dir', 'edit-node-tf-workspace', 'edit-node-tf-cmds', 'edit-node-tf-vars', 'edit-node-tf-vault-project', 'edit-node-tf-vault-roleset'].forEach(id => {
        const el = document.getElementById(id);
        if (el) el.value = '';
    });

    if (window.clearNicRows) window.clearNicRows();

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

    if (typeof window.updateDynamicLabels === 'function') window.updateDynamicLabels();
    if (window.refreshNicContainerMode) window.refreshNicContainerMode();
    window.updateNodeFormFields('', 'data');
    if (window.populateNicSwitchOptions) window.populateNicSwitchOptions();
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

    let primaryIp  = document.getElementById('edit-primary-ip').value.trim();
    let eth0Field  = document.getElementById('edit-eth0').value.trim();
    let gwField    = document.getElementById('edit-gw').value.trim();
    let finalTerm  = document.getElementById('edit-term').value.trim();

    // Primary NIC name (mirrors Lab.primary_nic_for): tun0 remote/cloud,
    // eth0 controller/mgmt, eth1 otherwise.
    let primaryNicJs = 'eth1';
    if (typeField === 'controller' || planeField === 'mgmt') primaryNicJs = 'eth0';
    if (providerField !== 'local') primaryNicJs = 'tun0';

    if (providerField !== 'local' && !finalTerm && eth0Field) {
        const ipOnly = eth0Field.split('/')[0];
        finalTerm = `ssh://ansible@${ipOnly}`;
    }

    const nicRows = window.collectNicRows ? window.collectNicRows() : [];

    let nicsArray = [];
    if (primaryNicJs !== 'eth0' && eth0Field) nicsArray.push(`eth0=${eth0Field}`);
    if (primaryIp) nicsArray.push(`${primaryNicJs}=${primaryIp}`);
    nicRows.forEach(r => nicsArray.push(`${r.name}=${r.ip}`));

    let finalNics = nicsArray.join('\n');

    // Per-NIC switch wiring map (JSON) — lets the backend auto-create one
    // link per interface instead of only wiring the primary NIC.
    const nicSwitches = {};
    const mainSwitchEl = document.getElementById('edit-switch');
    if (mainSwitchEl && mainSwitchEl.value) nicSwitches[primaryNicJs] = mainSwitchEl.value;
    nicRows.forEach(r => { if (r.sw) nicSwitches[r.name] = r.sw; });

    // Per-NIC gateway map — the primary NIC's gateway is the node-level 'gw'.
    const nicGws = {};
    nicRows.forEach(r => { if (r.gw) nicGws[r.name] = r.gw; });

    // Per-NIC "keep in container" map (qemu nodes only).
    const nicContainer = {};
    nicRows.forEach(r => { if (r.container) nicContainer[r.name] = true; });

    if (isAdding) {
        formData.append('node_name', nodeName);
        formData.append('switch', document.getElementById('edit-switch').value);
        formData.append('ip', primaryIp || eth0Field);
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
        formData.append('nic_switches', JSON.stringify(nicSwitches));
        formData.append('nic_gws', JSON.stringify(nicGws));
        formData.append('nic_container', JSON.stringify(nicContainer));

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
            const cloudEditor = document.getElementById('node-cloud-vm-editor');
            const cloudYaml = window.cmEditors && window.cmEditors['node-cloud-vm-editor'] ? window.cmEditors['node-cloud-vm-editor'].getValue() : (cloudEditor ? cloudEditor.value : '');
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
