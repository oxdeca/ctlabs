/*
 -----------------------------------------------------------------------------
 File        : ctlabs/public/js/images.js
 Description : Logic for managing container images
 License     : MIT License
 -----------------------------------------------------------------------------
*/

window.openManageImagesModal = function() {
    document.getElementById('manage-images-modal').style.display = 'block';
};

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
    } catch(err) { alert("Failed to delete image: " + err.message); }
};

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

window.filterContainerImages = function() {
  const input = document.getElementById('image-filter-input');
  const filter = input.value.toUpperCase();
  const table = document.getElementById('container-images-table');
  if (!table) return;
  
  const trs = table.getElementsByClassName('image-row');

  for (let i = 0; i < trs.length; i++) {
    let tds = trs[i].getElementsByTagName('td');
    let textValue = "";
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
