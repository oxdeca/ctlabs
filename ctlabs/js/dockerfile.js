/*
 -----------------------------------------------------------------------------
 File        : ctlabs/public/js/dockerfile.js
 License     : MIT License
 -----------------------------------------------------------------------------
*/

// Add/Import Container Image
window.openAddLocalImageModal = function() {
  document.getElementById('add-container-image').style.display = 'block';
};

// --- CODEMIRROR RAW IMAGE EDITOR ---
window.openBuildModal = async function(imageEnc) {
    const decodedImg = decodeURIComponent(imageEnc);
    
    // 1. CAPTURE THE LAST ACTIVE TAB BEFORE WE DO ANYTHING ELSE!
    const lastActiveTab = localStorage.getItem('build_active_tab_' + decodedImg) || 'BuildFile-Dockerfile';

    document.getElementById('build-img-name').textContent       = decodedImg;
    document.getElementById('build-img-ref').value              = decodedImg;
    document.getElementById('build-img-version').value          = "Loading...";
    document.getElementById('build-image-result').style.display = 'none';
    document.getElementById('dockerfile-editor').style.display  = 'block';

    if (typeof window.openBuildTab === 'function') window.openBuildTab('BuildSettings');

    // Safely clear old context tabs
    document.querySelectorAll('.build-tablink:not(:first-child):not(:nth-child(2)):not(:last-child)').forEach(e => e.remove());
    document.querySelectorAll('.build-tab[data-filepath]').forEach(e => {
        const taId = e.querySelector('textarea')?.id;
        if (taId && window.cmEditors[taId]) delete window.cmEditors[taId];
        e.remove();
    });

    try {
        const res = await fetch(`/images/dockerfile?image=${encodeURIComponent(decodedImg)}`);
        let data;
        try { data = await res.json(); } 
        catch (e) { throw new Error("Backend did not return valid JSON. Dockerfile missing?"); }
        
        const editor = window.initCodeEditor('editor-BuildFile-Dockerfile', 'dockerfile');
        
        if (res.ok) {
            document.getElementById('build-img-version').value = data.version || "latest";
            editor.setValue(data.dockerfile);
            
            // Restore context tabs
            const savedTabsStr = localStorage.getItem('build_tabs_' + decodedImg);
            let savedTabs = savedTabsStr ? JSON.parse(savedTabsStr) : null;
            if (savedTabs && savedTabs.length > 0) {
                for (const filepath of savedTabs) {
                    if (typeof window.fetchBuildFile === 'function') await window.fetchBuildFile(filepath);
                }
            }

            // 2. RESTORE FOCUS TO THE CORRECT TAB NOW THAT EVERYTHING IS LOADED
            if (document.getElementById(lastActiveTab)) {
                window.openBuildTab(lastActiveTab);
            } else {
                window.openBuildTab('BuildFile-Dockerfile');
            }

        } else {
            editor.setValue(`# Error: ${data.error}`);
        }
    } catch (err) {
        const editor = window.initCodeEditor('editor-BuildFile-Dockerfile', 'dockerfile');
        editor.setValue(`# Fetch Error:\n# ${err.message}`);
    }
};

