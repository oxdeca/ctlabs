/*
 -----------------------------------------------------------------------------
 File        : ctlabs/public/js/profiles.js
 Description : Logic for managing node profiles (images)
 License     : MIT License
 -----------------------------------------------------------------------------
*/

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
    const imgInput = document.getElementById('edit-img-ref'); 
    
    const safeType = type || '';
    const safeImg = image ? decodeURIComponent(image) : '';

    if (safeType && !Array.from(typeSelect.options).some(opt => opt.value === safeType)) {
        const newOpt = document.createElement('option');
        newOpt.value = safeType;
        newOpt.text = safeType + ' (Custom)';
        typeSelect.appendChild(newOpt);
    }
    typeSelect.value = safeType;
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

window.filterNodeProfiles = function() {
    const filter = document.getElementById('profile-filter-input').value.toUpperCase();
    const rows = document.getElementById('node-profiles-table')?.getElementsByClassName('profile-row') || [];
    for (let i = 0; i < rows.length; i++) {
        rows[i].style.display = rows[i].innerText.toUpperCase().indexOf(filter) > -1 ? "" : "none";
    }
};
