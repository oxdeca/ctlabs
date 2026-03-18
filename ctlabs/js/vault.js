/*
 -----------------------------------------------------------------------------
 File        : ctlabs/public/js/vault.js
 License     : MIT License
 -----------------------------------------------------------------------------
*/

// --- VAULT AUTHENTICATION LOGIC ---
window.openVaultLoginModal = async function() {
    document.getElementById('vault-login-modal').style.display = 'block';
    document.getElementById('vault-auth-state').style.display = 'none';
    document.getElementById('vault-login-state').style.display = 'none';

    try {
        const savedAddr = localStorage.getItem('ctlabs_vault_addr') || '';
        const res = await fetch(`/vault/info?addr=${encodeURIComponent(savedAddr)}`);
        const data = await res.json();

        if (res.ok && data.success && data.info) {
            // YOU ARE LOGGED IN
            document.getElementById('vault-auth-state').style.display = 'block';
            
            const displayName = data.info.display_name || 'N/A';
            const policies = (data.info.policies || []).join(', ');
            const entity = data.info.entity_id || 'N/A';
            
            // Vault returns `creation_ttl` (Max) and `ttl` (Remaining Time)
            const maxTtl = data.info.creation_ttl || 0;
            const remainingTtl = data.info.ttl || 0;
            
            // Helper function to format seconds into 0h 0m 0s
            const formatTTL = (seconds) => {
                if (!seconds || isNaN(seconds)) return "0s";
                const h = Math.floor(seconds / 3600);
                const m = Math.floor((seconds % 3600) / 60);
                const s = seconds % 60;
                if (h > 0) return `${h}h ${m}m ${s}s`;
                if (m > 0) return `${m}m ${s}s`;
                return `${s}s`;
            };
            
            let htmlContent = `
                <h6 style="color: #38bdf8; border-bottom: 1px solid #334155; padding-bottom: 4px; margin-top: 0; margin-bottom: 10px; text-align: left;">
                    <i class="fas fa-key"></i> Vault Identity
                </h6>
                <table class="w3-table w3-small" style="color: #e2e8f0; margin-bottom: 15px;">
                    <tr><td style="color: #94a3b8; width: 110px; border-bottom: none; padding: 2px 0;">Display Name:</td><td style="border-bottom: none; padding: 2px 0;"><strong>${displayName}</strong></td></tr>
                    <tr><td style="color: #94a3b8; border-bottom: none; padding: 2px 0;">Entity ID:</td><td style="border-bottom: none; padding: 2px 0; font-family: monospace;">${entity}</td></tr>
                    <tr><td style="color: #94a3b8; border-bottom: none; padding: 2px 0;">Policies:</td><td style="border-bottom: none; padding: 2px 0; color: #a78bfa;">${policies}</td></tr>
                    <tr><td style="color: #94a3b8; border-bottom: none; padding: 2px 0;">Max TTL:</td><td style="border-bottom: none; padding: 2px 0;">${maxTtl}s</td></tr>
                    <tr><td style="color: #94a3b8; border-bottom: none; padding: 2px 0;">Time Remaining:</td><td style="border-bottom: none; padding: 2px 0; color: #34d399;">⏱️ ${formatTTL(remainingTtl)}</td></tr>
                </table>
            `;

            // Append GCP Leases if any exist!
            if (data.gcp && data.gcp.length > 0) {
                htmlContent += `
                    <h6 style="color: #fbd38d; border-bottom: 1px solid #334155; padding-bottom: 4px; margin-top: 15px; margin-bottom: 10px; text-align: left;">
                        <i class="fab fa-google"></i> Active GCP Leases
                    </h6>
                `;
                
                data.gcp.forEach(g => {
                    if (g.error) {
                        htmlContent += `
                            <div class="w3-panel w3-leftbar w3-border-red" style="background-color: rgba(239,68,68,0.1); padding: 8px; font-size: 0.85em; margin-bottom: 8px; text-align: left;">
                                <strong style="color: #ef4444;">${g.project} (${g.roleset})</strong><br>
                                <span style="color: #94a3b8;">Error: ${g.error}</span>
                            </div>
                        `;
                    } else {
                        htmlContent += `
                            <div class="w3-panel w3-leftbar w3-border-orange" style="background-color: rgba(251,146,60,0.05); padding: 8px; font-size: 0.85em; margin-bottom: 8px; text-align: left;">
                                <strong style="color: #fbd38d;">${g.project} <span style="color:#94a3b8; font-weight:normal;">(${g.roleset})</span></strong><br>
                                <span style="color: #94a3b8;">Email:</span> <span style="color: #e2e8f0;">${g.email}</span><br>
                                <span style="color: #94a3b8;">Expires in:</span> <span style="color: #34d399;">⏱️ ${formatTTL(parseInt(g.expires_in))}</span>
                            </div>
                        `;
                    }
                });
            }

            document.getElementById('vault-session-info').innerHTML = htmlContent;

        } else {
            console.error("Vault lookup failed because:", data.error || "Unknown reason");
            throw new Error("Not logged in"); 
        }
    } catch(e) {
        // FALLBACK TO LOGIN FORM
        document.getElementById('vault-login-state').style.display = 'block';
        
        const form = document.getElementById('vault-login-form');
        if (form) form.reset();

        const savedAddr = localStorage.getItem('ctlabs_vault_addr');
        if (savedAddr) {
            const addrInput = document.getElementById('vault-addr');
            if (addrInput) addrInput.value = savedAddr;
        }
        
        const resultDiv = document.getElementById('vault-login-result');
        if (resultDiv) {
            resultDiv.style.display = 'none';
            resultDiv.innerHTML = '';
        }
    }
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

// Properly calls the backend to destroy the session before reloading
window.submitVaultLogout = async function() {
    try {
        await fetch('/vault/logout', { method: 'POST' });
    } catch (e) {
        console.error("Failed to call logout endpoint", e);
    }
    
    document.getElementById('vault-login-modal').style.display = 'none';
    location.reload(); 
};
