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
})(window);
