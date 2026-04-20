/*
 -----------------------------------------------------------------------------
 File        : ctlabs/public/js/logs_home.js
 License     : MIT License
 -----------------------------------------------------------------------------
*/

document.addEventListener('DOMContentLoaded', () => {
  const lastLogString = localStorage.getItem('ctlabs_last_log');
  const statusEl = document.getElementById('status');

  if (lastLogString) {
    try {
      // Parse the string into an object FIRST
      const logData = JSON.parse(lastLogString);
      const { id, lab, action, timestamp } = logData;

      // Now we can safely check the timestamp (Expire after 1 hour / 3600000ms)
      if (Date.now() - timestamp > 3600000) {
        localStorage.removeItem('ctlabs_last_log');
        statusEl.textContent = "No recent active log session.";
        return;
      }

      const url = `/logs?id=${encodeURIComponent(id)}&lab=${encodeURIComponent(lab)}&action=${encodeURIComponent(action)}`;
      
      // Auto-redirect after a brief delay (for UX feedback)
      statusEl.innerHTML = `
        <strong>Resuming active log...</strong><br>
        Lab: <code>${lab}</code> (${action === 'up' ? 'Starting' : 'Stopping'})
      `;
      
      setTimeout(() => {
        window.location.href = url;
      }, 800); // 0.8 second delay so user sees message

    } catch (e) {
      console.warn('Failed to resume log:', e);
      localStorage.removeItem('ctlabs_last_log');
      statusEl.textContent = "No valid log session found.";
    }
  } else {
    statusEl.textContent = "No active log session.";
  }
});
