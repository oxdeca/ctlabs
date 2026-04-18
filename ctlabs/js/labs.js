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
      const isMap = ['images-map', 'switch-gws'].includes(key);
      if (!dataDiv) return isMap ? {} : [];
      try { 
        const val = dataDiv.getAttribute('data-' + key);
        return JSON.parse(val || (isMap ? '{}' : '[]')); 
      } catch(e) { 
        return isMap ? {} : []; 
      }
  };

  // Old helper mapped to new helper to prevent breaking existing code
  function getImagesMap() { return window.getLabData('images-map'); }


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

  // ===================================================
  // TERMINAL SESSION MANAGEMENT
  // ===================================================
  window.openTerminal = function(nodeName) {
      const w=900, h=600, t=(window.top.outerHeight/2)+window.top.screenY-(h/2), l=(window.top.outerWidth/2)+window.top.screenX-(w/2);
      const winName = `term_${nodeName.replace(/[^a-zA-Z0-9]/g, '_')}_${Date.now()}`;
      window.open(`/terminal/${encodeURIComponent(nodeName)}`, winName, `width=${w},height=${h},top=${t},left=${l},resizable=yes,scrollbars=yes,toolbar=no,location=no`);
  };

  window.manageTerminal = async function(nodeName) {
      try {
          const res = await fetch(`/terminal/${encodeURIComponent(nodeName)}/sessions`);
          if (!res.ok) throw new Error("Failed to fetch session count");
          const data = await res.json();
          const count = data.count || 0;

          // Only show the manager if we've reached the session limit (3)
          if (count < 3) {
              window.openTerminal(nodeName);
          } else {
              if (typeof window.showTerminalManager === 'function') {
                  window.showTerminalManager(nodeName, count);
              } else {
                  // Fallback if modal script not available
                  if (confirm(`This node has reached the limit of ${count} active sessions. Terminate the oldest and open a new one?`)) {
                      await fetch(`/terminal/${encodeURIComponent(nodeName)}/terminate_oldest`, { method: 'POST' });
                      window.openTerminal(nodeName);
                  }
              }
          }
      } catch (err) {
          console.error("Terminal Manager Error:", err);
          window.openTerminal(nodeName);
      }
  };
