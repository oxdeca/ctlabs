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

  // 1. PREVENT SILENT FAILURES
  if (!logFile || logFile.trim() === '') {
      if (logContent) logContent.innerHTML = "<span style='color: #ef4444;'>❌ Error: No log file path provided by backend. Check your Sinatra variables!</span>";
      return;
  }
  if (!logContent) return;

  // === Save log context to localStorage ===
  localStorage.setItem('ctlabs_last_log', JSON.stringify({
    file:      logFile,
    lab:       labName,
    action:    action,
    timestamp: Date.now()
  }));

  // === Auto-scroll with pause/resume ===
  let isAutoScroll = true;
  let isFetching = false;

  logContent.addEventListener('scroll', () => {
    // Increased the padding tolerance slightly to prevent false-pauses on different browsers
    const atBottom = logContent.scrollHeight - logContent.scrollTop <= logContent.clientHeight + 15;
    isAutoScroll = atBottom;
    if (scrollStatus) {
      scrollStatus.textContent = isAutoScroll ? '' : '⏸ Paused (scroll to bottom to resume)';
    }
  });

  // === Bulletproof Fetch Engine ===
  function fetchLog() {
    // If paused OR already fetching, wait 1 second and check again
    if (!isAutoScroll || isFetching) {
        setTimeout(fetchLog, 1000);
        return;
    }

    isFetching = true;

    // Cache-busting timestamp + explicit no-store
    const fetchUrl = `/logs/content?file=${encodeURIComponent(logFile)}&t=${Date.now()}`;

    fetch(fetchUrl, { cache: 'no-store' })
      .then(async response => {
        if (!response.ok) {
            const errText = await response.text();
            throw new Error(`HTTP ${response.status}: ${errText}`);
        }
        return response.text();
      })
      .then(html => {
        // Only update the DOM if the server actually sent data
        if (html.trim() !== '') {
            logContent.innerHTML = html;
        } else if (logContent.innerHTML === '') {
            logContent.innerHTML = "<i style='color: #64748b;'>Waiting for log output...</i>";
        }
        
        if (isAutoScroll) {
          logContent.scrollTop = logContent.scrollHeight;
        }
      })
      .catch(err => {
        console.error("Log fetch failed:", err);
        // Print the error directly to the user's screen instead of failing silently!
        logContent.innerHTML += `\n<span style='color: #ef4444;'>\n[Connection Error: ${err.message}]</span>`;
      })
      .finally(() => {
        isFetching = false;
        // RECURSIVE TIMEOUT: Only schedule the next fetch AFTER this one finishes!
        setTimeout(fetchLog, 1000);
      });
  }

  // Kick off the loop
  fetchLog();
});
