/**
 * -----------------------------------------------------------------------------
 * File        : ctlabs/js/screenshot_editor.js
 * Description : Screenshot Annotation Editor & Image Context Menu for ctlabs
 * License     : MIT License
 * -----------------------------------------------------------------------------
 */

(function() {
  'use strict';

  // --- Toast Notification Helper ---
  function ctlabsToast(message, icon = 'fas fa-check-circle', color = '#10b981') {
    const existing = document.querySelector('.ctlabs-toast');
    if (existing) existing.remove();

    const toast = document.createElement('div');
    toast.className = 'ctlabs-toast';
    toast.innerHTML = `<i class="${icon}" style="color: ${color}; font-size: 1.1em;"></i><span>${message}</span>`;
    document.body.appendChild(toast);
    setTimeout(() => {
      if (toast.parentNode) toast.remove();
    }, 3000);
  }

  // --- Helpers ---
  function getFilenameFromUrl(url) {
    if (!url) return 'image.png';
    try {
      const clean = url.split('?')[0].split('#')[0];
      return decodeURIComponent(clean.substring(clean.lastIndexOf('/') + 1)) || 'image.png';
    } catch (e) {
      return 'image.png';
    }
  }

  function getBaseFromImageUrl(url) {
    if (!url) return null;
    try {
      const clean = url.split('?')[0].split('#')[0];
      const filename = clean.substring(clean.lastIndexOf('/') + 1);
      const match = filename.match(/^([a-zA-Z0-9_\-]+)\.(?:svg|png)$/i);
      return match ? decodeURIComponent(match[1]) : null;
    } catch (err) {
      return null;
    }
  }

  function hexToRgba(hex, alpha = 1) {
    let c = hex.replace('#', '');
    if (c.length === 3) c = c.split('').map(x => x + x).join('');
    const num = parseInt(c, 16);
    const r = (num >> 16) & 255;
    const g = (num >> 8) & 255;
    const b = num & 255;
    return `rgba(${r}, ${g}, ${b}, ${alpha})`;
  }

  function copyTextToClipboard(text) {
    const ta = document.createElement('textarea');
    ta.value = text;
    ta.setAttribute('readonly', '');
    ta.style.position = 'fixed';
    ta.style.left = '0';
    ta.style.top = '0';
    ta.style.opacity = '0.01';
    document.body.appendChild(ta);
    ta.select();
    try { document.execCommand('copy'); } catch (e) {}
    document.body.removeChild(ta);
    if (navigator.clipboard && navigator.clipboard.writeText) {
      navigator.clipboard.writeText(text).catch(() => {});
    }
  }

  // =========================================================================
  // Part 1: Floating Image Right-Click Context Menu
  // =========================================================================
  const imageContextMenu = document.getElementById('image-context-menu');
  const imageContextFilename = document.getElementById('image-context-filename');
  const imageContextEditDiagram = document.getElementById('image-context-edit-diagram');
  const imageContextAnnotate = document.getElementById('image-context-annotate');
  const imageContextViewFull = document.getElementById('image-context-view-full');
  const imageContextCopyMarkdown = document.getElementById('image-context-copy-markdown');
  const imageContextCopyUrl = document.getElementById('image-context-copy-url');

  let activeContextTarget = null;

  function hideImageContextMenu() {
    if (imageContextMenu) imageContextMenu.style.display = 'none';
    activeContextTarget = null;
  }

  function openImageContextMenu(e, img) {
    if (!imageContextMenu || !img) return;
    activeContextTarget = img;

    const src = img.src || img.getAttribute('src') || '';
    const alt = img.alt || img.getAttribute('alt') || '';
    const title = img.title || img.getAttribute('title') || '';
    const filename = getFilenameFromUrl(src);
    const base = getBaseFromImageUrl(src);

    if (imageContextFilename) {
      imageContextFilename.textContent = filename;
      imageContextFilename.title = filename;
    }

    // Check if Graphviz diagram source exists for this image
    if (imageContextEditDiagram) {
      imageContextEditDiagram.style.display = 'none';
      if (base) {
        const wt = (window.CtlabsWalkthrough && window.CtlabsWalkthrough.getActiveWalkthrough()) || '';
        const cached = window.CtlabsWalkthrough && window.CtlabsWalkthrough.cachedDiagramBases;
        if (cached && cached.has(base)) {
          imageContextEditDiagram.style.display = 'flex';
        } else if (wt) {
          fetch(`/walkthroughs/${encodeURIComponent(wt)}/graphviz/sources/${encodeURIComponent(base)}`, {
            credentials: 'same-origin'
          })
          .then(res => res.json())
          .then(data => {
            if (data.ok && activeContextTarget === img && imageContextMenu.style.display !== 'none') {
              if (cached) cached.add(base);
              imageContextEditDiagram.style.display = 'flex';
            }
          })
          .catch(() => {});
        }
      }
    }

    // Position menu clamped to window boundaries
    imageContextMenu.style.display = 'block';
    const rect = imageContextMenu.getBoundingClientRect();
    let x = e.clientX;
    let y = e.clientY;
    if (x + rect.width > window.innerWidth - 8) x = Math.max(8, window.innerWidth - rect.width - 8);
    if (y + rect.height > window.innerHeight - 8) y = Math.max(8, window.innerHeight - rect.height - 8);
    imageContextMenu.style.left = x + 'px';
    imageContextMenu.style.top = y + 'px';
  }

  // Context menu actions
  if (imageContextEditDiagram) {
    imageContextEditDiagram.addEventListener('click', () => {
      const img = activeContextTarget;
      hideImageContextMenu();
      if (!img) return;
      const base = getBaseFromImageUrl(img.src);
      if (base && window.CtlabsWalkthrough && typeof window.CtlabsWalkthrough.openGraphvizModal === 'function') {
        window.CtlabsWalkthrough.openGraphvizModal(base);
      }
    });
  }

  if (imageContextAnnotate) {
    imageContextAnnotate.addEventListener('click', () => {
      const img = activeContextTarget;
      hideImageContextMenu();
      if (!img) return;
      openScreenshotEditor(img.src, {
        filename: getFilenameFromUrl(img.src),
        alt: img.alt || ''
      });
    });
  }

  if (imageContextViewFull) {
    imageContextViewFull.addEventListener('click', () => {
      const img = activeContextTarget;
      hideImageContextMenu();
      if (!img) return;
      if (window.CtlabsWalkthrough && typeof window.CtlabsWalkthrough.openImageModal === 'function') {
        window.CtlabsWalkthrough.openImageModal(img.src, img.alt, img.title);
      }
    });
  }

  if (imageContextCopyMarkdown) {
    imageContextCopyMarkdown.addEventListener('click', () => {
      const img = activeContextTarget;
      hideImageContextMenu();
      if (!img) return;
      const filename = getFilenameFromUrl(img.src);
      const alt = (img.alt || filename).replace(/[[\]]/g, '\\$&');
      const snippet = `![${alt}](/recordings/images/${filename})`;
      copyTextToClipboard(snippet);
      ctlabsToast(`Copied Markdown link: <code>${snippet}</code>`, 'fas fa-link', '#a855f7');
    });
  }

  if (imageContextCopyUrl) {
    imageContextCopyUrl.addEventListener('click', () => {
      const img = activeContextTarget;
      hideImageContextMenu();
      if (!img) return;
      copyTextToClipboard(img.src);
      ctlabsToast('Copied image URL to clipboard', 'fas fa-copy', '#cbd5e1');
    });
  }

  // Intercept right-clicks on images in preview pane, step notes, or lightbox
  document.addEventListener('contextmenu', (e) => {
    const img = e.target.closest('#md-preview-pane img, #demo-content img, .step-notes img, #image-modal-img');
    if (!img) {
      hideImageContextMenu();
      return;
    }
    // Only intercept content images with a valid src
    if (!img.src || img.src.startsWith('data:image/svg+xml')) return;

    e.preventDefault();
    e.stopPropagation();
    openImageContextMenu(e, img);
  });

  document.addEventListener('click', (e) => {
    if (imageContextMenu && !imageContextMenu.contains(e.target)) {
      hideImageContextMenu();
    }
  });

  window.addEventListener('blur', hideImageContextMenu);
  window.addEventListener('resize', () => {
    hideImageContextMenu();
    if (modal && modal.style.display === 'block') {
      fitToStage();
    }
  });


  // =========================================================================
  // Part 2: Screenshot Annotation Editor Modal & Canvas Engine
  // =========================================================================
  const modal = document.getElementById('screenshot-editor-modal');
  const closeX = document.getElementById('annotator-close-x');
  const filenameBadge = document.getElementById('annotator-filename-badge');
  const dimsBadge = document.getElementById('annotator-dims-badge');
  const stage = document.getElementById('annotator-stage');
  const viewport = document.getElementById('annotator-viewport');
  const baseCanvas = document.getElementById('annotator-base-canvas');
  const overlayCanvas = document.getElementById('annotator-overlay-canvas');
  const textWrapper = document.getElementById('annotator-text-wrapper');
  const textInput = document.getElementById('annotator-text-input');
  const cropBoxEl = document.getElementById('annotator-crop-box');
  const applyCropBtn = document.getElementById('annotator-apply-crop-btn');
  const undoBtn = document.getElementById('annotator-undo-btn');
  const redoBtn = document.getElementById('annotator-redo-btn');
  const rotateBtn = document.getElementById('annotator-rotate-btn');
  const deleteBtn = document.getElementById('annotator-delete-btn');
  const resetBtn = document.getElementById('annotator-reset-btn');
  const zoomInBtn = document.getElementById('annotator-zoom-in');
  const zoomOutBtn = document.getElementById('annotator-zoom-out');
  const zoomResetBtn = document.getElementById('annotator-zoom-reset');
  const zoomFitBtn = document.getElementById('annotator-zoom-fit');
  const saveBtn = document.getElementById('annotator-save-btn');
  const saveCopyBtn = document.getElementById('annotator-save-copy-btn');
  const downloadBtn = document.getElementById('annotator-download-btn');
  const statusEl = document.getElementById('annotator-status');

  const toolBtns = document.querySelectorAll('.annotator-tool-btn');
  const colorSwatches = document.querySelectorAll('.annotator-color-swatch');
  const strokeBtns = document.querySelectorAll('.annotator-stroke-btn');

  const fontSizeInput = document.getElementById('annotator-font-size-input');
  const fontDecBtn = document.getElementById('annotator-font-dec');
  const fontIncBtn = document.getElementById('annotator-font-inc');

  const badgeNumInput = document.getElementById('annotator-badge-num');
  const badgeDecBtn = document.getElementById('annotator-badge-dec');
  const badgeIncBtn = document.getElementById('annotator-badge-inc');
  const badgeResetBtn = document.getElementById('annotator-badge-reset');

  let baseCtx = null;
  let overlayCtx = null;

  // Offscreen canvas storing clean base image (without vector annotations)
  const cleanBaseCanvas = document.createElement('canvas');
  let cleanBaseCtx = null;

  // Editor State
  let currentOriginalSrc = '';
  let currentFilename = 'image.png';
  let originalImage = null;
  let imgWidth = 0;
  let imgHeight = 0;

  let activeTool = 'select'; // select, arrow, rect, ellipse, highlight, pixelate, text, badge, pen, crop
  let activeColor = '#ef4444';
  let activeStrokeWidth = 4;
  let activeFontSize = 13;
  let stepBadgeCounter = 1;

  // Object-based Vector Annotation Layer State
  let annotations = []; // Array of { id, type, ...props }
  let selectedId = null;
  let isDraggingAnnotation = false;
  let dragAnnStart = null;
  let isDraggingHandle = false;
  let activeHandle = null;
  let dragHandleStart = null;
  let baseVersion = 0;
  let editingTextAnnId = null;

  let undoStack = [];
  let redoStack = [];
  const MAX_UNDO = 30;

  // Drawing tracking
  let isDrawing = false;
  let dragStart = null;
  let penPoints = [];
  let cropSelection = null; // { x, y, w, h }

  // Zoom & Pan state
  let scale = 1.0;
  let panX = 0;
  let panY = 0;
  let isPanning = false;
  let panStart = null;
  let spacePressed = false;

  function initContexts() {
    if (baseCanvas) baseCtx = baseCanvas.getContext('2d', { willReadFrequently: true });
    if (overlayCanvas) overlayCtx = overlayCanvas.getContext('2d');
    if (cleanBaseCanvas) cleanBaseCtx = cleanBaseCanvas.getContext('2d', { willReadFrequently: true });
  }

  function generateId(prefix = 'ann') {
    return `${prefix}_${Date.now()}_${Math.random().toString(36).substr(2, 6)}`;
  }

  function setStatus(text, color = '#cbd5e1') {
    if (statusEl) {
      statusEl.textContent = text;
      statusEl.style.color = color;
    }
  }

  function updateUndoRedoButtons() {
    if (undoBtn) undoBtn.disabled = undoStack.length === 0;
    if (redoBtn) redoBtn.disabled = redoStack.length === 0;
    if (rotateBtn) {
      rotateBtn.disabled = !selectedId;
      rotateBtn.style.display = selectedId ? 'inline-flex' : 'none';
    }
    if (deleteBtn) {
      deleteBtn.disabled = !selectedId;
      deleteBtn.style.display = selectedId ? 'inline-flex' : 'none';
    }
  }

  function pushUndoState() {
    if (!cleanBaseCanvas || !cleanBaseCtx) return;
    try {
      const snapshot = {
        annotations: JSON.parse(JSON.stringify(annotations)),
        selectedId: selectedId,
        baseVersion: baseVersion,
        baseData: null,
        width: cleanBaseCanvas.width,
        height: cleanBaseCanvas.height
      };
      // Only capture heavy pixel snapshot if base version changed (e.g. crop or pixelate)
      if (undoStack.length === 0 || undoStack[undoStack.length - 1].baseVersion !== baseVersion) {
        snapshot.baseData = cleanBaseCtx.getImageData(0, 0, cleanBaseCanvas.width, cleanBaseCanvas.height);
      }
      undoStack.push(snapshot);
      if (undoStack.length > MAX_UNDO) undoStack.shift();
      redoStack = []; // Clear redo stack on new action
      updateUndoRedoButtons();
    } catch (e) {}
  }

  function undo() {
    if (undoStack.length === 0) return;
    try {
      const currentSnapshot = {
        annotations: JSON.parse(JSON.stringify(annotations)),
        selectedId: selectedId,
        baseVersion: baseVersion,
        baseData: null,
        width: cleanBaseCanvas.width,
        height: cleanBaseCanvas.height
      };
      if (redoStack.length === 0 || redoStack[redoStack.length - 1].baseVersion !== baseVersion) {
        currentSnapshot.baseData = cleanBaseCtx.getImageData(0, 0, cleanBaseCanvas.width, cleanBaseCanvas.height);
      }
      redoStack.push(currentSnapshot);

      const prev = undoStack.pop();
      annotations = prev.annotations || [];
      selectedId = prev.selectedId || null;

      if (prev.baseData) {
        baseVersion = prev.baseVersion;
        cleanBaseCanvas.width = prev.width;
        cleanBaseCanvas.height = prev.height;
        cleanBaseCtx.putImageData(prev.baseData, 0, 0);

        baseCanvas.width = prev.width;
        baseCanvas.height = prev.height;
        overlayCanvas.width = prev.width;
        overlayCanvas.height = prev.height;
        updateViewportDimensions(prev.width, prev.height);
      }

      renderAll();
      updateToolbarForSelection();
      updateUndoRedoButtons();
      setStatus('Undo applied');
    } catch (e) {}
  }

  function redo() {
    if (redoStack.length === 0) return;
    try {
      const currentSnapshot = {
        annotations: JSON.parse(JSON.stringify(annotations)),
        selectedId: selectedId,
        baseVersion: baseVersion,
        baseData: null,
        width: cleanBaseCanvas.width,
        height: cleanBaseCanvas.height
      };
      if (undoStack.length === 0 || undoStack[undoStack.length - 1].baseVersion !== baseVersion) {
        currentSnapshot.baseData = cleanBaseCtx.getImageData(0, 0, cleanBaseCanvas.width, cleanBaseCanvas.height);
      }
      undoStack.push(currentSnapshot);

      const next = redoStack.pop();
      annotations = next.annotations || [];
      selectedId = next.selectedId || null;

      if (next.baseData) {
        baseVersion = next.baseVersion;
        cleanBaseCanvas.width = next.width;
        cleanBaseCanvas.height = next.height;
        cleanBaseCtx.putImageData(next.baseData, 0, 0);

        baseCanvas.width = next.width;
        baseCanvas.height = next.height;
        overlayCanvas.width = next.width;
        overlayCanvas.height = next.height;
        updateViewportDimensions(next.width, next.height);
      }

      renderAll();
      updateToolbarForSelection();
      updateUndoRedoButtons();
      setStatus('Redo applied');
    } catch (e) {}
  }

  function resetToOriginal() {
    if (!originalImage || !cleanBaseCtx) return;
    if (!confirm('Discard all annotations and reset to the original image?')) return;
    pushUndoState();
    loadOriginalImageIntoCanvas(originalImage);
    stepBadgeCounter = 1;
    if (badgeNumInput) badgeNumInput.value = 1;
    setStatus('Reset to original image');
  }

  // --- Viewport Transform & Zoom/Pan ---
  function updateViewportTransform() {
    if (!viewport) return;
    viewport.style.transform = `translate(${panX}px, ${panY}px) scale(${scale})`;
    if (zoomResetBtn) {
      zoomResetBtn.textContent = Math.round(scale * 100) + '%';
    }
  }

  function updateViewportDimensions(w, h) {
    imgWidth = w;
    imgHeight = h;
    if (viewport) {
      viewport.style.width = w + 'px';
      viewport.style.height = h + 'px';
    }
    if (dimsBadge) {
      dimsBadge.textContent = `${w} × ${h}`;
    }
  }

  function fitToStage() {
    if (!stage || imgWidth === 0 || imgHeight === 0) return;
    const stageW = stage.clientWidth - 40;
    const stageH = stage.clientHeight - 40;
    if (stageW <= 0 || stageH <= 0) {
      requestAnimationFrame(() => fitToStage());
      return;
    }

    scale = Math.min(1.0, Math.min(stageW / imgWidth, stageH / imgHeight));
    scale = Math.max(0.1, scale);
    panX = Math.round((stage.clientWidth - imgWidth * scale) / 2);
    panY = Math.round((stage.clientHeight - imgHeight * scale) / 2);
    updateViewportTransform();
  }

  function zoomAt(clientX, clientY, factor) {
    if (!stage) return;
    const rect = stage.getBoundingClientRect();
    const cx = clientX - rect.left;
    const cy = clientY - rect.top;

    const prevScale = scale;
    const nextScale = Math.min(10.0, Math.max(0.1, prevScale * factor));

    panX = cx - (cx - panX) * (nextScale / prevScale);
    panY = cy - (cy - panY) * (nextScale / prevScale);
    scale = nextScale;
    updateViewportTransform();
  }

  // --- Canvas Coordinate Conversion ---
  function screenToCanvasCoords(clientX, clientY) {
    if (!viewport) return { x: 0, y: 0 };
    const rect = viewport.getBoundingClientRect();
    const x = (clientX - rect.left) / scale;
    const y = (clientY - rect.top) / scale;
    return {
      x: Math.max(0, Math.min(imgWidth, x)),
      y: Math.max(0, Math.min(imgHeight, y))
    };
  }

  // --- Pixelation Algorithm ---
  function pixelateRegion(ctx, rx, ry, rw, rh) {
    if (rw <= 2 || rh <= 2) return;
    const blockSize = Math.max(6, Math.round(Math.min(rw, rh) / 10));
    try {
      const imgData = ctx.getImageData(rx, ry, rw, rh);
      const data = imgData.data;

      for (let y = 0; y < rh; y += blockSize) {
        for (let x = 0; x < rw; x += blockSize) {
          const bw = Math.min(blockSize, rw - x);
          const bh = Math.min(blockSize, rh - y);

          let r = 0, g = 0, b = 0, count = 0;
          for (let py = 0; py < bh; py++) {
            for (let px = 0; px < bw; px++) {
              const idx = ((y + py) * rw + (x + px)) * 4;
              r += data[idx];
              g += data[idx + 1];
              b += data[idx + 2];
              count++;
            }
          }

          if (count === 0) continue;
          r = Math.round(r / count);
          g = Math.round(g / count);
          b = Math.round(b / count);

          for (let py = 0; py < bh; py++) {
            for (let px = 0; px < bw; px++) {
              const idx = ((y + py) * rw + (x + px)) * 4;
              data[idx] = r;
              data[idx + 1] = g;
              data[idx + 2] = b;
            }
          }
        }
      }

      ctx.putImageData(imgData, rx, ry);
    } catch (err) {}
  }

  // --- Drawing Helpers ---
  function drawArrow(ctx, x1, y1, x2, y2, color, strokeWidth) {
    const dx = x2 - x1;
    const dy = y2 - y1;
    const dist = Math.sqrt(dx * dx + dy * dy);
    if (dist < 4) return;

    const angle = Math.atan2(dy, dx);
    const headLen = Math.max(14, strokeWidth * 3.4);

    ctx.save();
    ctx.strokeStyle = color;
    ctx.fillStyle = color;
    ctx.lineWidth = strokeWidth;
    ctx.lineCap = 'round';
    ctx.lineJoin = 'round';

    // Main arrow shaft
    ctx.beginPath();
    ctx.moveTo(x1, y1);
    ctx.lineTo(x2, y2);
    ctx.stroke();

    // Solid triangular arrowhead
    ctx.beginPath();
    ctx.moveTo(x2, y2);
    ctx.lineTo(
      x2 - headLen * Math.cos(angle - Math.PI / 6.5),
      y2 - headLen * Math.sin(angle - Math.PI / 6.5)
    );
    ctx.lineTo(
      x2 - headLen * 0.75 * Math.cos(angle),
      y2 - headLen * 0.75 * Math.sin(angle)
    );
    ctx.lineTo(
      x2 - headLen * Math.cos(angle + Math.PI / 6.5),
      y2 - headLen * Math.sin(angle + Math.PI / 6.5)
    );
    ctx.closePath();
    ctx.fill();

    ctx.restore();
  }

  function drawRect(ctx, x1, y1, x2, y2, color, strokeWidth) {
    const rx = Math.min(x1, x2);
    const ry = Math.min(y1, y2);
    const rw = Math.abs(x2 - x1);
    const rh = Math.abs(y2 - y1);
    if (rw < 2 || rh < 2) return;

    ctx.save();
    ctx.strokeStyle = color;
    ctx.lineWidth = strokeWidth;
    ctx.lineJoin = 'round';
    ctx.strokeRect(rx, ry, rw, rh);
    ctx.restore();
  }

  function drawEllipse(ctx, x1, y1, x2, y2, color, strokeWidth) {
    const rx = Math.abs(x2 - x1) / 2;
    const ry = Math.abs(y2 - y1) / 2;
    const cx = Math.min(x1, x2) + rx;
    const cy = Math.min(y1, y2) + ry;
    if (rx < 2 || ry < 2) return;

    ctx.save();
    ctx.strokeStyle = color;
    ctx.lineWidth = strokeWidth;
    ctx.beginPath();
    ctx.ellipse(cx, cy, rx, ry, 0, 0, 2 * Math.PI);
    ctx.stroke();
    ctx.restore();
  }

  function drawHighlight(ctx, x1, y1, x2, y2, color) {
    const rx = Math.min(x1, x2);
    const ry = Math.min(y1, y2);
    const rw = Math.abs(x2 - x1);
    const rh = Math.abs(y2 - y1);
    if (rw < 2 || rh < 2) return;

    ctx.save();
    ctx.fillStyle = hexToRgba(color, 0.35);
    ctx.fillRect(rx, ry, rw, rh);
    ctx.restore();
  }

  function drawStepBadge(ctx, x, y, number, color, fontSize = activeFontSize) {
    const radius = Math.max(10, Math.round((fontSize || activeFontSize) * 0.78));

    ctx.save();
    // Circle background with subtle shadow
    ctx.shadowColor = 'rgba(0, 0, 0, 0.45)';
    ctx.shadowBlur = 4;
    ctx.fillStyle = color;
    ctx.beginPath();
    ctx.arc(x, y, radius, 0, 2 * Math.PI);
    ctx.fill();

    // White outline for contrast
    ctx.shadowBlur = 0;
    ctx.lineWidth = Math.max(1.5, Math.round(radius * 0.12));
    ctx.strokeStyle = '#ffffff';
    ctx.stroke();

    // Number text
    ctx.fillStyle = (color === '#ffffff' || color === '#eab308') ? '#0f172a' : '#ffffff';
    ctx.font = `bold ${Math.round(radius * 1.12)}px ui-sans-serif, system-ui, sans-serif`;
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';
    ctx.fillText(String(number), x, y + 1);

    ctx.restore();
  }

  function drawPen(ctx, points, color, strokeWidth) {
    if (!points || points.length < 2) return;
    ctx.save();
    ctx.strokeStyle = color;
    ctx.lineWidth = strokeWidth;
    ctx.lineCap = 'round';
    ctx.lineJoin = 'round';
    ctx.beginPath();
    ctx.moveTo(points[0].x, points[0].y);
    for (let i = 1; i < points.length; i++) {
      ctx.lineTo(points[i].x, points[i].y);
    }
    ctx.stroke();
    ctx.restore();
  }

  function drawTextOnCanvas(ctx, text, x, y, color, fontSize) {
    if (!ctx || !text || !text.trim()) return;

    ctx.save();
    ctx.font = `bold ${fontSize}px ui-sans-serif, system-ui, sans-serif`;
    ctx.textAlign = 'left';
    ctx.textBaseline = 'top';

    const lines = text.split('\n');
    const lineHeight = Math.round(fontSize * 1.28);

    let maxW = 0;
    lines.forEach(line => {
      const w = ctx.measureText(line).width;
      if (w > maxW) maxW = w;
    });

    const padX = Math.max(4, Math.round(fontSize * 0.32));
    const padY = Math.max(3, Math.round(fontSize * 0.22));
    const totalH = lines.length * lineHeight;

    ctx.fillStyle = 'rgba(15, 23, 42, 0.85)';
    ctx.fillRect(x - padX, y - padY, maxW + padX * 2, totalH + padY * 2);

    ctx.strokeStyle = '#334155';
    ctx.lineWidth = 1;
    ctx.strokeRect(x - padX, y - padY, maxW + padX * 2, totalH + padY * 2);

    lines.forEach((line, idx) => {
      const ly = y + idx * lineHeight;
      ctx.lineWidth = 3;
      ctx.strokeStyle = (color === '#0f172a' || color === '#000000') ? '#ffffff' : 'rgba(0, 0, 0, 0.8)';
      ctx.strokeText(line, x, ly);

      ctx.fillStyle = color;
      ctx.fillText(line, x, ly);
    });

    ctx.restore();
  }

  // --- Geometry & Hit-Testing for Vector Annotations ---
  function rotatePoint(x, y, cx, cy, rad) {
    if (!rad) return { x, y };
    const cos = Math.cos(rad);
    const sin = Math.sin(rad);
    const dx = x - cx;
    const dy = y - cy;
    return {
      x: cx + dx * cos - dy * sin,
      y: cy + dx * sin + dy * cos
    };
  }

  function distToSegment(p, v, w) {
    const l2 = (v.x - w.x) * (v.x - w.x) + (v.y - w.y) * (v.y - w.y);
    if (l2 === 0) return Math.hypot(p.x - v.x, p.y - v.y);
    let t = ((p.x - v.x) * (w.x - v.x) + (p.y - v.y) * (w.y - v.y)) / l2;
    t = Math.max(0, Math.min(1, t));
    return Math.hypot(p.x - (v.x + t * (w.x - v.x)), p.y - (v.y + t * (w.y - v.y)));
  }

  function getAnnotationCenter(ann) {
    if (!ann) return { x: 0, y: 0 };
    if (ann.type === 'arrow') {
      return { x: (ann.x1 + ann.x2) / 2, y: (ann.y1 + ann.y2) / 2 };
    }
    if (ann.type === 'rect' || ann.type === 'ellipse' || ann.type === 'highlight') {
      const x1 = ann.x1 !== undefined ? ann.x1 : ann.x;
      const y1 = ann.y1 !== undefined ? ann.y1 : ann.y;
      const x2 = ann.x2 !== undefined ? ann.x2 : (ann.x + (ann.w || 0));
      const y2 = ann.y2 !== undefined ? ann.y2 : (ann.y + (ann.h || 0));
      return { x: (x1 + x2) / 2, y: (y1 + y2) / 2 };
    }
    if (ann.type === 'badge') {
      return { x: ann.x, y: ann.y };
    }
    if (ann.type === 'text' || ann.type === 'pen') {
      const b = getAnnotationBounds(ann, true);
      if (!b) return { x: ann.x || 0, y: ann.y || 0 };
      return { x: b.x + b.w / 2, y: b.y + b.h / 2 };
    }
    return { x: 0, y: 0 };
  }

  function getAnnotationBounds(ann, unrotated = false) {
    if (!ann) return null;
    let raw = null;
    if (ann.type === 'arrow') {
      const minX = Math.min(ann.x1, ann.x2);
      const maxX = Math.max(ann.x1, ann.x2);
      const minY = Math.min(ann.y1, ann.y2);
      const maxY = Math.max(ann.y1, ann.y2);
      const pad = Math.max(12, (ann.strokeWidth || 4) * 2);
      raw = { x: minX - pad, y: minY - pad, w: (maxX - minX) + pad * 2, h: (maxY - minY) + pad * 2 };
    } else if (ann.type === 'rect' || ann.type === 'ellipse' || ann.type === 'highlight') {
      const x1 = ann.x1 !== undefined ? ann.x1 : ann.x;
      const y1 = ann.y1 !== undefined ? ann.y1 : ann.y;
      const x2 = ann.x2 !== undefined ? ann.x2 : (ann.x + (ann.w || 0));
      const y2 = ann.y2 !== undefined ? ann.y2 : (ann.y + (ann.h || 0));
      const minX = Math.min(x1, x2);
      const maxX = Math.max(x1, x2);
      const minY = Math.min(y1, y2);
      const maxY = Math.max(y1, y2);
      const pad = Math.max(6, (ann.strokeWidth || 4) + 2);
      raw = { x: minX - pad, y: minY - pad, w: (maxX - minX) + pad * 2, h: (maxY - minY) + pad * 2 };
    } else if (ann.type === 'badge') {
      const rad = Math.max(10, Math.round((ann.fontSize || activeFontSize) * 0.78)) + 4;
      raw = { x: ann.x - rad, y: ann.y - rad, w: rad * 2, h: rad * 2 };
    } else if (ann.type === 'text') {
      const fontSize = ann.fontSize || 13;
      const lines = (ann.text || '').split('\n');
      const lineHeight = Math.round(fontSize * 1.28);
      let maxW = 0;
      if (baseCtx) {
        baseCtx.save();
        baseCtx.font = `bold ${fontSize}px ui-sans-serif, system-ui, sans-serif`;
        lines.forEach(l => {
          const w = baseCtx.measureText(l).width;
          if (w > maxW) maxW = w;
        });
        baseCtx.restore();
      }
      if (maxW === 0) maxW = Math.max(30, (ann.text || '').length * fontSize * 0.65);
      const padX = Math.max(4, Math.round(fontSize * 0.32));
      const padY = Math.max(3, Math.round(fontSize * 0.22));
      raw = {
        x: ann.x - padX - 4,
        y: ann.y - padY - 4,
        w: maxW + padX * 2 + 8,
        h: lines.length * lineHeight + padY * 2 + 8
      };
    } else if (ann.type === 'pen') {
      if (!ann.points || ann.points.length === 0) return null;
      let minX = ann.points[0].x, maxX = ann.points[0].x;
      let minY = ann.points[0].y, maxY = ann.points[0].y;
      for (let i = 1; i < ann.points.length; i++) {
        minX = Math.min(minX, ann.points[i].x);
        maxX = Math.max(maxX, ann.points[i].x);
        minY = Math.min(minY, ann.points[i].y);
        maxY = Math.max(maxY, ann.points[i].y);
      }
      const pad = Math.max(6, (ann.strokeWidth || 4) + 2);
      raw = { x: minX - pad, y: minY - pad, w: (maxX - minX) + pad * 2, h: (maxY - minY) + pad * 2 };
    }

    if (!raw) return null;
    if (unrotated || !ann.rotation) return raw;

    // Enclosing bounds for rotated element
    const cx = raw.x + raw.w / 2;
    const cy = raw.y + raw.h / 2;
    const corners = [
      rotatePoint(raw.x, raw.y, cx, cy, ann.rotation),
      rotatePoint(raw.x + raw.w, raw.y, cx, cy, ann.rotation),
      rotatePoint(raw.x + raw.w, raw.y + raw.h, cx, cy, ann.rotation),
      rotatePoint(raw.x, raw.y + raw.h, cx, cy, ann.rotation)
    ];
    let minX = corners[0].x, maxX = corners[0].x;
    let minY = corners[0].y, maxY = corners[0].y;
    for (let i = 1; i < 4; i++) {
      minX = Math.min(minX, corners[i].x);
      maxX = Math.max(maxX, corners[i].x);
      minY = Math.min(minY, corners[i].y);
      maxY = Math.max(maxY, corners[i].y);
    }
    return { x: minX, y: minY, w: maxX - minX, h: maxY - minY };
  }

  function isPointInAnnotation(pt, ann) {
    if (!pt || !ann) return false;
    const tol = Math.max(8, (ann.strokeWidth || 4) * 1.5);

    if (ann.type === 'arrow') {
      return distToSegment(pt, { x: ann.x1, y: ann.y1 }, { x: ann.x2, y: ann.y2 }) <= tol;
    }

    let testPt = pt;
    if (ann.rotation) {
      const center = getAnnotationCenter(ann);
      testPt = rotatePoint(pt.x, pt.y, center.x, center.y, -ann.rotation);
    }

    if (ann.type === 'rect' || ann.type === 'highlight') {
      const x1 = ann.x1 !== undefined ? ann.x1 : ann.x;
      const y1 = ann.y1 !== undefined ? ann.y1 : ann.y;
      const x2 = ann.x2 !== undefined ? ann.x2 : (ann.x + (ann.w || 0));
      const y2 = ann.y2 !== undefined ? ann.y2 : (ann.y + (ann.h || 0));
      const rx = Math.min(x1, x2);
      const ry = Math.min(y1, y2);
      const rw = Math.abs(x2 - x1);
      const rh = Math.abs(y2 - y1);
      return (testPt.x >= rx - tol && testPt.x <= rx + rw + tol && testPt.y >= ry - tol && testPt.y <= ry + rh + tol);
    }
    if (ann.type === 'ellipse') {
      const x1 = ann.x1 !== undefined ? ann.x1 : ann.x;
      const y1 = ann.y1 !== undefined ? ann.y1 : ann.y;
      const x2 = ann.x2 !== undefined ? ann.x2 : (ann.x + (ann.w || 0));
      const y2 = ann.y2 !== undefined ? ann.y2 : (ann.y + (ann.h || 0));
      const rx = Math.abs(x2 - x1) / 2;
      const ry = Math.abs(y2 - y1) / 2;
      const cx = Math.min(x1, x2) + rx;
      const cy = Math.min(y1, y2) + ry;
      if (rx <= 0 || ry <= 0) return false;
      const normDist = Math.pow((testPt.x - cx) / (rx + tol), 2) + Math.pow((testPt.y - cy) / (ry + tol), 2);
      return normDist <= 1.1;
    }
    if (ann.type === 'badge') {
      const rad = Math.max(10, Math.round((ann.fontSize || activeFontSize) * 0.78)) + 5;
      return Math.hypot(testPt.x - ann.x, testPt.y - ann.y) <= rad;
    }
    if (ann.type === 'text') {
      const b = getAnnotationBounds(ann, true);
      return b && (testPt.x >= b.x && testPt.x <= b.x + b.w && testPt.y >= b.y && testPt.y <= b.y + b.h);
    }
    if (ann.type === 'pen') {
      if (!ann.points || ann.points.length < 2) return false;
      for (let i = 1; i < ann.points.length; i++) {
        if (distToSegment(testPt, ann.points[i - 1], ann.points[i]) <= tol) {
          return true;
        }
      }
      return false;
    }
    return false;
  }

  function getAnnotationHandles(ann) {
    if (!ann) return [];

    if (ann.type === 'arrow') {
      const mx = (ann.x1 + ann.x2) / 2;
      const my = (ann.y1 + ann.y2) / 2;
      const dx = ann.x2 - ann.x1;
      const dy = ann.y2 - ann.y1;
      const len = Math.hypot(dx, dy) || 1;
      // Perpendicular stem to rotation handle
      const perpX = -dy / len;
      const perpY = dx / len;
      const stemLen = 28;
      const rotX = mx + perpX * stemLen;
      const rotY = my + perpY * stemLen;

      return [
        { id: 'tail', x: ann.x1, y: ann.y1, cursor: 'crosshair', kind: 'endpoint' },
        { id: 'head', x: ann.x2, y: ann.y2, cursor: 'crosshair', kind: 'endpoint' },
        { id: 'rot', x: rotX, y: rotY, stemStart: { x: mx, y: my }, cursor: 'grab', kind: 'rotate' }
      ];
    }

    if (ann.type === 'rect' || ann.type === 'ellipse' || ann.type === 'highlight') {
      const x1 = ann.x1 !== undefined ? ann.x1 : ann.x;
      const y1 = ann.y1 !== undefined ? ann.y1 : ann.y;
      const x2 = ann.x2 !== undefined ? ann.x2 : (ann.x + (ann.w || 0));
      const y2 = ann.y2 !== undefined ? ann.y2 : (ann.y + (ann.h || 0));
      const minX = Math.min(x1, x2);
      const maxX = Math.max(x1, x2);
      const minY = Math.min(y1, y2);
      const maxY = Math.max(y1, y2);
      const cx = (minX + maxX) / 2;
      const cy = (minY + maxY) / 2;
      const rot = ann.rotation || 0;

      const rawHandles = [
        { id: 'nw', x: minX, y: minY, cursor: 'nwse-resize' },
        { id: 'n',  x: cx,   y: minY, cursor: 'ns-resize' },
        { id: 'ne', x: maxX, y: minY, cursor: 'nesw-resize' },
        { id: 'e',  x: maxX, y: cy,   cursor: 'ew-resize' },
        { id: 'se', x: maxX, y: maxY, cursor: 'nwse-resize' },
        { id: 's',  x: cx,   y: maxY, cursor: 'ns-resize' },
        { id: 'sw', x: minX, y: maxY, cursor: 'nesw-resize' },
        { id: 'w',  x: minX, y: cy,   cursor: 'ew-resize' }
      ];

      const handles = rawHandles.map(h => {
        const pt = rotatePoint(h.x, h.y, cx, cy, rot);
        return { id: h.id, x: pt.x, y: pt.y, cursor: h.cursor, kind: 'resize' };
      });

      const rotWorld = rotatePoint(cx, minY - 26, cx, cy, rot);
      const topWorld = rotatePoint(cx, minY, cx, cy, rot);
      handles.push({
        id: 'rot',
        x: rotWorld.x,
        y: rotWorld.y,
        stemStart: topWorld,
        cursor: 'grab',
        kind: 'rotate'
      });

      return handles;
    }

    if (ann.type === 'text') {
      const b = getAnnotationBounds(ann, true);
      if (!b) return [];
      const cx = b.x + b.w / 2;
      const cy = b.y + b.h / 2;
      const rot = ann.rotation || 0;
      const rawCorners = [
        { id: 'nw', x: b.x, y: b.y, cursor: 'nwse-resize' },
        { id: 'ne', x: b.x + b.w, y: b.y, cursor: 'nesw-resize' },
        { id: 'se', x: b.x + b.w, y: b.y + b.h, cursor: 'nwse-resize' },
        { id: 'sw', x: b.x, y: b.y + b.h, cursor: 'nesw-resize' }
      ];
      const handles = rawCorners.map(h => {
        const pt = rotatePoint(h.x, h.y, cx, cy, rot);
        return { id: h.id, x: pt.x, y: pt.y, cursor: h.cursor, kind: 'scale' };
      });
      const rotWorld = rotatePoint(cx, b.y - 24, cx, cy, rot);
      const topWorld = rotatePoint(cx, b.y, cx, cy, rot);
      handles.push({
        id: 'rot',
        x: rotWorld.x,
        y: rotWorld.y,
        stemStart: topWorld,
        cursor: 'grab',
        kind: 'rotate'
      });
      return handles;
    }

    if (ann.type === 'badge') {
      const rad = Math.max(10, Math.round((ann.fontSize || activeFontSize) * 0.78)) + 4;
      return [
        { id: 'ne', x: ann.x + rad * 0.707, y: ann.y - rad * 0.707, cursor: 'nesw-resize', kind: 'scale' },
        { id: 'se', x: ann.x + rad * 0.707, y: ann.y + rad * 0.707, cursor: 'nwse-resize', kind: 'scale' },
        { id: 'sw', x: ann.x - rad * 0.707, y: ann.y + rad * 0.707, cursor: 'nesw-resize', kind: 'scale' },
        { id: 'nw', x: ann.x - rad * 0.707, y: ann.y - rad * 0.707, cursor: 'nwse-resize', kind: 'scale' }
      ];
    }

    if (ann.type === 'pen') {
      const b = getAnnotationBounds(ann, true);
      if (!b) return [];
      const cx = b.x + b.w / 2;
      const cy = b.y + b.h / 2;
      const rot = ann.rotation || 0;
      const rawCorners = [
        { id: 'nw', x: b.x, y: b.y, cursor: 'nwse-resize' },
        { id: 'ne', x: b.x + b.w, y: b.y, cursor: 'nesw-resize' },
        { id: 'se', x: b.x + b.w, y: b.y + b.h, cursor: 'nwse-resize' },
        { id: 'sw', x: b.x, y: b.y + b.h, cursor: 'nesw-resize' }
      ];
      return rawCorners.map(h => {
        const pt = rotatePoint(h.x, h.y, cx, cy, rot);
        return { id: h.id, x: pt.x, y: pt.y, cursor: h.cursor, kind: 'scale' };
      });
    }

    return [];
  }

  function findHandleAt(pt, ann) {
    if (!pt || !ann) return null;
    const handles = getAnnotationHandles(ann);
    const hitRadius = 12;
    for (let i = handles.length - 1; i >= 0; i--) {
      const h = handles[i];
      if (Math.hypot(pt.x - h.x, pt.y - h.y) <= hitRadius) {
        return h;
      }
    }
    return null;
  }

  function findAnnotationAt(ptOrX, maybeY) {
    let pt = ptOrX;
    if (typeof ptOrX === 'number' && typeof maybeY === 'number') {
      pt = { x: ptOrX, y: maybeY };
    }
    if (!pt || typeof pt.x !== 'number' || typeof pt.y !== 'number') return null;
    // Search top-to-bottom (last drawn is on top)
    for (let i = annotations.length - 1; i >= 0; i--) {
      if (isPointInAnnotation(pt, annotations[i])) {
        return annotations[i];
      }
    }
    return null;
  }

  function applyOffsetToAnnotation(ann, orig, dx, dy) {
    if (!ann || !orig) return;
    if (orig.rotation !== undefined) {
      ann.rotation = orig.rotation;
    }
    if (ann.type === 'arrow' || ann.type === 'rect' || ann.type === 'ellipse' || ann.type === 'highlight') {
      if (orig.x1 !== undefined && orig.x2 !== undefined) {
        ann.x1 = Math.round(orig.x1 + dx);
        ann.y1 = Math.round(orig.y1 + dy);
        ann.x2 = Math.round(orig.x2 + dx);
        ann.y2 = Math.round(orig.y2 + dy);
      }
      if (orig.x !== undefined && orig.y !== undefined) {
        ann.x = Math.round(orig.x + dx);
        ann.y = Math.round(orig.y + dy);
      }
      if (orig.w !== undefined) ann.w = orig.w;
      if (orig.h !== undefined) ann.h = orig.h;
    } else if (ann.type === 'text' || ann.type === 'badge') {
      ann.x = Math.round(orig.x + dx);
      ann.y = Math.round(orig.y + dy);
    } else if (ann.type === 'pen' && ann.points && orig.points) {
      for (let i = 0; i < ann.points.length && i < orig.points.length; i++) {
        ann.points[i].x = Math.round(orig.points[i].x + dx);
        ann.points[i].y = Math.round(orig.points[i].y + dy);
      }
    }
  }

  function rotateSelectedAnnotation(degrees = 45) {
    if (!selectedId) return;
    const ann = annotations.find(a => a.id === selectedId);
    if (!ann) return;

    pushUndoState();
    const rad = degrees * Math.PI / 180;

    if (ann.type === 'arrow') {
      const mx = (ann.x1 + ann.x2) / 2;
      const my = (ann.y1 + ann.y2) / 2;
      const p1 = rotatePoint(ann.x1, ann.y1, mx, my, rad);
      const p2 = rotatePoint(ann.x2, ann.y2, mx, my, rad);
      ann.x1 = Math.round(p1.x);
      ann.y1 = Math.round(p1.y);
      ann.x2 = Math.round(p2.x);
      ann.y2 = Math.round(p2.y);
    } else {
      ann.rotation = ((ann.rotation || 0) + rad) % (2 * Math.PI);
    }

    renderAll();
    setStatus(`Rotated ${ann.type} by ${degrees}°`);
  }

  function handleDragTransform(ann, handleId, dragStartData, currPt, event) {
    if (!ann || !handleId || !dragStartData) return;
    const orig = dragStartData.originalAnn;
    if (!orig) return;

    // 1. ARROW TRANSFORM (head, tail, rot)
    if (ann.type === 'arrow') {
      if (handleId === 'head') {
        let nx = currPt.x;
        let ny = currPt.y;
        if (event && event.shiftKey) {
          const dx = nx - orig.x1;
          const dy = ny - orig.y1;
          const dist = Math.hypot(dx, dy);
          let ang = Math.atan2(dy, dx);
          ang = Math.round(ang / (Math.PI / 12)) * (Math.PI / 12);
          nx = Math.round(orig.x1 + Math.cos(ang) * dist);
          ny = Math.round(orig.y1 + Math.sin(ang) * dist);
        }
        ann.x2 = nx;
        ann.y2 = ny;
        ann.x1 = orig.x1;
        ann.y1 = orig.y1;
        dragStartData.hasMoved = true;
      } else if (handleId === 'tail') {
        let nx = currPt.x;
        let ny = currPt.y;
        if (event && event.shiftKey) {
          const dx = nx - orig.x2;
          const dy = ny - orig.y2;
          const dist = Math.hypot(dx, dy);
          let ang = Math.atan2(dy, dx);
          ang = Math.round(ang / (Math.PI / 12)) * (Math.PI / 12);
          nx = Math.round(orig.x2 + Math.cos(ang) * dist);
          ny = Math.round(orig.y2 + Math.sin(ang) * dist);
        }
        ann.x1 = nx;
        ann.y1 = ny;
        ann.x2 = orig.x2;
        ann.y2 = orig.y2;
        dragStartData.hasMoved = true;
      } else if (handleId === 'rot') {
        const mx = (orig.x1 + orig.x2) / 2;
        const my = (orig.y1 + orig.y2) / 2;
        const startAng = Math.atan2(dragStartData.y - my, dragStartData.x - mx);
        const currAng = Math.atan2(currPt.y - my, currPt.x - mx);
        let deltaAng = currAng - startAng;
        if (event && event.shiftKey) {
          deltaAng = Math.round(deltaAng / (Math.PI / 12)) * (Math.PI / 12);
        }
        const p1 = rotatePoint(orig.x1, orig.y1, mx, my, deltaAng);
        const p2 = rotatePoint(orig.x2, orig.y2, mx, my, deltaAng);
        ann.x1 = Math.round(p1.x);
        ann.y1 = Math.round(p1.y);
        ann.x2 = Math.round(p2.x);
        ann.y2 = Math.round(p2.y);
        dragStartData.hasMoved = true;
      }
      return;
    }

    // 2. SHAPES ROTATION (lollipop handle)
    if (handleId === 'rot') {
      const center = dragStartData.center || getAnnotationCenter(orig);
      const startAng = Math.atan2(dragStartData.y - center.y, dragStartData.x - center.x);
      const currAng = Math.atan2(currPt.y - center.y, currPt.x - center.x);
      let deltaAng = currAng - startAng;
      let newRot = (orig.rotation || 0) + deltaAng;
      if (event && event.shiftKey) {
        newRot = Math.round(newRot / (Math.PI / 12)) * (Math.PI / 12);
      }
      ann.rotation = newRot;
      dragStartData.hasMoved = true;
      return;
    }

    // 3. SHAPES RESIZING (nw, n, ne, e, se, s, sw, w)
    if (ann.type === 'rect' || ann.type === 'ellipse' || ann.type === 'highlight') {
      const rot = orig.rotation || 0;
      const center = dragStartData.center || getAnnotationCenter(orig);

      // Convert points to local unrotated space relative to original center
      const localStart = rotatePoint(dragStartData.x, dragStartData.y, center.x, center.y, -rot);
      const localCurr = rotatePoint(currPt.x, currPt.y, center.x, center.y, -rot);
      const dLocalX = localCurr.x - localStart.x;
      const dLocalY = localCurr.y - localStart.y;

      const origX1 = orig.x1 !== undefined ? orig.x1 : orig.x;
      const origY1 = orig.y1 !== undefined ? orig.y1 : orig.y;
      const origX2 = orig.x2 !== undefined ? orig.x2 : (orig.x + (orig.w || 0));
      const origY2 = orig.y2 !== undefined ? orig.y2 : (orig.y + (orig.h || 0));

      let minX = Math.min(origX1, origX2);
      let maxX = Math.max(origX1, origX2);
      let minY = Math.min(origY1, origY2);
      let maxY = Math.max(origY1, origY2);

      if (handleId.includes('w')) minX = Math.min(maxX - 8, minX + dLocalX);
      if (handleId.includes('e')) maxX = Math.max(minX + 8, maxX + dLocalX);
      if (handleId.includes('n')) minY = Math.min(maxY - 8, minY + dLocalY);
      if (handleId.includes('s')) maxY = Math.max(minY + 8, maxY + dLocalY);

      const newLocalCx = (minX + maxX) / 2;
      const newLocalCy = (minY + maxY) / 2;
      const newWorldCenter = rotatePoint(newLocalCx, newLocalCy, center.x, center.y, rot);
      const halfW = (maxX - minX) / 2;
      const halfH = (maxY - minY) / 2;

      ann.x1 = Math.round(newWorldCenter.x - halfW);
      ann.y1 = Math.round(newWorldCenter.y - halfH);
      ann.x2 = Math.round(newWorldCenter.x + halfW);
      ann.y2 = Math.round(newWorldCenter.y + halfH);
      ann.x = ann.x1;
      ann.y = ann.y1;
      ann.w = Math.round(halfW * 2);
      ann.h = Math.round(halfH * 2);
      dragStartData.hasMoved = true;
      return;
    }

    // 4. TEXT / BADGE SCALING
    if (ann.type === 'text' || ann.type === 'badge') {
      const center = dragStartData.center || getAnnotationCenter(orig);
      const origDist = Math.hypot(dragStartData.x - center.x, dragStartData.y - center.y) || 1;
      const currDist = Math.hypot(currPt.x - center.x, currPt.y - center.y);
      const scaleRatio = Math.max(0.3, Math.min(5, currDist / origDist));
      const origSize = orig.fontSize || 13;
      const newSize = Math.max(8, Math.min(72, Math.round(origSize * scaleRatio)));
      ann.fontSize = newSize;
      if (fontSizeInput) fontSizeInput.value = newSize;
      dragStartData.hasMoved = true;
      return;
    }
  }

  // --- Rendering Vector Annotations & Selection Box ---
  function renderAnnotation(ctx, ann) {
    if (!ctx || !ann) return;
    if (ann.type === 'arrow') {
      drawArrow(ctx, ann.x1, ann.y1, ann.x2, ann.y2, ann.color, ann.strokeWidth);
      return;
    }

    const rot = ann.rotation || 0;
    const center = rot ? getAnnotationCenter(ann) : null;

    ctx.save();
    if (rot && center) {
      ctx.translate(center.x, center.y);
      ctx.rotate(rot);
      ctx.translate(-center.x, -center.y);
    }

    if (ann.type === 'rect') {
      const x1 = ann.x1 !== undefined ? ann.x1 : ann.x;
      const y1 = ann.y1 !== undefined ? ann.y1 : ann.y;
      const x2 = ann.x2 !== undefined ? ann.x2 : (ann.x + (ann.w || 0));
      const y2 = ann.y2 !== undefined ? ann.y2 : (ann.y + (ann.h || 0));
      drawRect(ctx, x1, y1, x2, y2, ann.color, ann.strokeWidth);
    } else if (ann.type === 'ellipse') {
      const x1 = ann.x1 !== undefined ? ann.x1 : ann.x;
      const y1 = ann.y1 !== undefined ? ann.y1 : ann.y;
      const x2 = ann.x2 !== undefined ? ann.x2 : (ann.x + (ann.w || 0));
      const y2 = ann.y2 !== undefined ? ann.y2 : (ann.y + (ann.h || 0));
      drawEllipse(ctx, x1, y1, x2, y2, ann.color, ann.strokeWidth);
    } else if (ann.type === 'highlight') {
      const x1 = ann.x1 !== undefined ? ann.x1 : ann.x;
      const y1 = ann.y1 !== undefined ? ann.y1 : ann.y;
      const x2 = ann.x2 !== undefined ? ann.x2 : (ann.x + (ann.w || 0));
      const y2 = ann.y2 !== undefined ? ann.y2 : (ann.y + (ann.h || 0));
      drawHighlight(ctx, x1, y1, x2, y2, ann.color);
    } else if (ann.type === 'text') {
      drawTextOnCanvas(ctx, ann.text, ann.x, ann.y, ann.color, ann.fontSize || 13);
    } else if (ann.type === 'badge') {
      drawStepBadge(ctx, ann.x, ann.y, ann.number, ann.color, ann.fontSize || activeFontSize);
    } else if (ann.type === 'pen') {
      drawPen(ctx, ann.points, ann.color, ann.strokeWidth);
    }

    ctx.restore();
  }

  function drawSelectionOverlay(ctx, ann) {
    if (!ctx || !ann) return;

    // ARROWS: Shaft outline + Tail, Head, and Midpoint Rotation stem & handle
    if (ann.type === 'arrow') {
      ctx.save();
      // Dashed line along arrow shaft
      ctx.strokeStyle = '#38bdf8';
      ctx.lineWidth = 1.5;
      ctx.setLineDash([4, 4]);
      ctx.beginPath();
      ctx.moveTo(ann.x1, ann.y1);
      ctx.lineTo(ann.x2, ann.y2);
      ctx.stroke();

      const handles = getAnnotationHandles(ann);
      const rotHandle = handles.find(h => h.id === 'rot');
      if (rotHandle && rotHandle.stemStart) {
        // Stem to rotation handle
        ctx.beginPath();
        ctx.moveTo(rotHandle.stemStart.x, rotHandle.stemStart.y);
        ctx.lineTo(rotHandle.x, rotHandle.y);
        ctx.stroke();
      }

      ctx.setLineDash([]);
      handles.forEach(h => {
        ctx.beginPath();
        if (h.id === 'head') {
          // Solid sky-blue circular handle on arrow head
          ctx.arc(h.x, h.y, 5.5, 0, 2 * Math.PI);
          ctx.fillStyle = '#0284c7';
          ctx.fill();
          ctx.lineWidth = 2;
          ctx.strokeStyle = '#ffffff';
          ctx.stroke();
        } else if (h.id === 'tail') {
          // White circular handle on arrow tail
          ctx.arc(h.x, h.y, 5, 0, 2 * Math.PI);
          ctx.fillStyle = '#ffffff';
          ctx.fill();
          ctx.lineWidth = 2;
          ctx.strokeStyle = '#0284c7';
          ctx.stroke();
        } else if (h.id === 'rot') {
          // Emerald rotate lollipop handle
          ctx.arc(h.x, h.y, 5.5, 0, 2 * Math.PI);
          ctx.fillStyle = '#10b981';
          ctx.fill();
          ctx.lineWidth = 2;
          ctx.strokeStyle = '#ffffff';
          ctx.stroke();
        }
      });

      ctx.restore();
      return;
    }

    // SHAPES / TEXT / BADGES / PEN
    const handles = getAnnotationHandles(ann);
    const b = getAnnotationBounds(ann, true); // unrotated bounds
    if (!b) return;

    ctx.save();
    const center = getAnnotationCenter(ann);
    const rot = ann.rotation || 0;

    if (rot) {
      ctx.translate(center.x, center.y);
      ctx.rotate(rot);
      ctx.translate(-center.x, -center.y);
    }

    // Dashed bounding box in local orientation
    ctx.strokeStyle = '#38bdf8';
    ctx.lineWidth = 1.5;
    ctx.setLineDash([4, 4]);

    const x1 = ann.x1 !== undefined ? ann.x1 : ann.x;
    const y1 = ann.y1 !== undefined ? ann.y1 : ann.y;
    const x2 = ann.x2 !== undefined ? ann.x2 : (ann.x + (ann.w || 0));
    const y2 = ann.y2 !== undefined ? ann.y2 : (ann.y + (ann.h || 0));
    const rx = Math.min(x1, x2);
    const ry = Math.min(y1, y2);
    const rw = Math.abs(x2 - x1);
    const rh = Math.abs(y2 - y1);
    const isShape = (ann.type === 'rect' || ann.type === 'ellipse' || ann.type === 'highlight');
    const bx = isShape ? rx : b.x;
    const by = isShape ? ry : b.y;
    const bw = isShape ? rw : b.w;
    const bh = isShape ? rh : b.h;

    ctx.strokeRect(bx, by, bw, bh);

    // Stem to rotate handle if present
    const hasRot = handles.some(h => h.id === 'rot');
    if (hasRot) {
      ctx.beginPath();
      ctx.moveTo(bx + bw / 2, by);
      ctx.lineTo(bx + bw / 2, by - 26);
      ctx.stroke();
    }

    ctx.restore();

    // Draw handles in world coordinates
    ctx.save();
    handles.forEach(h => {
      ctx.beginPath();
      if (h.id === 'rot') {
        ctx.arc(h.x, h.y, 5.5, 0, 2 * Math.PI);
        ctx.fillStyle = '#10b981';
        ctx.fill();
        ctx.lineWidth = 2;
        ctx.strokeStyle = '#ffffff';
        ctx.stroke();
      } else {
        ctx.arc(h.x, h.y, 4.5, 0, 2 * Math.PI);
        ctx.fillStyle = '#ffffff';
        ctx.fill();
        ctx.lineWidth = 2;
        ctx.strokeStyle = '#0284c7';
        ctx.stroke();
      }
    });
    ctx.restore();
  }

  function renderAll(options = {}) {
    if (!baseCanvas || !baseCtx || !cleanBaseCanvas) return;

    // 1. Draw clean base image
    baseCtx.clearRect(0, 0, baseCanvas.width, baseCanvas.height);
    baseCtx.drawImage(cleanBaseCanvas, 0, 0);

    // 2. Draw all vector annotations
    for (let i = 0; i < annotations.length; i++) {
      renderAnnotation(baseCtx, annotations[i]);
    }

    // 3. Selection outline on overlay canvas (unless exporting)
    if (overlayCtx) {
      overlayCtx.clearRect(0, 0, overlayCanvas.width, overlayCanvas.height);
      if (!options.exportMode && selectedId) {
        const selAnn = annotations.find(a => a.id === selectedId);
        if (selAnn) {
          drawSelectionOverlay(overlayCtx, selAnn);
        }
      }
    }

    updateUndoRedoButtons();
  }

  function updateToolbarForSelection() {
    if (!selectedId) return;
    const ann = annotations.find(a => a.id === selectedId);
    if (!ann) return;

    if (ann.color) {
      activeColor = ann.color;
      colorSwatches.forEach(s => {
        s.classList.toggle('active', s.getAttribute('data-color') === ann.color);
      });
    }

    if (ann.strokeWidth) {
      activeStrokeWidth = ann.strokeWidth;
      strokeBtns.forEach(s => {
        s.classList.toggle('active', parseInt(s.getAttribute('data-width'), 10) === ann.strokeWidth);
      });
    }

    if (ann.fontSize) {
      activeFontSize = ann.fontSize;
      if (fontSizeInput) fontSizeInput.value = ann.fontSize;
    }

    if (ann.type === 'badge' && ann.number) {
      if (badgeNumInput) badgeNumInput.value = ann.number;
    }
  }

  function deleteSelectedAnnotation() {
    if (!selectedId) return;
    const ann = annotations.find(a => a.id === selectedId);
    if (!ann) return;

    pushUndoState();
    annotations = annotations.filter(a => a.id !== selectedId);
    const type = ann.type;
    selectedId = null;
    renderAll();
    setStatus(`Deleted ${type} annotation`);
  }

  // --- Inline Text Tool Editing ---
  let textInputCoords = null;

  function commitTextInput() {
    if (!textWrapper || textWrapper.style.display === 'none' || !textInputCoords) return;
    const val = (textInput ? textInput.value : '').trim();
    textWrapper.style.display = 'none';

    if (val) {
      pushUndoState();
      if (editingTextAnnId) {
        const ann = annotations.find(a => a.id === editingTextAnnId);
        if (ann) {
          ann.text = val;
          renderAll();
          setStatus(`Updated text: "${val.slice(0, 25)}"`);
        }
        editingTextAnnId = null;
      } else {
        const newAnn = {
          id: generateId('text'),
          type: 'text',
          x: textInputCoords.x,
          y: textInputCoords.y,
          text: val,
          color: activeColor,
          fontSize: activeFontSize
        };
        annotations.push(newAnn);
        selectedId = newAnn.id;
        renderAll();
        setStatus(`Added text: "${val.slice(0, 25)}"`);
      }
    }
    textInputCoords = null;
    editingTextAnnId = null;
    if (textInput) textInput.value = '';
  }

  function cancelTextInput() {
    if (textWrapper) textWrapper.style.display = 'none';
    textInputCoords = null;
    editingTextAnnId = null;
    if (textInput) textInput.value = '';
  }

  // --- Crop Handling ---
  function applyCrop() {
    if (!cropSelection || !cleanBaseCanvas || !cleanBaseCtx) return;
    const { x, y, w, h } = cropSelection;
    if (w < 10 || h < 10) return;

    pushUndoState();
    baseVersion++;

    const croppedData = cleanBaseCtx.getImageData(x, y, w, h);
    cleanBaseCanvas.width = w;
    cleanBaseCanvas.height = h;
    cleanBaseCtx.putImageData(croppedData, 0, 0);

    // Adjust vector annotation coordinates relative to crop
    annotations.forEach(ann => {
      if (ann.type === 'arrow' || ann.type === 'rect' || ann.type === 'ellipse' || ann.type === 'highlight') {
        ann.x1 -= x; ann.y1 -= y;
        ann.x2 -= x; ann.y2 -= y;
      } else if (ann.type === 'text' || ann.type === 'badge') {
        ann.x -= x; ann.y -= y;
      } else if (ann.type === 'pen' && ann.points) {
        ann.points.forEach(p => { p.x -= x; p.y -= y; });
      }
    });

    baseCanvas.width = w;
    baseCanvas.height = h;
    overlayCanvas.width = w;
    overlayCanvas.height = h;

    updateViewportDimensions(w, h);

    cropSelection = null;
    if (cropBoxEl) cropBoxEl.style.display = 'none';
    if (applyCropBtn) applyCropBtn.style.display = 'none';

    renderAll();
    fitToStage();
    setStatus(`Cropped image to ${w} × ${h}`);
    setActiveTool('select');
  }

  // --- Tool Switching ---
  function setActiveTool(tool) {
    commitTextInput();
    activeTool = tool;

    toolBtns.forEach(btn => {
      btn.classList.toggle('active', btn.getAttribute('data-tool') === tool);
    });

    const fontGroup = document.getElementById('annotator-font-size-group');
    if (fontGroup) {
      fontGroup.style.display = (tool === 'text' || tool === 'badge') ? 'inline-flex' : 'none';
    }

    const badgeGroup = document.getElementById('annotator-badge-group');
    if (badgeGroup) {
      badgeGroup.style.display = (tool === 'badge') ? 'inline-flex' : 'none';
    }

    if (cropBoxEl && tool !== 'crop') {
      cropBoxEl.style.display = 'none';
      cropSelection = null;
    }
    if (applyCropBtn && tool !== 'crop') {
      applyCropBtn.style.display = 'none';
    }

    // Cursor styling
    if (stage) {
      if (tool === 'select') {
        stage.style.cursor = 'grab';
      } else if (tool === 'text') {
        stage.style.cursor = 'text';
      } else {
        stage.style.cursor = 'crosshair';
      }
    }
  }

  // --- Event Listeners for Toolbar ---
  toolBtns.forEach(btn => {
    btn.addEventListener('click', () => {
      setActiveTool(btn.getAttribute('data-tool'));
    });
  });

  colorSwatches.forEach(btn => {
    btn.addEventListener('click', () => {
      colorSwatches.forEach(s => s.classList.remove('active'));
      btn.classList.add('active');
      activeColor = btn.getAttribute('data-color') || '#ef4444';
      if (textInput && textWrapper && textWrapper.style.display !== 'none') {
        textInput.style.color = activeColor;
      }
      if (selectedId) {
        const ann = annotations.find(a => a.id === selectedId);
        if (ann && ann.color !== activeColor) {
          pushUndoState();
          ann.color = activeColor;
          renderAll();
        }
      }
    });
  });

  strokeBtns.forEach(btn => {
    btn.addEventListener('click', () => {
      strokeBtns.forEach(s => s.classList.remove('active'));
      btn.classList.add('active');
      activeStrokeWidth = parseInt(btn.getAttribute('data-width'), 10) || 4;
      if (selectedId) {
        const ann = annotations.find(a => a.id === selectedId);
        if (ann && ann.strokeWidth !== undefined && ann.strokeWidth !== activeStrokeWidth) {
          pushUndoState();
          ann.strokeWidth = activeStrokeWidth;
          renderAll();
        }
      }
    });
  });

  function setFontSize(size) {
    size = Math.max(8, Math.min(72, parseInt(size, 10) || 13));
    activeFontSize = size;
    if (fontSizeInput) fontSizeInput.value = size;
    if (textInput && textWrapper && textWrapper.style.display !== 'none') {
      textInput.style.fontSize = activeFontSize + 'px';
      textInput.style.height = 'auto';
      textInput.style.height = Math.max(28, textInput.scrollHeight) + 'px';
    }
    if (selectedId) {
      const ann = annotations.find(a => a.id === selectedId);
      if (ann && (ann.type === 'text' || ann.type === 'badge') && ann.fontSize !== activeFontSize) {
        pushUndoState();
        ann.fontSize = activeFontSize;
        renderAll();
      }
    }
  }

  if (fontSizeInput) {
    fontSizeInput.addEventListener('change', () => setFontSize(fontSizeInput.value));
    fontSizeInput.addEventListener('input', () => setFontSize(fontSizeInput.value));
  }
  if (fontDecBtn) {
    fontDecBtn.addEventListener('click', () => setFontSize(activeFontSize - 1));
  }
  if (fontIncBtn) {
    fontIncBtn.addEventListener('click', () => setFontSize(activeFontSize + 1));
  }

  function setBadgeNumber(num) {
    num = Math.max(1, Math.min(999, parseInt(num, 10) || 1));
    stepBadgeCounter = num;
    if (badgeNumInput) badgeNumInput.value = num;
    if (selectedId) {
      const ann = annotations.find(a => a.id === selectedId);
      if (ann && ann.type === 'badge' && ann.number !== num) {
        pushUndoState();
        ann.number = num;
        renderAll();
      }
    }
  }

  if (badgeNumInput) {
    badgeNumInput.addEventListener('change', () => setBadgeNumber(badgeNumInput.value));
    badgeNumInput.addEventListener('input', () => setBadgeNumber(badgeNumInput.value));
  }
  if (badgeDecBtn) {
    badgeDecBtn.addEventListener('click', () => setBadgeNumber(stepBadgeCounter - 1));
  }
  if (badgeIncBtn) {
    badgeIncBtn.addEventListener('click', () => setBadgeNumber(stepBadgeCounter + 1));
  }
  if (badgeResetBtn) {
    badgeResetBtn.addEventListener('click', () => {
      setBadgeNumber(1);
      setStatus('Reset step badge counter to 1');
    });
  }

  if (rotateBtn) rotateBtn.addEventListener('click', () => rotateSelectedAnnotation(45));
  if (deleteBtn) deleteBtn.addEventListener('click', deleteSelectedAnnotation);
  if (undoBtn) undoBtn.addEventListener('click', undo);
  if (redoBtn) redoBtn.addEventListener('click', redo);
  if (resetBtn) resetBtn.addEventListener('click', resetToOriginal);
  if (applyCropBtn) applyCropBtn.addEventListener('click', applyCrop);

  // Zoom buttons
  if (zoomInBtn) zoomInBtn.addEventListener('click', () => {
    if (!stage) return;
    zoomAt(stage.clientWidth / 2, stage.clientHeight / 2, 1.25);
  });
  if (zoomOutBtn) zoomOutBtn.addEventListener('click', () => {
    if (!stage) return;
    zoomAt(stage.clientWidth / 2, stage.clientHeight / 2, 0.8);
  });
  if (zoomResetBtn) zoomResetBtn.addEventListener('click', () => {
    scale = 1.0;
    if (stage) {
      panX = Math.round((stage.clientWidth - imgWidth) / 2);
      panY = Math.round((stage.clientHeight - imgHeight) / 2);
    }
    updateViewportTransform();
  });
  if (zoomFitBtn) zoomFitBtn.addEventListener('click', fitToStage);

  // --- Stage Pointer Interaction ---
  if (stage) {
    stage.addEventListener('wheel', (e) => {
      e.preventDefault();
      const factor = e.deltaY < 0 ? 1.15 : 0.87;
      zoomAt(e.clientX, e.clientY, factor);
    }, { passive: false });

    stage.addEventListener('pointerdown', (e) => {
      // Spacebar or Middle-mouse -> Panning
      if (spacePressed || e.button === 1) {
        isPanning = true;
        panStart = { x: e.clientX, y: e.clientY, panX, panY };
        stage.style.cursor = 'grabbing';
        if (stage.setPointerCapture) {
          try { stage.setPointerCapture(e.pointerId); } catch (err) {}
        }
        return;
      }

      if (e.button !== 0) return; // Only left click for drawing or selecting

      // If text input is open and user clicks outside, commit the active text input
      if (textWrapper && textWrapper.style.display !== 'none' && !textWrapper.contains(e.target)) {
        commitTextInput();
      }

      const pt = screenToCanvasCoords(e.clientX, e.clientY);

      // Handle Select tool
      if (activeTool === 'select') {
        if (selectedId) {
          const selAnn = annotations.find(a => a.id === selectedId);
          if (selAnn) {
            const hitHandle = findHandleAt(pt, selAnn);
            if (hitHandle) {
              pushUndoState();
              isDraggingHandle = true;
              activeHandle = hitHandle.id;
              dragHandleStart = {
                x: pt.x,
                y: pt.y,
                center: getAnnotationCenter(selAnn),
                originalAnn: JSON.parse(JSON.stringify(selAnn)),
                hasMoved: false
              };
              stage.style.cursor = hitHandle.cursor;
              if (stage.setPointerCapture) {
                try { stage.setPointerCapture(e.pointerId); } catch (err) {}
              }
              return;
            }
          }
        }

        const hit = findAnnotationAt(pt.x, pt.y);
        if (hit) {
          pushUndoState();
          selectedId = hit.id;
          isDraggingAnnotation = true;
          dragAnnStart = {
            x: pt.x,
            y: pt.y,
            originalAnn: JSON.parse(JSON.stringify(hit)),
            hasMoved: false
          };
          updateToolbarForSelection();
          renderAll();
          stage.style.cursor = 'move';
          if (stage.setPointerCapture) {
            try { stage.setPointerCapture(e.pointerId); } catch (err) {}
          }
          return;
        } else {
          // Clicked empty canvas in select mode -> deselect and allow stage pan
          if (selectedId) {
            selectedId = null;
            updateToolbarForSelection();
            renderAll();
          }
          isPanning = true;
          panStart = { x: e.clientX, y: e.clientY, panX, panY };
          stage.style.cursor = 'grabbing';
          if (stage.setPointerCapture) {
            try { stage.setPointerCapture(e.pointerId); } catch (err) {}
          }
          return;
        }
      }

      // If another tool is active and an item was selected, deselect it
      if (selectedId) {
        selectedId = null;
        updateToolbarForSelection();
        renderAll();
      }

      // Handle Text tool click
      if (activeTool === 'text') {
        if (textWrapper && textWrapper.contains(e.target)) {
          return;
        }

        commitTextInput();
        textInputCoords = pt;
        editingTextAnnId = null;
        if (textWrapper && textInput) {
          textWrapper.style.display = 'block';
          textWrapper.style.left = pt.x + 'px';
          textWrapper.style.top = pt.y + 'px';
          textInput.style.fontSize = activeFontSize + 'px';
          textInput.style.color = activeColor;
          textInput.style.width = '140px';
          textInput.style.height = Math.max(30, activeFontSize + 14) + 'px';
          textInput.value = '';

          e.preventDefault();
          textInput.focus();
          setTimeout(() => {
            if (textInput) {
              textInput.focus();
            }
          }, 10);
        }
        return;
      }

      // Handle Badge tool click
      if (activeTool === 'badge') {
        pushUndoState();
        const badgeAnn = {
          id: generateId('badge'),
          type: 'badge',
          x: pt.x,
          y: pt.y,
          number: stepBadgeCounter,
          color: activeColor,
          fontSize: activeFontSize
        };
        annotations.push(badgeAnn);
        selectedId = badgeAnn.id;
        setStatus(`Placed step badge #${stepBadgeCounter}`);
        stepBadgeCounter++;
        if (badgeNumInput) badgeNumInput.value = stepBadgeCounter;
        updateToolbarForSelection();
        renderAll();
        return;
      }

      // Drawing shapes / crop
      isDrawing = true;
      dragStart = pt;
      penPoints = [pt];

      if (stage.setPointerCapture) {
        try { stage.setPointerCapture(e.pointerId); } catch (err) {}
      }
    });

    stage.addEventListener('pointermove', (e) => {
      if (isPanning && panStart) {
        panX = panStart.panX + (e.clientX - panStart.x);
        panY = panStart.panY + (e.clientY - panStart.y);
        updateViewportTransform();
        return;
      }

      const pt = screenToCanvasCoords(e.clientX, e.clientY);

      if (isDraggingHandle && activeHandle && dragHandleStart && selectedId) {
        const ann = annotations.find(a => a.id === selectedId);
        if (ann) {
          handleDragTransform(ann, activeHandle, dragHandleStart, pt, e);
          renderAll();
        }
        return;
      }

      if (isDraggingAnnotation && dragAnnStart && selectedId) {
        const ann = annotations.find(a => a.id === selectedId);
        if (ann && dragAnnStart.originalAnn) {
          const dx = pt.x - dragAnnStart.x;
          const dy = pt.y - dragAnnStart.y;
          if (Math.abs(dx) > 1 || Math.abs(dy) > 1) {
            dragAnnStart.hasMoved = true;
          }
          applyOffsetToAnnotation(ann, dragAnnStart.originalAnn, dx, dy);
          renderAll();
        }
        return;
      }

      if (activeTool === 'select' && !isDrawing) {
        if (selectedId) {
          const selAnn = annotations.find(a => a.id === selectedId);
          if (selAnn) {
            const h = findHandleAt(pt, selAnn);
            if (h) {
              stage.style.cursor = h.cursor;
              return;
            }
          }
        }
        const hover = findAnnotationAt(pt.x, pt.y);
        stage.style.cursor = hover ? 'move' : 'grab';
        return;
      }

      if (!isDrawing || !dragStart || !overlayCtx) return;

      overlayCtx.clearRect(0, 0, overlayCanvas.width, overlayCanvas.height);

      if (activeTool === 'arrow') {
        drawArrow(overlayCtx, dragStart.x, dragStart.y, pt.x, pt.y, activeColor, activeStrokeWidth);
      } else if (activeTool === 'rect') {
        drawRect(overlayCtx, dragStart.x, dragStart.y, pt.x, pt.y, activeColor, activeStrokeWidth);
      } else if (activeTool === 'ellipse') {
        drawEllipse(overlayCtx, dragStart.x, dragStart.y, pt.x, pt.y, activeColor, activeStrokeWidth);
      } else if (activeTool === 'highlight') {
        drawHighlight(overlayCtx, dragStart.x, dragStart.y, pt.x, pt.y, activeColor);
      } else if (activeTool === 'pixelate') {
        // Preview selection box
        const rx = Math.min(dragStart.x, pt.x);
        const ry = Math.min(dragStart.y, pt.y);
        const rw = Math.abs(pt.x - dragStart.x);
        const rh = Math.abs(pt.y - dragStart.y);
        overlayCtx.save();
        overlayCtx.strokeStyle = '#38bdf8';
        overlayCtx.lineWidth = 1.5;
        overlayCtx.setLineDash([4, 4]);
        overlayCtx.strokeRect(rx, ry, rw, rh);
        overlayCtx.fillStyle = 'rgba(56, 189, 248, 0.15)';
        overlayCtx.fillRect(rx, ry, rw, rh);
        overlayCtx.restore();
      } else if (activeTool === 'pen') {
        penPoints.push(pt);
        drawPen(overlayCtx, penPoints, activeColor, activeStrokeWidth);
      } else if (activeTool === 'crop') {
        const rx = Math.round(Math.min(dragStart.x, pt.x));
        const ry = Math.round(Math.min(dragStart.y, pt.y));
        const rw = Math.round(Math.abs(pt.x - dragStart.x));
        const rh = Math.round(Math.abs(pt.y - dragStart.y));
        if (cropBoxEl) {
          cropBoxEl.style.display = 'block';
          cropBoxEl.style.left = rx + 'px';
          cropBoxEl.style.top = ry + 'px';
          cropBoxEl.style.width = rw + 'px';
          cropBoxEl.style.height = rh + 'px';
        }
        cropSelection = { x: rx, y: ry, w: rw, h: rh };
      }
    });

    const endDrag = (e) => {
      if (isPanning) {
        isPanning = false;
        panStart = null;
        stage.style.cursor = (activeTool === 'select') ? 'grab' : 'crosshair';
        if (e && stage.releasePointerCapture && e.pointerId !== undefined) {
          try { stage.releasePointerCapture(e.pointerId); } catch (err) {}
        }
        return;
      }

      if (isDraggingHandle) {
        isDraggingHandle = false;
        activeHandle = null;
        if (e && stage.releasePointerCapture && e.pointerId !== undefined) {
          try { stage.releasePointerCapture(e.pointerId); } catch (err) {}
        }
        if (dragHandleStart) {
          if (dragHandleStart.hasMoved) {
            setStatus('Transformed annotation');
          } else {
            // Did not move: pop redundant undo state
            if (undoStack.length > 0) undoStack.pop();
            updateUndoRedoButtons();
          }
          dragHandleStart = null;
        }
        stage.style.cursor = (activeTool === 'select') ? 'grab' : 'crosshair';
        return;
      }

      if (isDraggingAnnotation) {
        isDraggingAnnotation = false;
        if (e && stage.releasePointerCapture && e.pointerId !== undefined) {
          try { stage.releasePointerCapture(e.pointerId); } catch (err) {}
        }
        if (dragAnnStart) {
          if (dragAnnStart.hasMoved) {
            setStatus('Moved annotation');
          } else {
            // Did not move: pop redundant undo state
            if (undoStack.length > 0) undoStack.pop();
            updateUndoRedoButtons();
          }
          dragAnnStart = null;
        }
        stage.style.cursor = (activeTool === 'select') ? 'grab' : 'crosshair';
        return;
      }

      if (!isDrawing || !dragStart) return;
      isDrawing = false;

      const pt = screenToCanvasCoords(e.clientX, e.clientY);
      if (overlayCtx) overlayCtx.clearRect(0, 0, overlayCanvas.width, overlayCanvas.height);

      if (e && stage.releasePointerCapture && e.pointerId !== undefined) {
        try { stage.releasePointerCapture(e.pointerId); } catch (err) {}
      }

      let newAnn = null;

      if (activeTool === 'arrow') {
        const dx = pt.x - dragStart.x;
        const dy = pt.y - dragStart.y;
        if (Math.sqrt(dx * dx + dy * dy) > 5) {
          newAnn = {
            id: generateId('arrow'),
            type: 'arrow',
            x1: dragStart.x,
            y1: dragStart.y,
            x2: pt.x,
            y2: pt.y,
            color: activeColor,
            strokeWidth: activeStrokeWidth
          };
          setStatus('Added arrow');
        }
      } else if (activeTool === 'rect') {
        const rw = Math.abs(pt.x - dragStart.x);
        const rh = Math.abs(pt.y - dragStart.y);
        if (rw > 4 && rh > 4) {
          newAnn = {
            id: generateId('rect'),
            type: 'rect',
            x1: dragStart.x,
            y1: dragStart.y,
            x2: pt.x,
            y2: pt.y,
            x: Math.min(dragStart.x, pt.x),
            y: Math.min(dragStart.y, pt.y),
            w: rw,
            h: rh,
            color: activeColor,
            strokeWidth: activeStrokeWidth
          };
          setStatus('Added box');
        }
      } else if (activeTool === 'ellipse') {
        const rw = Math.abs(pt.x - dragStart.x);
        const rh = Math.abs(pt.y - dragStart.y);
        if (rw > 4 && rh > 4) {
          newAnn = {
            id: generateId('ellipse'),
            type: 'ellipse',
            x1: dragStart.x,
            y1: dragStart.y,
            x2: pt.x,
            y2: pt.y,
            x: Math.min(dragStart.x, pt.x),
            y: Math.min(dragStart.y, pt.y),
            w: rw,
            h: rh,
            color: activeColor,
            strokeWidth: activeStrokeWidth
          };
          setStatus('Added circle');
        }
      } else if (activeTool === 'highlight') {
        const rw = Math.abs(pt.x - dragStart.x);
        const rh = Math.abs(pt.y - dragStart.y);
        if (rw > 4 && rh > 4) {
          newAnn = {
            id: generateId('highlight'),
            type: 'highlight',
            x1: dragStart.x,
            y1: dragStart.y,
            x2: pt.x,
            y2: pt.y,
            x: Math.min(dragStart.x, pt.x),
            y: Math.min(dragStart.y, pt.y),
            w: rw,
            h: rh,
            color: activeColor
          };
          setStatus('Added highlight');
        }
      } else if (activeTool === 'pixelate') {
        const rx = Math.round(Math.min(dragStart.x, pt.x));
        const ry = Math.round(Math.min(dragStart.y, pt.y));
        const rw = Math.round(Math.abs(pt.x - dragStart.x));
        const rh = Math.round(Math.abs(pt.y - dragStart.y));
        if (rw > 6 && rh > 6 && cleanBaseCtx) {
          pushUndoState();
          pixelateRegion(cleanBaseCtx, rx, ry, rw, rh);
          baseVersion++;
          renderAll();
          setStatus(`Pixelated area (${rw} × ${rh})`);
        }
      } else if (activeTool === 'pen') {
        if (penPoints.length > 1) {
          newAnn = {
            id: generateId('pen'),
            type: 'pen',
            points: penPoints.slice(),
            color: activeColor,
            strokeWidth: activeStrokeWidth
          };
          setStatus('Added freehand drawing');
        }
      } else if (activeTool === 'crop') {
        if (cropSelection && cropSelection.w > 10 && cropSelection.h > 10) {
          if (applyCropBtn) applyCropBtn.style.display = 'inline-flex';
          setStatus(`Selected crop area: ${cropSelection.w} × ${cropSelection.h} — click "Apply Crop" to commit`);
        }
      }

      if (newAnn) {
        pushUndoState();
        annotations.push(newAnn);
        selectedId = newAnn.id;
        updateToolbarForSelection();
        renderAll();
      }

      dragStart = null;
      penPoints = [];
    };

    stage.addEventListener('pointerup', endDrag);
    stage.addEventListener('pointercancel', endDrag);

    // Double click to edit text annotation or fit
    stage.addEventListener('dblclick', (e) => {
      const pt = screenToCanvasCoords(e.clientX, e.clientY);
      const hit = findAnnotationAt(pt.x, pt.y);
      if (hit && hit.type === 'text') {
        selectedId = hit.id;
        editingTextAnnId = hit.id;
        textInputCoords = { x: hit.x, y: hit.y };
        if (textWrapper && textInput) {
          textWrapper.style.display = 'block';
          textWrapper.style.left = hit.x + 'px';
          textWrapper.style.top = hit.y + 'px';
          textInput.style.fontSize = (hit.fontSize || activeFontSize) + 'px';
          textInput.style.color = hit.color || activeColor;
          textInput.value = hit.text || '';
          textInput.style.height = 'auto';
          textInput.style.height = Math.max(28, textInput.scrollHeight) + 'px';
          textInput.style.width = 'auto';
          textInput.style.width = Math.max(120, Math.min(500, textInput.scrollWidth + 12)) + 'px';
          textInput.focus();
        }
        renderAll();
        return;
      }
      if (activeTool === 'select') {
        fitToStage();
      }
    });
  }

  // --- Text Input Event Handling ---
  if (textWrapper) {
    textWrapper.addEventListener('pointerdown', (e) => e.stopPropagation());
    textWrapper.addEventListener('mousedown', (e) => e.stopPropagation());
    textWrapper.addEventListener('click', (e) => e.stopPropagation());
  }

  if (textInput) {
    textInput.addEventListener('keydown', (e) => {
      if (e.key === 'Enter' && !e.shiftKey) {
        e.preventDefault();
        commitTextInput();
      } else if (e.key === 'Escape') {
        e.preventDefault();
        cancelTextInput();
      }
    });

    textInput.addEventListener('input', () => {
      textInput.style.height = 'auto';
      textInput.style.height = Math.max(28, textInput.scrollHeight) + 'px';
      textInput.style.width = 'auto';
      textInput.style.width = Math.max(120, Math.min(500, textInput.scrollWidth + 12)) + 'px';
    });
  }

  // --- Keyboard Shortcuts in Editor ---
  window.addEventListener('keydown', (e) => {
    // Spacebar to pan
    if (e.code === 'Space' && !spacePressed && modal && modal.style.display === 'block') {
      if (document.activeElement && (document.activeElement.tagName === 'INPUT' || document.activeElement.tagName === 'TEXTAREA')) return;
      spacePressed = true;
      if (stage) stage.style.cursor = 'grab';
    }

    if (!modal || modal.style.display !== 'block') return;

    // Avoid hijacking typing inside inputs
    if (document.activeElement && (document.activeElement.tagName === 'INPUT' || document.activeElement.tagName === 'TEXTAREA')) {
      if (e.key === 'Escape') {
        cancelTextInput();
      }
      return;
    }

    if (e.key === 'Delete' || e.key === 'Backspace') {
      if (selectedId) {
        e.preventDefault();
        deleteSelectedAnnotation();
        return;
      }
    } else if (e.key === '[' || e.key === ']') {
      if (selectedId) {
        e.preventDefault();
        const deg = (e.key === ']') ? (e.shiftKey ? 15 : 45) : (e.shiftKey ? -15 : -45);
        rotateSelectedAnnotation(deg);
        return;
      }
    } else if (['ArrowUp', 'ArrowDown', 'ArrowLeft', 'ArrowRight'].includes(e.key)) {
      if (selectedId) {
        const ann = annotations.find(a => a.id === selectedId);
        if (ann) {
          e.preventDefault();
          pushUndoState();
          const step = e.shiftKey ? 10 : 1;
          let dx = 0, dy = 0;
          if (e.key === 'ArrowUp') dy = -step;
          if (e.key === 'ArrowDown') dy = step;
          if (e.key === 'ArrowLeft') dx = -step;
          if (e.key === 'ArrowRight') dx = step;
          const cloned = JSON.parse(JSON.stringify(ann));
          applyOffsetToAnnotation(ann, cloned, dx, dy);
          renderAll();
          return;
        }
      }
    } else if ((e.ctrlKey || e.metaKey) && e.key.toLowerCase() === 'z') {
      e.preventDefault();
      if (e.shiftKey) {
        redo();
      } else {
        undo();
      }
    } else if ((e.ctrlKey || e.metaKey) && e.key.toLowerCase() === 'y') {
      e.preventDefault();
      redo();
    } else if ((e.ctrlKey || e.metaKey) && e.key.toLowerCase() === 's') {
      e.preventDefault();
      saveAnnotatedImage('overwrite');
    } else if (e.key === 'Escape') {
      e.preventDefault();
      if (selectedId) {
        selectedId = null;
        updateToolbarForSelection();
        renderAll();
      } else {
        closeScreenshotEditor();
      }
    } else if (e.key.toLowerCase() === 'f') {
      fitToStage();
    } else if (e.key.toLowerCase() === 'v') {
      setActiveTool('select');
    } else if (e.key.toLowerCase() === 'a') {
      setActiveTool('arrow');
    } else if (e.key.toLowerCase() === 'r') {
      setActiveTool('rect');
    } else if (e.key.toLowerCase() === 'o') {
      setActiveTool('ellipse');
    } else if (e.key.toLowerCase() === 'h') {
      setActiveTool('highlight');
    } else if (e.key.toLowerCase() === 'b') {
      setActiveTool('pixelate');
    } else if (e.key.toLowerCase() === 't') {
      setActiveTool('text');
    } else if (e.key.toLowerCase() === 's' && !e.ctrlKey && !e.metaKey) {
      setActiveTool('badge');
    } else if (e.key.toLowerCase() === 'p') {
      setActiveTool('pen');
    } else if (e.key.toLowerCase() === 'c') {
      setActiveTool('crop');
    }
  });

  window.addEventListener('keyup', (e) => {
    if (e.code === 'Space') {
      spacePressed = false;
      if (stage) stage.style.cursor = (activeTool === 'select') ? 'grab' : 'crosshair';
    }
  });

  // --- Loading Image into Canvas ---
  function loadOriginalImageIntoCanvas(img) {
    if (!img || !baseCanvas || !overlayCanvas) return;
    initContexts();

    const w = img.naturalWidth || img.width || 800;
    const h = img.naturalHeight || img.height || 600;

    baseCanvas.width = w;
    baseCanvas.height = h;
    overlayCanvas.width = w;
    overlayCanvas.height = h;

    cleanBaseCanvas.width = w;
    cleanBaseCanvas.height = h;
    cleanBaseCtx.clearRect(0, 0, w, h);
    cleanBaseCtx.drawImage(img, 0, 0, w, h);

    annotations = [];
    selectedId = null;
    baseVersion = 0;
    editingTextAnnId = null;

    updateViewportDimensions(w, h);

    renderAll();

    undoStack = [];
    redoStack = [];
    updateUndoRedoButtons();
    fitToStage();
    requestAnimationFrame(() => {
      fitToStage();
    });
  }

  // --- Open / Close Modal ---
  function openScreenshotEditor(src, options = {}) {
    if (!modal) return;
    initContexts();

    currentOriginalSrc = src;
    currentFilename = options.filename || getFilenameFromUrl(src);

    if (filenameBadge) {
      filenameBadge.textContent = currentFilename;
      filenameBadge.title = currentFilename;
    }

    setStatus('Loading image...');
    modal.style.display = 'block';

    const img = new Image();
    img.crossOrigin = 'anonymous';
    img.onload = () => {
      originalImage = img;
      loadOriginalImageIntoCanvas(img);
      setStatus('Ready');
    };
    img.onerror = () => {
      if (img.crossOrigin) {
        // Fallback retry without crossOrigin if CORS failed
        img.crossOrigin = null;
        img.src = src;
        return;
      }
      setStatus('Failed to load image', '#ef4444');
      alert('Could not load image: ' + src);
    };
    img.src = src;

    setActiveTool('arrow'); // Default to arrow tool as requested!
  }

  function closeScreenshotEditor() {
    if (!modal) return;
    commitTextInput();
    modal.style.display = 'none';
  }

  if (closeX) closeX.addEventListener('click', closeScreenshotEditor);

  // --- Save / Export Handlers ---
  function saveAnnotatedImage(mode = 'overwrite') {
    if (!baseCanvas) return;
    commitTextInput();

    // Deselect element and render clean flattened export
    selectedId = null;
    updateToolbarForSelection();
    renderAll({ exportMode: true });

    const wt = (window.CtlabsWalkthrough && window.CtlabsWalkthrough.getActiveWalkthrough()) || '';
    const btn = (mode === 'overwrite') ? saveBtn : saveCopyBtn;
    const origHtml = btn ? btn.innerHTML : '';
    if (btn) {
      btn.disabled = true;
      btn.innerHTML = '<i class="fas fa-spinner fa-spin"></i> Saving...';
    }

    setStatus(`Saving ${mode === 'overwrite' ? 'changes' : 'new copy'}...`);

    baseCanvas.toBlob((blob) => {
      if (!blob) {
        if (btn) { btn.disabled = false; btn.innerHTML = origHtml; }
        setStatus('Failed to export canvas blob', '#ef4444');
        return;
      }

      const formData = new FormData();
      formData.append('file', blob, currentFilename);
      formData.append('filename', currentFilename);
      formData.append('mode', mode);
      formData.append('walkthrough', wt);

      fetch('/recordings/save-annotated-image', {
        method: 'POST',
        body: formData,
        credentials: 'same-origin'
      })
      .then(res => res.json())
      .then(data => {
        if (btn) { btn.disabled = false; btn.innerHTML = origHtml; }
        if (!data.ok) {
          setStatus('Save error: ' + (data.error || 'Unknown'), '#ef4444');
          alert('Save failed: ' + (data.error || 'Unknown error'));
          return;
        }

        closeScreenshotEditor();

        if (mode === 'overwrite') {
          // Cache-bust all matching images on the page
          const cleanName = currentFilename.split('?')[0];
          document.querySelectorAll('img').forEach(im => {
            if (im.src && im.src.includes(cleanName)) {
              im.src = `${data.clean_url}?t=${Date.now()}`;
            }
          });

          ctlabsToast(`Updated image <code>${data.filename}</code>`, 'fas fa-save', '#10b981');
        } else {
          // Saved as copy -> update markdown editor
          if (window.CtlabsWalkthrough && typeof window.CtlabsWalkthrough.replaceOrInsertImage === 'function') {
            window.CtlabsWalkthrough.replaceOrInsertImage(currentFilename, data.filename);
          }
          ctlabsToast(`Saved copy <code>${data.filename}</code> and updated Markdown!`, 'fas fa-copy', '#38bdf8');
        }
      })
      .catch(err => {
        if (btn) { btn.disabled = false; btn.innerHTML = origHtml; }
        setStatus('Network error: ' + err.message, '#ef4444');
        alert('Network error saving image: ' + err.message);
      });
    }, 'image/png');
  }

  if (saveBtn) {
    saveBtn.addEventListener('click', () => saveAnnotatedImage('overwrite'));
  }

  if (saveCopyBtn) {
    saveCopyBtn.addEventListener('click', () => saveAnnotatedImage('copy'));
  }

  if (downloadBtn) {
    downloadBtn.addEventListener('click', () => {
      if (!baseCanvas) return;
      commitTextInput();

      // Deselect element and render clean flattened export
      selectedId = null;
      updateToolbarForSelection();
      renderAll({ exportMode: true });

      const a = document.createElement('a');
      a.href = baseCanvas.toDataURL('image/png');
      const base = currentFilename.replace(/\.[^.]+$/, '');
      a.download = `${base}_annotated.png`;
      document.body.appendChild(a);
      a.click();
      document.body.removeChild(a);
      ctlabsToast(`Downloaded <code>${a.download}</code>`, 'fas fa-download', '#38bdf8');
    });
  }

  // Expose global interface
  window.openScreenshotEditor = openScreenshotEditor;
  window.closeScreenshotEditor = closeScreenshotEditor;
  window.openImageContextMenu = openImageContextMenu;
  window.hideImageContextMenu = hideImageContextMenu;

})();
