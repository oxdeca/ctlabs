/*
 -----------------------------------------------------------------------------
 File        : ctlabs/public/js/terminal.js
 Description : Unified Terminal Session Management
 License     : MIT License
 -----------------------------------------------------------------------------
*/

(function(window) {
  if (window.terminalManagerInitialized) return;
  window.terminalManagerInitialized = true;

  window.openTerminal = function(nodeName) {
      const w=900, h=600, t=(window.top.outerHeight/2)+window.top.screenY-(h/2), l=(window.top.outerWidth/2)+window.top.screenX-(w/2);
      const winName = `term_${nodeName.replace(/[^a-zA-Z0-9]/g, '_')}_${Date.now()}`;
      window.open(`/terminal/${encodeURIComponent(nodeName)}`, winName, `width=${w},height=${h},top=${t},left=${l},resizable=yes,scrollbars=yes,toolbar=no,location=no`);
  };

  window.manageTerminal = async function(nodeName) {
      try {
          const res = await fetch(`/terminal/${encodeURIComponent(nodeName)}/sessions?_=${Date.now()}`);
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
  window.currentTermNode = null;

  window.showTerminalManager = function(nodeName, count) {
      window.currentTermNode = nodeName;
      document.getElementById('term-mgr-title').innerHTML = `<i class="fas fa-terminal"></i> Terminal: <span style="color: #f8fafc;">${nodeName}</span>`;
      
      const msg = document.getElementById('term-mgr-msg');
      const openBtn = document.getElementById('btn-open-new');
      const terminateBtn = document.getElementById('btn-terminate-oldest');
      
      if (count >= 3) {
          msg.innerHTML = `This node has reached the maximum of <strong style="color: #ef4444;">3</strong> active terminal sessions. You must terminate an existing session to open a new one.`;
          openBtn.style.display = 'none';
          terminateBtn.innerHTML = `<i class="fas fa-recycle"></i> Terminate Oldest & Open New`;
      } else {
          msg.innerHTML = `There are already <strong>${count}</strong> active terminal sessions for this node. What would you like to do?`;
          openBtn.style.display = 'block';
          terminateBtn.innerHTML = `<i class="fas fa-trash-alt"></i> Terminate Oldest & Open New`;
      }
      
      document.getElementById('terminal-manager-modal').style.display = 'block';
  };

  window.confirmTerminalAction = async function(action) {
      const nodeName = window.currentTermNode;
      if (!nodeName) return;

      const terminateBtn = document.getElementById('btn-terminate-oldest');
      const openBtn = document.getElementById('btn-open-new');
      const originalTerminateHtml = terminateBtn.innerHTML;
      const originalOpenHtml = openBtn.innerHTML;

      if (action === 'terminate') {
          terminateBtn.disabled = true;
          terminateBtn.innerHTML = '<i class="fas fa-spinner fa-spin"></i> Terminating...';
          try {
              const res = await fetch(`/terminal/${encodeURIComponent(nodeName)}/terminate_oldest`, { method: 'POST' });
              if (!res.ok) throw new Error("Failed to terminate session");
          } catch (e) {
              alert("Error terminating session: " + e.message);
              terminateBtn.disabled = false;
              terminateBtn.innerHTML = originalTerminateHtml;
              return;
          }
      }
      
      window.openTerminal(nodeName);
      document.getElementById('terminal-manager-modal').style.display = 'none';
      
      setTimeout(() => {
          terminateBtn.disabled = false;
          terminateBtn.innerHTML = originalTerminateHtml;
          openBtn.disabled = false;
          openBtn.innerHTML = originalOpenHtml;
      }, 500);
  };
})(window);
