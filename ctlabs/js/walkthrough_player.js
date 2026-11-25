/*
 -----------------------------------------------------------------------------
 File        : ctlabs/js/walkthrough_player.js
 Description : Walkthrough Player, sidebar navigation, terminal/video player,
               screen recorder, and step management controller
 License     : MIT License
 -----------------------------------------------------------------------------
*/

(function() {
  const cfg = window.WalkthroughConfig || {};
  const activeWalkthrough = cfg.activeWalkthrough || '';
  const preferredRecording = cfg.preferredRecording || '';
  window.activeWalkthrough = activeWalkthrough;
  try {
    localStorage.setItem('ctlabs_active_walkthrough', activeWalkthrough);
  } catch (e) {}

  const demoDiv = document.getElementById('demo');
  const demoContainer = document.getElementById('demo-container');
  const mdContainer = document.getElementById('md-container');
  const mdPreviewPane = document.getElementById('md-preview-pane');
  const mdEditPane = document.getElementById('md-edit-pane');
  const mdTextarea = document.getElementById('md-textarea');
  const mdSettingsMenu = document.getElementById('md-settings-menu');
  const mdSettingsBtn = document.getElementById('md-settings-btn');
  const titleEl = document.getElementById('rec-title');
  const titleIcon = document.getElementById('rec-title-icon');
  const actionsEl = document.getElementById('rec-actions');
  const downloadEl = document.getElementById('rec-download');
  const deleteForm = document.getElementById('rec-delete');
  const metaForm = document.getElementById('meta-form');
  const editTitle = document.getElementById('edit-title');
  const stepContextMenu = document.getElementById('step-context-menu');
  const stepContextTitle = document.getElementById('step-context-title');
  const stepContextEditTitle = document.getElementById('step-context-edit-title');
  const stepContextEdit = document.getElementById('step-context-edit');
  const stepContextCopyLink = document.getElementById('step-context-copy-link');
  let stepContextBtn = null;
  let pendingMdEditMode = false;

  const mdImgContextMenu = document.getElementById('md-img-context-menu');
  const mdImgContextTitle = document.getElementById('md-img-context-title');
  const mdImgContextDownload = document.getElementById('md-img-context-download');
  const mdImgContextEditDiagram = document.getElementById('md-img-context-edit-diagram');
  const mdImgContextCopyLink = document.getElementById('md-img-context-copy-link');
  const mdImgContextOpenTab = document.getElementById('md-img-context-open-tab');
  let currentContextImg = null;
  const recsList = document.getElementById('recs-list');
  const otherList = document.getElementById('other-list');
  const importBtn = document.getElementById('import-btn');
  const importFileInput = document.getElementById('import-file-input');
  const newSetBtn = document.getElementById('new-set-btn');
  const newSetName = document.getElementById('new-set-name');

  const stepPrevBtn = document.getElementById('step-prev-btn');
  const stepNextBtn = document.getElementById('step-next-btn');
  const stepNavCounter = document.getElementById('step-nav-counter');

  const mdInsertImgBtn = document.getElementById('md-insert-img-btn');
  const mdImgFileInput = document.getElementById('md-img-file-input');
  const mdGraphvizBtn = document.getElementById('md-graphviz-btn');
  const mdSaveBtn = document.getElementById('md-save-btn');
  const mdGitWrapper = document.getElementById('md-git-wrapper');
  const mdGitCommitBtn = document.getElementById('md-git-commit-btn');
  const mdGitHistoryBtn = document.getElementById('md-git-history-btn');
  const mdSettingsWrapper = document.getElementById('md-settings-wrapper');
  const mdSettingsDivider = document.getElementById('md-settings-divider');
  const imageModalEditDiagram = document.getElementById('image-modal-edit-diagram');
  const exportNoteModal = document.getElementById('export-note-modal');
  const confirmExportNoteBtn = document.getElementById('confirm-export-note-btn');
  const exportNoteTitleSpan = document.getElementById('export-note-title-span');
  const exportNoteFilenameInput = document.getElementById('export-note-filename');
  const exportNoteFilenameHint = document.getElementById('export-note-filename-hint');

  let draggedItem = null;
  let draggedSource = null;

  function getDroppedFiles(dt) {
    if (!dt) return [];
    if (dt.files && dt.files.length > 0) {
      return Array.from(dt.files);
    }
    if (dt.items && dt.items.length > 0) {
      const list = [];
      for (let i = 0; i < dt.items.length; i++) {
        const item = dt.items[i];
        if (item.kind === 'file') {
          const f = item.getAsFile();
          if (f) list.push(f);
        }
      }
      if (list.length > 0) return list;
    }
    return [];
  }
  const mdEmojiWrapper = document.getElementById('md-emoji-wrapper');
  const mdEmojiBtn = document.getElementById('md-emoji-btn');
  const mdEmojiMenu = document.getElementById('md-emoji-menu');
  const mdEmojiSearch = document.getElementById('md-emoji-search');
  const mdEmojiSearchClear = document.getElementById('md-emoji-search-clear');
  const mdEmojiGrid = document.getElementById('md-emoji-grid');
  const mdEmojiFooterPreview = document.getElementById('md-emoji-footer-preview');
  const mdEmojiCatBtns = document.querySelectorAll('.md-emoji-cat-btn');

  const imageModal = document.getElementById('image-modal');
  const imageModalStage = document.getElementById('image-modal-stage');
  const imageModalImg = document.getElementById('image-modal-img');
  const imageModalCaption = document.getElementById('image-modal-caption');
  const imageModalExternal = document.getElementById('image-modal-external');
  const imageModalClose = document.getElementById('image-modal-close');
  const imageModalZoomIn = document.getElementById('image-modal-zoom-in');
  const imageModalZoomOut = document.getElementById('image-modal-zoom-out');
  const imageModalZoomReset = document.getElementById('image-modal-zoom-reset');
  const imageModalZoomFit = document.getElementById('image-modal-zoom-fit');

  const videoContainer = document.getElementById('video-container');
  const videoPlayer = document.getElementById('video-player');

  const recordDropdownBtn = document.getElementById('record-dropdown-btn');
  const recordDropdownMenu = document.getElementById('record-dropdown-menu');

  const recordCastBtn = document.getElementById('record-cast-btn');
  const recordCastModal = document.getElementById('record-cast-modal');
  const closeRecordCastModal = document.getElementById('close-record-cast-modal');
  const cancelRecordCastBtn = document.getElementById('cancel-record-cast-btn');
  const castOpenTermBtn = document.getElementById('cast-open-term-btn');
  const castNodeSelect = document.getElementById('cast-node-select');
  const castImportBtn = document.getElementById('cast-import-btn');

  const recordScreenBtn = document.getElementById('record-screen-btn');
  const recordScreenModal = document.getElementById('record-screen-modal');
  const recScreenMic = document.getElementById('rec-screen-mic');
  const confirmRecordScreenBtn = document.getElementById('confirm-record-screen-btn');
  const cancelRecordScreenBtn = document.getElementById('cancel-record-screen-btn');
  const closeRecordScreenModal = document.getElementById('close-record-screen-modal');

  const screenRecBar = document.getElementById('screen-rec-bar');
  const screenRecTimer = document.getElementById('screen-rec-timer');
  const screenRecSize = document.getElementById('screen-rec-size');
  const screenRecStopBtn = document.getElementById('screen-rec-stop-btn');
  const screenRecCancelBtn = document.getElementById('screen-rec-cancel-btn');
  const screenRecFocusBtn = document.getElementById('screen-rec-focus-btn');

  const launchRecWinBtn = document.getElementById('launch-rec-win-btn');
  const focusRecWinBtn = document.getElementById('focus-rec-win-btn');
  const closeRecWinBtn = document.getElementById('close-rec-win-btn');
  const recWinUrlInput = document.getElementById('rec-win-url');
  const recWinResSelect = document.getElementById('rec-win-res');
  const recWinStatusBadge = document.getElementById('rec-win-status-badge');

  let activeRecWindow = null;
  let recWindowLaunched = false;
  let recWindowUrl = '';
  let recWindowIsCross = false;
  let recFramePollTimer = null;

  const saveScreenModal = document.getElementById('save-screen-modal');
  const saveScreenDuration = document.getElementById('save-screen-duration');
  const saveScreenLimitNotice = document.getElementById('save-screen-limit-notice');
  const saveScreenLimitMsg = document.getElementById('save-screen-limit-msg');
  const saveScreenTitle = document.getElementById('save-screen-title');
  const confirmScreenSaveBtn = document.getElementById('confirm-screen-save-btn');
  const discardScreenSaveBtn = document.getElementById('discard-screen-save-btn');
  const saveScreenProgress = document.getElementById('save-screen-progress');
  const saveScreenActions = document.getElementById('save-screen-actions');

  let player = null;
  let activeId = null;
  let activeDataType = 'cast';
  window.activeId = activeId;
  window.activeDataType = activeDataType;

  // --- Image Lightbox Modal Functions ---
  let cachedDiagramBases = new Set();

  function getBaseFromImageUrl(url) {
    if (!url) return null;
    try {
      const clean = url.split('?')[0].split('#')[0];
      const filename = clean.substring(clean.lastIndexOf('/') + 1);
      const match = filename.match(/^([a-zA-Z0-9_.\-]+)\.(?:svg|png|dot)$/i);
      return match ? decodeURIComponent(match[1]) : null;
    } catch (err) {
      return null;
    }
  }

  function refreshCachedDiagramBases() {
    if (!activeWalkthrough) return Promise.resolve();
    return fetch(`/walkthroughs/${encodeURIComponent(activeWalkthrough)}/graphviz/sources`, {
      credentials: 'same-origin'
    })
    .then(res => res.json())
    .then(list => {
      if (Array.isArray(list)) {
        cachedDiagramBases = new Set(list.map(item => item && item.base).filter(Boolean));
      }
    })
    .catch(() => {});
  }

  let imageModalScale = 1;
  let imageModalPanX = 0;
  let imageModalPanY = 0;
  let imageModalDragging = false;
  let imageModalDragStart = null;
  let imageModalHasDragged = false;

  function applyImageModalTransform() {
    if (!imageModalImg) return;
    imageModalImg.style.transform = `translate(${imageModalPanX}px, ${imageModalPanY}px) scale(${imageModalScale})`;
    if (imageModalZoomReset) {
      imageModalZoomReset.textContent = Math.round(imageModalScale * 100) + '%';
    }
  }

  function initImageModalDimensions() {
    if (!imageModalStage || !imageModalImg) return;
    const cw = imageModalStage.clientWidth;
    const ch = imageModalStage.clientHeight;
    if (cw <= 0 || ch <= 0) return;

    const nw = imageModalImg.naturalWidth || imageModalImg.clientWidth || 800;
    const nh = imageModalImg.naturalHeight || imageModalImg.clientHeight || 600;

    if (imageModalImg.naturalWidth && imageModalImg.naturalHeight) {
      imageModalImg.style.width = imageModalImg.naturalWidth + 'px';
      imageModalImg.style.height = imageModalImg.naturalHeight + 'px';
    } else {
      imageModalImg.style.width = '';
      imageModalImg.style.height = '';
    }

    const pad = 40;
    const availW = Math.max(50, cw - pad);
    const availH = Math.max(50, ch - pad);
    const fitScale = Math.min(availW / nw, availH / nh);
    // If image exceeds viewport, fit it; otherwise start at 100% actual size
    const startScale = fitScale < 1 ? fitScale : 1.0;
    imageModalScale = Math.min(15, Math.max(0.05, startScale));
    imageModalPanX = (cw - nw * imageModalScale) / 2;
    imageModalPanY = (ch - nh * imageModalScale) / 2;
    applyImageModalTransform();
  }

  function fitImageModalToView() {
    if (!imageModalStage || !imageModalImg) return;
    const cw = imageModalStage.clientWidth;
    const ch = imageModalStage.clientHeight;
    if (cw <= 0 || ch <= 0) return;

    const nw = imageModalImg.naturalWidth || imageModalImg.clientWidth || 800;
    const nh = imageModalImg.naturalHeight || imageModalImg.clientHeight || 600;
    const pad = 40;
    const availW = Math.max(50, cw - pad);
    const availH = Math.max(50, ch - pad);
    const scale = Math.min(15, Math.max(0.05, Math.min(availW / nw, availH / nh)));

    imageModalScale = scale;
    imageModalPanX = (cw - nw * scale) / 2;
    imageModalPanY = (ch - nh * scale) / 2;
    applyImageModalTransform();
  }

  function resetImageModalZoom() {
    if (!imageModalStage || !imageModalImg) return;
    const cw = imageModalStage.clientWidth;
    const ch = imageModalStage.clientHeight;
    if (cw <= 0 || ch <= 0) return;

    const nw = imageModalImg.naturalWidth || imageModalImg.clientWidth || 800;
    const nh = imageModalImg.naturalHeight || imageModalImg.clientHeight || 600;

    imageModalScale = 1.0;
    imageModalPanX = (cw - nw) / 2;
    imageModalPanY = (ch - nh) / 2;
    applyImageModalTransform();
  }

  function zoomImageModalAt(clientX, clientY, factor) {
    if (!imageModalStage || !imageModalImg) return;
    const rect = imageModalStage.getBoundingClientRect();
    const cx = clientX - rect.left;
    const cy = clientY - rect.top;
    const previous = imageModalScale;
    const next = Math.min(15, Math.max(0.05, previous * factor));
    if (next === previous) return;

    imageModalPanX = cx - (cx - imageModalPanX) * (next / previous);
    imageModalPanY = cy - (cy - imageModalPanY) * (next / previous);
    imageModalScale = next;
    applyImageModalTransform();
  }

  function zoomImageModalBy(factor) {
    if (!imageModalStage) return;
    const rect = imageModalStage.getBoundingClientRect();
    zoomImageModalAt(rect.left + rect.width / 2, rect.top + rect.height / 2, factor);
  }

  if (imageModalZoomIn) {
    imageModalZoomIn.addEventListener('click', (e) => {
      e.stopPropagation();
      zoomImageModalBy(1.25);
    });
  }

  if (imageModalZoomOut) {
    imageModalZoomOut.addEventListener('click', (e) => {
      e.stopPropagation();
      zoomImageModalBy(1 / 1.25);
    });
  }

  if (imageModalZoomReset) {
    imageModalZoomReset.addEventListener('click', (e) => {
      e.stopPropagation();
      resetImageModalZoom();
    });
  }

  if (imageModalZoomFit) {
    imageModalZoomFit.addEventListener('click', (e) => {
      e.stopPropagation();
      fitImageModalToView();
    });
  }

  if (imageModalStage) {
    imageModalStage.addEventListener('wheel', (e) => {
      if (!imageModalImg || !imageModalImg.src) return;
      e.preventDefault();
      zoomImageModalAt(e.clientX, e.clientY, e.deltaY < 0 ? 1.15 : (1 / 1.15));
    }, { passive: false });

    imageModalStage.addEventListener('pointerdown', (e) => {
      if (e.button !== 0) return;
      if (e.target.closest('button') || e.target.closest('a')) return;
      if (!imageModalImg || !imageModalImg.src) return;
      imageModalDragging = true;
      imageModalHasDragged = false;
      imageModalDragStart = { x: e.clientX, y: e.clientY, panX: imageModalPanX, panY: imageModalPanY };
    });

    imageModalStage.addEventListener('pointermove', (e) => {
      if (!imageModalDragging || !imageModalDragStart) return;
      const dx = e.clientX - imageModalDragStart.x;
      const dy = e.clientY - imageModalDragStart.y;
      if (!imageModalHasDragged) {
        if (Math.abs(dx) > 3 || Math.abs(dy) > 3) {
          imageModalHasDragged = true;
          imageModalStage.style.cursor = 'grabbing';
          if (imageModalStage.setPointerCapture) {
            try { imageModalStage.setPointerCapture(e.pointerId); } catch (err) {}
          }
        } else {
          return;
        }
      }
      e.preventDefault();
      imageModalPanX = imageModalDragStart.panX + dx;
      imageModalPanY = imageModalDragStart.panY + dy;
      applyImageModalTransform();
    });

    const endImageModalDrag = (e) => {
      if (!imageModalDragging) return;
      imageModalDragging = false;
      imageModalDragStart = null;
      imageModalStage.style.cursor = 'grab';
      if (e && imageModalStage.releasePointerCapture && e.pointerId !== undefined) {
        try { imageModalStage.releasePointerCapture(e.pointerId); } catch (err) {}
      }
    };

    imageModalStage.addEventListener('pointerup', endImageModalDrag);
    imageModalStage.addEventListener('pointercancel', endImageModalDrag);

    imageModalStage.addEventListener('dblclick', (e) => {
      if (e.target.closest('button') || e.target.closest('a')) return;
      e.preventDefault();
      // Toggle between 100% actual size and fit to view
      if (Math.abs(imageModalScale - 1.0) < 0.05) {
        fitImageModalToView();
      } else {
        zoomImageModalAt(e.clientX, e.clientY, 1.0 / imageModalScale);
      }
    });
  }

  function openGraphvizModal(base) {
    if (window.MarkdownEditor && typeof window.MarkdownEditor.openGraphviz === 'function') {
      return window.MarkdownEditor.openGraphviz(base);
    }
    if (typeof window.openGraphvizModal === 'function') {
      return window.openGraphvizModal(base);
    }
  }

  function openImageModal(src, alt, title) {
    if (!imageModal || !imageModalImg) return;
    imageModalImg.src = src;
    imageModalImg.alt = alt || '';
    if (imageModalCaption) {
      const cap = (alt || title || '').trim();
      imageModalCaption.textContent = cap;
      imageModalCaption.style.display = cap ? 'block' : 'none';
    }
    if (imageModalExternal) imageModalExternal.href = src;

    imageModalDragging = false;
    imageModalDragStart = null;
    imageModalHasDragged = false;
    imageModalScale = 1;
    imageModalPanX = 0;
    imageModalPanY = 0;

    imageModal.style.display = 'flex';

    const setupImg = () => {
      initImageModalDimensions();
    };

    if (imageModalImg.complete && imageModalImg.naturalWidth) {
      requestAnimationFrame(setupImg);
    } else {
      imageModalImg.onload = () => {
        setupImg();
      };
    }

    const base = getBaseFromImageUrl(src);
    if (imageModalEditDiagram) {
      if (base && cachedDiagramBases.has(base)) {
        imageModalEditDiagram.style.display = 'flex';
        imageModalEditDiagram.onclick = (e) => {
          e.stopPropagation();
          closeImageModal();
          openGraphvizModal(base);
        };
      } else if (base) {
        imageModalEditDiagram.style.display = 'none';
        fetch(`/walkthroughs/${encodeURIComponent(activeWalkthrough || '')}/graphviz/sources/${encodeURIComponent(base)}`, {
          credentials: 'same-origin'
        })
        .then(res => res.json())
        .then(data => {
          if (data.ok && imageModal && imageModal.style.display === 'flex' && imageModalImg.src === src) {
            cachedDiagramBases.add(base);
            imageModalEditDiagram.style.display = 'flex';
            imageModalEditDiagram.onclick = (e) => {
              e.stopPropagation();
              closeImageModal();
              openGraphvizModal(base);
            };
          }
        })
        .catch(() => {});
      } else {
        imageModalEditDiagram.style.display = 'none';
      }
    }
  }

  function closeImageModal() {
    if (!imageModal) return;
    imageModal.style.display = 'none';
    if (imageModalImg) {
      imageModalImg.src = '';
      imageModalImg.style.width = '';
      imageModalImg.style.height = '';
      imageModalImg.style.transform = '';
    }
    if (imageModalEditDiagram) imageModalEditDiagram.style.display = 'none';
    imageModalDragging = false;
    imageModalDragStart = null;
    imageModalHasDragged = false;
  }
  window.openImageModal = openImageModal;
  window.closeImageModal = closeImageModal;

  if (imageModalClose) {
    imageModalClose.addEventListener('click', (e) => {
      e.stopPropagation();
      closeImageModal();
    });
  }

  const imageModalAnnotate = document.getElementById('image-modal-annotate');
  if (imageModalAnnotate) {
    imageModalAnnotate.addEventListener('click', (e) => {
      e.stopPropagation();
      if (!imageModalImg || !imageModalImg.src) return;
      const src = imageModalImg.src;
      const alt = imageModalImg.alt || '';
      closeImageModal();
      if (typeof window.openScreenshotEditor === 'function') {
        window.openScreenshotEditor(src, { alt: alt });
      }
    });
  }



  // --- Picture Inspector ---
  const picInspectorModal = document.getElementById('pic-inspector-modal');
  const picInspectorSummary = document.getElementById('pic-inspector-summary');
  const picInspectorList = document.getElementById('pic-inspector-list');
  const picInspectorBtn = document.getElementById('pic-inspector-btn');
  const picInspectorSelectAll = document.getElementById('pic-inspector-select-all');
  const picInspectorDeleteSelected = document.getElementById('pic-inspector-delete-selected');
  const picSelectedCount = document.getElementById('pic-selected-count');

  let picInspectorItems = [];
  let picInspectorActiveTab = 'all';
  let picInspectorSelectedFiles = new Set();

  function escapeHtml(str) {
    return String(str == null ? '' : str).replace(/[&<>"']/g, (c) => ({
      '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;'
    }[c]));
  }

  function picInspectorImageUrl(name) {
    return '/recordings/' + encodeURIComponent(activeWalkthrough) + '/images/' + encodeURIComponent(name);
  }

  function picInspectorMarkdownFor(filename) {
    const alt = String(filename || '').replace(/\.[^.]+$/, '');
    return `![${alt}](images/${filename})`;
  }

  function updatePicInspectorSelectionUI() {
    if (picSelectedCount) {
      picSelectedCount.textContent = picInspectorSelectedFiles.size;
    }
    if (picInspectorDeleteSelected) {
      const hasSel = picInspectorSelectedFiles.size > 0;
      picInspectorDeleteSelected.disabled = !hasSel;
      picInspectorDeleteSelected.style.opacity = hasSel ? '1' : '0.5';
      picInspectorDeleteSelected.style.cursor = hasSel ? 'pointer' : 'not-allowed';
    }
    if (picInspectorSelectAll) {
      const visibleCheckboxes = picInspectorList ? picInspectorList.querySelectorAll('.pic-inspector-check') : [];
      if (visibleCheckboxes.length > 0) {
        const allChecked = Array.from(visibleCheckboxes).every(cb => cb.checked);
        picInspectorSelectAll.checked = allChecked;
        picInspectorSelectAll.indeterminate = !allChecked && Array.from(visibleCheckboxes).some(cb => cb.checked);
      } else {
        picInspectorSelectAll.checked = false;
        picInspectorSelectAll.indeterminate = false;
      }
    }
  }

  function renderPicInspectorRow(item) {
    const usedBy = (item.used_by || []).map(u => (u.step ? '#' + u.step + ' ' : '') + escapeHtml(u.title)).join(', ');
    const status = item.missing
      ? '<span style="background:#7f1d1d; color:#fecaca; padding:1px 6px; border-radius:3px; font-size:0.75em;">Missing</span>'
      : item.used
        ? '<span style="background:#14532d; color:#bbf7d0; padding:1px 6px; border-radius:3px; font-size:0.75em;">Used</span>'
        : '<span style="background:#78350f; color:#fde68a; padding:1px 6px; border-radius:3px; font-size:0.75em;">Unused</span>';
    const diagramBadge = item.diagram
      ? '<span style="background:#0369a1; color:#bae6fd; padding:1px 6px; border-radius:3px; font-size:0.75em;"><i class="fas fa-project-diagram" style="margin-right:3px;"></i>Diagram</span>'
      : '';
    const thumb = item.missing
      ? '<div style="width:48px; height:36px; display:flex; align-items:center; justify-content:center; background:#1e293b; border:1px solid #475569; border-radius:4px; color:#ef4444;"><i class="fas fa-image-slash"></i></div>'
      : `<img src="${picInspectorImageUrl(item.filename)}" alt="" loading="lazy" class="pic-inspector-thumb" data-filename="${escapeHtml(item.filename)}" data-url="${escapeHtml(picInspectorImageUrl(item.filename))}" title="Click to preview full size (hover for quick preview)" style="width:48px; height:36px; object-fit:cover; border-radius:4px; border:1px solid #475569; background:#1e293b; cursor:pointer;" />`;
    const detail = item.missing
      ? 'Referenced but file is missing'
      : (item.used ? 'Used in: ' + usedBy : 'Not referenced by any note');
    const globalTag = item.global_only ? ' <span style="color:#94a3b8; font-size:0.75em;">(global fallback)</span>' : '';

    const canDelete = (!item.used && !item.missing && item.scoped);
    const isChecked = picInspectorSelectedFiles.has(item.filename);

    const checkboxHtml = canDelete
      ? `<input type="checkbox" class="pic-inspector-check" data-filename="${escapeHtml(item.filename)}" ${isChecked ? 'checked' : ''} title="Select to delete" style="width:16px; height:16px; cursor:pointer; accent-color:#ef4444; flex-shrink:0;" />`
      : `<div style="width:16px; height:16px; flex-shrink:0;"></div>`;

    const btnStyle = 'width:28px; height:28px; display:inline-flex; align-items:center; justify-content:center; padding:0; background:#1e293b; border:1px solid #334155; border-radius:4px; cursor:pointer; transition:all 0.15s; font-size:0.85em;';

    const previewBtn = item.missing ? '' :
      `<button type="button" class="pic-inspector-preview" data-filename="${escapeHtml(item.filename)}" data-url="${escapeHtml(picInspectorImageUrl(item.filename))}" title="Preview full size in lightbox" style="${btnStyle} color:#38bdf8;" onmouseover="this.style.background='#334155'" onmouseout="this.style.background='#1e293b'"><i class="fas fa-eye"></i></button>`;

    const annotateBtn = item.missing ? '' :
      `<button type="button" class="pic-inspector-annotate" data-filename="${escapeHtml(item.filename)}" data-url="${escapeHtml(picInspectorImageUrl(item.filename))}" title="Annotate picture in screenshot editor" style="${btnStyle} color:#10b981;" onmouseover="this.style.background='#334155'" onmouseout="this.style.background='#1e293b'"><i class="fas fa-paint-brush"></i></button>`;

    const copyBtn = item.missing ? '' :
      `<button type="button" class="pic-inspector-copy" data-filename="${escapeHtml(item.filename)}" title="Copy Markdown link" style="${btnStyle} color:#cbd5e1;" onmouseover="this.style.background='#334155'" onmouseout="this.style.background='#1e293b'"><i class="fas fa-link" style="color:#38bdf8;"></i></button>`;

    const editBtn = (item.diagram && item.diagram_base) ?
      `<button type="button" class="pic-inspector-edit" data-base="${escapeHtml(item.diagram_base)}" title="Edit diagram source" style="${btnStyle} background:#0284c7; border-color:#0284c7; color:#ffffff;" onmouseover="this.style.background='#0369a1'" onmouseout="this.style.background='#0284c7'"><i class="fas fa-edit"></i></button>` : '';

    const deleteBtn = canDelete ?
      `<button type="button" class="pic-inspector-delete" data-filename="${escapeHtml(item.filename)}" title="Delete picture" style="${btnStyle} background:#450a0a; border-color:#991b1b; color:#fca5a5;" onmouseover="this.style.background='#7f1d1d'" onmouseout="this.style.background='#450a0a'"><i class="fas fa-trash-alt"></i></button>` : '';

    return `<div class="pic-inspector-row" data-filename="${escapeHtml(item.filename)}" style="display:flex; align-items:center; gap:10px; padding:8px 12px; border-bottom:1px solid #1e293b; transition:background 0.15s;">
      ${checkboxHtml}
      ${thumb}
      <div style="flex:1; min-width:0;">
        <div style="display:flex; align-items:center; gap:6px; flex-wrap:wrap;">
          <span style="font-family:ui-monospace, monospace; font-size:0.82em; color:#f8fafc; font-weight:500; overflow:hidden; text-overflow:ellipsis; white-space:nowrap;" title="${escapeHtml(item.filename)}">${escapeHtml(item.filename)}</span>
          ${status}${diagramBadge}${globalTag}
        </div>
        <div style="color:#94a3b8; font-size:0.76em; margin-top:2px; overflow:hidden; text-overflow:ellipsis; white-space:nowrap;" title="${escapeHtml(detail)}">${detail}</div>
      </div>
      <div style="color:#64748b; font-size:0.76em; white-space:nowrap; margin-right:4px;">${formatFileSize(item.size)}</div>
      <div style="display:flex; align-items:center; gap:4px; flex-shrink:0;">
        ${previewBtn}
        ${annotateBtn}
        ${copyBtn}
        ${editBtn}
        ${deleteBtn}
      </div>
    </div>`;
  }

  function renderPicInspector(items) {
    if (!picInspectorList) return;
    picInspectorItems = items || [];
    picInspectorItems.forEach(i => {
      if (i.diagram && i.diagram_base) cachedDiagramBases.add(i.diagram_base);
    });

    const used = picInspectorItems.filter(i => i.used && !i.missing);
    const unused = picInspectorItems.filter(i => !i.used && !i.missing);
    const missing = picInspectorItems.filter(i => i.missing);

    // Update tab counts
    const tabCountUnused = document.getElementById('pic-tab-count-unused');
    const tabCountUsed = document.getElementById('pic-tab-count-used');
    const tabCountAll = document.getElementById('pic-tab-count-all');
    if (tabCountUnused) tabCountUnused.textContent = unused.length;
    if (tabCountUsed) tabCountUsed.textContent = used.length;
    if (tabCountAll) tabCountAll.textContent = picInspectorItems.length;

    if (picInspectorSummary) {
      picInspectorSummary.textContent = `${picInspectorItems.length} picture${picInspectorItems.length === 1 ? '' : 's'} · ${used.length} used · ${unused.length} unused${missing.length > 0 ? ' · ' + missing.length + ' missing' : ''}`;
    }

    // Clean up selected files that no longer exist
    const currentUnusedNames = new Set(unused.map(i => i.filename));
    picInspectorSelectedFiles.forEach(fn => {
      if (!currentUnusedNames.has(fn)) picInspectorSelectedFiles.delete(fn);
    });

    // Update tab button styles
    const tabBtns = document.querySelectorAll('.pic-inspector-tab-btn');
    tabBtns.forEach(btn => {
      const t = btn.getAttribute('data-tab');
      if (t === picInspectorActiveTab) {
        btn.style.background = '#0284c7';
        btn.style.color = '#ffffff';
      } else {
        btn.style.background = 'transparent';
        btn.style.color = '#94a3b8';
      }
    });

    if (picInspectorItems.length === 0) {
      picInspectorList.innerHTML = '<div style="padding: 24px; text-align: center; color: #94a3b8; font-size: 0.9em;">No pictures in this walkthrough set.</div>';
      updatePicInspectorSelectionUI();
      return;
    }

    let html = '';
    if (picInspectorActiveTab === 'unused') {
      if (unused.length === 0) {
        html = '<div style="padding: 24px; text-align: center; color: #94a3b8; font-size: 0.9em;"><i class="fas fa-check-circle" style="color:#10b981; margin-right:6px;"></i>No unused pictures. All pictures are referenced by walkthrough notes.</div>';
      } else {
        html = unused.map(item => renderPicInspectorRow(item)).join('');
      }
    } else if (picInspectorActiveTab === 'used') {
      if (used.length === 0) {
        html = '<div style="padding: 24px; text-align: center; color: #94a3b8; font-size: 0.9em;">No used pictures in this walkthrough set.</div>';
      } else {
        html = used.map(item => renderPicInspectorRow(item)).join('');
      }
    } else {
      // 'all' tab: render 2 clear sections with sticky headers!
      if (unused.length > 0) {
        html += `<div style="background:#1e293b; padding:6px 12px; font-size:0.78em; font-weight:600; color:#fde68a; display:flex; align-items:center; justify-content:space-between; border-bottom:1px solid #334155; position:sticky; top:0; z-index:2;">
          <span style="display:flex; align-items:center; gap:6px;"><i class="fas fa-trash-alt" style="color:#f59e0b;"></i> Unused Pictures (${unused.length})</span>
          <span style="font-size:0.88em; font-weight:normal; color:#94a3b8;">Not referenced in any note</span>
        </div>`;
        html += unused.map(item => renderPicInspectorRow(item)).join('');
      }
      if (used.length > 0) {
        html += `<div style="background:#1e293b; padding:6px 12px; font-size:0.78em; font-weight:600; color:#86efac; display:flex; align-items:center; justify-content:space-between; border-bottom:1px solid #334155; position:sticky; top:0; z-index:2;">
          <span style="display:flex; align-items:center; gap:6px;"><i class="fas fa-check-circle" style="color:#10b981;"></i> Used Pictures (${used.length})</span>
          <span style="font-size:0.88em; font-weight:normal; color:#94a3b8;">Referenced in steps</span>
        </div>`;
        html += used.map(item => renderPicInspectorRow(item)).join('');
      }
      if (missing.length > 0) {
        html += `<div style="background:#1e293b; padding:6px 12px; font-size:0.78em; font-weight:600; color:#fca5a5; display:flex; align-items:center; justify-content:space-between; border-bottom:1px solid #334155; position:sticky; top:0; z-index:2;">
          <span style="display:flex; align-items:center; gap:6px;"><i class="fas fa-exclamation-triangle" style="color:#ef4444;"></i> Missing Picture References (${missing.length})</span>
          <span style="font-size:0.88em; font-weight:normal; color:#94a3b8;">Referenced in notes but file is missing</span>
        </div>`;
        html += missing.map(item => renderPicInspectorRow(item)).join('');
      }
    }

    picInspectorList.innerHTML = html;
    updatePicInspectorSelectionUI();
    attachPicInspectorListeners();
  }

  function attachPicInspectorListeners() {
    if (!picInspectorList) return;

    // Checkboxes
    picInspectorList.querySelectorAll('.pic-inspector-check').forEach(cb => {
      cb.addEventListener('change', () => {
        const fn = cb.getAttribute('data-filename');
        if (!fn) return;
        if (cb.checked) {
          picInspectorSelectedFiles.add(fn);
        } else {
          picInspectorSelectedFiles.delete(fn);
        }
        updatePicInspectorSelectionUI();
      });
    });

    // Thumb & preview clicks
    picInspectorList.querySelectorAll('.pic-inspector-thumb, .pic-inspector-preview').forEach(el => {
      el.addEventListener('click', (e) => {
        e.stopPropagation();
        const filename = el.getAttribute('data-filename');
        const url = el.getAttribute('data-url');
        if (!url) return;
        hidePicInspectorHover();
        if (typeof openImageModal === 'function') {
          openImageModal(url, filename, filename);
        }
      });
    });

    // Thumb hovers
    const hoverBox = document.getElementById('pic-inspector-hover-preview');
    const hoverImg = document.getElementById('pic-inspector-hover-img');
    if (hoverBox && hoverImg) {
      picInspectorList.querySelectorAll('.pic-inspector-thumb').forEach(thumb => {
        thumb.addEventListener('mouseenter', (e) => {
          const url = thumb.getAttribute('data-url');
          if (!url) return;
          hoverImg.src = url;
          hoverBox.style.display = 'block';
          positionPicInspectorHover(e);
        });
        thumb.addEventListener('mousemove', (e) => {
          positionPicInspectorHover(e);
        });
        thumb.addEventListener('mouseleave', () => {
          hoverBox.style.display = 'none';
          hoverImg.removeAttribute('src');
        });
      });
    }

    // Annotate button
    picInspectorList.querySelectorAll('.pic-inspector-annotate').forEach(btn => {
      btn.addEventListener('click', () => {
        const filename = btn.getAttribute('data-filename');
        const url = btn.getAttribute('data-url');
        if (!filename || !url) return;
        if (picInspectorModal) picInspectorModal.style.display = 'none';
        if (typeof window.openScreenshotEditor === 'function') {
          window.openScreenshotEditor(url, { filename });
        }
      });
    });

    // Copy link button
    picInspectorList.querySelectorAll('.pic-inspector-copy').forEach(btn => {
      btn.addEventListener('click', () => {
        const filename = btn.getAttribute('data-filename');
        if (!filename) return;
        copyTextToClipboard(picInspectorMarkdownFor(filename));
        const original = btn.innerHTML;
        btn.innerHTML = '<i class="fas fa-check" style="color:#10b981;"></i>';
        btn.title = 'Copied!';
        setTimeout(() => {
          btn.innerHTML = original;
          btn.title = 'Copy Markdown link';
        }, 1200);
      });
    });

    // Edit diagram button
    picInspectorList.querySelectorAll('.pic-inspector-edit').forEach(btn => {
      btn.addEventListener('click', () => {
        const base = btn.getAttribute('data-base');
        if (!base) return;
        if (picInspectorModal) picInspectorModal.style.display = 'none';
        openGraphvizModal(base);
      });
    });

    // Single delete button
    picInspectorList.querySelectorAll('.pic-inspector-delete').forEach(btn => {
      btn.addEventListener('click', () => deletePicInspectorImage(btn.getAttribute('data-filename'), btn));
    });
  }

  async function loadPicInspector(options = {}) {
    if (!picInspectorList) return;
    const preserveScroll = options.preserveScroll === true;
    const savedScrollTop = picInspectorList.scrollTop;

    if (!preserveScroll || !picInspectorItems || picInspectorItems.length === 0) {
      picInspectorList.innerHTML = '<div style="padding: 24px; text-align: center; color: #94a3b8; font-size: 0.9em;"><i class="fas fa-spinner fa-spin"></i> Loading pictures...</div>';
    } else {
      picInspectorList.style.opacity = '0.7';
    }

    try {
      const res = await fetch('/walkthroughs/' + encodeURIComponent(activeWalkthrough) + '/images/inventory', { credentials: 'same-origin' });
      if (!res.ok) throw new Error('HTTP ' + res.status);
      const items = await res.json();
      renderPicInspector(Array.isArray(items) ? items : []);
      if (preserveScroll && picInspectorList) {
        picInspectorList.scrollTop = savedScrollTop;
      }
    } catch (err) {
      console.error('Picture inspector load failed:', err);
      if (picInspectorSummary) picInspectorSummary.textContent = '';
      picInspectorList.innerHTML = '<div style="padding: 24px; text-align: center; color: #ef4444; font-size: 0.9em;"><i class="fas fa-exclamation-triangle"></i> Failed to load pictures.</div>';
    } finally {
      if (picInspectorList) picInspectorList.style.opacity = '1';
    }
  }

  async function deletePicInspectorImage(filename, btn) {
    if (!filename) return;
    if (!confirm('Delete unused picture "' + filename + '"?')) return;
    const row = btn ? btn.closest('.pic-inspector-row') : null;
    if (row) {
      row.style.opacity = '0.3';
      row.style.pointerEvents = 'none';
    }
    const fd = new FormData();
    fd.append('filename', filename);
    try {
      const res = await fetch('/walkthroughs/' + encodeURIComponent(activeWalkthrough) + '/images/delete', { method: 'POST', credentials: 'same-origin', body: fd });
      const data = await res.json().catch(() => ({}));
      if (!res.ok || !data.ok) throw new Error(data.error || ('HTTP ' + res.status));
      picInspectorSelectedFiles.delete(filename);
      if (row) row.remove();
      loadPicInspector({ preserveScroll: true });
    } catch (err) {
      if (row) {
        row.style.opacity = '1';
        row.style.pointerEvents = 'auto';
      }
      alert('Failed to delete picture: ' + err.message);
    }
  }

  if (picInspectorDeleteSelected) {
    picInspectorDeleteSelected.addEventListener('click', async () => {
      const files = Array.from(picInspectorSelectedFiles);
      if (files.length === 0) return;
      if (!confirm(`Delete ${files.length} selected picture${files.length === 1 ? '' : 's'}?`)) return;

      picInspectorDeleteSelected.disabled = true;
      picInspectorDeleteSelected.innerHTML = '<i class="fas fa-spinner fa-spin"></i> Deleting...';

      const fd = new FormData();
      fd.append('filenames', JSON.stringify(files));

      try {
        const res = await fetch('/walkthroughs/' + encodeURIComponent(activeWalkthrough) + '/images/delete', {
          method: 'POST',
          credentials: 'same-origin',
          body: fd
        });
        const data = await res.json().catch(() => ({}));
        if (!res.ok || !data.ok) throw new Error(data.error || ('HTTP ' + res.status));
        picInspectorSelectedFiles.clear();
        loadPicInspector({ preserveScroll: true });
      } catch (err) {
        alert('Failed to delete selected pictures: ' + err.message);
        loadPicInspector({ preserveScroll: true });
      } finally {
        if (picInspectorDeleteSelected) {
          picInspectorDeleteSelected.innerHTML = '<i class="fas fa-trash-alt"></i> Delete Selected (<span id="pic-selected-count">0</span>)';
        }
      }
    });
  }

  if (picInspectorSelectAll) {
    picInspectorSelectAll.addEventListener('change', () => {
      const isChecked = picInspectorSelectAll.checked;
      const visibleCheckboxes = picInspectorList ? picInspectorList.querySelectorAll('.pic-inspector-check') : [];
      visibleCheckboxes.forEach(cb => {
        cb.checked = isChecked;
        const fn = cb.getAttribute('data-filename');
        if (fn) {
          if (isChecked) picInspectorSelectedFiles.add(fn);
          else picInspectorSelectedFiles.delete(fn);
        }
      });
      updatePicInspectorSelectionUI();
    });
  }

  document.querySelectorAll('.pic-inspector-tab-btn').forEach(btn => {
    btn.addEventListener('click', () => {
      const tab = btn.getAttribute('data-tab');
      if (tab) {
        picInspectorActiveTab = tab;
        renderPicInspector(picInspectorItems);
      }
    });
  });

  function positionPicInspectorHover(e) {
    const hoverBox = document.getElementById('pic-inspector-hover-preview');
    if (!hoverBox || hoverBox.style.display === 'none') return;
    const pad = 16;
    let x = e.clientX + pad;
    let y = e.clientY - 60;
    const boxW = hoverBox.offsetWidth || 300;
    const boxH = hoverBox.offsetHeight || 220;
    if (x + boxW > window.innerWidth) x = e.clientX - boxW - pad;
    if (y + boxH > window.innerHeight) y = window.innerHeight - boxH - pad;
    if (y < pad) y = pad;
    hoverBox.style.left = `${Math.max(pad, x)}px`;
    hoverBox.style.top = `${Math.max(pad, y)}px`;
  }

  function hidePicInspectorHover() {
    const hoverBox = document.getElementById('pic-inspector-hover-preview');
    const hoverImg = document.getElementById('pic-inspector-hover-img');
    if (hoverBox) hoverBox.style.display = 'none';
    if (hoverImg) hoverImg.removeAttribute('src');
  }

  if (picInspectorBtn) {
    picInspectorBtn.addEventListener('click', () => {
      if (picInspectorModal) picInspectorModal.style.display = 'block';
      loadPicInspector();
    });
  }

  window.addEventListener('keydown', (e) => {
    if (e.key === 'Escape' && picInspectorModal && picInspectorModal.style.display === 'block') {
      hidePicInspectorHover();
      picInspectorModal.style.display = 'none';
    }
  });


  // supported on purpose: they change when steps are reordered.
  function stepIdFromHref(href) {
    const h = (href || '').trim();
    if (h.startsWith('#step-')) return h.slice(6);
    if (h.startsWith('step:')) return h.slice(5);
    return null;
  }

  if (mdPreviewPane) {
    mdPreviewPane.addEventListener('click', (e) => {
      const link = e.target.closest('a');
      if (!link) return;
      const id = stepIdFromHref(link.getAttribute('href'));
      if (!id) return;
      const target = document.querySelector(`.rec-item[data-id="${CSS.escape(id)}"]`);
      if (!target) return;
      e.preventDefault();
      selectRecording(target, true);
      target.scrollIntoView({ block: 'nearest', behavior: 'smooth' });
    });
  }

  // --- Step Context Menu (right-click -> copy Markdown link) ---
  function copyTextToClipboard(text) {
    // Synchronous path first: WebKit requires a live user activation for
    // execCommand('copy'), and the async clipboard call may not have it.
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

  function hideStepContextMenu() {
    if (stepContextMenu) stepContextMenu.style.display = 'none';
    stepContextBtn = null;
  }

  function hideImageContextMenu() {
    if (mdImgContextMenu) mdImgContextMenu.style.display = 'none';
    currentContextImg = null;
  }

  function downloadImageOrDiagram(src, suggestedName) {
    if (!src) return;
    let filename = (suggestedName || '').trim();
    if (!filename) {
      try {
        const u = new URL(src, window.location.href);
        filename = decodeURIComponent(u.pathname.split('/').pop() || '');
      } catch (_) {
        filename = 'image';
      }
    }
    filename = (filename || 'image').split('?')[0];
    if (!filename.includes('.')) {
      filename += '.png';
    }

    if (src.startsWith('data:')) {
      const a = document.createElement('a');
      a.href = src;
      a.download = filename;
      document.body.appendChild(a);
      a.click();
      document.body.removeChild(a);
      return;
    }

    // Blob download to ensure browser download attribute behavior
    fetch(src, { credentials: 'same-origin' })
      .then(res => {
        if (!res.ok) throw new Error('Download request failed');
        return res.blob();
      })
      .then(blob => {
        const blobUrl = URL.createObjectURL(blob);
        const a = document.createElement('a');
        a.href = blobUrl;
        a.download = filename;
        document.body.appendChild(a);
        a.click();
        document.body.removeChild(a);
        setTimeout(() => URL.revokeObjectURL(blobUrl), 1000);
      })
      .catch(() => {
        const a = document.createElement('a');
        a.href = src;
        a.download = filename;
        a.target = '_blank';
        document.body.appendChild(a);
        a.click();
        document.body.removeChild(a);
      });
  }
  window.downloadImageOrDiagram = downloadImageOrDiagram;

  function stepLinkFor(btn) {
    const id = btn.getAttribute('data-id') || '';
    if (!id) return null;
    const titleNode = btn.querySelector('.item-title');
    const rawTitle = (btn.getAttribute('data-title') || (titleNode ? titleNode.textContent : '') || 'Step').trim();
    const label = rawTitle.replace(/[[\]]/g, '\\$&').replace(/\s+/g, ' ');
    return `[${label}](#step-${id})`;
  }

  document.addEventListener('contextmenu', (e) => {
    // 1. Sidebar step item context menu
    const btn = e.target.closest('.rec-item');
    if (btn && stepContextMenu) {
      hideImageContextMenu();
      e.preventDefault();
      stepContextBtn = btn;

      const id = btn.getAttribute('data-id') || '';
      const step = btn.getAttribute('data-step') || '';
      const dataType = btn.getAttribute('data-type') || 'terminal';
      const titleNode = btn.querySelector('.item-title');
      const title = (btn.getAttribute('data-title') || (titleNode ? titleNode.textContent : '') || id || 'Step').trim();
      if (stepContextTitle) stepContextTitle.textContent = (step ? '#' + step + ' ' : '') + title;

      if (stepContextEdit) {
        stepContextEdit.style.display = (dataType === 'markdown') ? 'flex' : 'none';
      }

      const currentStatus = (btn.getAttribute('data-status') || 'none').toLowerCase();
      stepContextMenu.querySelectorAll('.step-status-option').forEach(opt => {
        const optStatus = opt.getAttribute('data-status');
        const check = opt.querySelector('.step-status-active-check');
        if (check) {
          check.style.display = (optStatus === currentStatus) ? 'inline-block' : 'none';
        }
      });

      stepContextMenu.style.display = 'block';
      const rect = stepContextMenu.getBoundingClientRect();
      let x = e.clientX;
      let y = e.clientY;
      if (x + rect.width > window.innerWidth - 8) x = Math.max(8, window.innerWidth - rect.width - 8);
      if (y + rect.height > window.innerHeight - 8) y = Math.max(8, window.innerHeight - rect.height - 8);
      stepContextMenu.style.left = x + 'px';
      stepContextMenu.style.top = y + 'px';
      return;
    }

    // 2. Picture / Diagram context menu in markdown preview pane, lightbox stage, or graphviz preview
    const img = e.target.closest('img');
    if (img && mdImgContextMenu) {
      const inMdPreview = (mdPreviewPane && mdPreviewPane.contains(img)) || img.closest('.markdown-body') || img.closest('#md-preview-pane');
      const inLightbox = img.id === 'image-modal-img' || img.closest('#image-modal-stage');
      const inGvPreview = img.id === 'md-graphviz-preview-img' || img.closest('#md-graphviz-preview');

      if (inMdPreview || inLightbox || inGvPreview) {
        hideStepContextMenu();
        e.preventDefault();
        e.stopPropagation();

        currentContextImg = img;
        const src = img.currentSrc || img.src || '';
        let fname = '';
        try {
          const u = new URL(src, window.location.href);
          fname = decodeURIComponent(u.pathname.split('/').pop() || '');
        } catch (_) {
          fname = (img.alt || 'image').trim();
        }
        fname = (fname || 'image').split('?')[0];

        if (mdImgContextTitle) {
          mdImgContextTitle.textContent = fname || img.alt || 'IMAGE';
        }

        if (mdImgContextOpenTab) {
          mdImgContextOpenTab.href = src;
        }

        // Check if diagram
        const base = getBaseFromImageUrl(src);
        if (mdImgContextEditDiagram) {
          if (base && (cachedDiagramBases.has(base) || /\.svg$/i.test(fname))) {
            mdImgContextEditDiagram.style.display = 'flex';
            mdImgContextEditDiagram.onclick = (ev) => {
              ev.stopPropagation();
              hideImageContextMenu();
              if (typeof closeImageModal === 'function') closeImageModal();
              openGraphvizModal(base);
            };
          } else {
            mdImgContextEditDiagram.style.display = 'none';
          }
        }

        mdImgContextMenu.style.display = 'block';
        const rect = mdImgContextMenu.getBoundingClientRect();
        let x = e.clientX;
        let y = e.clientY;
        if (x + rect.width > window.innerWidth - 8) x = Math.max(8, window.innerWidth - rect.width - 8);
        if (y + rect.height > window.innerHeight - 8) y = Math.max(8, window.innerHeight - rect.height - 8);
        mdImgContextMenu.style.left = `${x}px`;
        mdImgContextMenu.style.top = `${y}px`;
        return;
      }
    }
  });

  function saveStepTitle(id, newTitle, btn) {
    const activeWalkthrough = (window.activeWalkthrough || (typeof getActiveWalkthrough === 'function' ? getActiveWalkthrough() : ''));
    const body = new URLSearchParams({
      title: newTitle,
      walkthrough: activeWalkthrough
    });

    fetch(`/recordings/${encodeURIComponent(id)}/meta`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded;charset=UTF-8',
        'Accept': 'application/json'
      },
      body: body,
      credentials: 'same-origin'
    })
    .then(res => res.json())
    .then(data => {
      if (data && data.ok) {
        const nextId = data.id || id;
        const targetBtn = btn || document.querySelector(`.rec-item[data-id="${CSS.escape(id)}"]`);
        if (targetBtn) {
          targetBtn.setAttribute('data-title', newTitle);
          targetBtn.setAttribute('data-id', nextId);
          targetBtn.setAttribute('data-src', '/recordings/' + encodeURIComponent(nextId));
          const titleSpan = targetBtn.querySelector('.item-title');
          if (titleSpan) titleSpan.textContent = newTitle;

          const wrapper = targetBtn.closest('.rec-item-wrapper') || document.getElementById('step-' + id);
          if (wrapper) {
            wrapper.id = 'step-' + nextId;
            wrapper.setAttribute('data-id', nextId);
          }

          const currentActive = document.querySelector('.rec-item.active');
          const isCurrentActive = (targetBtn === currentActive) || (id === activeId) || (id === window.activeId);
          if (isCurrentActive) {
            const step = targetBtn.getAttribute('data-step');
            if (titleEl) {
              const span = titleEl.querySelector('span');
              const fullTitleText = (step ? '#' + step + ': ' : '') + newTitle;
              if (span) span.textContent = fullTitleText;
              titleEl.title = fullTitleText;
            }
            if (editTitle) editTitle.value = newTitle;

            if (nextId !== id) {
              activeId = nextId;
              window.activeId = nextId;

              const formRecInput = document.getElementById('walkthrough-form-recording');
              if (formRecInput) formRecInput.value = nextId;

              const newSrc = '/recordings/' + encodeURIComponent(nextId);
              if (downloadEl) downloadEl.href = newSrc + '?download=1';
              if (deleteForm) deleteForm.action = newSrc + '/delete';
              if (metaForm) metaForm.action = newSrc + '/meta';

              const url = new URL(window.location);
              url.searchParams.set('recording', nextId);
              window.history.replaceState({}, '', url.toString());

              try {
                if (activeWalkthrough) localStorage.setItem('ctlabs_last_step_' + activeWalkthrough, nextId);
              } catch (e) {}
            }
          }

          if (nextId !== id) {
            if (window.MarkdownEditor && typeof window.MarkdownEditor.renameNote === 'function') {
              window.MarkdownEditor.renameNote(id, nextId);
            }
            window.dispatchEvent(new CustomEvent('recording:renamed', {
              detail: { oldId: id, newId: nextId, title: newTitle }
            }));
          }
        }
      }
    })
    .catch(err => {
      console.error('Failed to update step title:', err);
    });
  }

  const renameStepModal = document.getElementById('rename-step-modal');
  const renameStepForm = document.getElementById('rename-step-form');
  const renameStepInput = document.getElementById('rename-step-input');
  const closeRenameStepModal = document.getElementById('close-rename-step-modal');
  const cancelRenameStepBtn = document.getElementById('cancel-rename-step-btn');
  let stepBeingRenamed = null;

  function openRenameStepModal(btn) {
    if (!btn || !renameStepModal || !renameStepInput) return;
    stepBeingRenamed = btn;
    const titleSpan = btn.querySelector('.item-title');
    const currentTitle = (btn.getAttribute('data-title') || (titleSpan ? titleSpan.textContent : '') || '').trim();
    renameStepInput.value = currentTitle;
    renameStepModal.style.display = 'block';
    setTimeout(() => {
      renameStepInput.focus();
      renameStepInput.select();
    }, 50);
  }

  function closeRenameStepModalFn() {
    if (renameStepModal) renameStepModal.style.display = 'none';
    stepBeingRenamed = null;
  }

  if (closeRenameStepModal) closeRenameStepModal.addEventListener('click', closeRenameStepModalFn);
  if (cancelRenameStepBtn) cancelRenameStepBtn.addEventListener('click', closeRenameStepModalFn);
  if (renameStepModal) {
    renameStepModal.addEventListener('click', (e) => {
      if (e.target === renameStepModal) closeRenameStepModalFn();
    });
  }

  if (renameStepForm) {
    renameStepForm.addEventListener('submit', (e) => {
      e.preventDefault();
      if (!stepBeingRenamed) {
        closeRenameStepModalFn();
        return;
      }
      const newTitle = renameStepInput.value.trim();
      const id = stepBeingRenamed.getAttribute('data-id');
      const targetBtn = stepBeingRenamed;
      closeRenameStepModalFn();

      if (id && newTitle) {
        saveStepTitle(id, newTitle, targetBtn);
      }
    });
  }

  if (stepContextEditTitle) {
    stepContextEditTitle.addEventListener('click', (e) => {
      e.stopPropagation();
      if (!stepContextBtn) return;
      const targetBtn = stepContextBtn;
      hideStepContextMenu();
      openRenameStepModal(targetBtn);
    });
  }

  if (stepContextEdit) {
    stepContextEdit.addEventListener('click', (e) => {
      e.stopPropagation();
      if (!stepContextBtn) return;
      const targetBtn = stepContextBtn;
      hideStepContextMenu();

      const currentActive = document.querySelector('.rec-item.active');
      if (targetBtn === currentActive) {
        if (window.MarkdownEditor && typeof window.MarkdownEditor.enterEditMode === 'function') {
          window.MarkdownEditor.enterEditMode();
        } else if (typeof setMdMode === 'function') {
          setMdMode('edit');
        }
      } else {
        pendingMdEditMode = true;
        targetBtn.click();
      }
    });
  }

  if (stepContextCopyLink) {
    stepContextCopyLink.addEventListener('click', (e) => {
      e.stopPropagation();
      if (!stepContextBtn) return;
      const snippet = stepLinkFor(stepContextBtn);
      if (!snippet) return;
      copyTextToClipboard(snippet);
      const original = stepContextCopyLink.innerHTML;
      stepContextCopyLink.innerHTML = '<i class="fas fa-check" style="color: #10b981; width: 14px; text-align: center;"></i> Copied!';
      setTimeout(() => {
        stepContextCopyLink.innerHTML = original;
        hideStepContextMenu();
      }, 800);
    });
  }

  function renderStatusBadge(status) {
    if (status === 'done') {
      return '<i class="fas fa-check-circle" style="color: #10b981;" title="Status: Done"></i>';
    } else if (status === 'in_progress') {
      return '<i class="fas fa-spinner fa-spin" style="color: #f59e0b;" title="Status: In Progress"></i>';
    } else if (status === 'open') {
      return '<i class="far fa-circle" style="color: #38bdf8;" title="Status: Open"></i>';
    }
    return '';
  }

  function updateStepStatusBadge(btn, status) {
    if (!btn) return;
    const badge = btn.querySelector('.step-status-badge');
    const norm = (status || 'none').toLowerCase();
    if (badge) {
      badge.innerHTML = renderStatusBadge(norm);
      badge.style.marginRight = badge.innerHTML ? '6px' : '0px';
    }
    btn.setAttribute('data-status', norm);
  }

  function saveStepStatus(id, newStatus, btn) {
    const activeWalkthrough = (window.activeWalkthrough || (typeof getActiveWalkthrough === 'function' ? getActiveWalkthrough() : ''));
    const body = new URLSearchParams({
      status: newStatus,
      walkthrough: activeWalkthrough
    });

    // Optimistic update
    updateStepStatusBadge(btn, newStatus);

    fetch(`/recordings/${encodeURIComponent(id)}/status`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded;charset=UTF-8',
        'Accept': 'application/json'
      },
      body: body,
      credentials: 'same-origin'
    })
    .then(res => res.json())
    .then(data => {
      if (data && data.ok) {
        updateStepStatusBadge(btn, data.status || 'none');
      }
    })
    .catch(err => {
      console.error('Failed to update step status:', err);
    });
  }

  if (stepContextMenu) {
    stepContextMenu.querySelectorAll('.step-status-option').forEach(btnOpt => {
      btnOpt.addEventListener('click', (e) => {
        e.stopPropagation();
        if (!stepContextBtn) return;
        const targetBtn = stepContextBtn;
        const newStatus = btnOpt.getAttribute('data-status');
        const id = targetBtn.getAttribute('data-id');
        hideStepContextMenu();
        if (id && newStatus) {
          saveStepStatus(id, newStatus, targetBtn);
        }
      });
    });
  }

  if (mdImgContextDownload) {
    mdImgContextDownload.addEventListener('click', (e) => {
      e.stopPropagation();
      if (!currentContextImg) return;
      const img = currentContextImg;
      const src = img.currentSrc || img.src;
      let fname = '';
      try {
        const u = new URL(src, window.location.href);
        fname = decodeURIComponent(u.pathname.split('/').pop() || '');
      } catch (_) {
        fname = (img.alt || 'image').trim();
      }
      fname = (fname || 'image').split('?')[0];
      downloadImageOrDiagram(src, fname);
      hideImageContextMenu();
    });
  }

  if (mdImgContextCopyLink) {
    mdImgContextCopyLink.addEventListener('click', (e) => {
      e.stopPropagation();
      if (!currentContextImg) return;
      const src = currentContextImg.currentSrc || currentContextImg.src;
      copyTextToClipboard(src);
      hideImageContextMenu();
    });
  }

  if (mdImgContextOpenTab) {
    mdImgContextOpenTab.addEventListener('click', () => {
      hideImageContextMenu();
    });
  }

  document.addEventListener('click', (e) => {
    if (stepContextMenu && stepContextMenu.style.display !== 'none' && !stepContextMenu.contains(e.target)) {
      hideStepContextMenu();
    }
    if (mdImgContextMenu && mdImgContextMenu.style.display !== 'none' && !mdImgContextMenu.contains(e.target)) {
      hideImageContextMenu();
    }
  });
  document.addEventListener('scroll', () => {
    hideStepContextMenu();
    hideImageContextMenu();
  }, true);
  window.addEventListener('resize', () => {
    hideStepContextMenu();
    hideImageContextMenu();
  });
  window.addEventListener('keydown', (e) => {
    if (e.key === 'Escape') {
      hideStepContextMenu();
      hideImageContextMenu();
      if (renameStepModal && renameStepModal.style.display === 'block') {
        closeRenameStepModalFn();
      }
    }
  });

  document.addEventListener('dblclick', (e) => {
    const titleSpan = e.target.closest('.item-title');
    if (titleSpan) {
      const btn = titleSpan.closest('.rec-item');
      if (btn) {
        e.preventDefault();
        e.stopPropagation();
        openRenameStepModal(btn);
      }
    }
  });

  if (titleEl) {
    titleEl.addEventListener('dblclick', () => {
      const activeBtn = document.querySelector('.rec-item.active');
      if (activeBtn) openRenameStepModal(activeBtn);
    });
  }

