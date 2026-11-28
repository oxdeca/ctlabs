/*
 -----------------------------------------------------------------------------
 File        : ctlabs/public/js/vault.js
 License     : MIT License
 -----------------------------------------------------------------------------
*/

// --- UNIFIED AUTHENTICATION MODAL (VAULT + GCP OAUTH) ---
window.switchAuthTab = function(tab) {
    const isGcp = (tab === 'gcp');
    const vaultPane = document.getElementById('auth-pane-vault');
    const gcpPane   = document.getElementById('auth-pane-gcp');
    const vaultBtn  = document.getElementById('auth-tab-btn-vault');
    const gcpBtn    = document.getElementById('auth-tab-btn-gcp');

    if (vaultPane) vaultPane.style.display = isGcp ? 'none' : 'block';
    if (gcpPane)   gcpPane.style.display   = isGcp ? 'block' : 'none';
    if (vaultBtn) {
        vaultBtn.style.borderBottomColor = isGcp ? 'transparent' : '#10b981';
        vaultBtn.style.color = isGcp ? '#94a3b8' : '#f8fafc';
    }
    if (gcpBtn) {
        gcpBtn.style.borderBottomColor = isGcp ? '#38bdf8' : 'transparent';
        gcpBtn.style.color = isGcp ? '#f8fafc' : '#94a3b8';
    }
    if (isGcp) {
        window.refreshAuthGcpStatus();
    }
};

