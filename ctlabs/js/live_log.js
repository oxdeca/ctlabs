/*
 -----------------------------------------------------------------------------
 File        : ctlabs/public/js/live_log.js
 License     : MIT License
 -----------------------------------------------------------------------------
*/

document.addEventListener('DOMContentLoaded', () => {
  const container = document.getElementById('log-data-container');
  if (!container) return;

  const logId = container.dataset.logId;
  const labName = container.dataset.labName;
  const action  = container.dataset.action;
  const logContent = document.getElementById('log-content');
  const scrollStatus = document.getElementById('scroll-status');

  // 1. PREVENT SILENT FAILURES
  if (!logId || logId.trim() === '') {
      if (logContent) logContent.innerHTML = "<span style='color: #ef4444;'>❌ Error: No log ID provided by backend.</span>";
      return;
  }
  if (!logContent) return;

  // === Save log context to localStorage ===
  localStorage.setItem('ctlabs_last_log', JSON.stringify({
    id:        logId,
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
  let currentOffset = 0;

  function fetchLog() {
    // If paused OR already fetching, wait 1 second and check again
    if (!isAutoScroll || isFetching) {
        setTimeout(fetchLog, 1000);
        return;
    }

    isFetching = true;

    // Cache-busting timestamp + explicit no-store + offset + json format
    const fetchUrl = `/logs/content?id=${encodeURIComponent(logId)}&offset=${currentOffset}&format=json&t=${Date.now()}`;

    fetch(fetchUrl, { cache: 'no-store' })
      .then(async response => {
        if (!response.ok) {
            const errText = await response.text();
            throw new Error(`HTTP ${response.status}: ${errText}`);
        }
        return response.json();
      })
      .then(data => {
        const { content, offset, truncated } = data;
        
        // Update the current offset for the next request
        currentOffset = offset;

        // Only update the DOM if the server actually sent data
        if (content && content.trim() !== '') {
            if (logContent.innerHTML.includes('Waiting for log output...')) {
                logContent.innerHTML = '';
            }
            
            // Show truncation warning if this is the initial load and it was limited
            if (truncated && !logContent.querySelector('.truncation-warning')) {
              const warning = document.createElement('div');
              warning.className = 'truncation-warning';
              warning.style.cssText = 'color: #fbbf24; padding-bottom: 10px; border-bottom: 1px dashed #334155; margin-bottom: 10px; font-style: italic; font-size: 0.9em;';
              warning.innerHTML = `<i class='fas fa-exclamation-triangle'></i> Large log file detected. Only showing the last 256KB. <a href="/logs/download?id=${encodeURIComponent(logId)}" style="color: #38bdf8; text-decoration: underline;">Download full log</a> for complete history.`;
              logContent.appendChild(warning);
            }

            logContent.insertAdjacentHTML('beforeend', content);
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
        logContent.insertAdjacentHTML('beforeend', `\n<span style='color: #ef4444;'>\n[Connection Error: ${err.message}]</span>`);
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