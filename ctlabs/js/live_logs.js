/*
 -----------------------------------------------------------------------------
 File        : ctlabs/public/js/live_log.js
 License     : MIT License
 -----------------------------------------------------------------------------
*/

document.addEventListener('DOMContentLoaded', () => {
  const container = document.getElementById('log-data-container');
  if (!container) return;

  const logFile = container.dataset.logFile;
  const labName = container.dataset.labName;
  const action  = container.dataset.action;
  const logContent = document.getElementById('log-content');
  const scrollStatus = document.getElementById('scroll-status');

  if (!logFile || !logContent) return;

  // === Save log context to localStorage ===
  localStorage.setItem('ctlabs_last_log', JSON.stringify({
    file:      logFile,
    lab:       labName,
    action:    action,
    timestamp: Date.now()
  }));

  // === Auto-scroll with pause/resume ===
  let isAutoScroll = true;

  logContent.addEventListener('scroll', () => {
    const atBottom = logContent.scrollHeight - logContent.scrollTop <= logContent.clientHeight + 5;
    isAutoScroll = atBottom;
    if (scrollStatus) {
      scrollStatus.textContent = isAutoScroll ? '' : '⏸ Paused (scroll to bottom to resume)';
    }
  });

  function fetchLog() {
    if (!isAutoScroll) return;
    fetch(`/logs/content?file=${encodeURIComponent(logFile)}`)
      .then(response => response.text())
      .then(html => {
        logContent.innerHTML = html;
        if (isAutoScroll) {
          logContent.scrollTop = logContent.scrollHeight;
        }
      })
      .catch(err => console.error("Log fetch failed:", err));
  }

  fetchLog();
  const logInterval = setInterval(fetchLog, 500);
  window.addEventListener('beforeunload', () => clearInterval(logInterval));
});