window.openAuthModal = async function(tab = 'vault') {
    document.getElementById('vault-login-modal').style.display = 'block';
    window.switchAuthTab(tab || 'vault');
    document.getElementById('vault-auth-state').style.display = 'none';
    document.getElementById('vault-login-state').style.display = 'none';

    try {
        const savedAddr = localStorage.getItem('ctlabs_vault_addr') || '';
        const res = await fetch(`/vault/info?addr=${encodeURIComponent(savedAddr)}&t=${Date.now()}`);
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

            // Append active GCP tokens if any exist, from either auth method!
            if (data.gcp && data.gcp.length > 0) {
                htmlContent += `
                    <h6 style="color: #fbd38d; border-bottom: 1px solid #334155; padding-bottom: 4px; margin-top: 15px; margin-bottom: 10px; text-align: left;">
                        <i class="fab fa-google"></i> Active GCP Tokens
                    </h6>
                `;

                data.gcp.forEach(g => {
                    const isWif = g.method === 'wif';
                    const title = isWif
                        ? `<i class="fas fa-key"></i> ${g.vault_role} <span style="color:#94a3b8; font-weight:normal;">(WIF)</span>`
                        : `${g.project} <span style="color:#94a3b8; font-weight:normal;">(${g.roleset})</span>`;

                    if (g.error) {
                        htmlContent += `
                            <div class="w3-panel w3-leftbar w3-border-red" style="background-color: rgba(239,68,68,0.1); padding: 8px; font-size: 0.85em; margin-bottom: 8px; text-align: left;">
                                <strong style="color: #ef4444;">${title}</strong><br>
                                <span style="color: #94a3b8;">Error: ${g.error}</span>
                            </div>
                        `;
                    } else {
                        const scopeBadges = (g.scope || '').split(/\s+/).filter(Boolean).map(s => {
                            const short = s.replace('https://www.googleapis.com/auth/', '');
                            return `<span class="w3-tag w3-tiny w3-round" title="${s}" style="background-color: #334155; color: #cbd5e1; margin: 2px 4px 0 0; display: inline-block; padding: 2px 6px;">${short}</span>`;
                        }).join('');
                        htmlContent += `
                            <div class="w3-panel w3-leftbar ${isWif ? 'w3-border-purple' : 'w3-border-orange'}" style="background-color: rgba(251,146,60,0.05); padding: 8px; font-size: 0.85em; margin-bottom: 8px; text-align: left;">
                                <strong style="color: #fbd38d;">${title}</strong><br>
                                <span style="color: #94a3b8;">Email:</span> <span style="color: #e2e8f0;">${g.email}</span><br>
                                <span style="color: #94a3b8;">Expires in:</span> <span style="color: #34d399;">⏱️ ${formatTTL(parseInt(g.expires_in))}</span>
                                ${scopeBadges ? `<br><span style="color: #94a3b8;">Scopes:</span><br>${scopeBadges}` : ''}
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
                navIndicator.innerHTML = '<i class="fas fa-lock w3-text-green"></i> Vault';
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

window.openVaultLoginModal = function(tab) {
    return window.openAuthModal(tab || 'vault');
};

window.renderAuthGcpStatus = function(st) {
    const badge      = document.getElementById('auth-gcp-status-badge');
    const signoutBtn = document.getElementById('auth-gcp-signout-btn');
    const navGcp     = document.getElementById('gcp-oauth-nav-indicator');

    const esc = (s) => String(s || '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');

    if (badge) {
        if (st && st.signed_in) {
            const who = st.email ? `Signed in as <strong style="color:#10b981;">${esc(st.email)}</strong>` : '<strong style="color:#10b981;">Signed in</strong>';
            badge.innerHTML = `<i class="fas fa-check-circle" style="color:#10b981;"></i> ${who}`;
        } else {
            badge.innerHTML = '<i class="fas fa-exclamation-circle" style="color:#f59e0b;"></i> <span style="color:#94a3b8;">Not signed in</span>';
        }
    }
    if (signoutBtn) signoutBtn.style.display = (st && st.signed_in) ? 'inline-block' : 'none';
    if (navGcp) {
        navGcp.innerHTML = (st && st.signed_in)
            ? '<i class="fab fa-google w3-text-green"></i> GCP'
            : '<i class="fab fa-google w3-text-gray"></i> GCP';
    }

    const cidEl = document.getElementById('auth-gcp-client-id');
    if (cidEl && !cidEl.value && st && st.client_id) cidEl.value = st.client_id;
    const projEl = document.getElementById('auth-gcp-project');
    if (projEl && !projEl.value && st && st.project) projEl.value = st.project;
    const ruriEl = document.getElementById('auth-gcp-redirect-uri');
    if (ruriEl && !ruriEl.value) {
        ruriEl.value = (st && st.redirect_uri) ? st.redirect_uri : 'http://localhost';
    }

    if (typeof window.renderGcpOauthStatus === 'function') {
        window.renderGcpOauthStatus(st);
    }
};

window.refreshAuthGcpStatus = async function() {
    try {
        const res = await fetch('/controller/gcp/oauth/status');
        if (!res.ok) return;
        const st = await res.json();
        window.renderAuthGcpStatus(st);
    } catch (e) {}
};

window.startAuthGcpLogin = async function() {
    const clientId     = (document.getElementById('auth-gcp-client-id')?.value || '').trim();
    const clientSecret = (document.getElementById('auth-gcp-client-secret')?.value || '').trim();
    const redirectUri  = (document.getElementById('auth-gcp-redirect-uri')?.value || '').trim() || 'http://localhost';
    const project      = (document.getElementById('auth-gcp-project')?.value || '').trim();
    const resDiv       = document.getElementById('auth-gcp-result');
    if (!clientId) { alert('Please enter your Google OAuth 2.0 Client ID first.'); return; }

    try {
        const body = new URLSearchParams({ client_id: clientId, client_secret: clientSecret, redirect_uri: redirectUri, project });
        const res = await fetch('/controller/gcp/oauth/start', { method: 'POST', body });
        const data = await res.json();
        if (!res.ok || !data.success) throw new Error(data.error || 'Failed to start OAuth flow');
        if (resDiv) resDiv.style.display = 'none';
        window.open(data.auth_url, 'ctlabs_gcp_oauth', 'width=560,height=680');
    } catch (err) {
        if (resDiv) {
            resDiv.style.cssText = 'background-color: rgba(239, 68, 68, 0.2); color: #ef4444; border: 1px solid #ef4444; display: block; margin-top: 10px; padding: 8px;';
            resDiv.innerHTML = '❌ ' + err.message;
        } else {
            alert('Google OAuth Error: ' + err.message);
        }
    }
};

window.completeAuthGcpManual = async function() {
    const codeOrUrl = (document.getElementById('auth-gcp-manual-code')?.value || '').trim();
    const resDiv    = document.getElementById('auth-gcp-result');
    if (!codeOrUrl) { alert('Paste the callback URL or authorization code first.'); return; }

    try {
        const body = new URLSearchParams({ code_or_url: codeOrUrl });
        const res = await fetch('/controller/gcp/oauth/exchange', { method: 'POST', body });
        const data = await res.json();
        if (!res.ok || !data.success) throw new Error(data.error || 'OAuth exchange failed');
        document.getElementById('auth-gcp-manual-code').value = '';
        window.renderAuthGcpStatus(data.status);
        if (resDiv) {
            resDiv.style.cssText = 'background-color: rgba(16, 185, 129, 0.2); color: #10b981; border: 1px solid #10b981; display: block; margin-top: 10px; padding: 8px;';
            resDiv.innerHTML = '✅ Google OAuth sign-in complete.';
        }
    } catch (err) {
        if (resDiv) {
            resDiv.style.cssText = 'background-color: rgba(239, 68, 68, 0.2); color: #ef4444; border: 1px solid #ef4444; display: block; margin-top: 10px; padding: 8px;';
            resDiv.innerHTML = '❌ ' + err.message;
        } else {
            alert('Google OAuth Error: ' + err.message);
        }
    }
};

window.logoutAuthGcp = async function() {
    try {
        const res = await fetch('/controller/gcp/oauth/logout', { method: 'POST' });
        const data = await res.json();
        if (res.ok && data.success) window.renderAuthGcpStatus(data.status);
    } catch (err) {
        alert('Error: ' + err.message);
    }
};

window.addEventListener('message', (e) => {
    if (e.data && e.data.type === 'ctlabs_gcp_oauth_done' && e.data.status) {
        window.renderAuthGcpStatus(e.data.status);
    }
});
