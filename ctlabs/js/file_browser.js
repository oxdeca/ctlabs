/*
 -----------------------------------------------------------------------------
 File        : ctlabs/public/js/file_browser.js
 License     : MIT License
 -----------------------------------------------------------------------------
*/

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
