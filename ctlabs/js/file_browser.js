/*
 -----------------------------------------------------------------------------
 File        : ctlabs/public/js/file_browser.js
 License     : MIT License
 -----------------------------------------------------------------------------
*/

(function() {
  window.rawWorkspaceFiles = [];
  window.currentBrowsedDir = '';
  window.currentBrowserMode = 'ansible';

  function escapeHtml(str) {
    if (!str) return '';
    return String(str)
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;')
      .replace(/'/g, '&#39;');
  }

  function getFileIconAndBadge(name) {
    let icon = '<i class="fas fa-file-alt" style="color: #94a3b8; width: 16px; text-align: center;"></i>';
    let badge = 'file';

    if (name.startsWith('id_') || name.endsWith('.pub') || name.endsWith('.pem') || name.endsWith('.key') || name === 'authorized_keys' || name === 'known_hosts' || name === 'config') {
      icon = '<i class="fas fa-key" style="color: #eab308; width: 16px; text-align: center;"></i>';
      badge = 'key';
    } else if (/\.(ya?ml)$/i.test(name)) {
      icon = '<i class="fas fa-file-code" style="color: #f87171; width: 16px; text-align: center;"></i>';
      badge = 'yaml';
    } else if (/\.(tf|tfvars)$/i.test(name)) {
      icon = '<i class="fas fa-cubes" style="color: #c084fc; width: 16px; text-align: center;"></i>';
      badge = 'tf';
    } else if (/\.py$/i.test(name)) {
      icon = '<i class="fab fa-python" style="color: #60a5fa; width: 16px; text-align: center;"></i>';
      badge = 'python';
    } else if (/\.(sh|bash|zsh)$/i.test(name)) {
      icon = '<i class="fas fa-terminal" style="color: #4ade80; width: 16px; text-align: center;"></i>';
      badge = 'sh';
    } else if (/\.(ini|cfg|conf)$/i.test(name)) {
      icon = '<i class="fas fa-cog" style="color: #38bdf8; width: 16px; text-align: center;"></i>';
      badge = 'ini';
    } else if (/\.(json|xml)$/i.test(name)) {
      icon = '<i class="fas fa-code" style="color: #fb923c; width: 16px; text-align: center;"></i>';
      badge = 'json';
    } else if (/\.(tar|gz|zip|bz2|xz|7z|tgz)$/i.test(name)) {
      icon = '<i class="fas fa-file-archive" style="color: #ec4899; width: 16px; text-align: center;"></i>';
      badge = 'archive';
    } else if (/\.(md|markdown|txt)$/i.test(name)) {
      icon = '<i class="fas fa-file-alt" style="color: #a855f7; width: 16px; text-align: center;"></i>';
      badge = 'doc';
    }

    return { icon, badge };
  }

  // Parse flat file list into hierarchical folders and files for a specific directory
  function getContentsAtDir(targetDir, allFiles) {
    const normDir = (targetDir || '').replace(/^\/+|\/+$/g, '');
    const prefix = normDir ? normDir + '/' : '';
    const foldersMap = {};
    const filesList = [];

    allFiles.forEach(rawPath => {
      const isExplicitDir = (rawPath || '').endsWith('/');
      const cleanPath = (rawPath || '').replace(/^\/+|\/+$/g, '');
      if (!cleanPath) return;

      if (normDir === '') {
        // At root level
        const parts = cleanPath.split('/');
        if (parts.length > 1) {
          const folderName = parts[0];
          foldersMap[folderName] = (foldersMap[folderName] || 0) + 1;
        } else if (isExplicitDir) {
          foldersMap[parts[0]] = (foldersMap[parts[0]] || 0);
        } else {
          // File at root
          filesList.push({ name: parts[0], path: parts[0] });
        }
      } else if (cleanPath.startsWith(prefix)) {
        // Inside targetDir
        const remainder = cleanPath.slice(prefix.length);
        const parts = remainder.split('/');
        if (parts.length > 1) {
          const folderName = parts[0];
          foldersMap[folderName] = (foldersMap[folderName] || 0) + 1;
        } else if (isExplicitDir) {
          foldersMap[parts[0]] = (foldersMap[parts[0]] || 0);
        } else {
          filesList.push({ name: parts[0], path: normDir + '/' + parts[0] });
        }
      }
    });

    const folderArray = Object.keys(foldersMap).sort().map(folderName => ({
      name: folderName,
      path: normDir ? normDir + '/' + folderName : folderName,
      count: foldersMap[folderName]
    }));

    // Deduplicate files by path and sort alphabetically
    const seenFiles = new Set();
    const sortedFiles = [];
    filesList.forEach(f => {
      if (!seenFiles.has(f.path)) {
        seenFiles.add(f.path);
        sortedFiles.push(f);
      }
    });
    sortedFiles.sort((a, b) => a.name.localeCompare(b.name));

    return { folders: folderArray, files: sortedFiles };
  }

  // Render directory contents into modal list
  window.renderUnifiedDir = function(dir) {
    window.currentBrowsedDir = (dir || '').replace(/^\/+|\/+$/g, '');
    const listDiv = document.getElementById('unified-file-list');
    const breadcrumbsDiv = document.getElementById('unified-dir-breadcrumbs');
    const dirHint = document.getElementById('unified-current-dir-hint');
    const pathInput = document.getElementById('unified-file-input');

    if (!listDiv) return;

    // Render Breadcrumbs
    if (breadcrumbsDiv) {
      let bHtml = `<button class="unified-breadcrumb-btn" onclick="window.navigateUnifiedDir('')"><i class="fas fa-home"></i> root</button>`;
      if (window.currentBrowsedDir) {
        const segments = window.currentBrowsedDir.split('/');
        let accum = '';
        segments.forEach((seg, idx) => {
          accum = accum ? accum + '/' + seg : seg;
          if (idx === segments.length - 1) {
            bHtml += ` <span style="color: #64748b;">/</span> <span style="color: #f8fafc; font-family: monospace; font-size: 0.88em; padding: 2px 4px; font-weight: 600;">${escapeHtml(seg)}</span>`;
          } else {
            bHtml += ` <span style="color: #64748b;">/</span> <button class="unified-breadcrumb-btn" onclick="window.navigateUnifiedDir('${escapeHtml(accum)}')">${escapeHtml(seg)}</button>`;
          }
        });
      }
      breadcrumbsDiv.innerHTML = bHtml;
    }

    if (dirHint) {
      dirHint.textContent = window.currentBrowsedDir ? `dir: ${window.currentBrowsedDir}/` : 'dir: root/';
    }

    listDiv.innerHTML = '';

    // If inside a subfolder, render ".." parent directory row
    if (window.currentBrowsedDir !== '') {
      const parentDir = window.currentBrowsedDir.includes('/')
        ? window.currentBrowsedDir.replace(/\/[^\/]+$/, '')
        : '';

      const parentRow = document.createElement('div');
      parentRow.className = 'unified-file-item-row';
      parentRow.innerHTML = `
        <div style="display: flex; align-items: center; gap: 8px; color: #94a3b8;">
          <i class="fas fa-level-up-alt" style="color: #94a3b8; font-size: 0.9em; width: 16px; text-align: center;"></i>
          <span style="font-family: monospace; font-weight: 500;">.. (parent directory)</span>
        </div>
        <span class="unified-badge">up</span>
      `;
      parentRow.onclick = function() {
        window.navigateUnifiedDir(parentDir);
      };
      listDiv.appendChild(parentRow);
    }

    const contents = getContentsAtDir(window.currentBrowsedDir, window.rawWorkspaceFiles);

    // Empty state
    if (contents.folders.length === 0 && contents.files.length === 0) {
      const emptyDiv = document.createElement('div');
      emptyDiv.style.cssText = 'padding: 24px; text-align: center; color: #64748b; font-style: italic; font-size: 0.88em;';
      emptyDiv.innerHTML = '<i class="fas fa-folder-open" style="font-size: 1.5em; margin-bottom: 6px; display: block; color: #475569;"></i> Directory is empty';
      listDiv.appendChild(emptyDiv);
      return;
    }

    // Render Folders
    contents.folders.forEach(folder => {
      const row = document.createElement('div');
      row.className = 'unified-file-item-row';
      row.innerHTML = `
        <div style="display: flex; align-items: center; gap: 8px;">
          <i class="fas fa-folder" style="color: #f59e0b; width: 16px; text-align: center;"></i>
          <span style="font-family: monospace; color: #f8fafc; font-weight: 500;">${escapeHtml(folder.name)}/</span>
        </div>
        <div style="display: flex; align-items: center; gap: 6px;">
          <span class="unified-badge">${folder.count}</span>
          <i class="fas fa-chevron-right" style="color: #64748b; font-size: 0.75em;"></i>
        </div>
      `;
      row.onclick = function() {
        window.navigateUnifiedDir(folder.path);
      };
      listDiv.appendChild(row);
    });

    // Render Files
    contents.files.forEach(file => {
      const { icon, badge } = getFileIconAndBadge(file.name);
      const row = document.createElement('div');
      row.className = 'unified-file-item-row';
      row.innerHTML = `
        <div style="display: flex; align-items: center; gap: 8px; flex: 1; min-width: 0; overflow: hidden;">
          ${icon}
          <span style="font-family: monospace; color: #f8fafc; white-space: nowrap; overflow: hidden; text-overflow: ellipsis;">${escapeHtml(file.name)}</span>
        </div>
        <span class="unified-badge">${badge}</span>
      `;
      row.onclick = function() {
        document.querySelectorAll('.unified-file-item-row').forEach(el => el.classList.remove('selected'));
        row.classList.add('selected');
        if (pathInput) pathInput.value = file.path;
      };
      row.ondblclick = function() {
        if (pathInput) pathInput.value = file.path;
        window.confirmUnifiedFileBrowser();
      };
      listDiv.appendChild(row);
    });
  };

  // Navigate to directory
  window.navigateUnifiedDir = function(dir) {
    const searchInput = document.getElementById('unified-file-search');
    if (searchInput) searchInput.value = '';
    window.renderUnifiedDir(dir);
  };

  // Open Unified File Browser
  window.openUnifiedBrowser = async function(mode) {
    window.currentBrowserMode = mode; // 'ansible' or 'terraform'
    const searchInput = document.getElementById('unified-file-search');
    const listDiv = document.getElementById('unified-file-list');
    const pathInput = document.getElementById('unified-file-input');

    if (searchInput) searchInput.value = '';
    if (pathInput) pathInput.value = '';
    window.currentBrowsedDir = '';

    if (listDiv) {
      listDiv.innerHTML = '<div style="padding: 24px; text-align: center; color: #94a3b8;"><i class="fas fa-spinner fa-spin"></i> Loading workspace...</div>';
    }

    const modal = document.getElementById('unified-file-browser-modal');
    if (modal) modal.style.display = 'block';

    await window.refreshUnifiedFileBrowser();
  };

  // Fetch / refresh files from backend
  window.refreshUnifiedFileBrowser = async function() {
    const listDiv = document.getElementById('unified-file-list');
    const mode = window.currentBrowserMode || 'ansible';

    try {
      const rootDirInput = mode === 'ansible'
        ? document.getElementById('edit-ansible-root-dir')
        : document.getElementById('edit-terraform-root-dir');
      const rootDir = (rootDirInput?.value || '').trim();

      const scope = (typeof window.ansScope === 'function') ? window.ansScope() : '/controller';
      let url = `${scope}/${mode}/tree?t=${Date.now()}`;
      if (rootDir) url += `&root_dir=${encodeURIComponent(rootDir)}`;

      const res = await fetch(url, { credentials: 'same-origin' });
      if (res.ok) {
        const files = await res.json();
        window.rawWorkspaceFiles = Array.isArray(files) ? files : [];
        window.renderUnifiedDir(window.currentBrowsedDir || '');
      } else {
        if (listDiv) {
          listDiv.innerHTML = `<div style="padding: 20px; color: #ef4444; text-align: center;"><i class="fas fa-exclamation-triangle"></i> Failed to load files (HTTP ${res.status})</div>`;
        }
      }
    } catch (e) {
      if (listDiv) {
        listDiv.innerHTML = `<div style="padding: 20px; color: #ef4444; text-align: center;"><i class="fas fa-exclamation-triangle"></i> Error loading workspace: ${escapeHtml(e.message)}</div>`;
      }
    }
  };

  // Filter / Search across workspace files
  window.filterUnifiedFileBrowser = function() {
    const searchInput = document.getElementById('unified-file-search');
    const filter = (searchInput?.value || '').trim().toLowerCase();
    const listDiv = document.getElementById('unified-file-list');
    const pathInput = document.getElementById('unified-file-input');

    if (!filter) {
      window.renderUnifiedDir(window.currentBrowsedDir);
      return;
    }

    if (!listDiv) return;
    listDiv.innerHTML = '';

    const matchingFiles = window.rawWorkspaceFiles.filter(p => {
      const clean = (p || '').replace(/^\/+|\/+$/g, '');
      return clean && !clean.endsWith('/') && clean.toLowerCase().includes(filter);
    });

    if (matchingFiles.length === 0) {
      listDiv.innerHTML = `<div style="padding: 24px; text-align: center; color: #64748b; font-style: italic;"><i class="fas fa-search"></i> No files matching "${escapeHtml(filter)}"</div>`;
      return;
    }

    matchingFiles.forEach(rawPath => {
      const cleanPath = rawPath.replace(/^\/+|\/+$/g, '');
      const fileName = cleanPath.split('/').pop();
      const parentPath = cleanPath.includes('/') ? cleanPath.replace(/\/[^\/]+$/, '') : '';
      const { icon, badge } = getFileIconAndBadge(fileName);

      const row = document.createElement('div');
      row.className = 'unified-file-item-row';
      row.innerHTML = `
        <div style="display: flex; align-items: center; gap: 8px; flex: 1; min-width: 0; overflow: hidden;">
          ${icon}
          <div style="display: flex; flex-direction: column; min-width: 0; overflow: hidden;">
            <span style="font-family: monospace; color: #f8fafc; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; font-weight: 500;">${escapeHtml(fileName)}</span>
            ${parentPath ? `<span style="font-size: 0.78em; color: #64748b; font-family: monospace; white-space: nowrap; overflow: hidden; text-overflow: ellipsis;">${escapeHtml(parentPath)}/</span>` : ''}
          </div>
        </div>
        <span class="unified-badge">${badge}</span>
      `;
      row.onclick = function() {
        document.querySelectorAll('.unified-file-item-row').forEach(el => el.classList.remove('selected'));
        row.classList.add('selected');
        if (pathInput) pathInput.value = cleanPath;
      };
      row.ondblclick = function() {
        if (pathInput) pathInput.value = cleanPath;
        window.confirmUnifiedFileBrowser();
      };
      listDiv.appendChild(row);
    });
  };

  // Confirm Open / Create file selection
  window.confirmUnifiedFileBrowser = function() {
    const pathInput = document.getElementById('unified-file-input');
    const path = (pathInput?.value || '').trim();
    if (!path) return;

    const modal = document.getElementById('unified-file-browser-modal');
    if (modal) modal.style.display = 'none';

    if (window.currentBrowserMode === 'ansible') {
      if (typeof window.fetchAnsibleFile === 'function') {
        window.fetchAnsibleFile(path);
      }
    } else {
      if (typeof window.fetchTerraformFile === 'function') {
        window.fetchTerraformFile(path);
      }
    }
  };
})();
