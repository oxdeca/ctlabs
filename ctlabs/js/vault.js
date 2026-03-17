/*
 -----------------------------------------------------------------------------
 File        : ctlabs/public/js/vault.js
 License     : MIT License
 -----------------------------------------------------------------------------
*/

// --- VAULT AUTHENTICATION LOGIC ---

window.openVaultLoginModal = function() {
    document.getElementById('vault-login-form').reset();
    document.getElementById('vault-login-result').style.display = 'none';
    window.toggleVaultAuthFields('userpass'); // Default to human login
    document.getElementById('vault-login-modal').style.display = 'block';
};

window.toggleVaultAuthFields = function(method) {
    const humanFields = document.getElementById('vault-human-fields');
    const machineFields = document.getElementById('vault-machine-fields');
    
    if (method === 'approle') {
        humanFields.style.display = 'none';
        machineFields.style.display = 'block';
    } else {
        humanFields.style.display = 'block';
        machineFields.style.display = 'none';
    }
};

window.submitVaultLogin = async function(e) {
    e.preventDefault();
    const form = e.target;
    const formData = new FormData(form);
    const resultDiv = document.getElementById('vault-login-result');
    const btn = document.getElementById('vault-login-btn');
    const originalBtnHTML = btn.innerHTML;
    
    btn.disabled = true;
    btn.innerHTML = '<i class="fas fa-spinner fa-spin"></i> Authenticating...';
    
    try {
        const res = await fetch('/api/vault/login', {
            method: 'POST',
            body: formData
        });
        
        // --- SMART HTML/JSON DETECTION ---
        const contentType = res.headers.get("content-type");
        if (!contentType || !contentType.includes("application/json")) {
            // The server sent back HTML instead of JSON! Grab the text to see what broke.
            const errText = await res.text();
            console.error("Server returned non-JSON:", errText);
            throw new Error(`Server returned an HTML error page (Check backend console). HTTP Status: ${res.status}`);
        }

        const data = await res.json();
        
        if (res.ok && data.success) {
            resultDiv.style.cssText = 'background-color: rgba(16, 185, 129, 0.2); color: #10b981; border: 1px solid #10b981; display: block; margin-top: 10px; padding: 8px;';
            resultDiv.innerHTML = `✅ ${data.message}`;
            
            const navIndicator = document.getElementById('vault-status-indicator');
            if (navIndicator) {
                navIndicator.innerHTML = '<i class="fas fa-lock w3-text-green"></i> Vault Active';
            }

            setTimeout(() => {
                document.getElementById('vault-login-modal').style.display = 'none';
                btn.disabled = false;
                btn.innerHTML = originalBtnHTML;
            }, 1000);
            
        } else {
            throw new Error(data.error || 'Authentication failed');
        }
    } catch (err) {
        resultDiv.style.cssText = 'background-color: rgba(239, 68, 68, 0.2); color: #ef4444; border: 1px solid #ef4444; display: block; margin-top: 10px; padding: 8px;';
        resultDiv.innerHTML = `❌ ${err.message}`;
        btn.disabled = false;
        btn.innerHTML = originalBtnHTML;
    }
};

window.submitVaultLogout = async function() {
    try {
        await fetch('/api/vault/logout', { method: 'POST' });
        const navIndicator = document.getElementById('vault-status-indicator');
        if (navIndicator) {
            navIndicator.innerHTML = '<i class="fas fa-unlock w3-text-red"></i> Vault Logged Out';
        }
        alert("Logged out of Vault successfully.");
    } catch (err) {
        console.error("Logout failed:", err);
    }
};
