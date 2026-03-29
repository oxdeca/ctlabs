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
      if (!dataDiv) return (key === 'images-map') ? {} : [];
      try { return JSON.parse(dataDiv.getAttribute('data-' + key) || (key === 'images-map' ? '{}' : '[]')); } 
      catch(e) { return (key === 'images-map') ? {} : []; }
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

  // --- IMAGES ---
  window.openImageEditor = function(labName) {
      window.currentEditLab = labName;
      document.getElementById('node-profile-editor-result').style.display = 'none';
      document.getElementById('edit-img-type').value = 'host';
      document.getElementById('edit-img-kind').value = '';
      document.getElementById('edit-img-ref').value = '';
      document.getElementById('edit-img-caps').value = '';
      document.getElementById('edit-img-env').value = '';
      document.getElementById('edit-img-extras').value = '';
      document.getElementById('node-profile-editor').style.display = 'block';
  };

  window.editImageConfig = function(labPath, type, kind, provider, image, caps, env, extras) {
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
      document.getElementById('edit-img-provider').value = provider || 'local';
      
      const resDiv = document.getElementById('node-profile-editor-result');
      if (resDiv) resDiv.style.display = 'none';
      
      document.getElementById('node-profile-editor').style.display = 'block';
  };

  window.saveImageConfig = async function() {
      const resDiv = document.getElementById('node-profile-editor-result');
      
      if (!window.currentEditLab) {
          resDiv.style.cssText = 'background-color: rgba(239, 68, 68, 0.2); color: #ef4444; border: 1px solid #ef4444; display: block; padding: 8px;';
          resDiv.innerHTML = '❌ Error: Lab path is missing from memory. Please close and re-open the modal.';
          return;
      }

      const formData = new URLSearchParams({
          type: document.getElementById('edit-img-type').value.trim(),
          kind: document.getElementById('edit-img-kind').value.trim(),
          provider: document.getElementById('edit-img-provider').value,
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

