/*
 -----------------------------------------------------------------------------
 File        : ctlabs/public/js/ctlabs-maps.js
 Description : topology view
 License     : MIT License
 -----------------------------------------------------------------------------
*/

// --- GLOBAL MAP STATE ---
window.panZoomData = null;
window.panZoomMgmt = null;

// --- TOOLTIP & CONTEXT MENU ENGINE ---
function attachCustomTooltips(svgObject) {
  const svgDoc = svgObject.contentDocument;
  if (!svgDoc) return;

  // 1. Ensure Tooltip Div Exists & Force Critical Floating Styles
  let tooltip = document.getElementById('custom-html-tooltip') || (function() {
    let t = document.createElement('div'); 
    t.id = 'custom-html-tooltip';
    
    // BULLETPROOFING: Force these styles inline just in case the CSS file 404s!
    t.style.position = 'fixed';
    t.style.zIndex = '10000';
    t.style.pointerEvents = 'none';
    t.style.display = 'none';
    
    // Add some fallback styling in case CSS completely fails
    t.style.background = 'rgba(15, 23, 42, 0.95)';
    t.style.color = '#f8fafc';
    t.style.border = '1px solid #38bdf8';
    t.style.borderRadius = '8px';
    t.style.padding = '12px';
    
    document.body.appendChild(t); 
    return t;
  })();

  // 2. Ensure Context Menu Div Exists & Force Critical Floating Styles
  let contextMenu = document.getElementById('custom-context-menu') || (function() {
    let c = document.createElement('div'); 
    c.id = 'custom-context-menu';
    
    c.style.position = 'fixed';
    c.style.zIndex = '10002';
    c.style.display = 'none';
    c.style.background = '#0f172a';
    c.style.border = '1px solid #334155';
    c.style.color = '#cbd5e1';
    
    document.body.appendChild(c);
    document.addEventListener('click', () => { c.style.display = 'none'; });
    return c;
  })();
  
  svgDoc.addEventListener('click', () => { contextMenu.style.display = 'none'; });

  // 3. Convert Native Graphviz <title> tags to Custom Data Attributes
  const allTitles = svgDoc.querySelectorAll('title');
  allTitles.forEach(t => {
    const text = t.textContent.trim();
    const parent = t.parentElement;
    if (parent.classList.contains('node')) {
      let actualName = text.split('\n')[0].trim();
      parent.setAttribute('data-node-name', actualName);
    }
    if (text && text.includes('[')) {
      parent.setAttribute('data-custom-tooltip', text);
    }
    t.remove();
  });

  // 4. Scrub any lingering title attributes from links/groups
  const allLinks = svgDoc.querySelectorAll('a, g.node');
  allLinks.forEach(el => {
    ['title', 'xlink:title'].forEach(attr => {
      if (el.hasAttribute(attr)) {
        const text = el.getAttribute(attr).trim();
        if (text && text.includes('[')) {
          el.setAttribute('data-custom-tooltip', text);
        }
        el.removeAttribute(attr);
      }
    });
  });

  // 5. Attach Hover and Right-Click Events
  const interactiveElements = svgDoc.querySelectorAll('[data-custom-tooltip]');
  interactiveElements.forEach(el => {
    const rawText = el.getAttribute('data-custom-tooltip');
    
    const customLinks = [];
    const linkRegex = /\[LINK:(.+?)\|(.+?)\]/g;
    let match;
    while ((match = linkRegex.exec(rawText)) !== null) {
      customLinks.push({ title: match[1], url: match[2] });
    }

    const termRegex = /\[TERM:(.+?)\]/g;
    let termMatch = termRegex.exec(rawText);
    let termLink = termMatch ? termMatch[1] : null;

    let cleanText = rawText.replace(/\[LINK:.+?\|.+?\](&#10;)?/g, '').trim();
    cleanText = cleanText.replace(/\[TERM:.+?\](&#10;)?/g, '').trim();
    const formattedText = cleanText.replace(/&#10;/g, '<br>').replace(/\\n/g, '<br>').replace(/\n/g, '<br>');

    el.style.cursor = 'pointer';

    // --- SMART TOOLTIP POSITIONING ---
    const updateTooltipPosition = (e) => {
      const rect = svgObject.getBoundingClientRect();
      const offset = 15; // Distance from cursor
      
      // Calculate base cursor position relative to the screen
      const cursorX = e.clientX + rect.left;
      const cursorY = e.clientY + rect.top;
      
      // Get the actual dimensions of the tooltip box
      const tWidth = tooltip.offsetWidth;
      const tHeight = tooltip.offsetHeight;
      
      // Default to bottom-right of the cursor
      let posX = cursorX + offset;
      let posY = cursorY + offset;
      
      // COLLISION DETECTION: Right Edge
      if (posX + tWidth > window.innerWidth) {
          posX = cursorX - tWidth - offset; // Flip to the left side
      }
      
      // COLLISION DETECTION: Bottom Edge
      if (posY + tHeight > window.innerHeight) {
          posY = cursorY - tHeight - offset; // Flip to the top side
      }
      
      // Safety clamp so it never goes off the left/top edges either
      posX = Math.max(10, posX);
      posY = Math.max(10, posY);
      
      tooltip.style.left = posX + 'px';
      tooltip.style.top = posY + 'px';
    };

    el.addEventListener('mouseover', (e) => {
      tooltip.innerHTML = formattedText;
      tooltip.style.display = 'block'; // Must display first to calculate width!
      updateTooltipPosition(e);
    });

    el.addEventListener('mousemove', (e) => {
      updateTooltipPosition(e);
    });

/*
    el.addEventListener('mouseover', (e) => {
      tooltip.innerHTML = formattedText;
      tooltip.style.display = 'block';
      const rect = svgObject.getBoundingClientRect();
      tooltip.style.left = (e.clientX + rect.left + 15) + 'px';
      tooltip.style.top = (e.clientY + rect.top + 15) + 'px';
    });

    el.addEventListener('mousemove', (e) => {
      const rect = svgObject.getBoundingClientRect();
      tooltip.style.left = (e.clientX + rect.left + 15) + 'px';
      tooltip.style.top = (e.clientY + rect.top + 15) + 'px';
    });
*/

    el.addEventListener('mouseout', () => {
      tooltip.style.display = 'none';
    });

    el.addEventListener('contextmenu', (e) => {
      e.preventDefault();
      tooltip.style.display = 'none';
      let menuHtml = '';

      const nodeName = cleanText.split('\n')[0].split(/\s+/)[0].trim().toLowerCase();
      const isNode = el.classList.contains('node') || (el.closest && el.closest('.node'));

      if (nodeName && isNode) {
        menuHtml += `<div class="context-menu-item" style="padding:10px; cursor:pointer;" onclick="window.open('/flashcards?node=${encodeURIComponent(nodeName)}', '_blank')"><i class="fas fa-layer-group w3-text-purple"></i> Walkthrough / Flashcards</div>`;
        
        // --- BULLETPROOF POPUP CENTERING ---
        const w = 900;
        const h = 600;
        
        const topWin = window.top || window;
        
        // Get the browser's current screen position
        const dualScreenLeft = topWin.screenLeft !== undefined ? topWin.screenLeft : topWin.screenX;
        const dualScreenTop = topWin.screenTop !== undefined ? topWin.screenTop : topWin.screenY;
        
        // Use inner dimensions which are immune to Linux fractional-scaling window border bugs
        const winWidth = topWin.innerWidth || document.documentElement.clientWidth || screen.width;
        const winHeight = topWin.innerHeight || document.documentElement.clientHeight || screen.height;
        
        // Calculate center. (Removed the Math.max clamp so left/top monitors work natively!)
        const left = Math.round((winWidth / 2) - (w / 2) + dualScreenLeft);
        const top = Math.round((winHeight / 2) - (h / 2) + dualScreenTop);
        // -----------------------------------

        menuHtml += `<div class="context-menu-item" style="padding:10px; cursor:pointer;" onclick="window.open('/terminal/${encodeURIComponent(nodeName)}', 'term_${encodeURIComponent(nodeName)}', 'width=${w},height=${h},top=${top},left=${left},resizable=yes,scrollbars=yes,toolbar=no,location=no')"><i class="fas fa-terminal w3-text-green"></i> Open Web Terminal</div>`;
      }

      customLinks.forEach(link => {
        menuHtml += `<div class="context-menu-item" style="padding:10px; cursor:pointer;" onclick="window.open('${link.url}', '_blank')"><i class="fas fa-external-link-alt"></i> ${link.title}</div>`;
      });

      let linkElement = el.tagName.toLowerCase() === 'a' ? el : el.querySelector('a');
      let href = linkElement ? (linkElement.getAttribute('href') || linkElement.getAttribute('xlink:href')) : null;
      if (href && href !== "" && !customLinks.some(l => l.url === href)) {
        menuHtml += `<div class="context-menu-item" style="padding:10px; cursor:pointer;" onclick="window.open('${href}', '_blank')"><i class="fas fa-external-link-alt"></i> Open Web Interface</div>`;
      }

      const safeText = cleanText.replace(/'/g, "\\'").replace(/"/g, "&quot;").replace(/\n/g, "\\n").replace(/&#10;/g, "\\n");
      menuHtml += `<div class="context-menu-item" style="padding:10px; cursor:pointer;" onclick="navigator.clipboard.writeText('${safeText.replace(/<br>/g, '\\n')}'); alert('Node details copied to clipboard!');"><i class="fas fa-copy"></i> Copy Node Info</div>`;

      if (termLink) {
        menuHtml += `<div class="context-menu-item" style="padding:10px; cursor:pointer;" onclick="window.open('${termLink}', '_self')"><i class="fas fa-network-wired"></i> Connect via Local SSH Client</div>`;
      }

      contextMenu.innerHTML = menuHtml;
      
      // 1. Show the menu FIRST so the browser can calculate its physical dimensions
      contextMenu.style.display = 'block'; 

      const rect = svgObject.getBoundingClientRect();
      let cursorX = e.clientX + rect.left;
      let cursorY = e.clientY + rect.top;

      const menuWidth = contextMenu.offsetWidth;
      const menuHeight = contextMenu.offsetHeight;

      // 2. COLLISION DETECTION: Right Edge
      if (cursorX + menuWidth > window.innerWidth) {
          cursorX = cursorX - menuWidth; // Flip to the left of the cursor
      }

      // 3. COLLISION DETECTION: Bottom Edge
      if (cursorY + menuHeight > window.innerHeight) {
          cursorY = cursorY - menuHeight; // Flip above the cursor
      }

      // 4. Safety clamp so it never goes off the top or left edges
      cursorX = Math.max(10, cursorX);
      cursorY = Math.max(10, cursorY);

      contextMenu.style.left = cursorX + 'px';
      contextMenu.style.top = cursorY + 'px';
    });
  });

/*
      contextMenu.innerHTML = menuHtml;
      const rect = svgObject.getBoundingClientRect();
      contextMenu.style.left = (e.clientX + rect.left) + 'px';
      contextMenu.style.top = (e.clientY + rect.top) + 'px';
      contextMenu.style.display = 'block';
    });
  });
*/

  let customStyle = svgDoc.getElementById('custom-dark-controls');
  if (!customStyle) {
    customStyle = svgDoc.createElementNS("http://www.w3.org/2000/svg", "style");
    customStyle.id = 'custom-dark-controls';
    customStyle.textContent = `
      #svg-pan-zoom-controls rect { fill: #1e293b !important; fill-opacity: 0.95 !important; stroke: #334155; stroke-width: 1px; }
      #svg-pan-zoom-controls path { fill: #f8fafc !important; }
      #svg-pan-zoom-controls g:hover rect { fill: #334155 !important; cursor: pointer; }
      #svg-pan-zoom-controls g:hover path { fill: #38bdf8 !important; }
    `;
    svgDoc.documentElement.appendChild(customStyle);
  }
}

// --- LAZY LOAD ENGINE & SVG PATCHER ---
function initMap(objId, panZoomVarName) {
    const obj = document.getElementById(objId);
    
    if (!obj || !obj.contentDocument || !obj.contentDocument.querySelector('svg')) {
        return; // Will catch it later via load event
    }

    // 1. Strip Graphviz's hardcoded dimensions so it scales natively
    const svgElement = obj.contentDocument.querySelector('svg');
    if (svgElement) {
        svgElement.removeAttribute('width');
        svgElement.removeAttribute('height');
        svgElement.style.width = '100%';
        svgElement.style.height = '100%';
    }

    // 2. If it's already initialized, just recalculate
    if (window[panZoomVarName]) {
        window[panZoomVarName].resize();
        window[panZoomVarName].fit();
        window[panZoomVarName].center();
        return;
    }

    // 3. Initialize fresh
    window[panZoomVarName] = svgPanZoom(obj, { zoomEnabled: true, controlIconsEnabled: true, fit: true, center: true, minZoom: 0.1, maxZoom: 10 });
    attachCustomTooltips(obj);
}

// Ensure events map correctly on initial load
document.addEventListener('DOMContentLoaded', () => {
    const dataObj = document.getElementById('topo-obj');
    const mgmtObj = document.getElementById('mgmt-topo-obj');

    if (dataObj) {
        dataObj.addEventListener('load', () => {
            if (document.getElementById('DataNet').style.display !== 'none') initMap('topo-obj', 'panZoomData');
        });
    }
    
    if (mgmtObj) {
        mgmtObj.addEventListener('load', () => {
            if (document.getElementById('MgmtNet').style.display !== 'none') initMap('mgmt-topo-obj', 'panZoomMgmt');
        });
    }
});

// Handle Map Switching Safely
window.openMapTab = function(evt, tabName) {
    const tabs = document.getElementsByClassName("map-tab");
    for (let i = 0; i < tabs.length; i++) tabs[i].style.display = "none";

    const links = document.getElementsByClassName("tablink");
    for (let i = 0; i < links.length; i++) links[i].className = links[i].className.replace(" w3-blue", "");

    document.getElementById(tabName).style.display = "block";
    evt.currentTarget.className += " w3-blue";

    setTimeout(() => {
        if (tabName === 'DataNet') initMap('topo-obj', 'panZoomData');
        else if (tabName === 'MgmtNet') initMap('mgmt-topo-obj', 'panZoomMgmt');
    }, 50);
};

// --- GLOBAL RESIZE LISTENER ---
let resizeTimeout;
window.addEventListener('resize', function() {
    clearTimeout(resizeTimeout);
    resizeTimeout = setTimeout(function() {
        // Recalculate both maps if they exist!
        if (window.panZoomData) {
            window.panZoomData.resize();
            window.panZoomData.fit();
            window.panZoomData.center();
        }
        if (window.panZoomMgmt) {
            window.panZoomMgmt.resize();
            window.panZoomMgmt.fit();
            window.panZoomMgmt.center();
        }
    }, 150); // 150ms debounce
});