// --- DOCKERFILE TAB MANAGEMENT LOGIC ---
window.openBuildTab = function(tabId) {
    document.querySelectorAll(".build-tab").forEach(tab => tab.style.display = "none");
    document.querySelectorAll(".build-tablink").forEach(btn => {
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

    const deleteBtn = document.getElementById('build-delete-file-btn');
    if (deleteBtn) {
        deleteBtn.style.display = (tabId === 'BuildSettings' || tabId === 'BuildFile-Dockerfile') ? 'none' : 'inline-block';
    }

    // 3. SAVE THE NEW ACTIVE TAB TO MEMORY
    const imgRef = document.getElementById('build-img-ref').value;
    if (imgRef && tabId) {
        localStorage.setItem('build_active_tab_' + imgRef, tabId);
    }

    if (tabId === 'BuildFile-Dockerfile') {
        if (window.cmEditors['editor-BuildFile-Dockerfile']) {
            setTimeout(() => window.cmEditors['editor-BuildFile-Dockerfile'].refresh(), 50);
        }
    } else {
        const taId = 'editor-' + tabId;
        if (window.cmEditors && window.cmEditors[taId]) {
            setTimeout(() => window.cmEditors[taId].refresh(), 50);
        }
    }
};

window.addBuildFileTab = function(filepath, content = "") {
    const tabId = 'build-tab-' + filepath.replace(/[^a-zA-Z0-9_-]/g, '-');
    if (document.getElementById(tabId)) { window.openBuildTab(tabId); return; }

    const basename = filepath.split('/').pop();
    const btn = document.createElement('button');
    btn.className = "w3-bar-item w3-button build-tablink";
    btn.style.display = "flex"; btn.style.alignItems = "center"; btn.style.gap = "8px";
    btn.setAttribute("data-target-tab", tabId);
    btn.setAttribute("onclick", `window.openBuildTab('${tabId}')`);
    btn.innerHTML = `<span><i class="fas fa-file-alt"></i> ${basename}</span> <i class="fas fa-times w3-text-gray w3-hover-text-red" onclick="window.closeBuildTab(event, '${tabId}')" style="font-size: 1.1em; margin-top: 1px;"></i>`;
    
    const tabBar = document.getElementById('build-tab-bar');
    tabBar.insertBefore(btn, tabBar.lastElementChild);

    const div = document.createElement('div');
    div.id = tabId; div.className = "build-tab"; div.style.display = "none"; div.style.height = "100%";
    div.setAttribute('data-filepath', filepath);
    div.innerHTML = `<textarea id="editor-${tabId}"></textarea>`;
    
    document.getElementById('build-editors-container').insertBefore(div, document.getElementById('build-image-result'));

    let mode = 'shell';
    if (filepath.endsWith('.json')) mode = 'javascript';
    else if (filepath.endsWith('.yml') || filepath.endsWith('.yaml')) mode = 'yaml';
    else if (filepath.endsWith('.py')) mode = 'python';

    const editor = window.initCodeEditor(`editor-${tabId}`, mode);
    editor.setValue(content);
    window.openBuildTab(tabId);
    window.updateBuildOpenTabs();
};

window.closeBuildTab = function(e, tabId) {
    e.stopPropagation();
    const tabBtn = e.currentTarget.closest('button');
    if (tabBtn) tabBtn.remove();
    const tabDiv = document.getElementById(tabId);
    if (tabDiv) {
        const taId = tabDiv.querySelector('textarea')?.id;
        if (taId && window.cmEditors[taId]) delete window.cmEditors[taId];
        tabDiv.remove();
    }
    document.querySelector('.build-tablink[data-target-tab="BuildFile-Dockerfile"]').click();
    window.updateBuildOpenTabs(); 
};

window.updateBuildOpenTabs = function() {
    const imgRef = document.getElementById('build-img-ref').value;
    if (!imgRef) return;
    const tabs = [];
    document.querySelectorAll('.build-tab[data-filepath]').forEach(tab => tabs.push(tab.getAttribute('data-filepath')));
    localStorage.setItem('build_tabs_' + imgRef, JSON.stringify(tabs));
};

window.openBuildFileBrowser = async function() {
    const imageRef = document.getElementById('build-img-ref').value;
    try {
        const res = await fetch(`/images/context/tree?image=${encodeURIComponent(imageRef)}&t=${Date.now()}`);
        if (res.ok) {
            const files = await res.json();
            const datalist = document.getElementById('build-files-datalist');
            datalist.innerHTML = '';
            files.forEach(f => {
                if(f !== 'Dockerfile') {
                    const opt = document.createElement('option');
                    opt.value = f; datalist.appendChild(opt);
                }
            });
        }
    } catch (e) { console.error("Failed to load build context tree", e); }
    document.getElementById('build-file-browser-input').value = '';
    document.getElementById('build-file-browser-modal').style.display = 'block';
};

window.confirmBuildFileBrowser = function() {
    const val = document.getElementById('build-file-browser-input').value.trim();
    if (val) {
        window.fetchBuildFile(val);
        document.getElementById('build-file-browser-modal').style.display = 'none';
    }
};

window.fetchBuildFile = async function(filepath) {
    const resultDiv = document.getElementById('build-image-result');
    const imageRef = document.getElementById('build-img-ref').value;
    try {
        const res = await fetch(`/images/context/file?image=${encodeURIComponent(imageRef)}&path=${encodeURIComponent(filepath)}`);
        if (!res.ok) throw new Error((await res.json()).error);
        const data = await res.json();
        window.addBuildFileTab(filepath, data.content);
    } catch (err) {
        resultDiv.style.cssText = 'background-color: rgba(239, 68, 68, 0.2); color: #ef4444; border: 1px solid #ef4444; display: block; margin-top: 15px; padding: 8px;';
        resultDiv.innerHTML = '❌ ' + err.message;
    }
};

window.deleteActiveBuildFile = async function() {
    const activeTab = document.querySelector('.build-tab[style*="display: block"]');
    if (!activeTab || activeTab.id === 'BuildSettings' || activeTab.id === 'BuildFile-Dockerfile') return;
    const filepath = activeTab.getAttribute('data-filepath');
    const imageRef = document.getElementById('build-img-ref').value;
    if (!filepath) return;

    if (!confirm(`WARNING: Are you sure you want to permanently delete '${filepath}' from the build context?`)) return;

    try {
        const res = await fetch(`/images/context/delete`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
            body: new URLSearchParams({ image: imageRef, filepath: filepath }).toString()
        });
        if (res.ok) {
            const tabBtn = document.querySelector(`button[onclick*="openBuildTab('${activeTab.id}')"]`);
            if (tabBtn) tabBtn.remove();
            const taId = activeTab.querySelector('textarea')?.id;
            if (taId && window.cmEditors[taId]) delete window.cmEditors[taId];
            activeTab.remove();
            document.querySelector('.build-tablink[data-target-tab="BuildFile-Dockerfile"]').click();
            window.updateBuildOpenTabs();
        } else throw new Error((await res.json()).error);
    } catch (err) { alert("Failed to delete file: " + err.message); }
};

window.saveDockerConfig = async function() {
    const resultDiv = document.getElementById('build-image-result');
    const dockerfileText = window.cmEditors['editor-BuildFile-Dockerfile'] ? window.cmEditors['editor-BuildFile-Dockerfile'].getValue() : '';

    const contextFiles = {};
    document.querySelectorAll('.build-tab[data-filepath]').forEach(tab => {
        const filepath = tab.getAttribute('data-filepath');
        const taId = tab.querySelector('textarea').id;
        contextFiles[filepath] = window.cmEditors[taId].getValue();
    });

    const formData = new URLSearchParams({
        image: document.getElementById('build-img-ref').value,
        version: document.getElementById('build-img-version').value,
        dockerfile: dockerfileText,
        context_files: JSON.stringify(contextFiles)
    });

    resultDiv.style.cssText = 'background-color: rgba(56, 189, 248, 0.2); color: #38bdf8; border: 1px solid #38bdf8; display: block; margin-top: 10px; padding: 8px;';
    resultDiv.innerHTML = '<i class="fas fa-spinner fa-spin"></i> Saving...';

    try {
        const res = await fetch(`/images/save`, { method: 'POST', body: formData });
        if (res.ok) {
            resultDiv.style.cssText = 'background-color: rgba(16, 185, 129, 0.2); color: #10b981; border: 1px solid #10b981; display: block; margin-top: 10px; padding: 8px;';
            resultDiv.innerHTML = `✅ Saved successfully.`;
            setTimeout(() => {resultDiv.style.display = 'none'; }, 2000);
        } else throw new Error((await res.json()).error);
    } catch (err) {
        resultDiv.style.cssText = 'background-color: rgba(239, 68, 68, 0.2); color: #ef4444; border: 1px solid #ef4444; display: block; margin-top: 10px; padding: 8px;';
        resultDiv.innerHTML = '❌ ' + err.message;
    }
};

window.triggerImageBuild = async function(event) {
    const resultDiv = document.getElementById('build-image-result');
    const dockerfileText = window.cmEditors['editor-BuildFile-Dockerfile'] ? window.cmEditors['editor-BuildFile-Dockerfile'].getValue() : '';

    const contextFiles = {};
    document.querySelectorAll('.build-tab[data-filepath]').forEach(tab => {
        const filepath = tab.getAttribute('data-filepath');
        const taId = tab.querySelector('textarea').id;
        contextFiles[filepath] = window.cmEditors[taId].getValue();
    });

    const formData = new URLSearchParams({
        image: document.getElementById('build-img-ref').value,
        version: document.getElementById('build-img-version').value,
        dockerfile: dockerfileText,
        context_files: JSON.stringify(contextFiles)
    });

    const btn = event ? event.currentTarget : document.querySelector("button[onclick='window.triggerImageBuild(event)']");
    const originalHtml = btn ? btn.innerHTML : '';
    if (btn) { btn.disabled = true; btn.innerHTML = '<i class="fas fa-spinner fa-spin"></i> Starting...'; }

    resultDiv.style.cssText = 'background-color: rgba(245, 158, 11, 0.2); color: #f59e0b; border: 1px solid #f59e0b; display: block; margin-top: 10px; padding: 8px;';
    resultDiv.innerHTML = '<i class="fas fa-spinner fa-spin"></i> Triggering build...';

    try {
        const res = await fetch(`/images/build`, { method: 'POST', body: formData });
        const data = await res.json();
        if (res.ok) {
            document.getElementById('dockerfile-editor').style.display = 'none';
            window.location.href = `/logs?id=${data.log_id}&lab=ImageBuilder&action=build`;
        } else throw new Error(data.error);    } catch (err) {
        resultDiv.style.cssText = 'background-color: rgba(239, 68, 68, 0.2); color: #ef4444; border: 1px solid #ef4444; display: block; margin-top: 10px; padding: 8px;';
        resultDiv.innerHTML = '❌ ' + err.message;
        if (btn) { btn.innerHTML = originalHtml; btn.disabled = false; }
    }
};