// --- Metadata & Note Save Handler ---
if (metaForm) {
  metaForm.addEventListener('submit', (e) => {
    if (activeDataType === 'markdown') {
      e.preventDefault();
      const newTitle = editTitle ? editTitle.value.trim() : '';
      if (newTitle && activeId) {
        const activeWalkthrough = (window.activeWalkthrough || (typeof getActiveWalkthrough === 'function' ? getActiveWalkthrough() : ''));
        const body = new URLSearchParams({
          title: newTitle,
          walkthrough: activeWalkthrough
        });

        fetch(metaForm.action || `/recordings/${encodeURIComponent(activeId)}/meta`, {
          method: 'POST',
          headers: {
            'Content-Type': 'application/x-www-form-urlencoded;charset=UTF-8',
            'Accept': 'application/json'
          },
          body: body,
          credentials: 'same-origin'
        })
        .then(res => res.json())
        .then(data => {
          if (data && data.ok) {
            const nextId = data.id || activeId;
            const oldId = activeId;
            const activeBtn = document.querySelector(`.rec-item[data-id="${CSS.escape(oldId)}"]`);
            if (activeBtn) {
              activeBtn.setAttribute('data-title', newTitle);
              activeBtn.setAttribute('data-id', nextId);
              activeBtn.setAttribute('data-src', '/recordings/' + encodeURIComponent(nextId));
              const titleSpan = activeBtn.querySelector('.item-title');
              if (titleSpan) titleSpan.textContent = newTitle;
              const step = activeBtn.getAttribute('data-step');
              const titleEl = document.getElementById('rec-title');
              if (titleEl) {
                const span = titleEl.querySelector('span');
                const fullTitleText = (step ? '#' + step + ': ' : '') + newTitle;
                if (span) span.textContent = fullTitleText;
                titleEl.title = fullTitleText;
              }
              const wrapper = activeBtn.closest('.rec-item-wrapper') || document.getElementById('step-' + oldId);
              if (wrapper) {
                wrapper.id = 'step-' + nextId;
                wrapper.setAttribute('data-id', nextId);
              }
            }

            if (nextId !== oldId) {
              activeId = nextId;
              window.activeId = nextId;
              const formRecInput = document.getElementById('walkthrough-form-recording');
              if (formRecInput) formRecInput.value = nextId;
              const newSrc = '/recordings/' + encodeURIComponent(nextId);
              if (downloadEl) downloadEl.href = newSrc + '?download=1';
              if (deleteForm) deleteForm.action = newSrc + '/delete';
              if (metaForm) metaForm.action = newSrc + '/meta';
              const url = new URL(window.location);
              url.searchParams.set('recording', nextId);
              window.history.replaceState({}, '', url.toString());

              try {
                if (activeWalkthrough) localStorage.setItem('ctlabs_last_step_' + activeWalkthrough, nextId);
              } catch (e) {}

              if (window.MarkdownEditor && typeof window.MarkdownEditor.renameNote === 'function') {
                window.MarkdownEditor.renameNote(oldId, nextId);
              }
              window.dispatchEvent(new CustomEvent('recording:renamed', {
                detail: { oldId: oldId, newId: nextId, title: newTitle }
              }));
            }

            if (editTitle) editTitle.value = newTitle;
            const statusEl = document.getElementById('md-save-status');
            if (statusEl) {
              statusEl.style.display = 'inline-flex';
              setTimeout(() => { statusEl.style.display = 'none'; }, 2000);
            }
            if (typeof saveMarkdownContent === 'function') saveMarkdownContent(false);
          } else {
            if (typeof saveMarkdownContent === 'function') saveMarkdownContent(false);
          }
        })
        .catch(err => {
          console.error('Failed to update title:', err);
          if (typeof saveMarkdownContent === 'function') saveMarkdownContent(false);
        });
      } else {
        if (typeof saveMarkdownContent === 'function') saveMarkdownContent(false);
      }
    }
  });
}


  // --- Note Export Modal & Actions ---
  function updateExportNoteFilenameExtension(targetExt) {
    if (!exportNoteFilenameInput) return;
    let val = exportNoteFilenameInput.value.trim();
    if (val) {
      val = val.replace(/\.(zip|md|docx|pdf)$/i, '');
      exportNoteFilenameInput.value = `${val}.${targetExt}`;
    }
    if (exportNoteFilenameHint) {
      exportNoteFilenameHint.innerHTML = `The <code>.${targetExt}</code> extension will be added automatically if omitted.`;
    }
  }

  function openExportNoteModal() {
    if (!activeId || activeDataType !== 'markdown') return;
    if (typeof saveMarkdownContent === 'function') {
      try { saveMarkdownContent(false); } catch (e) {}
    }
    const activeBtn = document.querySelector(`.rec-item[data-id="${CSS.escape(activeId)}"]`);
    const currentTitle = (activeBtn && activeBtn.getAttribute('data-title')) || (titleEl && titleEl.textContent ? titleEl.textContent.trim().replace(/^#\d+:\s*/, '') : ((editTitle && editTitle.value) ? editTitle.value : activeId));
    if (exportNoteTitleSpan) {
      exportNoteTitleSpan.textContent = `“${currentTitle}”`;
    }
    const defaultRadio = document.querySelector('input[name="export-note-format"][value="bundle"]');
    if (defaultRadio) defaultRadio.checked = true;

    if (exportNoteFilenameInput) {
      const clean = currentTitle.replace(/[^a-zA-Z0-9_-]+/g, '_').replace(/^_+|_+$/g, '') || 'note';
      exportNoteFilenameInput.value = `${clean}.zip`;
    }
    if (exportNoteFilenameHint) {
      exportNoteFilenameHint.innerHTML = 'The <code>.zip</code> extension will be added automatically if omitted.';
    }
    if (exportNoteModal) {
      exportNoteModal.style.display = 'block';
      if (exportNoteFilenameInput) {
        setTimeout(() => {
          exportNoteFilenameInput.focus();
          exportNoteFilenameInput.select();
        }, 50);
      }
    }
  }

  document.querySelectorAll('input[name="export-note-format"]').forEach(radio => {
    radio.addEventListener('change', () => {
      let ext = 'zip';
      if (radio.value === 'raw') ext = 'md';
      else if (radio.value === 'docx') ext = 'docx';
      else if (radio.value === 'pdf') ext = 'pdf';
      updateExportNoteFilenameExtension(ext);
    });
  });

  if (exportNoteFilenameInput) {
    exportNoteFilenameInput.addEventListener('keydown', (e) => {
      if (e.key === 'Enter') {
        e.preventDefault();
        if (confirmExportNoteBtn) confirmExportNoteBtn.click();
      }
    });
  }

  if (confirmExportNoteBtn) {
    confirmExportNoteBtn.addEventListener('click', () => {
      if (!activeId) return;
      if (typeof saveMarkdownContent === 'function') {
        try { saveMarkdownContent(false); } catch (e) {}
      }
      const selectedFormat = document.querySelector('input[name="export-note-format"]:checked');
      const format = selectedFormat ? selectedFormat.value : 'bundle';
      let filename = exportNoteFilenameInput ? exportNoteFilenameInput.value.trim() : '';
      const expectedExt = (format === 'docx') ? '.docx' : (format === 'pdf' ? '.pdf' : (format === 'raw' ? '.md' : '.zip'));
      if (filename) {
        filename = filename.replace(/\.(zip|md|docx|pdf)$/i, '') + expectedExt;
      }
      let url = '/recordings/' + encodeURIComponent(activeId) + '?download=1';
      if (format === 'bundle') {
        url += '&bundle=1';
      } else if (format === 'docx') {
        url += '&format=docx';
      } else if (format === 'pdf') {
        url += '&format=pdf';
      }
      if (filename) {
        url += '&filename=' + encodeURIComponent(filename);
      }
      window.location.href = url;
      if (exportNoteModal) exportNoteModal.style.display = 'none';
    });
  }

  if (downloadEl) {
    downloadEl.addEventListener('click', (e) => {
      if (activeDataType === 'markdown') {
        e.preventDefault();
        openExportNoteModal();
      }
    });
  }

  // --- New Walkthrough Set Handler ---
  if (newSetBtn && newSetName) {
    newSetBtn.addEventListener('click', () => {
      const name = window.prompt('Name for the new walkthrough set:', 'New Walkthrough');
      if (name === null) return;
      newSetName.value = name.trim() || 'New Walkthrough';
      newSetBtn.form.submit();
    });
  }

  let lastImportFiles = null;
  let lastConflictInfo = null;

  // --- Upload & Import Helper (supports single and multiple .cast, .md, .zip) ---
  function uploadImportFiles(fileList, options = {}) {
    const files = Array.from(fileList || []);
    if (files.length === 0) return;
    lastImportFiles = files;

    const validExts = ['.cast', '.md', '.zip', '.webm', '.mp4', '.png', '.jpg', '.jpeg', '.gif', '.svg', '.webp'];
    const validFiles = files.filter(f => {
      const name = f.name.toLowerCase();
      return validExts.some(ext => name.endsWith(ext));
    });

    if (validFiles.length === 0) {
      alert('Unsupported file format. Please drop or upload .cast recordings, .webm/.mp4 videos, .md notes, or .zip archives.');
      return;
    }

    const overlay = document.getElementById('sidebar-drop-overlay');
    const idleBox = document.getElementById('sidebar-drop-idle');
    const busyBox = document.getElementById('sidebar-drop-busy');
    const busyTitle = document.getElementById('sidebar-drop-busy-title');
    const busyDesc = document.getElementById('sidebar-drop-busy-desc');

    if (overlay) {
      if (idleBox) idleBox.style.display = 'none';
      if (busyBox) busyBox.style.display = 'flex';
      if (busyTitle) busyTitle.textContent = `Importing ${validFiles.length} file${validFiles.length > 1 ? 's' : ''}...`;
      if (busyDesc) busyDesc.textContent = validFiles.map(f => f.name).slice(0, 3).join(', ') + (validFiles.length > 3 ? '...' : '');
      overlay.style.display = 'flex';
    }

    const formData = new FormData();
    validFiles.forEach(file => {
      formData.append('files[]', file);
    });
    if (validFiles.length === 1) {
      formData.append('file', validFiles[0]);
    }
    formData.append('walkthrough', activeWalkthrough);

    if (options.conflict_action) {
      formData.append('conflict_action', options.conflict_action);
    }
    if (options.custom_name) {
      formData.append('custom_name', options.custom_name);
    }
    if (options.target_id) {
      formData.append('target_id', options.target_id);
    }

    fetch('/recordings/import', {
      method: 'POST',
      body: formData,
      credentials: 'same-origin'
    })
    .then(res => res.json())
    .then(data => {
      if (overlay) overlay.style.display = 'none';
      if (idleBox) idleBox.style.display = 'flex';
      if (busyBox) busyBox.style.display = 'none';

      if (data.conflict) {
        lastConflictInfo = data;
        const dupModal = document.getElementById('duplicate-import-modal');
        const dupNameSpan = document.getElementById('duplicate-existing-name-span');
        const dupMsg = document.getElementById('duplicate-modal-msg');
        const dupInput = document.getElementById('duplicate-rename-input');
        if (dupNameSpan) dupNameSpan.textContent = `“${data.existing_title || data.filename}”`;
        if (dupMsg) {
          if (data.is_walkthrough) {
            dupMsg.innerHTML = `A walkthrough set named <strong style="color: #38bdf8;">“${data.existing_title || data.filename}”</strong> already exists.`;
          } else {
            dupMsg.innerHTML = `A step or file matching <strong id="duplicate-existing-name-span" style="color: #38bdf8;">“${data.existing_title || data.filename}”</strong> already exists in this walkthrough set.`;
          }
        }
        if (dupInput) {
          dupInput.value = data.suggested_name || ((data.existing_title || data.filename) + ' (1)');
          setTimeout(() => { dupInput.focus(); dupInput.select(); }, 80);
        }
        if (dupModal) dupModal.style.display = 'block';
        return;
      }

      if (data.ok) {
        const targetWk = data.walkthrough || activeWalkthrough;
        let url = '/demo?walkthrough=' + encodeURIComponent(targetWk);
        const targetRec = data.selected || (data.imported && data.imported[0]);
        if (targetRec) {
          url += '&recording=' + encodeURIComponent(targetRec);
        }
        window.location.href = url;
      } else {
        alert('Import failed: ' + (data.error || 'Unknown error'));
      }
    })
    .catch(err => {
      console.error('Import error:', err);
      if (overlay) overlay.style.display = 'none';
      if (idleBox) idleBox.style.display = 'flex';
      if (busyBox) busyBox.style.display = 'none';
      alert('Failed to upload import file: ' + err.message);
    });
  }
  window.uploadImportFiles = uploadImportFiles;

  const dupModal = document.getElementById('duplicate-import-modal');
  const dupRenameBtn = document.getElementById('duplicate-rename-btn');
  const dupOverwriteBtn = document.getElementById('duplicate-overwrite-btn');
  const dupCancelBtn = document.getElementById('duplicate-cancel-btn');
  const closeDupModalBtn = document.getElementById('close-duplicate-modal-btn');
  const dupInput = document.getElementById('duplicate-rename-input');

  if (dupRenameBtn) {
    dupRenameBtn.addEventListener('click', () => {
      if (!lastImportFiles || !lastConflictInfo) return;
      const newName = dupInput ? dupInput.value.trim() : '';
      if (dupModal) dupModal.style.display = 'none';
      uploadImportFiles(lastImportFiles, {
        conflict_action: 'rename',
        custom_name: newName,
        target_id: lastConflictInfo.existing_id
      });
    });
  }

  if (dupOverwriteBtn) {
    dupOverwriteBtn.addEventListener('click', () => {
      if (!lastImportFiles || !lastConflictInfo) return;
      if (dupModal) dupModal.style.display = 'none';
      uploadImportFiles(lastImportFiles, {
        conflict_action: 'overwrite',
        target_id: lastConflictInfo.existing_id
      });
    });
  }

  [dupCancelBtn, closeDupModalBtn].forEach(btn => {
    if (btn) {
      btn.addEventListener('click', () => {
        if (dupModal) dupModal.style.display = 'none';
        lastConflictInfo = null;
      });
    }
  });

  // --- Import Walkthrough Handler ---
  if (importBtn && importFileInput) {
    importBtn.addEventListener('click', () => {
      importFileInput.accept = '.zip,.cast,.md,.webm,.mp4';
      importFileInput.click();
    });

    importFileInput.addEventListener('change', () => {
      if (!importFileInput.files || importFileInput.files.length === 0) return;
      uploadImportFiles(importFileInput.files);
      importFileInput.value = '';
    });
  }

  // --- Drag and Drop files onto Walkthrough Sidebar & Global Page ---
  const sidebarElForDrop = document.getElementById('walkthrough-sidebar');
  const sidebarDropOverlay = document.getElementById('sidebar-drop-overlay');
  let sidebarDragCounter = 0;

  if (sidebarElForDrop && sidebarDropOverlay) {
    sidebarElForDrop.addEventListener('dragenter', (e) => {
      if (draggedItem) return;
      e.preventDefault();
      sidebarDragCounter++;
      if (sidebarDragCounter === 1) {
        const busyBox = document.getElementById('sidebar-drop-busy');
        if (!busyBox || busyBox.style.display !== 'flex') {
          const idleBox = document.getElementById('sidebar-drop-idle');
          if (idleBox) idleBox.style.display = 'flex';
          sidebarDropOverlay.style.display = 'flex';
        }
      }
    });

    sidebarElForDrop.addEventListener('dragover', (e) => {
      if (draggedItem) return;
      e.preventDefault();
      if (e.dataTransfer) e.dataTransfer.dropEffect = 'copy';
    });

    sidebarElForDrop.addEventListener('dragleave', (e) => {
      if (draggedItem) return;
      e.preventDefault();
      sidebarDragCounter = Math.max(0, sidebarDragCounter - 1);
      if (sidebarDragCounter === 0) {
        const busyBox = document.getElementById('sidebar-drop-busy');
        if (!busyBox || busyBox.style.display !== 'flex') {
          sidebarDropOverlay.style.display = 'none';
        }
      }
    });

    sidebarElForDrop.addEventListener('drop', (e) => {
      if (draggedItem) return;
      e.preventDefault();
      e.stopPropagation();
      sidebarDragCounter = 0;
      if (e._ctlabsHandled) return;
      e._ctlabsHandled = true;

      const idleBox = document.getElementById('sidebar-drop-idle');
      if (idleBox) idleBox.style.display = 'none';

      const files = getDroppedFiles(e.dataTransfer);
      if (files.length > 0) {
        uploadImportFiles(files);
      } else {
        sidebarDropOverlay.style.display = 'none';
      }
    });
  }

  // Prevent default navigation and indicate copy across BOTH window and document in capture phase
  ['dragenter', 'dragover'].forEach(evt => {
    window.addEventListener(evt, (e) => {
      if (!draggedItem) {
        e.preventDefault();
        if (e.dataTransfer) e.dataTransfer.dropEffect = 'copy';
      }
    }, true);
    document.addEventListener(evt, (e) => {
      if (!draggedItem) {
        e.preventDefault();
        if (e.dataTransfer) e.dataTransfer.dropEffect = 'copy';
      }
    }, true);
  });

  // Global dragend to reset visual states if drag is cancelled
  window.addEventListener('dragend', () => {
    sidebarDragCounter = 0;
    if (sidebarDropOverlay) sidebarDropOverlay.style.display = 'none';
    if (mdContainer) mdContainer.style.boxShadow = 'none';
  });

  // Global drop handler across window/document (bubbling phase, element-specific handlers fire first)
  const handleGlobalFileDrop = (e) => {
    if (draggedItem) return;
    // In Firefox, preventDefault() MUST be called unconditionally first to stop Firefox navigating to the dropped file
    e.preventDefault();
    if (e._ctlabsHandled) return;

    const files = getDroppedFiles(e.dataTransfer);
    if (files.length === 0) return;

    e.stopPropagation();
    e._ctlabsHandled = true;

    sidebarDragCounter = 0;
    if (sidebarDropOverlay) sidebarDropOverlay.style.display = 'none';

    const isSingleImg = files.length === 1 && (
      (files[0].type && files[0].type.startsWith('image/')) ||
      (/\.(png|jpe?g|gif|svg|webp)$/i.test(files[0].name || ''))
    );

    if (isSingleImg && activeDataType === 'markdown') {
      const cm = getMdEditor();
      uploadAndInsertImage(files[0], cm ? cm.getCursor() : null);
    } else {
      uploadImportFiles(files);
    }
  };

  window.addEventListener('drop', handleGlobalFileDrop, false);
  document.addEventListener('drop', handleGlobalFileDrop, false);

  // --- Dedicated Recording Window Helpers & Focus Flash ---
  let recFlashTimeout = null;

  function isCrossOriginUrl(testUrl) {
    try {
      const parsed = new URL(testUrl, window.location.href);
      return parsed.origin !== window.location.origin;
    } catch (e) {
      return false;
    }
  }

  function normalizeRecUrl(raw) {
    let s = (raw || '').trim();
    if (!s) return '/labs';

    // Protocol schemes (http://, https://, etc.)
    if (/^[a-zA-Z][a-zA-Z0-9+.-]*:\/\//.test(s)) return s;

    // Root paths or relative paths
    if (s.startsWith('/') || s.startsWith('./') || s.startsWith('../')) return s;

    const locProto = (window.location && window.location.protocol) ? window.location.protocol : 'https:';
    const locHost = (window.location && window.location.host) ? window.location.host : '';

    // Localhost or loopback IP (match port and path)
    if (s.startsWith('localhost') || s.startsWith('127.0.0.1')) {
      return locProto + '//' + s;
    }

    // Matches current host/origin (e.g. "127.0.0.1:4567/labs" or "h3.ctlabs.internal:4567/demo")
    if (locHost && (s === locHost || s.startsWith(locHost + '/'))) {
      return locProto + '//' + s;
    }

    // Known internal application routes without leading slash
    const internalPrefixes = ['labs', 'demo', 'terminal', 'config', 'inventory', 'recordings', 'walkthroughs', 'status'];
    const cleanPath = s.replace(/^\/+/, '');
    const firstPart = cleanPath.split('/')[0].split('?')[0].split('#')[0].toLowerCase();
    if (internalPrefixes.includes(firstPart)) {
      return '/' + cleanPath;
    }

    // If it contains a domain dot or port colon (e.g. "google.com", "example.org/path", "host:8080")
    if (/^[a-zA-Z0-9_-]+\.[a-zA-Z]{2,}/.test(s) || s.includes(':')) {
      return 'https://' + s;
    }

    // Default fallback: internal application path
    return '/' + cleanPath;
  }

  function isRecWindowOpen() {
    if (activeRecWindow && !activeRecWindow.closed) return true;
    if (recWindowLaunched && recWindowIsCross) return true;
    return false;
  }

  function markTargetWindowRecTitle(win) {
    if (!win || win.closed) return;
    try {
      if (win.document) {
        let t = win.document.title || '';
        if (!t.startsWith('🔴 [REC TARGET]')) {
          win.document.title = '🔴 [REC TARGET] ' + (t.replace(/^🔴\s*\[REC TARGET\]\s*/, '') || 'CTLABS');
        }
      }
    } catch (e) {
      // Cross-origin restriction
    }
  }

  function focusTargetWindow() {
    if (activeRecWindow && !activeRecWindow.closed) {
      try {
        activeRecWindow.focus();
        markTargetWindowRecTitle(activeRecWindow);
        flashRecWindowHighlight(activeRecWindow, 1500);
        return;
      } catch (e) {}
    }
    // Note: If COOP isolated the window (e.g. https://www.suse.de), calling
    // window.open('', target) opens an about:blank tab because the browser prevents
    // referencing cross-origin isolated browsing context groups.
    // Therefore, do NOT call window.open('', ...) if the opener handle is detached.
  }

  function updateRecWindowUI() {
    const isOpen = isRecWindowOpen();
    const canFocusDirectly = !!(activeRecWindow && !activeRecWindow.closed);
    if (recWinStatusBadge) {
      if (isOpen) {
        if (recWindowIsCross) {
          recWinStatusBadge.innerHTML = '<i class="fas fa-external-link-alt" style="margin-right: 4px;"></i>Window Open (External)';
          recWinStatusBadge.style.background = '#065f46';
          recWinStatusBadge.style.color = '#34d399';
        } else {
          recWinStatusBadge.textContent = 'Window Open';
          recWinStatusBadge.style.background = '#065f46';
          recWinStatusBadge.style.color = '#34d399';
        }
      } else {
        recWinStatusBadge.textContent = 'Not open';
        recWinStatusBadge.style.background = '#334155';
        recWinStatusBadge.style.color = '#94a3b8';
      }
    }
    if (focusRecWinBtn) {
      // Only show Focus button if browser still maintains an attached window handle
      focusRecWinBtn.style.display = canFocusDirectly ? 'inline-flex' : 'none';
    }
    if (closeRecWinBtn) {
      closeRecWinBtn.style.display = isOpen ? 'inline-flex' : 'none';
    }
    if (screenRecFocusBtn) {
      screenRecFocusBtn.style.display = (canFocusDirectly && screenRecorder && screenRecorder.isRecording) ? 'inline-flex' : 'none';
    }
  }

  function flashRecWindowHighlight(win, durationMs = 1500) {
    if (!win || win.closed) return;
    try {
      const doc = win.document;
      if (!doc || !doc.body) return;

      let styleEl = doc.getElementById('ctlabs-rec-flash-style');
      if (!styleEl) {
        styleEl = doc.createElement('style');
        styleEl.id = 'ctlabs-rec-flash-style';
        styleEl.textContent = `
          @keyframes ctlabsFocusFlash {
            0% { opacity: 0; box-shadow: inset 0 0 0 5px #38bdf8, inset 0 0 26px rgba(56, 189, 248, 0.85); }
            20% { opacity: 1; box-shadow: inset 0 0 0 5px #38bdf8, inset 0 0 32px rgba(56, 189, 248, 0.95); }
            75% { opacity: 1; box-shadow: inset 0 0 0 5px #38bdf8, inset 0 0 26px rgba(56, 189, 248, 0.85); }
            100% { opacity: 0; box-shadow: inset 0 0 0 5px #0284c7, inset 0 0 10px rgba(2, 132, 199, 0.2); }
          }
          #ctlabs-rec-flash-indicator {
            position: fixed !important;
            top: 0 !important;
            left: 0 !important;
            right: 0 !important;
            bottom: 0 !important;
            border: 5px solid #38bdf8 !important;
            animation: ctlabsFocusFlash ${durationMs}ms ease-out forwards !important;
            pointer-events: none !important;
            z-index: 2147483647 !important;
          }
        `;
        doc.head.appendChild(styleEl);
      }

      const existing = doc.getElementById('ctlabs-rec-flash-indicator');
      if (existing) existing.remove();

      const ind = doc.createElement('div');
      ind.id = 'ctlabs-rec-flash-indicator';
      doc.body.appendChild(ind);

      if (recFlashTimeout) clearTimeout(recFlashTimeout);
      recFlashTimeout = setTimeout(() => {
        try {
          const el = doc.getElementById('ctlabs-rec-flash-indicator');
          if (el) el.remove();
        } catch (e) {}
      }, durationMs);
    } catch (e) {
      // Gracefully ignore cross-origin security errors or closed window
    }
  }

  function removeRecWindowHighlight(win) {
    if (!win || win.closed) return;
    try {
      const doc = win.document;
      if (!doc) return;
      const ind = doc.getElementById('ctlabs-rec-flash-indicator');
      if (ind) ind.remove();
      const legacyInd = doc.getElementById('ctlabs-rec-active-indicator');
      if (legacyInd) legacyInd.remove();
      const legacyBadge = doc.getElementById('ctlabs-rec-active-badge');
      if (legacyBadge) legacyBadge.remove();
    } catch (e) {}
  }

  function focusAndHighlightWindow(win) {
    if (!win || win.closed) return;
    try { win.focus(); } catch (e) {}
    flashRecWindowHighlight(win, 1500);
  }

  function formatFileSize(bytes) {
    const b = Number(bytes) || 0;
    if (b <= 0) return '0 B';
    if (b < 1024) return `${b} B`;
    const units = ['KB', 'MB', 'GB', 'TB'];
    let val = b / 1024;
    let idx = 0;
    while (val >= 1024 && idx < units.length - 1) {
      val /= 1024;
      idx++;
    }
    return `${val.toFixed(1)} ${units[idx]}`;
  }

  function formatDuration(sec) {
    const s = Math.max(0, Math.round(Number(sec) || 0));
    const mins = String(Math.floor(s / 60)).padStart(2, '0');
    const secs = String(s % 60).padStart(2, '0');
    return `${mins}:${secs}`;
  }

  function detectSupportedVideoCodec() {
    if (typeof MediaRecorder === 'undefined' || typeof MediaRecorder.isTypeSupported !== 'function') return 'WebM';
    if (MediaRecorder.isTypeSupported('video/webm;codecs=av01.0.08M.10,opus') || MediaRecorder.isTypeSupported('video/webm;codecs=av1')) return 'AV1';
    if (MediaRecorder.isTypeSupported('video/webm;codecs=vp9,opus') || MediaRecorder.isTypeSupported('video/webm;codecs=vp9')) return 'VP9';
    if (MediaRecorder.isTypeSupported('video/webm;codecs=vp8,opus') || MediaRecorder.isTypeSupported('video/webm;codecs=vp8')) return 'VP8';
    if (MediaRecorder.isTypeSupported('video/webm;codecs=h264,opus') || MediaRecorder.isTypeSupported('video/webm;codecs=h264')) return 'H.264';
    return 'WebM';
  }

  async function acquireDisplayStream(controller = null) {
    if (!navigator.mediaDevices || !navigator.mediaDevices.getDisplayMedia) {
      throw new Error('Screen capture API (getDisplayMedia) is not supported in this browser.');
    }

    const supported = (navigator.mediaDevices.getSupportedConstraints && navigator.mediaDevices.getSupportedConstraints()) || {};
    const videoConstraints = supported.cursor ? { cursor: 'always' } : true;

    const gdmOptions = {
      video: videoConstraints,
      audio: true,
      preferCurrentTab: false,
      selfBrowserSurface: 'exclude',
      surfaceSwitching: 'include',
      systemAudio: 'include'
    };
    if (controller) {
      gdmOptions.controller = controller;
    }

    try {
      return await navigator.mediaDevices.getDisplayMedia(gdmOptions);
    } catch (err) {
      if (err.name === 'NotAllowedError') throw err;
      // Fallback to basic getDisplayMedia if advanced options or controller rejected (e.g. Firefox)
      try {
        return await navigator.mediaDevices.getDisplayMedia({
          video: videoConstraints,
          audio: true
        });
      } catch (err2) {
        if (err2.name === 'NotAllowedError') throw err2;
        return await navigator.mediaDevices.getDisplayMedia({
          video: true
        });
      }
    }
  }

  // --- Browser Screen Recorder ---
  class ScreenRecorder {
    constructor() {
      this.mediaRecorder = null;
      this.recordedChunks = [];
      this.stream = null;
      this.displayStream = null;
      this.micStream = null;
      this.audioCtx = null;
      this.captureController = null;
      this.cropCancelLoop = null;
      this.timerInterval = null;
      this.startTime = 0;
      this.durationSec = 0;
      this.currentSizeBytes = 0;
      this.maxDurationSec = 0;
      this.maxSizeBytes = 0;
      this.stopReason = null;
      this.isRecording = false;
      this.isStopping = false;
    }

    updateBarUI() {
      if (screenRecTimer) {
        const curTimeStr = formatDuration(this.durationSec);
        if (this.maxDurationSec > 0) {
          const maxTimeStr = formatDuration(this.maxDurationSec);
          screenRecTimer.textContent = `${curTimeStr} / ${maxTimeStr}`;
          screenRecTimer.style.color = (this.durationSec >= this.maxDurationSec * 0.9) ? '#f59e0b' : '#f8fafc';
        } else {
          screenRecTimer.textContent = curTimeStr;
          screenRecTimer.style.color = '#f8fafc';
        }
      }
      if (screenRecSize) {
        const curSizeStr = formatFileSize(this.currentSizeBytes);
        if (this.maxSizeBytes > 0) {
          const maxSizeStr = formatFileSize(this.maxSizeBytes);
          screenRecSize.textContent = `${curSizeStr} / ${maxSizeStr}`;
          screenRecSize.style.color = (this.currentSizeBytes >= this.maxSizeBytes * 0.9) ? '#f59e0b' : '#94a3b8';
        } else {
          screenRecSize.textContent = curSizeStr;
          screenRecSize.style.color = '#94a3b8';
        }
      }
    }

    async mixMicrophone(videoStream, displayAudioSource, enableMic = false) {
      let combinedAudio = [...displayAudioSource.getAudioTracks()];
      if (enableMic && navigator.mediaDevices.getUserMedia) {
        try {
          const micStream = await navigator.mediaDevices.getUserMedia({
            audio: {
              echoCancellation: true,
              noiseSuppression: true
            }
          });
          this.micStream = micStream;

          const hasDisplayAudio = displayAudioSource.getAudioTracks().length > 0;
          const hasMicAudio = micStream.getAudioTracks().length > 0;

          if (hasDisplayAudio || hasMicAudio) {
            const AudioContextClass = window.AudioContext || window.webkitAudioContext;
            if (AudioContextClass) {
              const ctx = new AudioContextClass();
              this.audioCtx = ctx;
              const dest = ctx.createMediaStreamDestination();

              if (hasDisplayAudio) {
                const displaySource = ctx.createMediaStreamSource(new MediaStream(displayAudioSource.getAudioTracks()));
                displaySource.connect(dest);
              }
              if (hasMicAudio) {
                const micSource = ctx.createMediaStreamSource(micStream);
                micSource.connect(dest);
              }

              combinedAudio = dest.stream.getAudioTracks();
            } else {
              combinedAudio = [
                ...displayAudioSource.getAudioTracks(),
                ...micStream.getAudioTracks()
              ];
            }
          }
        } catch (micErr) {
          console.warn('Microphone access could not be acquired; proceeding with screen video only:', micErr);
        }
      }

      return new MediaStream([
        ...videoStream.getVideoTracks(),
        ...combinedAudio
      ]);
    }

    initRecorder(combinedStream, displayStream) {
      // Pick preferred mimeType based on available codecs: AV1 -> VP9 -> VP8 -> H.264
      const hasAudio = combinedStream.getAudioTracks().length > 0;
      const candidates = hasAudio ? [
        'video/webm;codecs=av01.0.08M.10,opus',
        'video/webm;codecs=av1,opus',
        'video/webm;codecs=vp9,opus',
        'video/webm;codecs=vp8,opus',
        'video/webm;codecs=h264,opus',
        'video/mp4;codecs=avc1.42E01E,mp4a.40.2',
        'video/webm'
      ] : [
        'video/webm;codecs=av01.0.08M.10',
        'video/webm;codecs=av1',
        'video/webm;codecs=vp9',
        'video/webm;codecs=vp8',
        'video/webm;codecs=h264',
        'video/mp4',
        'video/webm'
      ];

      let mimeType = '';
      if (typeof MediaRecorder.isTypeSupported === 'function') {
        for (const candidate of candidates) {
          if (MediaRecorder.isTypeSupported(candidate)) {
            mimeType = candidate;
            break;
          }
        }
      }

      // Bitrate based on compression quality choice
      const qualitySelect = document.getElementById('rec-screen-quality');
      const quality = qualitySelect ? qualitySelect.value : 'ultra_compact';
      let videoBps = 250000; // 250 Kbps default: Ultra-Compact (~1.8 MB/min, crisp text in VP9/AV1)
      let audioBps = 64000;  // 64 Kbps voice-optimized Opus
      if (quality === 'compact') {
        videoBps = 600000;  // 600 Kbps (~4.5 MB/min)
        audioBps = 80000;
      } else if (quality === 'balanced') {
        videoBps = 1200000; // 1.2 Mbps (~9.0 MB/min)
        audioBps = 96000;
      } else if (quality === 'hq') {
        videoBps = 2500000; // 2.5 Mbps (~18 MB/min)
        audioBps = 128000;
      }

      const options = {
        videoBitsPerSecond: videoBps,
        audioBitsPerSecond: audioBps
      };
      if (mimeType) {
        options.mimeType = mimeType;
      }

      try {
        this.mediaRecorder = new MediaRecorder(combinedStream, options);
      } catch (recErr) {
        // Fallback to basic options if browser rejects explicit bitrate constraints
        const fallbackOpts = mimeType ? { mimeType } : {};
        this.mediaRecorder = new MediaRecorder(combinedStream, fallbackOpts);
      }

      this.isRecording = true;
      this.isStopping = false;

      this.mediaRecorder.ondataavailable = (event) => {
        if (event.data && event.data.size > 0) {
          this.recordedChunks.push(event.data);
          this.currentSizeBytes += event.data.size;
          this.updateBarUI();

          if (this.maxSizeBytes > 0 && this.currentSizeBytes >= this.maxSizeBytes) {
            if (this.isRecording && !this.isStopping) {
              this.stopReason = 'max_size';
              handleStopRecording('max_size');
            }
          }
        }
      };

      // Detect when user clicks native browser "Stop sharing" chrome (Chrome, Firefox, Safari)
      displayStream.getTracks().forEach(track => {
        track.onended = () => {
          if (this.isRecording && !this.isStopping) {
            handleStopRecording();
          }
        };
      });

      // In Firefox/Safari, recorder may automatically transition to inactive and stop when tracks end
      this.mediaRecorder.onstop = () => {
        if (this.isRecording && !this.isStopping) {
          handleStopRecording();
        }
      };

      this.mediaRecorder.start(1000);
      this.startTime = Date.now();

      this.updateBarUI();
      if (screenRecBar) screenRecBar.style.display = 'flex';
      if (screenRecFocusBtn) {
        screenRecFocusBtn.style.display = (activeRecWindow && !activeRecWindow.closed) ? 'inline-flex' : 'none';
      }

      this.timerInterval = setInterval(() => {
        this.durationSec = Math.round((Date.now() - this.startTime) / 1000);
        this.updateBarUI();
        if (this.maxDurationSec > 0 && this.durationSec >= this.maxDurationSec) {
          if (this.isRecording && !this.isStopping) {
            this.stopReason = 'max_len';
            handleStopRecording('max_len');
          }
        }
      }, 500);
    }

    async start(enableMic = false) {
      this.cleanup();
      this.recordedChunks = [];
      this.durationSec = 0;
      this.currentSizeBytes = 0;
      this.isRecording = false;
      this.isStopping = false;
      this.stopReason = null;

      const maxLenSelect = document.getElementById('rec-screen-max-len');
      const maxSizeSelect = document.getElementById('rec-screen-max-size');
      this.maxDurationSec = maxLenSelect ? parseInt(maxLenSelect.value, 10) || 0 : 0;
      const maxSizeMB = maxSizeSelect ? parseInt(maxSizeSelect.value, 10) || 0 : 0;
      this.maxSizeBytes = maxSizeMB > 0 ? maxSizeMB * 1024 * 1024 : 0;

      let controller = null;
      if (typeof CaptureController !== 'undefined') {
        try {
          controller = new CaptureController();
        } catch (e) {
          controller = null;
        }
      }
      this.captureController = controller;

      const displayStream = await acquireDisplayStream(controller);

      // In Chromium, automatically focus the captured surface
      if (controller && typeof controller.setFocusBehavior === 'function') {
        try {
          const videoTrack = displayStream.getVideoTracks()[0];
          const settings = videoTrack && videoTrack.getSettings ? videoTrack.getSettings() : {};
          if (settings.displaySurface !== 'monitor') {
            controller.setFocusBehavior('focus-captured-surface');
          }
        } catch (focusErr) {
          console.warn('CaptureController setFocusBehavior notice:', focusErr);
        }
      }

      // If dedicated window is open, bring it to focus and make sure NO border is visible in the recording
      if (activeRecWindow && !activeRecWindow.closed) {
        try { activeRecWindow.focus(); } catch (e) {}
        removeRecWindowHighlight(activeRecWindow);
      }

      this.displayStream = displayStream;
      const combinedStream = await this.mixMicrophone(displayStream, displayStream, enableMic);
      this.stream = combinedStream;

      const cropBadge = document.getElementById('screen-rec-crop-badge');
      if (cropBadge) cropBadge.style.display = 'none';

      this.initRecorder(combinedStream, displayStream);
    }

    async startWithCrop(displayStream, cropArea, enableMic = false) {
      this.cleanup();
      this.recordedChunks = [];
      this.durationSec = 0;
      this.currentSizeBytes = 0;
      this.isRecording = false;
      this.isStopping = false;
      this.stopReason = null;

      const maxLenSelect = document.getElementById('rec-screen-max-len');
      const maxSizeSelect = document.getElementById('rec-screen-max-size');
      this.maxDurationSec = maxLenSelect ? parseInt(maxLenSelect.value, 10) || 0 : 0;
      const maxSizeMB = maxSizeSelect ? parseInt(maxSizeSelect.value, 10) || 0 : 0;
      this.maxSizeBytes = maxSizeMB > 0 ? maxSizeMB * 1024 * 1024 : 0;

      this.displayStream = displayStream;

      // 1. Offscreen video element playing the source stream
      const offscreenVid = document.createElement('video');
      offscreenVid.srcObject = displayStream;
      offscreenVid.muted = true;
      offscreenVid.playsInline = true;
      await offscreenVid.play().catch(() => {});

      // 2. Offscreen canvas of the exact cropped section resolution
      const cropCanvas = document.createElement('canvas');
      cropCanvas.width = cropArea.width;
      cropCanvas.height = cropArea.height;
      const cropCtx = cropCanvas.getContext('2d', { alpha: false, desynchronized: true });

      // 3. Render loop using requestAnimationFrame
      let isLooping = true;
      this.cropCancelLoop = () => {
        isLooping = false;
        try {
          offscreenVid.pause();
          offscreenVid.srcObject = null;
        } catch (e) {}
      };

      const renderLoop = () => {
        if (!isLooping) return;
        if (offscreenVid.readyState >= 2) {
          cropCtx.drawImage(
            offscreenVid,
            cropArea.x, cropArea.y, cropArea.width, cropArea.height,
            0, 0, cropArea.width, cropArea.height
          );
        }
        requestAnimationFrame(renderLoop);
      };
      requestAnimationFrame(renderLoop);

      // 4. Capture cropped stream from canvas at 30 fps
      const croppedStream = cropCanvas.captureStream(30);

      // 5. Mix microphone and system audio
      const combinedStream = await this.mixMicrophone(croppedStream, displayStream, enableMic);
      this.stream = combinedStream;

      // Show CROP badge in floating recording bar
      const cropBadge = document.getElementById('screen-rec-crop-badge');
      if (cropBadge) {
        cropBadge.textContent = `${cropArea.width}×${cropArea.height}`;
        cropBadge.style.display = 'inline-block';
      }

      this.initRecorder(combinedStream, displayStream);
    }

    stop() {
      if (activeRecWindow && !activeRecWindow.closed) {
        removeRecWindowHighlight(activeRecWindow);
      }
      if (screenRecFocusBtn) screenRecFocusBtn.style.display = 'none';
      return new Promise((resolve) => {
        if (this.timerInterval) {
          clearInterval(this.timerInterval);
          this.timerInterval = null;
        }
        this.durationSec = Math.max(1, Math.round((Date.now() - this.startTime) / 1000));

        const finish = () => {
          const mimeType = (this.mediaRecorder && this.mediaRecorder.mimeType) || 'video/webm';
          const blob = this.recordedChunks.length > 0 ? new Blob(this.recordedChunks, { type: mimeType }) : null;
          const reason = this.stopReason;
          this.cleanupTracks();
          this.isRecording = false;
          this.isStopping = false;
          resolve({ blob, duration: this.durationSec, stopReason: reason });
        };

        if (!this.mediaRecorder || this.mediaRecorder.state === 'inactive') {
          setTimeout(finish, 60);
          return;
        }

        this.mediaRecorder.onstop = () => {
          setTimeout(finish, 60);
        };

        try {
          this.mediaRecorder.stop();
        } catch (e) {
          finish();
        }
      });
    }

    cleanupTracks() {
      if (this.cropCancelLoop) {
        try { this.cropCancelLoop(); } catch (e) {}
        this.cropCancelLoop = null;
      }
      if (this.stream) {
        this.stream.getTracks().forEach(t => { try { t.stop(); } catch (e) {} });
        this.stream = null;
      }
      if (this.displayStream) {
        this.displayStream.getTracks().forEach(t => { try { t.stop(); } catch (e) {} });
        this.displayStream = null;
      }
      if (this.micStream) {
        this.micStream.getTracks().forEach(t => { try { t.stop(); } catch (e) {} });
        this.micStream = null;
      }
      if (this.audioCtx) {
        try { this.audioCtx.close(); } catch (e) {}
        this.audioCtx = null;
      }
    }

    cleanup() {
      if (activeRecWindow && !activeRecWindow.closed) {
        removeRecWindowHighlight(activeRecWindow);
      }
      if (screenRecFocusBtn) screenRecFocusBtn.style.display = 'none';
      const cropBadge = document.getElementById('screen-rec-crop-badge');
      if (cropBadge) cropBadge.style.display = 'none';
      if (this.timerInterval) {
        clearInterval(this.timerInterval);
        this.timerInterval = null;
      }
      this.cleanupTracks();
      this.mediaRecorder = null;
      this.recordedChunks = [];
      this.isRecording = false;
      this.isStopping = false;
      this.durationSec = 0;
      this.currentSizeBytes = 0;
      this.maxDurationSec = 0;
      this.maxSizeBytes = 0;
      this.stopReason = null;
      if (screenRecTimer) {
        screenRecTimer.textContent = '00:00';
        screenRecTimer.style.color = '#f8fafc';
      }
      if (screenRecSize) {
        screenRecSize.textContent = '0 B';
        screenRecSize.style.color = '#94a3b8';
      }
      if (screenRecBar) screenRecBar.style.display = 'none';
    }
  }

  const screenRecorder = new ScreenRecorder();
  let currentRecordingBlob = null;
  let currentRecordingDuration = 0;

  async function handleStopRecording(reason) {
    if (!screenRecorder.isRecording || screenRecorder.isStopping) return;
    screenRecorder.isStopping = true;
    if (reason) screenRecorder.stopReason = reason;

    if (screenRecBar) screenRecBar.style.display = 'none';
    const result = await screenRecorder.stop();
    if (!result || !result.blob || result.blob.size === 0) {
      alert('No video was recorded or recording was empty.');
      screenRecorder.cleanup();
      return;
    }
    currentRecordingBlob = result.blob;
    currentRecordingDuration = result.duration;

    const durStr = formatDuration(currentRecordingDuration);
    const sizeStr = formatFileSize(result.blob.size);

    if (saveScreenDuration) {
      saveScreenDuration.textContent = `(${durStr}, ${sizeStr})`;
    }

    const stopReason = result.stopReason || screenRecorder.stopReason || reason;
    if (saveScreenLimitNotice && saveScreenLimitMsg) {
      if (stopReason === 'max_len') {
        const maxLenStr = formatDuration(screenRecorder.maxDurationSec || currentRecordingDuration);
        saveScreenLimitMsg.textContent = `Recording reached the maximum length limit (${maxLenStr}) and was stopped automatically.`;
        saveScreenLimitNotice.style.display = 'flex';
      } else if (stopReason === 'max_size') {
        const maxSizeStr = formatFileSize(screenRecorder.maxSizeBytes || result.blob.size);
        saveScreenLimitMsg.textContent = `Recording reached the maximum file size limit (${maxSizeStr}) and was stopped automatically.`;
        saveScreenLimitNotice.style.display = 'flex';
      } else {
        saveScreenLimitNotice.style.display = 'none';
      }
    }

    const nextStepNum = recsList ? recsList.querySelectorAll('.rec-item-wrapper').length + 1 : 1;
    if (saveScreenTitle) {
      saveScreenTitle.value = `Browser Screen - Step ${nextStepNum}`;
    }

    if (saveScreenProgress) saveScreenProgress.style.display = 'none';
    if (saveScreenActions) saveScreenActions.style.display = 'flex';
    if (confirmScreenSaveBtn) confirmScreenSaveBtn.disabled = false;
    if (discardScreenSaveBtn) discardScreenSaveBtn.disabled = false;

    if (saveScreenModal) saveScreenModal.style.display = 'block';
    if (saveScreenTitle) {
      saveScreenTitle.focus();
      saveScreenTitle.select();
    }
  }

  // --- Record Dropdown Menu Handler ---
  if (recordDropdownBtn && recordDropdownMenu) {
    recordDropdownBtn.addEventListener('click', (e) => {
      e.stopPropagation();
      const isOpen = recordDropdownMenu.style.display === 'block';
      recordDropdownMenu.style.display = isOpen ? 'none' : 'block';
    });

    window.addEventListener('click', (e) => {
      if (!recordDropdownBtn.contains(e.target) && !recordDropdownMenu.contains(e.target)) {
        recordDropdownMenu.style.display = 'none';
      }
    });

    window.addEventListener('keydown', (e) => {
      if (e.key === 'Escape' && recordDropdownMenu.style.display === 'block') {
        recordDropdownMenu.style.display = 'none';
      }
    });
  }

  // --- Record Cast Modal Handlers ---
  if (recordCastBtn && recordCastModal) {
    recordCastBtn.addEventListener('click', (e) => {
      e.stopPropagation();
      if (recordDropdownMenu) recordDropdownMenu.style.display = 'none';
      recordCastModal.style.display = 'block';
    });
  }
  if (closeRecordCastModal && recordCastModal) {
    closeRecordCastModal.addEventListener('click', () => {
      recordCastModal.style.display = 'none';
    });
  }
  if (cancelRecordCastBtn && recordCastModal) {
    cancelRecordCastBtn.addEventListener('click', () => {
      recordCastModal.style.display = 'none';
    });
  }
  if (castOpenTermBtn && castNodeSelect) {
    castOpenTermBtn.addEventListener('click', () => {
      const node = castNodeSelect.value;
      if (!node) return;
      if (typeof window.openTerminal === 'function') {
        window.openTerminal(node);
      } else {
        const w = 960, h = 660, t = (window.top.outerHeight / 2) + window.top.screenY - (h / 2), l = (window.top.outerWidth / 2) + window.top.screenX - (w / 2);
        window.open('/terminal/' + encodeURIComponent(node), 'term_' + node.replace(/[^a-zA-Z0-9]/g, '_') + '_' + Date.now(), `width=${w},height=${h},top=${t},left=${l},resizable=yes,scrollbars=yes,popup=yes,menubar=no,toolbar=no,location=no,status=no`);
      }
    });
  }
  if (castImportBtn && importFileInput) {
    castImportBtn.addEventListener('click', () => {
      if (recordCastModal) recordCastModal.style.display = 'none';
      importFileInput.accept = '.cast';
      importFileInput.click();
    });
  }

  const recScreenQualitySelect = document.getElementById('rec-screen-quality');
  const recScreenMaxLenSelect = document.getElementById('rec-screen-max-len');
  const recScreenMaxSizeSelect = document.getElementById('rec-screen-max-size');

  try {
    const savedQuality = localStorage.getItem('ctlabs_screen_rec_quality');
    if (savedQuality && recScreenQualitySelect) {
      recScreenQualitySelect.value = savedQuality;
    }
    const savedMaxLen = localStorage.getItem('ctlabs_screen_rec_max_len');
    if (savedMaxLen !== null && recScreenMaxLenSelect) {
      recScreenMaxLenSelect.value = savedMaxLen;
    }
    const savedMaxSize = localStorage.getItem('ctlabs_screen_rec_max_size');
    if (savedMaxSize !== null && recScreenMaxSizeSelect) {
      recScreenMaxSizeSelect.value = savedMaxSize;
    }
  } catch (e) {}

  if (recScreenQualitySelect) {
    recScreenQualitySelect.addEventListener('change', () => {
      try { localStorage.setItem('ctlabs_screen_rec_quality', recScreenQualitySelect.value); } catch (e) {}
    });
  }
  if (recScreenMaxLenSelect) {
    recScreenMaxLenSelect.addEventListener('change', () => {
      try { localStorage.setItem('ctlabs_screen_rec_max_len', recScreenMaxLenSelect.value); } catch (e) {}
    });
  }
  if (recScreenMaxSizeSelect) {
    recScreenMaxSizeSelect.addEventListener('change', () => {
      try { localStorage.setItem('ctlabs_screen_rec_max_size', recScreenMaxSizeSelect.value); } catch (e) {}
    });
  }

  function switchRecScreenTab(targetTabId) {
    document.querySelectorAll('.rec-screen-tab-btn').forEach(btn => {
      const isTarget = btn.getAttribute('data-tab') === targetTabId;
      btn.style.borderBottom = isTarget ? '2px solid #f43f5e' : '2px solid transparent';
      btn.style.color = isTarget ? '#f8fafc' : '#94a3b8';
      btn.style.fontWeight = isTarget ? '600' : '500';
    });
    document.querySelectorAll('.rec-screen-tab-pane').forEach(pane => {
      pane.style.display = pane.id === targetTabId ? 'block' : 'none';
    });
  }

  document.querySelectorAll('.rec-screen-tab-btn').forEach(btn => {
    btn.addEventListener('click', () => {
      const tabId = btn.getAttribute('data-tab');
      if (tabId) switchRecScreenTab(tabId);
    });
  });

  if (recordScreenBtn) {
    recordScreenBtn.addEventListener('click', () => {
      if (recordDropdownMenu) recordDropdownMenu.style.display = 'none';
      switchRecScreenTab('rec-tab-general');
      const badge = document.getElementById('rec-codec-badge');
      if (badge) badge.textContent = detectSupportedVideoCodec();
      try {
        const savedArea = localStorage.getItem('ctlabs_screen_rec_area');
        if (savedArea) {
          const rad = document.querySelector(`input[name="rec-screen-area"][value="${savedArea}"]`);
          if (rad) rad.checked = true;
        }
      } catch (e) {}
      if (recordScreenModal) recordScreenModal.style.display = 'block';
    });
  }
  if (closeRecordScreenModal) {
    closeRecordScreenModal.addEventListener('click', () => {
      if (recordScreenModal) recordScreenModal.style.display = 'none';
    });
  }
  if (cancelRecordScreenBtn) {
    cancelRecordScreenBtn.addEventListener('click', () => {
      if (recordScreenModal) recordScreenModal.style.display = 'none';
    });
  }

  // --- Screen Recording Crop Area Selector ---
  const screenCropModal = document.getElementById('screen-crop-modal');
  const screenCropStage = document.getElementById('screen-crop-stage');
  const screenCropPreviewVideo = document.getElementById('screen-crop-preview-video');
  const screenCropBoxEl = document.getElementById('screen-crop-box');
  const screenCropBoxLabel = document.getElementById('screen-crop-box-label');
  const screenCropDimsBadge = document.getElementById('screen-crop-dims-badge');
  const closeScreenCropModal = document.getElementById('close-screen-crop-modal');
  const cancelScreenCropBtn = document.getElementById('cancel-screen-crop-btn');
  const confirmScreenCropBtn = document.getElementById('confirm-screen-crop-btn');

  let activeCropStream = null;
  let activeCropEnableMic = false;
  let cropBox = { x: 0, y: 0, w: 0, h: 0 };
  let cropDragState = null;

  function updateCropBoxDOM() {
    if (!screenCropBoxEl || !screenCropStage || !screenCropPreviewVideo) return;
    const stageW = screenCropStage.clientWidth;
    const stageH = screenCropStage.clientHeight;
    if (stageW <= 0 || stageH <= 0) return;

    cropBox.w = Math.max(30, Math.min(cropBox.w, stageW));
    cropBox.h = Math.max(30, Math.min(cropBox.h, stageH));
    cropBox.x = Math.max(0, Math.min(cropBox.x, stageW - cropBox.w));
    cropBox.y = Math.max(0, Math.min(cropBox.y, stageH - cropBox.h));

    screenCropBoxEl.style.left = cropBox.x + 'px';
    screenCropBoxEl.style.top = cropBox.y + 'px';
    screenCropBoxEl.style.width = cropBox.w + 'px';
    screenCropBoxEl.style.height = cropBox.h + 'px';

    const vidW = screenCropPreviewVideo.videoWidth || 1920;
    const vidH = screenCropPreviewVideo.videoHeight || 1080;
    const scaleX = vidW / stageW;
    const scaleY = vidH / stageH;

    const realW = Math.max(32, Math.floor((cropBox.w * scaleX) / 2) * 2);
    const realH = Math.max(32, Math.floor((cropBox.h * scaleY) / 2) * 2);

    const dimsStr = `${realW} &times; ${realH}`;
    if (screenCropDimsBadge) screenCropDimsBadge.innerHTML = dimsStr;
    if (screenCropBoxLabel) screenCropBoxLabel.innerHTML = dimsStr;
  }

  function initCropBox(aspect = 16 / 9) {
    if (!screenCropStage) return;
    const sw = screenCropStage.clientWidth;
    const sh = screenCropStage.clientHeight;
    if (sw <= 0 || sh <= 0) return;

    if (aspect === 'full' || !aspect) {
      cropBox = { x: 0, y: 0, w: sw, h: sh };
    } else {
      let bw = Math.round(sw * 0.75);
      let bh = Math.round(bw / aspect);
      if (bh > sh * 0.85) {
        bh = Math.round(sh * 0.85);
        bw = Math.round(bh * aspect);
      }
      cropBox = {
        x: Math.round((sw - bw) / 2),
        y: Math.round((sh - bh) / 2),
        w: bw,
        h: bh
      };
    }
    updateCropBoxDOM();
  }

  function openScreenCropModal(stream, enableMic) {
    activeCropStream = stream;
    activeCropEnableMic = enableMic;

    if (!screenCropModal || !screenCropPreviewVideo) return;

    screenCropModal.style.display = 'block';
    screenCropPreviewVideo.srcObject = stream;
    screenCropPreviewVideo.play().catch(() => {});

    const setupBox = () => {
      setTimeout(() => {
        initCropBox(16 / 9);
      }, 60);
    };

    if (screenCropPreviewVideo.readyState >= 1) {
      setupBox();
    } else {
      screenCropPreviewVideo.onloadedmetadata = setupBox;
    }

    stream.getVideoTracks().forEach(track => {
      track.onended = () => {
        if (screenCropModal && screenCropModal.style.display === 'block') {
          cancelCropSelection();
        }
      };
    });
  }

  function cancelCropSelection() {
    if (activeCropStream) {
      activeCropStream.getTracks().forEach(t => { try { t.stop(); } catch (e) {} });
      activeCropStream = null;
    }
    if (screenCropPreviewVideo) {
      try {
        screenCropPreviewVideo.pause();
        screenCropPreviewVideo.srcObject = null;
      } catch (e) {}
    }
    if (screenCropModal) screenCropModal.style.display = 'none';
  }

  if (screenCropStage) {
    screenCropStage.addEventListener('mousedown', (e) => {
      if (e.button !== 0) return;
      const rect = screenCropStage.getBoundingClientRect();
      const clickX = e.clientX - rect.left;
      const clickY = e.clientY - rect.top;

      const handle = e.target.getAttribute('data-handle');
      if (handle) {
        cropDragState = {
          type: 'resize',
          handle: handle,
          startX: e.clientX,
          startY: e.clientY,
          initBox: { ...cropBox }
        };
        e.preventDefault();
        e.stopPropagation();
      } else if (e.target === screenCropBoxEl || screenCropBoxEl.contains(e.target)) {
        cropDragState = {
          type: 'move',
          startX: e.clientX,
          startY: e.clientY,
          initBox: { ...cropBox }
        };
        e.preventDefault();
        e.stopPropagation();
      } else {
        cropDragState = {
          type: 'draw',
          startX: clickX,
          startY: clickY
        };
        cropBox = { x: clickX, y: clickY, w: 4, h: 4 };
        updateCropBoxDOM();
        e.preventDefault();
      }
    });
  }

  window.addEventListener('mousemove', (e) => {
    if (!cropDragState || !screenCropStage) return;
    const rect = screenCropStage.getBoundingClientRect();

    if (cropDragState.type === 'move') {
      const dx = e.clientX - cropDragState.startX;
      const dy = e.clientY - cropDragState.startY;
      cropBox.x = cropDragState.initBox.x + dx;
      cropBox.y = cropDragState.initBox.y + dy;
      updateCropBoxDOM();
    } else if (cropDragState.type === 'resize') {
      const dx = e.clientX - cropDragState.startX;
      const dy = e.clientY - cropDragState.startY;
      const h = cropDragState.handle;
      const ib = cropDragState.initBox;

      if (h.includes('e')) cropBox.w = ib.w + dx;
      if (h.includes('s')) cropBox.h = ib.h + dy;
      if (h.includes('w')) {
        const nw = ib.w - dx;
        if (nw >= 30) {
          cropBox.x = ib.x + dx;
          cropBox.w = nw;
        }
      }
      if (h.includes('n')) {
        const nh = ib.h - dy;
        if (nh >= 30) {
          cropBox.y = ib.y + dy;
          cropBox.h = nh;
        }
      }
      updateCropBoxDOM();
    } else if (cropDragState.type === 'draw') {
      const curX = Math.max(0, Math.min(e.clientX - rect.left, screenCropStage.clientWidth));
      const curY = Math.max(0, Math.min(e.clientY - rect.top, screenCropStage.clientHeight));
      cropBox.x = Math.min(cropDragState.startX, curX);
      cropBox.y = Math.min(cropDragState.startY, curY);
      cropBox.w = Math.abs(curX - cropDragState.startX);
      cropBox.h = Math.abs(curY - cropDragState.startY);
      updateCropBoxDOM();
    }
  });

  window.addEventListener('mouseup', () => {
    if (cropDragState) {
      cropDragState = null;
      if (cropBox.w < 20 || cropBox.h < 20) {
        initCropBox(16 / 9);
      }
    }
  });

  document.querySelectorAll('.crop-preset-btn').forEach(btn => {
    btn.addEventListener('click', () => {
      const asp = btn.getAttribute('data-aspect');
      if (asp === '16:9') initCropBox(16 / 9);
      else if (asp === '4:3') initCropBox(4 / 3);
      else if (asp === 'full') initCropBox('full');
    });
  });

  if (confirmScreenCropBtn) {
    confirmScreenCropBtn.addEventListener('click', async () => {
      if (!activeCropStream || !screenCropStage || !screenCropPreviewVideo) return;
      const stageW = screenCropStage.clientWidth;
      const stageH = screenCropStage.clientHeight;
      const vidW = screenCropPreviewVideo.videoWidth || 1920;
      const vidH = screenCropPreviewVideo.videoHeight || 1080;
      const scaleX = vidW / stageW;
      const scaleY = vidH / stageH;

      let rx = Math.round(cropBox.x * scaleX);
      let ry = Math.round(cropBox.y * scaleY);
      let rw = Math.max(32, Math.floor((cropBox.w * scaleX) / 2) * 2);
      let rh = Math.max(32, Math.floor((cropBox.h * scaleY) / 2) * 2);

      rx = Math.max(0, Math.min(rx, vidW - rw));
      ry = Math.max(0, Math.min(ry, vidH - rh));

      const cropArea = { x: rx, y: ry, width: rw, height: rh };
      const stream = activeCropStream;
      const mic = activeCropEnableMic;

      activeCropStream = null;
      if (screenCropPreviewVideo) {
        try {
          screenCropPreviewVideo.pause();
          screenCropPreviewVideo.srcObject = null;
        } catch (e) {}
      }
      if (screenCropModal) screenCropModal.style.display = 'none';

      try {
        await screenRecorder.startWithCrop(stream, cropArea, mic);
      } catch (err) {
        console.error('Failed to start cropped screen recording:', err);
        alert('Could not start cropped recording: ' + err.message);
        screenRecorder.cleanup();
      }
    });
  }

  if (closeScreenCropModal) closeScreenCropModal.addEventListener('click', cancelCropSelection);
  if (cancelScreenCropBtn) cancelScreenCropBtn.addEventListener('click', cancelCropSelection);

  if (confirmRecordScreenBtn) {
    confirmRecordScreenBtn.addEventListener('click', async () => {
      if (recordScreenModal) recordScreenModal.style.display = 'none';
      try {
        if (recScreenQualitySelect) localStorage.setItem('ctlabs_screen_rec_quality', recScreenQualitySelect.value);
        if (recScreenMaxLenSelect) localStorage.setItem('ctlabs_screen_rec_max_len', recScreenMaxLenSelect.value);
        if (recScreenMaxSizeSelect) localStorage.setItem('ctlabs_screen_rec_max_size', recScreenMaxSizeSelect.value);
      } catch (e) {}
      const enableMic = recScreenMic ? recScreenMic.checked : false;
      const areaRadio = document.querySelector('input[name="rec-screen-area"]:checked');
      const area = areaRadio ? areaRadio.value : 'full';
      try { localStorage.setItem('ctlabs_screen_rec_area', area); } catch (e) {}

      if (area === 'crop') {
        try {
          const displayStream = await acquireDisplayStream();
          openScreenCropModal(displayStream, enableMic);
        } catch (err) {
          console.error('Failed to acquire screen stream for crop:', err);
          if (err.name !== 'NotAllowedError') {
            alert('Could not start screen capture: ' + err.message);
          }
        }
      } else {
        try {
          await screenRecorder.start(enableMic);
        } catch (err) {
          console.error('Failed to start screen recording:', err);
          if (err.name !== 'NotAllowedError') {
            alert('Could not start screen recording: ' + err.message);
          }
          screenRecorder.cleanup();
        }
      }
    });
  }

  if (launchRecWinBtn) {
    launchRecWinBtn.addEventListener('click', () => {
      const rawUrl = (recWinUrlInput ? recWinUrlInput.value.trim() : '') || '/labs';
      const url = normalizeRecUrl(rawUrl);
      if (recWinUrlInput) recWinUrlInput.value = url;
      const mode = (recWinResSelect ? recWinResSelect.value : '') || '1280x720';

      recWindowLaunched = true;
      recWindowUrl = url;
      recWindowIsCross = isCrossOriginUrl(url);

      try {
        if (activeRecWindow && !activeRecWindow.closed) {
          activeRecWindow.location.href = url;
          focusTargetWindow();
        } else if (mode === 'tab' || mode === 'standard') {
          activeRecWindow = window.open(url, 'ctlabs_recorder_window');
          if (activeRecWindow) focusTargetWindow();
        } else {
          // Open as clean popup with fixed dimensions
          const [wStr, hStr] = mode.split('x');
          const width = parseInt(wStr, 10) || 1280;
          const height = parseInt(hStr, 10) || 720;
          const screenW = window.screen.availWidth || window.screen.width || 1280;
          const screenH = window.screen.availHeight || window.screen.height || 800;
          const left = Math.max(0, Math.round((screenW - width) / 2));
          const top = Math.max(0, Math.round((screenH - height) / 2));
          const windowFeatures = `width=${width},height=${height},left=${left},top=${top},menubar=no,toolbar=no,location=no,status=no,resizable=yes,scrollbars=yes`;
          activeRecWindow = window.open(url, 'ctlabs_recorder_window', windowFeatures);
          if (activeRecWindow) focusTargetWindow();
        }
      } catch (err) {
        console.warn('Could not launch or focus window:', err);
      }

      updateRecWindowUI();
      if (activeRecWindow) {
        const checkLoadedInterval = setInterval(() => {
          if (!recWindowIsCross && (!activeRecWindow || activeRecWindow.closed)) {
            clearInterval(checkLoadedInterval);
            recWindowLaunched = false;
            updateRecWindowUI();
            return;
          }
          markTargetWindowRecTitle(activeRecWindow);
          updateRecWindowUI();
        }, 1000);
      }
    });
  }

  if (focusRecWinBtn) {
    focusRecWinBtn.addEventListener('click', () => {
      focusTargetWindow();
    });
  }

  if (closeRecWinBtn) {
    closeRecWinBtn.addEventListener('click', () => {
      try {
        if (activeRecWindow && !activeRecWindow.closed) {
          activeRecWindow.close();
        }
      } catch (e) {}
      activeRecWindow = null;
      recWindowLaunched = false;
      recWindowIsCross = false;
      updateRecWindowUI();
    });
  }

  if (screenRecFocusBtn) {
    screenRecFocusBtn.addEventListener('click', () => {
      focusTargetWindow();
    });
  }

  if (screenRecStopBtn) {
    screenRecStopBtn.addEventListener('click', () => {
      handleStopRecording();
    });
  }

  if (screenRecCancelBtn) {
    screenRecCancelBtn.addEventListener('click', () => {
      if (confirm('Discard this screen recording?')) {
        screenRecorder.cleanup();
        currentRecordingBlob = null;
      }
    });
  }

  if (confirmScreenSaveBtn) {
    confirmScreenSaveBtn.addEventListener('click', async () => {
      if (!currentRecordingBlob) return;
      const title = (saveScreenTitle ? saveScreenTitle.value.trim() : '') || 'Browser Screen';

      if (saveScreenProgress) saveScreenProgress.style.display = 'flex';
      if (confirmScreenSaveBtn) confirmScreenSaveBtn.disabled = true;
      if (discardScreenSaveBtn) discardScreenSaveBtn.disabled = true;

      try {
        const formData = new FormData();
        formData.append('video', currentRecordingBlob, 'screen.webm');
        formData.append('title', title);
        formData.append('duration', currentRecordingDuration);
        formData.append('walkthrough', activeWalkthrough);

        const resp = await fetch('/recordings/upload-video', {
          method: 'POST',
          body: formData,
          credentials: 'same-origin'
        });

        const data = await resp.json();
        if (resp.ok && (data.ok || data.success)) {
          if (saveScreenModal) saveScreenModal.style.display = 'none';
          currentRecordingBlob = null;
          const nextId = data.id;
          const targetWk = data.walkthrough || activeWalkthrough;
          const targetUrl = new URL(window.location);
          if (targetWk) targetUrl.searchParams.set('walkthrough', targetWk);
          if (nextId) targetUrl.searchParams.set('recording', nextId);
          window.location.href = targetUrl.toString();
        } else {
          alert('Failed to save screen recording: ' + (data.error || 'Server error'));
          if (saveScreenProgress) saveScreenProgress.style.display = 'none';
          if (confirmScreenSaveBtn) confirmScreenSaveBtn.disabled = false;
          if (discardScreenSaveBtn) discardScreenSaveBtn.disabled = false;
        }
      } catch (err) {
        console.error('Error saving recording:', err);
        alert('Error saving screen recording: ' + err.message);
        if (saveScreenProgress) saveScreenProgress.style.display = 'none';
        if (confirmScreenSaveBtn) confirmScreenSaveBtn.disabled = false;
        if (discardScreenSaveBtn) discardScreenSaveBtn.disabled = false;
      }
    });
  }

  if (discardScreenSaveBtn) {
    discardScreenSaveBtn.addEventListener('click', () => {
      currentRecordingBlob = null;
      if (saveScreenModal) saveScreenModal.style.display = 'none';
    });
  }

  function play(src, label, id, step, title, dataType, autoPlay = false) {
    if (!src) return;
    activeId = id;
    activeDataType = dataType || 'cast';
    window.activeId = activeId;
    window.activeDataType = activeDataType;
    const formRecInput = document.getElementById('walkthrough-form-recording');
    if (formRecInput) formRecInput.value = id || '';

    if (player && typeof player.dispose === 'function') {
      try { player.dispose(); } catch (e) {}
      player = null;
    }
    demoDiv.innerHTML = '';
    const fullTitleText = (step ? '#' + step + ': ' : '') + (title || label);
    titleEl.querySelector('span').textContent = fullTitleText;
    titleEl.title = fullTitleText;
    actionsEl.style.display = 'flex';
    downloadEl.href = src + '?download=1';
    deleteForm.action = src + '/delete';
    if (metaForm) metaForm.action = src + '/meta';
    if (editTitle) editTitle.value = title || '';

    const deleteBtn = deleteForm ? deleteForm.querySelector('button') : null;
    if (deleteBtn) {
      deleteBtn.disabled = false;
      deleteBtn.title = 'Delete this step';
      deleteBtn.style.opacity = '1';
      deleteBtn.style.cursor = 'pointer';
    }

    if (activeDataType === 'markdown') {
      const videoAnnBtn = document.getElementById('video-annotate-toggle-btn');
      if (videoAnnBtn) videoAnnBtn.style.display = 'none';
      if (window.VideoAnnotations && typeof window.VideoAnnotations.clear === 'function') window.VideoAnnotations.clear();
      if (demoContainer) demoContainer.style.display = 'none';
      if (videoContainer) videoContainer.style.display = 'none';
      if (videoPlayer) { videoPlayer.pause(); videoPlayer.src = ''; }
      if (mdContainer) mdContainer.style.display = 'flex';
      let mdMode = 'preview';
      if (pendingMdEditMode) {
        pendingMdEditMode = false;
        mdMode = (window.MarkdownEditor && typeof window.MarkdownEditor.getSplitMode === 'function' && window.MarkdownEditor.getSplitMode())
          ? 'split'
          : 'edit';
      }
      if (mdSettingsWrapper) mdSettingsWrapper.style.display = (mdMode === 'preview') ? 'none' : 'inline-block';
      if (mdSettingsDivider) mdSettingsDivider.style.display = 'none';
      if (mdInsertImgBtn) mdInsertImgBtn.title = 'Upload picture or import markdown / zip note (or drag & drop)';
      if (mdGraphvizBtn) mdGraphvizBtn.style.display = (mdMode === 'preview') ? 'none' : 'inline-flex';
      if (mdSaveBtn) mdSaveBtn.style.display = (mdMode === 'preview') ? 'none' : 'inline-flex';
      if (mdGitWrapper) mdGitWrapper.style.display = (mdMode === 'preview') ? 'none' : 'inline-block';
      const mdTabEditBtn = document.getElementById('md-tab-edit');
      const mdTabViewBtn = document.getElementById('md-tab-preview');
      if (mdTabEditBtn) mdTabEditBtn.style.display = (mdMode === 'preview') ? 'inline-flex' : 'none';
      if (mdTabViewBtn) mdTabViewBtn.style.display = (mdMode === 'preview') ? 'none' : 'inline-flex';
      if (titleIcon) {
        titleIcon.className = 'fab fa-markdown';
        titleIcon.style.color = '#38bdf8';
      }
      if (window.MarkdownEditor && typeof window.MarkdownEditor.loadContent === 'function') {
        window.MarkdownEditor.loadContent(id);
      } else if (typeof loadMarkdownContent === 'function') {
        loadMarkdownContent(id);
      }
      if (window.MarkdownEditor && typeof window.MarkdownEditor.setMode === 'function') {
        window.MarkdownEditor.setMode(mdMode);
      } else if (typeof setMdMode === 'function') {
        setMdMode(mdMode);
      }
    } else if (activeDataType === 'video') {
      if (demoContainer) demoContainer.style.display = 'none';
      if (mdContainer) mdContainer.style.display = 'none';
      if (videoContainer) videoContainer.style.display = 'flex';
      if (mdSettingsWrapper) mdSettingsWrapper.style.display = 'none';
      if (mdSettingsDivider) mdSettingsDivider.style.display = 'none';
      if (mdInsertImgBtn) mdInsertImgBtn.title = 'Import recording / walkthrough';
      if (mdGraphvizBtn) mdGraphvizBtn.style.display = 'none';
      if (mdSaveBtn) mdSaveBtn.style.display = 'none';
      if (mdGitWrapper) mdGitWrapper.style.display = 'none';
      const mdTabEditVideo = document.getElementById('md-tab-edit');
      if (mdTabEditVideo) mdTabEditVideo.style.display = 'none';
      const videoAnnBtn = document.getElementById('video-annotate-toggle-btn');
      if (videoAnnBtn) videoAnnBtn.style.display = 'inline-flex';
      if (window.VideoAnnotations && typeof window.VideoAnnotations.loadForRecording === 'function') {
        window.VideoAnnotations.loadForRecording(id);
      }
      if (titleIcon) {
        titleIcon.className = 'fas fa-video';
        titleIcon.style.color = '#f43f5e';
      }
      if (videoPlayer) {
        videoPlayer.src = src;
        videoPlayer.onloadedmetadata = () => {
          let dur = videoPlayer.duration;
          const syncDurationUI = (discoveredDur) => {
            if (discoveredDur && !isNaN(discoveredDur) && isFinite(discoveredDur) && discoveredDur > 0 && activeId && activeDataType === 'video') {
              const activeBtn = document.querySelector(`.rec-item[data-id="${CSS.escape(activeId)}"]`);
              if (activeBtn) {
                activeBtn.setAttribute('data-duration', String(discoveredDur));
                const row1 = activeBtn.children[0];
                const durEl = row1 ? row1.children[1] : null;
                if (durEl && (durEl.textContent.trim() === '0s' || durEl.textContent.trim() === '0.0s')) {
                  const formatted = (discoveredDur < 60) ? `${discoveredDur.toFixed(1)}s` : `${Math.floor(discoveredDur / 60)}m ${Math.floor(discoveredDur % 60).toString().padStart(2, '0')}s`;
                  durEl.textContent = formatted;
                  fetch(`/recordings/${encodeURIComponent(activeId)}/duration`, {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
                    body: `duration=${encodeURIComponent(discoveredDur)}`
                  }).catch(() => {});
                }
              }
            }
          };

          if (!isFinite(dur) || dur === Infinity) {
            // Chrome WebM Infinity duration workaround: seek to 1e101 to force demuxer to resolve EOF cluster timestamp
            const onSeekDiscovered = () => {
              videoPlayer.removeEventListener('timeupdate', onSeekDiscovered);
              videoPlayer.currentTime = 0;
              const fixedDur = videoPlayer.duration;
              syncDurationUI(fixedDur);
              if (autoPlay) {
                videoPlayer.play().catch(() => {});
              }
            };
            videoPlayer.addEventListener('timeupdate', onSeekDiscovered, { once: true });
            videoPlayer.currentTime = 1e101;
            return;
          }

          syncDurationUI(dur);
        };
        if (autoPlay) {
          videoPlayer.play().catch(() => {});
        }
      }
    } else {
      if (mdContainer) mdContainer.style.display = 'none';
      if (videoContainer) videoContainer.style.display = 'none';
      if (videoPlayer) { videoPlayer.pause(); videoPlayer.src = ''; }
      if (demoContainer) demoContainer.style.display = 'flex';
      if (mdSettingsWrapper) mdSettingsWrapper.style.display = 'none';
      if (mdSettingsDivider) mdSettingsDivider.style.display = 'none';
      if (mdInsertImgBtn) mdInsertImgBtn.title = 'Import recording / walkthrough';
      if (mdGraphvizBtn) mdGraphvizBtn.style.display = 'none';
      if (mdSaveBtn) mdSaveBtn.style.display = 'none';
      if (mdGitWrapper) mdGitWrapper.style.display = 'none';
      const mdTabEditVideo = document.getElementById('md-tab-edit');
      if (mdTabEditVideo) mdTabEditVideo.style.display = 'none';
      const videoAnnBtn = document.getElementById('video-annotate-toggle-btn');
      if (videoAnnBtn) videoAnnBtn.style.display = 'none';
      if (window.VideoAnnotations && typeof window.VideoAnnotations.clear === 'function') {
        window.VideoAnnotations.clear();
      }
      if (titleIcon) {
        titleIcon.className = 'fas fa-play-circle w3-text-green';
        titleIcon.style.color = '';
      }
      if (typeof AsciinemaPlayer !== 'undefined' && typeof AsciinemaPlayer.create === 'function') {
        player = AsciinemaPlayer.create(src, demoDiv, { fit: 'both', autoplay: autoPlay, autoPlay: autoPlay });
        if (autoPlay && player && typeof player.play === 'function') {
          try {
            const p = player.play();
            if (p && typeof p.catch === 'function') p.catch(() => {});
          } catch (e) {}
        }
      } else {
        titleEl.querySelector('span').textContent = 'Asciinema player not loaded';
      }
    }
  }

  function selectRecording(btn, autoPlay = false) {
    if (!btn) return;
    const isDirty = (window.MarkdownEditor && typeof window.MarkdownEditor.isDirty === 'function')
      ? window.MarkdownEditor.isDirty()
      : ((typeof mdIsDirty !== 'undefined') ? mdIsDirty : false);
    if (isDirty && activeId && activeDataType === 'markdown') {
      if (window.MarkdownEditor && typeof window.MarkdownEditor.saveContent === 'function') {
        window.MarkdownEditor.saveContent(true);
      } else if (typeof saveMarkdownContent === 'function') {
        saveMarkdownContent(true);
      }
    }
    document.querySelectorAll('.rec-item').forEach(b => b.classList.remove('active'));
    btn.classList.add('active');
    const src = btn.getAttribute('data-src');
    const id = btn.getAttribute('data-id');
    const step = btn.getAttribute('data-step');
    const title = btn.getAttribute('data-title');
    const dataType = btn.getAttribute('data-type') || 'cast';
    const node = btn.querySelectorAll('div')[0] ? btn.querySelectorAll('div')[0].textContent.trim() : src;
    play(src, node, id, step, title, dataType, autoPlay);
    updateStepNav();

    // Persist the last highlighted step in localStorage, browser URL, and session
    if (id) {
      try {
        localStorage.setItem('ctlabs_last_step_' + activeWalkthrough, id);
        const url = new URL(window.location);
        url.searchParams.set('walkthrough', activeWalkthrough);
        url.searchParams.set('recording', id);
        window.history.replaceState({}, '', url);
      } catch (e) {}

      try {
        fetch('/recordings/' + encodeURIComponent(id) + '/active?walkthrough=' + encodeURIComponent(activeWalkthrough), {
          method: 'POST',
          credentials: 'same-origin'
        }).catch(() => {});
      } catch (e) {}
    }
  }
  window.selectRecording = selectRecording;
  window.play = play;

  // --- Step Navigation Controls ---
  function getStepButtons() {
    return Array.from(recsList ? recsList.querySelectorAll('.rec-item-wrapper .rec-item') : []);
  }

  function updateStepNav() {
    if (!stepPrevBtn || !stepNextBtn || !stepNavCounter) return;
    const stepButtons = getStepButtons();
    const totalSteps = stepButtons.length;

    if (totalSteps === 0) {
      stepNavCounter.textContent = 'No steps';
      stepPrevBtn.disabled = true;
      stepNextBtn.disabled = true;
      stepPrevBtn.title = 'No steps in this set';
      stepNextBtn.title = 'No steps in this set';
      return;
    }

    const currentIndex = stepButtons.findIndex(b => b.getAttribute('data-id') === activeId);

    if (currentIndex === -1) {
      stepNavCounter.textContent = `-- / ${totalSteps}`;
      stepPrevBtn.disabled = true;
      stepPrevBtn.title = 'No step selected';
      stepNextBtn.disabled = false;
      stepNextBtn.title = 'Start with Step 1 (Alt+Right)';
    } else {
      stepNavCounter.textContent = `Step ${currentIndex + 1} of ${totalSteps}`;
      stepPrevBtn.disabled = (currentIndex === 0);
      stepNextBtn.disabled = (currentIndex === totalSteps - 1);

      if (currentIndex > 0) {
        stepPrevBtn.title = `Previous: Step ${currentIndex} (Alt+Left, PageUp)`;
      } else {
        stepPrevBtn.title = 'First step reached';
      }

      if (currentIndex < totalSteps - 1) {
        stepNextBtn.title = `Next: Step ${currentIndex + 2} (Alt+Right, PageDown)`;
      } else {
        stepNextBtn.title = 'Last step reached';
      }
    }
  }

  function goToPreviousStep(autoPlay = true) {
    const stepButtons = getStepButtons();
    if (stepButtons.length === 0) return;
    const currentIndex = stepButtons.findIndex(b => b.getAttribute('data-id') === activeId);
    if (currentIndex > 0) {
      const targetBtn = stepButtons[currentIndex - 1];
      selectRecording(targetBtn, autoPlay);
      targetBtn.scrollIntoView({ block: 'nearest', behavior: 'smooth' });
    }
  }

  function goToNextStep(autoPlay = true) {
    const stepButtons = getStepButtons();
    if (stepButtons.length === 0) return;
    const currentIndex = stepButtons.findIndex(b => b.getAttribute('data-id') === activeId);
    if (currentIndex === -1) {
      const targetBtn = stepButtons[0];
      selectRecording(targetBtn, autoPlay);
      targetBtn.scrollIntoView({ block: 'nearest', behavior: 'smooth' });
    } else if (currentIndex < stepButtons.length - 1) {
      const targetBtn = stepButtons[currentIndex + 1];
      selectRecording(targetBtn, autoPlay);
      targetBtn.scrollIntoView({ block: 'nearest', behavior: 'smooth' });
    }
  }

  if (stepPrevBtn) stepPrevBtn.addEventListener('click', () => goToPreviousStep(true));
  if (stepNextBtn) stepNextBtn.addEventListener('click', () => goToNextStep(true));

  window.addEventListener('keydown', (e) => {
    if (imageModal && imageModal.style.display === 'flex') {
      if (e.key === 'Escape') {
        closeImageModal();
        return;
      }
      if (e.key === '+' || e.key === '=') {
        e.preventDefault();
        zoomImageModalBy(1.25);
        return;
      }
      if (e.key === '-' || e.key === '_') {
        e.preventDefault();
        zoomImageModalBy(1 / 1.25);
        return;
      }
      if (e.key === '0') {
        e.preventDefault();
        resetImageModalZoom();
        return;
      }
      if (e.key === 'f' || e.key === 'F') {
        e.preventDefault();
        fitImageModalToView();
        return;
      }
      if (e.key === 'ArrowLeft') {
        e.preventDefault();
        imageModalPanX += 60;
        applyImageModalTransform();
        return;
      }
      if (e.key === 'ArrowRight') {
        e.preventDefault();
        imageModalPanX -= 60;
        applyImageModalTransform();
        return;
      }
      if (e.key === 'ArrowUp') {
        e.preventDefault();
        imageModalPanY += 60;
        applyImageModalTransform();
        return;
      }
      if (e.key === 'ArrowDown') {
        e.preventDefault();
        imageModalPanY -= 60;
        applyImageModalTransform();
        return;
      }
      return;
    }

    if (e.key === 'Escape') {
      const deleteModal = document.getElementById('delete-set-modal');
      if (deleteModal && deleteModal.style.display === 'block') deleteModal.style.display = 'none';
      const exportModal = document.getElementById('export-modal');
      if (exportModal && exportModal.style.display === 'block') exportModal.style.display = 'none';
      const exportNoteModalEl = document.getElementById('export-note-modal');
      if (exportNoteModalEl && exportNoteModalEl.style.display === 'block') exportNoteModalEl.style.display = 'none';
      if (mdSettingsMenu && mdSettingsMenu.style.display === 'block') {
        mdSettingsMenu.style.display = 'none';
        if (mdSettingsBtn) {
          mdSettingsBtn.style.background = '#1e293b';
          mdSettingsBtn.style.borderColor = '#475569';
        }
      }
      if (mdEmojiMenu && mdEmojiMenu.style.display === 'flex') {
        if (typeof toggleMdEmojiMenu === 'function') {
          toggleMdEmojiMenu(false);
        } else if (window.MarkdownEditor && typeof window.MarkdownEditor.toggleEmoji === 'function') {
          window.MarkdownEditor.toggleEmoji(false);
        } else {
          mdEmojiMenu.style.display = 'none';
        }
      }
      if (recordScreenModal && recordScreenModal.style.display === 'block') recordScreenModal.style.display = 'none';
    }

    const isEditing = ['INPUT', 'TEXTAREA'].includes(document.activeElement?.tagName);
    if (isEditing) return;

    if ((e.altKey && e.key === 'ArrowLeft') || e.key === 'PageUp') {
      e.preventDefault();
      goToPreviousStep(true);
    } else if ((e.altKey && e.key === 'ArrowRight') || e.key === 'PageDown') {
      e.preventDefault();
      goToNextStep(true);
    }
  });

  // Click handlers for selecting items
  document.querySelectorAll('.rec-item').forEach((btn) => {
    btn.addEventListener('click', () => selectRecording(btn));
  });

  // Keep the step the user was editing selected, or restore the last highlighted step, or select the first item
  let initialItem = null;
  if (preferredRecording) {
    initialItem = Array.from(document.querySelectorAll('.rec-item')).find(btn => btn.getAttribute('data-id') === preferredRecording) || null;
  }
  if (!initialItem) {
    try {
      const lastStepId = localStorage.getItem('ctlabs_last_step_' + activeWalkthrough);
      if (lastStepId) {
        initialItem = Array.from(document.querySelectorAll('.rec-item')).find(btn => btn.getAttribute('data-id') === lastStepId) || null;
      }
    } catch (e) {}
  }
  initialItem = initialItem || document.querySelector('.rec-item') || null;
  if (initialItem) {
    selectRecording(initialItem);
    initialItem.scrollIntoView({ block: 'nearest' });
  } else {
    updateStepNav();
  }

  // --- Sidebar Resize & Collapse/Expand ---
  const sidebarEl = document.getElementById('walkthrough-sidebar');
  const sidebarDivider = document.getElementById('sidebar-divider');
  const sidebarCollapseBtn = document.getElementById('sidebar-collapse-btn');
  const sidebarExpandBtn = document.getElementById('sidebar-expand-btn');

  if (sidebarEl && sidebarDivider) {
    function updateSidebarCompactState(width) {
      if (!sidebarEl) return;
      const w = Number(width) || (sidebarEl.getBoundingClientRect ? sidebarEl.getBoundingClientRect().width : 340);
      if (w < 360) {
        sidebarEl.classList.add('sidebar-compact');
      } else {
        sidebarEl.classList.remove('sidebar-compact');
      }
      if (w < 240) {
        sidebarEl.classList.add('sidebar-mini');
      } else {
        sidebarEl.classList.remove('sidebar-mini');
      }
    }

    const savedWidth = localStorage.getItem('ctlabs_sidebar_width');
    let initialW = 340;
    if (savedWidth) {
      const w = parseInt(savedWidth, 10);
      if (!isNaN(w) && w >= 180 && w <= 900) {
        sidebarEl.style.width = w + 'px';
        initialW = w;
      }
    }
    updateSidebarCompactState(initialW);

    function refreshMdEditor() {
      const cm = (window.MarkdownEditor && typeof window.MarkdownEditor.getEditor === 'function')
        ? window.MarkdownEditor.getEditor()
        : ((typeof getMdEditor === 'function') ? getMdEditor() : null);
      if (cm && mdEditPane && mdEditPane.style.display !== 'none') {
        cm.refresh();
      }
    }

    function setSidebarCollapsed(collapsed) {
      if (collapsed) {
        sidebarEl.style.display = 'none';
        sidebarDivider.style.display = 'none';
        if (sidebarExpandBtn) sidebarExpandBtn.style.display = 'inline-flex';
        localStorage.setItem('ctlabs_sidebar_collapsed', 'true');
      } else {
        sidebarEl.style.display = 'flex';
        sidebarDivider.style.display = 'flex';
        if (sidebarExpandBtn) sidebarExpandBtn.style.display = 'none';
        localStorage.setItem('ctlabs_sidebar_collapsed', 'false');
        const curW = sidebarEl.getBoundingClientRect().width || 340;
        updateSidebarCompactState(curW);
      }
      refreshMdEditor();
      requestAnimationFrame(() => refreshMdEditor());
      setTimeout(refreshMdEditor, 40);
      setTimeout(refreshMdEditor, 120);
    }

    if (localStorage.getItem('ctlabs_sidebar_collapsed') === 'true') {
      setSidebarCollapsed(true);
    }

    if (sidebarCollapseBtn) {
      sidebarCollapseBtn.addEventListener('click', (e) => {
        e.stopPropagation();
        setSidebarCollapsed(true);
      });
    }
    if (sidebarExpandBtn) {
      sidebarExpandBtn.addEventListener('click', (e) => {
        e.stopPropagation();
        setSidebarCollapsed(false);
      });
    }

    // Double-click on vertical divider toggles collapse/expand
    sidebarDivider.addEventListener('dblclick', (e) => {
      e.preventDefault();
      const isCurrentlyCollapsed = (sidebarEl.style.display === 'none');
      setSidebarCollapsed(!isCurrentlyCollapsed);
    });

    // Horizontal drag-to-resize sidebar width
    let isResizingSidebar = false;
    let startX = 0;
    let startWidth = 0;

    sidebarDivider.addEventListener('mousedown', (e) => {
      if (e.button !== 0) return;
      isResizingSidebar = true;
      startX = e.clientX;
      startWidth = sidebarEl.getBoundingClientRect().width;
      sidebarDivider.classList.add('dragging');
      document.body.style.cursor = 'col-resize';
      document.body.style.userSelect = 'none';
    });

    window.addEventListener('mousemove', (e) => {
      if (!isResizingSidebar) return;
      const deltaX = e.clientX - startX;
      const containerWidth = sidebarEl.parentElement ? sidebarEl.parentElement.getBoundingClientRect().width : window.innerWidth;
      const targetW = startWidth + deltaX;

      // Auto-collapse if dragged towards the left edge
      if (targetW < 120) {
        setSidebarCollapsed(true);
        return;
      }

      if (sidebarEl.style.display === 'none') {
        setSidebarCollapsed(false);
      }

      const minW = 180;
      const maxW = Math.min(850, Math.floor(containerWidth * 0.75));
      const newW = Math.min(maxW, Math.max(minW, targetW));
      sidebarEl.style.width = newW + 'px';
      updateSidebarCompactState(newW);
      refreshMdEditor();
    });

    window.addEventListener('mouseup', () => {
      if (!isResizingSidebar) return;
      isResizingSidebar = false;
      sidebarDivider.classList.remove('dragging');
      document.body.style.cursor = '';
      document.body.style.userSelect = '';
      if (sidebarEl.style.display !== 'none') {
        const finalWidth = sidebarEl.getBoundingClientRect().width;
        localStorage.setItem('ctlabs_sidebar_width', Math.round(finalWidth));
        updateSidebarCompactState(finalWidth);
      }
      refreshMdEditor();
      requestAnimationFrame(() => refreshMdEditor());
      setTimeout(refreshMdEditor, 40);
    });

    window.addEventListener('resize', () => {
      refreshMdEditor();
    });
  }

  // --- Movable Divider / Resizer between Walkthrough Set and Other Recordings ---
  const setDivider = document.getElementById('set-divider');
  const otherSection = document.getElementById('other-section');
  const sidebar = setDivider ? setDivider.closest('aside') : null;

  if (setDivider && otherSection && sidebar) {
    const savedHeight = localStorage.getItem('ctlabs_other_section_height');
    if (savedHeight) {
      const h = parseInt(savedHeight, 10);
      if (!isNaN(h) && h >= 60) {
        otherSection.style.height = h + 'px';
      }
    }

    let isDragging = false;
    let startY = 0;
    let startHeight = 0;

    setDivider.addEventListener('mousedown', (e) => {
      isDragging = true;
      startY = e.clientY;
      startHeight = otherSection.getBoundingClientRect().height;
      setDivider.classList.add('dragging');
      document.body.style.cursor = 'row-resize';
      document.body.style.userSelect = 'none';
    });

    window.addEventListener('mousemove', (e) => {
      if (!isDragging) return;
      const deltaY = startY - e.clientY; // Dragging UP increases height of otherSection
      const sidebarHeight = sidebar.getBoundingClientRect().height;
      const minHeight = 60;
      const maxHeight = Math.max(minHeight, sidebarHeight - 160);
      const newHeight = Math.min(maxHeight, Math.max(minHeight, startHeight + deltaY));
      otherSection.style.height = newHeight + 'px';
    });

    window.addEventListener('mouseup', () => {
      if (!isDragging) return;
      isDragging = false;
      setDivider.classList.remove('dragging');
      document.body.style.cursor = '';
      document.body.style.userSelect = '';
      localStorage.setItem('ctlabs_other_section_height', parseInt(otherSection.style.height, 10));
    });
  }

  // --- Drag and Drop: reorder in the set, pull in from "Other", or move to "Other" ---
  // (draggedItem and draggedSource are declared above)

  function clearDragStyles() {
    document.querySelectorAll('.rec-item-wrapper').forEach(w => {
      w.style.opacity = '1';
      w.style.borderTop = '1px solid #334155';
    });
    const recsEnd = document.getElementById('recs-end-drop');
    if (recsEnd) recsEnd.style.borderTop = '2px solid transparent';
    const otherEnd = document.getElementById('other-end-drop');
    if (otherEnd) otherEnd.style.borderTop = '2px solid transparent';
    if (recsList) recsList.style.boxShadow = '';
    if (otherList) otherList.style.boxShadow = '';
  }

  function beginDrag(e) {
    draggedItem = e.target.closest('.rec-item-wrapper');
    if (draggedItem) {
      draggedSource = recsList.contains(draggedItem) ? 'recs' : 'other';
      draggedItem.style.opacity = '0.4';
      e.dataTransfer.effectAllowed = 'move';
    }
  }

  [recsList, otherList].forEach(list => {
    if (list) list.addEventListener('dragstart', beginDrag);
  });

  document.addEventListener('dragend', () => {
    clearDragStyles();
    draggedItem = null;
    draggedSource = null;
  });

  // --- recsList dragover & drop (Walkthrough Set) ---
  recsList.addEventListener('dragover', (e) => {
    if (!draggedItem) return;

    recsList.style.boxShadow = '';
    e.preventDefault();
    e.dataTransfer.dropEffect = 'move';
    const endZone = document.getElementById('recs-end-drop');
    if (endZone) {
      endZone.style.borderTop = (e.target === endZone) ? '2px solid #38bdf8' : '2px solid transparent';
    }
    const targetWrapper = e.target.closest('.rec-item-wrapper');
    if (targetWrapper && targetWrapper !== draggedItem && recsList.contains(targetWrapper)) {
      const rect = targetWrapper.getBoundingClientRect();
      const midpoint = rect.top + rect.height / 2;
      targetWrapper.style.borderTop = (e.clientY < midpoint) ? '2px solid #38bdf8' : '1px solid #334155';
    }
  });

  recsList.addEventListener('dragleave', (e) => {
    const targetWrapper = e.target.closest('.rec-item-wrapper');
    if (targetWrapper) targetWrapper.style.borderTop = '1px solid #334155';
    if (!recsList.contains(e.relatedTarget)) {
      recsList.style.boxShadow = '';
    }
  });

  function placeInSet(e) {
    const endZone = document.getElementById('recs-end-drop');
    const targetWrapper = e.target.closest('.rec-item-wrapper');
    const wrappers = Array.from(recsList.querySelectorAll('.rec-item-wrapper')).filter(w => w !== draggedItem);

    if (targetWrapper && targetWrapper !== draggedItem && recsList.contains(targetWrapper)) {
      const rect = targetWrapper.getBoundingClientRect();
      if (e.clientY < rect.top + rect.height / 2) {
        recsList.insertBefore(draggedItem, targetWrapper);
      } else {
        recsList.insertBefore(draggedItem, targetWrapper.nextSibling);
      }
      return;
    }

    const first = wrappers[0];
    if (first && e.clientY < first.getBoundingClientRect().top) {
      recsList.insertBefore(draggedItem, first);
    } else if (endZone && endZone.parentNode === recsList) {
      recsList.insertBefore(draggedItem, endZone);
    } else {
      recsList.appendChild(draggedItem);
    }
  }

  recsList.addEventListener('drop', (e) => {
    if (!draggedItem) return;
    e.preventDefault();
    recsList.style.boxShadow = '';

    if (e.target.closest('.rec-item-wrapper') === draggedItem) {
      clearDragStyles();
      return;
    }

    placeInSet(e);

    const empty = document.getElementById('recs-empty');
    if (empty) empty.style.display = 'none';

    updateOrderAndSync();
    updateListMeta();
    clearDragStyles();
  });

  // --- otherList dragover & drop (Other recordings) ---
  if (otherList) {
    otherList.addEventListener('dragover', (e) => {
      if (!draggedItem) return;

      otherList.style.boxShadow = '';
      e.preventDefault();
      e.dataTransfer.dropEffect = 'move';
      const endZone = document.getElementById('other-end-drop');
      if (endZone) {
        endZone.style.borderTop = (e.target === endZone) ? '2px solid #38bdf8' : '2px solid transparent';
      }
      const targetWrapper = e.target.closest('.rec-item-wrapper');
      if (targetWrapper && targetWrapper !== draggedItem && otherList.contains(targetWrapper)) {
        const rect = targetWrapper.getBoundingClientRect();
        const midpoint = rect.top + rect.height / 2;
        targetWrapper.style.borderTop = (e.clientY < midpoint) ? '2px solid #38bdf8' : '1px solid #334155';
      }
    });

    otherList.addEventListener('dragleave', (e) => {
      const targetWrapper = e.target.closest('.rec-item-wrapper');
      if (targetWrapper) targetWrapper.style.borderTop = '1px solid #334155';
      if (!otherList.contains(e.relatedTarget)) {
        otherList.style.boxShadow = '';
      }
    });

    function placeInOther(e) {
      const endZone = document.getElementById('other-end-drop');
      const targetWrapper = e.target.closest('.rec-item-wrapper');
      const wrappers = Array.from(otherList.querySelectorAll('.rec-item-wrapper')).filter(w => w !== draggedItem);

      if (targetWrapper && targetWrapper !== draggedItem && otherList.contains(targetWrapper)) {
        const rect = targetWrapper.getBoundingClientRect();
        if (e.clientY < rect.top + rect.height / 2) {
          otherList.insertBefore(draggedItem, targetWrapper);
        } else {
          otherList.insertBefore(draggedItem, targetWrapper.nextSibling);
        }
        return;
      }

      const first = wrappers[0];
      if (first && e.clientY < first.getBoundingClientRect().top) {
        otherList.insertBefore(draggedItem, first);
      } else if (endZone && endZone.parentNode === otherList) {
        otherList.insertBefore(draggedItem, endZone);
      } else {
        otherList.appendChild(draggedItem);
      }
    }

    otherList.addEventListener('drop', (e) => {
      if (!draggedItem) return;
      e.preventDefault();

      if (e.target.closest('.rec-item-wrapper') === draggedItem) {
        clearDragStyles();
        return;
      }

      placeInOther(e);

      // Strip step number badge from item placed in unintegrated list
      const btn = draggedItem.querySelector('.rec-item');
      const stepSpan = draggedItem.querySelector('.step-num');
      if (btn) btn.setAttribute('data-step', '');
      if (stepSpan) {
        stepSpan.textContent = '+';
        stepSpan.style.color = '#64748b';
      }

      // Renumber remaining steps in recsList and sync to backend
      updateOrderAndSync();

      if (btn && btn.classList.contains('active')) {
        const title = btn.getAttribute('data-title');
        const node = btn.querySelectorAll('div')[0] ? btn.querySelectorAll('div')[0].textContent.trim() : '';
        titleEl.querySelector('span').textContent = title || node;
      }

      updateListMeta();
      clearDragStyles();
    });
  }

  function updateListMeta() {
    const setCount = document.getElementById('set-count');
    const otherCount = document.getElementById('other-count');
    const otherEmpty = document.getElementById('other-empty');
    const recsEmpty = document.getElementById('recs-empty');
    const setItems = recsList.querySelectorAll('.rec-item-wrapper').length;
    const otherItems = otherList ? otherList.querySelectorAll('.rec-item-wrapper').length : 0;
    if (setCount) setCount.textContent = setItems;
    if (otherCount) otherCount.textContent = '(' + otherItems + ')';
    if (otherEmpty) otherEmpty.style.display = (otherItems === 0) ? '' : 'none';
    if (recsEmpty) recsEmpty.style.display = (setItems === 0) ? '' : 'none';

    // Dynamically update the count badge in the Walkthrough Set selector (<select id="walkthrough-select">)
    const wtSelect = document.getElementById('walkthrough-select');
    if (wtSelect) {
      const opt = wtSelect.querySelector(`option[value="${CSS.escape(activeWalkthrough)}"]`);
      if (opt) {
        const currentName = (document.getElementById('walkthrough-name')?.value || opt.value).trim();
        opt.textContent = `${currentName} (${setItems})`;
      }
    }

    updateStepNav();
  }

  function updateOrderAndSync() {
    const wrappers = recsList.querySelectorAll('.rec-item-wrapper');
    const orderedIds = [];

    wrappers.forEach((wrapper, index) => {
      const newStep = index + 1;
      const btn = wrapper.querySelector('.rec-item');
      const stepSpan = wrapper.querySelector('.step-num');

      if (btn) btn.setAttribute('data-step', newStep);
      if (stepSpan) {
        stepSpan.textContent = '#' + newStep;
        stepSpan.style.color = '#38bdf8';
      }
      if (btn) orderedIds.push(btn.getAttribute('data-id'));
    });

    if (activeId) {
      const activeBtn = document.querySelector(`.rec-item[data-id="${CSS.escape(activeId)}"]`);
      if (activeBtn) {
        const activeStep = activeBtn.getAttribute('data-step');
        const activeTitle = activeBtn.getAttribute('data-title');
        const activeNode = activeBtn.querySelectorAll('div')[0] ? activeBtn.querySelectorAll('div')[0].textContent.trim() : '';
        titleEl.querySelector('span').textContent = (activeStep ? '#' + activeStep + ': ' : '') + (activeTitle || activeNode);
      }
    }

    updateStepNav();

    fetch('/recordings/reorder', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ order: orderedIds, walkthrough: activeWalkthrough })
    }).catch(err => console.error('Failed to sync recording order', err));
  }

  const wtNameInput = document.getElementById('walkthrough-name');
  const wtForm = document.getElementById('walkthrough-form');
  const renameSetToggleBtn = document.getElementById('rename-set-toggle-btn');
  const renameSetCancelBtn = document.getElementById('rename-set-cancel-btn');
  const initialWtName = wtNameInput ? wtNameInput.value : '';

  function updateWtSelectLabel(nameVal) {
    const wtSelect = document.getElementById('walkthrough-select');
    if (wtSelect) {
      const opt = wtSelect.querySelector(`option[value="${CSS.escape(activeWalkthrough)}"]`);
      if (opt) {
        const setItems = recsList.querySelectorAll('.rec-item-wrapper').length;
        const val = (nameVal || '').trim() || opt.value;
        opt.textContent = `${val} (${setItems})`;
      }
    }
  }

  if (wtNameInput) {
    wtNameInput.addEventListener('input', () => {
      updateWtSelectLabel(wtNameInput.value);
    });
    wtNameInput.addEventListener('keydown', (e) => {
      if (e.key === 'Escape' && renameSetCancelBtn) {
        e.preventDefault();
        renameSetCancelBtn.click();
      }
    });
  }

  if (renameSetToggleBtn && wtForm) {
    renameSetToggleBtn.addEventListener('click', () => {
      const isHidden = (wtForm.style.display === 'none' || !wtForm.style.display);
      wtForm.style.display = isHidden ? 'flex' : 'none';
      if (isHidden && wtNameInput) {
        wtNameInput.focus();
        wtNameInput.select();
      }
    });
  }

  if (renameSetCancelBtn && wtForm) {
    renameSetCancelBtn.addEventListener('click', () => {
      if (wtNameInput) {
        wtNameInput.value = initialWtName;
        updateWtSelectLabel(initialWtName);
      }
      wtForm.style.display = 'none';
    });
  }

  if (wtForm) {
    wtForm.addEventListener('submit', () => {
      const formRecInput = document.getElementById('walkthrough-form-recording');
      if (formRecInput && activeId) formRecInput.value = activeId;
    });
  }

  // --- Export Modal Handler ---
  window.updateExportWalkthroughFormat = function(targetFmt) {
    const exportInput = document.getElementById('export-filename');
    const exportHint = document.getElementById('export-filename-hint');
    const submitBtn = document.getElementById('export-submit-btn');
    const ext = (targetFmt === 'pdf') ? 'pdf' : 'zip';

    if (exportInput) {
      let val = exportInput.value.trim();
      if (val) {
        val = val.replace(/\.(zip|pdf)$/i, '');
        exportInput.value = `${val}.${ext}`;
      }
    }
    if (exportHint) {
      exportHint.innerHTML = `The <code>.${ext}</code> extension will be added automatically if omitted.`;
    }
    if (submitBtn) {
      if (targetFmt === 'pdf') {
        submitBtn.innerHTML = '<i class="fas fa-file-pdf"></i> Download PDF';
      } else {
        submitBtn.innerHTML = '<i class="fas fa-download"></i> Download ZIP';
      }
    }
  };

  window.openExportModal = function() {
    const exportModal = document.getElementById('export-modal');
    const exportInput = document.getElementById('export-filename');
    if (exportModal && exportInput) {
      const defaultRadio = document.querySelector('input[name="format"][value="zip"]');
      if (defaultRadio) defaultRadio.checked = true;
      if (typeof window.updateExportWalkthroughFormat === 'function') {
        window.updateExportWalkthroughFormat('zip');
      }
      const rawName = (window.WalkthroughConfig && window.WalkthroughConfig.walkthroughName) || window.activeWalkthrough || 'walkthrough';
      const clean = rawName.replace(/[^a-zA-Z0-9_-]+/g, '_').replace(/^_+|_+$/g, '') || 'walkthrough';
      const dateStr = new Date().toISOString().slice(0, 10).replace(/-/g, '');
      exportInput.value = `ctlabs_${clean}_${dateStr}.zip`;
      exportModal.style.display = 'block';
      exportInput.focus();
      exportInput.select();
    }
  };

  const exportForm = document.getElementById('export-form');
  if (exportForm) {
    exportForm.addEventListener('submit', () => {
      setTimeout(() => {
        const exportModal = document.getElementById('export-modal');
        if (exportModal) exportModal.style.display = 'none';
      }, 600);
    });
  }

  window.addEventListener('click', (e) => {
    const deleteModal = document.getElementById('delete-set-modal');
    if (e.target === deleteModal) {
      deleteModal.style.display = 'none';
    }
    const exportModal = document.getElementById('export-modal');
    if (e.target === exportModal) {
      exportModal.style.display = 'none';
    }
    // Note: recordScreenModal intentionally does NOT close on backdrop click,
    // preventing accidental dismissal when dragging mouse selections or copying text.
  });

  // --- Bridge for Screenshot & Diagram External Modules ---
  window.CtlabsWalkthrough = {
    openGraphvizModal: (base) => openGraphvizModal(base),
    openImageModal: (src, alt, title) => openImageModal(src, alt, title),
    getActiveWalkthrough: () => activeWalkthrough,
    cachedDiagramBases: cachedDiagramBases,
    getBaseFromImageUrl: getBaseFromImageUrl,
    replaceOrInsertImage: (oldFilename, newFilename) => {
      const cm = (window.MarkdownEditor && typeof window.MarkdownEditor.getEditor === 'function')
        ? window.MarkdownEditor.getEditor()
        : ((typeof getMdEditor === 'function') ? getMdEditor() : null);
      const ta = document.getElementById('md-textarea');
      const newSnippet = `![${newFilename.replace(/\.[^.]+$/, '')}](images/${newFilename})`;
      if (cm) {
        const val = cm.getValue();
        const regex = new RegExp(`!\\[([^\\]]*)\\]\\([^)]*${oldFilename.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}[^)]*\\)`, 'g');
        if (regex.test(val)) {
          cm.setValue(val.replace(regex, `![$1](images/${newFilename})`));
        } else {
          if (window.MarkdownEditor && typeof window.MarkdownEditor.insertBlock === 'function') {
            window.MarkdownEditor.insertBlock(newSnippet, cm.getCursor(), null, true);
          } else if (typeof insertMarkdownBlock === 'function') {
            insertMarkdownBlock(newSnippet, cm.getCursor(), null, true);
          }
        }
        if (ta) ta.value = cm.getValue();
      } else if (ta) {
        const val = ta.value;
        const regex = new RegExp(`!\\[([^\\]]*)\\]\\([^)]*${oldFilename.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}[^)]*\\)`, 'g');
        if (regex.test(val)) {
          ta.value = val.replace(regex, `![$1](images/${newFilename})`);
        } else {
          if (window.MarkdownEditor && typeof window.MarkdownEditor.insertBlock === 'function') {
            window.MarkdownEditor.insertBlock(newSnippet, null, null, true);
          } else if (typeof insertMarkdownBlock === 'function') {
            insertMarkdownBlock(newSnippet, null, null, true);
          }
        }
      }
      if (typeof onMarkdownContentChanged === 'function') onMarkdownContentChanged();
      if (window.MarkdownEditor && typeof window.MarkdownEditor.saveContent === 'function') {
        window.MarkdownEditor.saveContent(false);
      } else if (typeof saveMarkdownContent === 'function') {
        saveMarkdownContent(false);
      }
    }
  };

  // Auto-open Graphviz Editor if requested via URL query (?graphviz=<diagram_base>)
  const autoGraphviz = new URLSearchParams(window.location.search).get('graphviz');
  if (autoGraphviz) {
    setTimeout(() => {
      openGraphvizModal(autoGraphviz);
    }, 350);
  }
})();
