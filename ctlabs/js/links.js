/*
 -----------------------------------------------------------------------------
 File        : ctlabs/public/js/links.js
 License     : MIT License
 -----------------------------------------------------------------------------
*/

// --- LINKS ---
window.openLinkEditor = function(labName) {
    window.currentEditLab = labName;
    document.getElementById('edit-link-old-ep1').value = '';
    document.getElementById('edit-link-old-ep2').value = '';
    document.getElementById('edit-link-node-a').value = '';
    document.getElementById('edit-link-int-a').value = '';
    document.getElementById('edit-link-node-b').value = '';
    document.getElementById('edit-link-int-b').value = '';
    document.getElementById('link-editor-modal').style.display = 'block';
};

// Real-time filter for Network Links
window.filterLinks = function() {
    const input = document.getElementById('link-filter-input');
    if (!input) return;
    
    const filter = input.value.toUpperCase();
    const rows = document.getElementById('network-links-table')?.getElementsByClassName('link-row') || [];
    
    for (let i = 0; i < rows.length; i++) {
        rows[i].style.display = rows[i].innerText.toUpperCase().indexOf(filter) > -1 ? "" : "none";
    }
};

window.editLinkConfig = function(labName, nodeA, intA, nodeB, intB, oldEp1, oldEp2) {
    window.currentEditLab = labName;
    document.getElementById('edit-link-old-ep1').value = oldEp1;
    document.getElementById('edit-link-old-ep2').value = oldEp2;
    document.getElementById('edit-link-node-a').value = nodeA;
    document.getElementById('edit-link-int-a').value = intA;
    document.getElementById('edit-link-node-b').value = nodeB;
    document.getElementById('edit-link-int-b').value = intB;
    document.getElementById('link-editor-modal').style.display = 'block';
};

window.saveLinkConfig = async function() {
    const safeLab = window.currentEditLab.split('/').map(encodeURIComponent).join('/');
    const formData = new URLSearchParams({
        old_ep1: document.getElementById('edit-link-old-ep1').value,
        old_ep2: document.getElementById('edit-link-old-ep2').value,
        node_a: document.getElementById('edit-link-node-a').value,
        int_a: document.getElementById('edit-link-int-a').value,
        node_b: document.getElementById('edit-link-node-b').value,
        int_b: document.getElementById('edit-link-int-b').value
    });
    try {
        const res = await fetch(`/labs/${safeLab}/link/save`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
            body: formData.toString()
        });
        if (res.ok) setTimeout(() => location.reload(), 300);
        else { const data = await res.json(); alert(data.error); }
    } catch (err) { alert("Error: " + err.message); }
};
