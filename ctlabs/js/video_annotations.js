/**
 * -----------------------------------------------------------------------------
 * File        : ctlabs/js/video_annotations.js
 * Description : Timeline Video Annotations Engine for ctlabs Walkthroughs
 * License     : MIT License
 * -----------------------------------------------------------------------------
 */

(function() {
  'use strict';

  // State
  let currentRecordingId = null;
  let annotations = []; // Array of annotation objects
  let selectedId = null;
  let isEditMode = false;
  let activeTool = 'callout'; // select, callout, arrow, rect, badge, text
  let activeColor = '#38bdf8'; // sky blue default
  let activeFontSize = 13;
  let saveDebounceTimer = null;

  // Dragging state
  let isDragging = false;
  let dragTarget = null; // { annId, handle: 'move'|'resize'|'tip'|'start'|'end', startX, startY, origX, origY, origW, origH, origX2, origY2 }

  // Drawing new annotation state
  let isDrawingNew = false;
  let drawState = null; // { tool, startX, startY, startPctX, startPctY, currPctX, currPctY }
  let drawPreviewEl = null;
  let ignoreNextClick = false;

  // DOM elements cache
  let containerEl = null;
  let stageEl = null;
  let videoEl = null;
  let overlayEl = null;
  let svgEl = null;
  let domEl = null;
  let toolbarEl = null;
  let toggleBtnEl = null;
  let trayEl = null;
  let chipsEl = null;
  let tlPlayBtnEl = null;
  let tlPlayIconEl = null;
  let tlBackBtnEl = null;
  let tlFwdBtnEl = null;
  let tlCurTimeEl = null;
  let tlDurTimeEl = null;
  let tlCountNumEl = null;
  let tlSelInfoEl = null;
  let tlSelLabelEl = null;
  let tlSelTimeEl = null;
  let tlRulerEl = null;
  let tlTrackEl = null;
  let tlLaneGuidesEl = null;
  let tlInnerEl = null;
  let tlProgressEl = null;
  let tlSegmentsEl = null;
  let tlPlayheadEl = null;
  let tlLanesBadgeEl = null;
  let tlLanesNumEl = null;
  let tlLaneUpBtnEl = null;
  let tlLaneDownBtnEl = null;
  let tlSelLaneNumEl = null;
  let tlAutoArrangeBtnEl = null;
  let tlToggleBtnEl = null;
  let tlCollapseBtnEl = null;
  let tlCollapseIconEl = null;
  let tlSettingsBtnEl = null;
  let tlSettingsMenuEl = null;
  let tlSettingTimelineCheckboxEl = null;
  let tlScrollEl = null;
  let tlZoomInnerEl = null;
  let tlZoomOutBtnEl = null;
  let tlZoomInBtnEl = null;
  let tlZoomLabelEl = null;
  let tlSpeedDownBtnEl = null;
  let tlSpeedUpBtnEl = null;
  let tlSpeedLabelEl = null;
  let tlSpeedTextEl = null;
  let tlSpeedIconEl = null;
  let tlVolBtnEl = null;
  let tlVolIconEl = null;
  let tlFsBtnEl = null;
  let tlFsIconEl = null;
  let timelineZoom = 1;
  let playbackSpeed = 1;
  let playheadRafId = null;
  let propsEl = null;
  let startInputEl = null;
  let endInputEl = null;
  let textInputEl = null;
  let stepLinkEl = null;
  let fontSizeEl = null;
  let badgeWrapEl = null;
  let badgeValEl = null;
  let saveBtnEl = null;

  // Colors
  const COLOR_PALETTE = ['#38bdf8', '#10b981', '#f59e0b', '#ef4444', '#a855f7'];

  // Helper: Toast
  function showToast(message, icon = 'fas fa-check-circle', color = '#10b981') {
    const existing = document.querySelector('.video-ann-toast');
    if (existing) existing.remove();

    const toast = document.createElement('div');
    toast.className = 'video-ann-toast';
    toast.style.cssText = 'position: absolute; top: 16px; left: 50%; transform: translateX(-50%); background: rgba(15,23,42,0.92); border: 1px solid #334155; color: #f8fafc; padding: 6px 14px; border-radius: 6px; font-size: 0.82em; font-weight: 500; display: flex; align-items: center; gap: 8px; box-shadow: 0 8px 24px rgba(0,0,0,0.6); z-index: 100; transition: opacity 0.2s; pointer-events: none;';
    toast.innerHTML = `<i class="${icon}" style="color: ${color};"></i><span>${message}</span>`;
    if (stageEl) {
      stageEl.appendChild(toast);
      setTimeout(() => {
        toast.style.opacity = '0';
        setTimeout(() => toast.remove(), 250);
      }, 2200);
    }
  }

  // Format seconds to mm:ss or mm:ss.s
  function formatTime(sec, showDecimal = false) {
    if (isNaN(sec) || sec === null || sec === undefined) return '00:00';
    const s = Math.max(0, parseFloat(sec));
    const mins = Math.floor(s / 60);
    const secs = s % 60;
    if (showDecimal) {
      return `${mins.toString().padStart(2, '0')}:${secs.toFixed(1).padStart(4, '0')}`;
    }
    return `${mins.toString().padStart(2, '0')}:${Math.floor(secs).toString().padStart(2, '0')}`;
  }

  // Format seconds to mm:ss.mmm (millisecond precision)
  function formatTimeMs(sec) {
    if (isNaN(sec) || sec === null || sec === undefined) return '00:00.000';
    const s = Math.max(0, parseFloat(sec));
    const mins = Math.floor(s / 60);
    const secs = s % 60;
    return `${mins.toString().padStart(2, '0')}:${secs.toFixed(3).padStart(6, '0')}`;
  }

  // Parse mm:ss or ss.s to seconds
  function parseTime(str) {
    if (!str) return 0;
    const clean = str.trim();
    if (clean.includes(':')) {
      const parts = clean.split(':');
      const m = parseFloat(parts[0]) || 0;
      const s = parseFloat(parts[1]) || 0;
      return Math.max(0, m * 60 + s);
    }
    return Math.max(0, parseFloat(clean) || 0);
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

  function escapeHtml(str) {
    const div = document.createElement('div');
    div.textContent = str || '';
    return div.innerHTML;
  }

  // Calculate and align overlay bounds with the video's active content rectangle
  function updateOverlayBounds() {
    if (!stageEl || !videoEl || !overlayEl) return;
    const sw = stageEl.clientWidth;
    const sh = stageEl.clientHeight;
    if (!sw || !sh) return;

    const vw = videoEl.videoWidth || sw;
    const vh = videoEl.videoHeight || sh;
    const stageRatio = sw / sh;
    const videoRatio = vw / vh;

    let rw, rh, rx, ry;
    if (stageRatio > videoRatio) {
      // Pillarbox (black bars left and right)
      rh = sh;
      rw = rh * videoRatio;
      ry = 0;
      rx = (sw - rw) / 2;
    } else {
      // Letterbox (black bars top and bottom)
      rw = sw;
      rh = rw / videoRatio;
      rx = 0;
      ry = (sh - rh) / 2;
    }

    overlayEl.style.left = `${Math.round(rx)}px`;
    overlayEl.style.top = `${Math.round(ry)}px`;
    overlayEl.style.width = `${Math.round(rw)}px`;
    overlayEl.style.height = `${Math.round(rh)}px`;
  }

  // Convert mouse client coordinates to percentage within the active video overlay
  function getOverlayPctCoords(clientX, clientY) {
    if (!overlayEl) return { x: 50, y: 50 };
    const rect = overlayEl.getBoundingClientRect();
    if (rect.width <= 0 || rect.height <= 0) return { x: 50, y: 50 };
    const pctX = Math.max(0, Math.min(100, parseFloat((((clientX - rect.left) / rect.width) * 100).toFixed(1))));
    const pctY = Math.max(0, Math.min(100, parseFloat((((clientY - rect.top) / rect.height) * 100).toFixed(1))));
    return { x: pctX, y: pctY };
  }

  // Helper: Retrieve Walkthrough Step Info
  function getStepInfo(stepId) {
    if (!stepId) return { label: 'Step', shortLabel: 'Step', stepNum: '', title: '' };
    const btn = document.querySelector(`.rec-item[data-id="${CSS.escape(stepId)}"]`);
    if (!btn) return { label: stepId, shortLabel: stepId, stepNum: '', title: stepId };
    const stepNum = btn.getAttribute('data-step') || '';
    const title = btn.getAttribute('data-title') || stepId;
    const shortLabel = stepNum ? `#${stepNum}` : (title.length > 12 ? title.substring(0, 10) + '..' : title);
    const label = stepNum ? `Step #${stepNum}: ${title}` : title;
    return { label, shortLabel, stepNum, title };
  }

  // Helper: Jump to Walkthrough Step
  function jumpToStep(stepId) {
    if (!stepId) return;
    const targetBtn = document.querySelector(`.rec-item[data-id="${CSS.escape(stepId)}"]`);
    if (!targetBtn) {
      showToast(`Step not found in current walkthrough`, 'fas fa-exclamation-triangle', '#ef4444');
      return;
    }
    if (videoEl && !videoEl.paused) {
      videoEl.pause();
    }
    const info = getStepInfo(stepId);
    showToast(`Navigating to ${info.label}...`, 'fas fa-arrow-right', '#38bdf8');
    if (typeof window.selectRecording === 'function') {
      window.selectRecording(targetBtn, true);
    } else {
      targetBtn.click();
    }
    targetBtn.scrollIntoView({ block: 'nearest', behavior: 'smooth' });
  }

  // Main Render Cycle
  let lastActiveKey = '';

  function render(force = false) {
    updateOverlayBounds();
    if (!overlayEl || !svgEl || !domEl) return;

    const curTime = videoEl ? videoEl.currentTime : 0;
    const hasAnnotations = annotations.length > 0;

    // Update video timeline track
    renderTimeline(curTime);

    // Identify which annotations are active at current timestamp
    const activeAnns = annotations.filter((ann) => {
      const inRange = curTime >= ann.startTime && curTime <= ann.endTime;
      const isSelected = ann.id === selectedId;
      return isEditMode ? (inRange || isSelected) : inRange;
    });

    const activeKey = `${isEditMode ? '1' : '0'}|${selectedId || ''}|` + 
      activeAnns.map(a => `${a.id}:${a.x}:${a.y}:${a.x2 !== undefined ? a.x2 : ''}:${a.y2 !== undefined ? a.y2 : ''}:${a.w}:${a.h}:${a.color}:${a.text}:${a.fontSize || 13}:${a.badge || ''}:${a.targetStepId || ''}:${a.startTime}:${a.endTime}`).join(';');

    if (!force && activeKey === lastActiveKey) {
      return; // DOM already matches current state, avoid destroying nodes mid-click!
    }
    lastActiveKey = activeKey;

    svgEl.innerHTML = '';
    domEl.innerHTML = '';

    activeAnns.forEach((ann) => {
      const isSelected = ann.id === selectedId;
      renderAnnotationElement(ann, isSelected);
    });

    updatePropertiesPanel();
  }

  // Render individual annotation
  function renderAnnotationElement(ann, isSelected) {
    const color = ann.color || activeColor;
    const isEditing = isEditMode;

    switch (ann.type) {
      case 'callout':
        renderCallout(ann, color, isSelected, isEditing);
        break;
      case 'arrow':
        renderArrow(ann, color, isSelected, isEditing);
        break;
      case 'rect':
        renderRect(ann, color, isSelected, isEditing);
        break;
      case 'highlight':
        renderHighlight(ann, color, isSelected, isEditing);
        break;
      case 'badge':
        renderBadge(ann, color, isSelected, isEditing);
        break;
      case 'text':
        renderText(ann, color, isSelected, isEditing);
        break;
    }
  }

  // 1. Callout Note
  function renderCallout(ann, color, isSelected, isEditing) {
    const card = document.createElement('div');
    card.className = 'video-ann-callout';
    card.setAttribute('data-id', ann.id);

    const left = ann.x || 30;
    const top = ann.y || 30;

    card.style.cssText = `
      position: absolute;
      left: ${left}%;
      top: ${top}%;
      transform: translate(-10%, -10%);
      background: rgba(15, 23, 42, 0.94);
      backdrop-filter: blur(8px);
      -webkit-backdrop-filter: blur(8px);
      border: 2px solid ${color};
      border-radius: 8px;
      box-shadow: 0 8px 26px rgba(0,0,0,0.7), 0 0 15px ${hexToRgba(color, 0.35)};
      color: #f8fafc;
      padding: 8px 12px;
      min-width: 140px;
      max-width: ${(ann.fontSize || 13) >= 20 ? 460 : 340}px;
      font-size: ${ann.fontSize || 13}px;
      line-height: 1.4;
      pointer-events: auto;
      cursor: ${isEditing ? 'move' : (ann.targetStepId ? 'pointer' : 'default')};
      user-select: none;
      z-index: ${isSelected ? 50 : 25};
      transition: box-shadow 0.15s, border-color 0.15s;
    `;

    if (isSelected) {
      card.style.outline = '2px dashed #ffffff';
      card.style.outlineOffset = '3px';
    }

    // Callout Header (Drag Handle)
    const headerEl = document.createElement('div');
    headerEl.style.cssText = 'display: flex; align-items: center; justify-content: space-between; gap: 8px; margin-bottom: 4px; border-bottom: 1px solid rgba(255,255,255,0.12); padding-bottom: 3px; cursor: move;';
    headerEl.innerHTML = `
      <span style="font-weight: 700; color: ${color}; font-size: 11px; text-transform: uppercase; letter-spacing: 0.5px; display: flex; align-items: center; gap: 4px;">
        <i class="fas fa-comment-dots"></i> Step Note
      </span>
      <span style="font-size: 10px; color: #94a3b8; font-family: monospace;">${formatTime(ann.startTime)} - ${formatTime(ann.endTime)}</span>
    `;
    card.appendChild(headerEl);

    // Callout Note Body (inline editable directly on the video)
    const noteBody = document.createElement('div');
    noteBody.className = 'video-ann-note-body';
    noteBody.style.cssText = 'color: #f1f5f9; font-weight: 500; word-break: break-word; outline: none; border-radius: 4px; padding: 2px 4px; min-height: 22px; line-height: 1.4;';
    if (isEditing) {
      noteBody.contentEditable = 'true';
      noteBody.style.cursor = 'text';
      noteBody.style.userSelect = 'text';
      noteBody.style.background = isSelected ? 'rgba(15, 23, 42, 0.75)' : 'transparent';
      noteBody.style.border = isSelected ? `1px dashed ${color}` : '1px solid transparent';
      noteBody.innerText = ann.text || (isSelected ? '' : 'Click to add step note...');
      noteBody.addEventListener('mousedown', (e) => {
        e.stopPropagation();
        if (!isSelected) selectAnnotation(ann.id);
      });
      noteBody.addEventListener('click', (e) => e.stopPropagation());
      noteBody.addEventListener('input', () => {
        ann.text = noteBody.innerText.trim();
        scheduleAutosave();
      });
      noteBody.addEventListener('blur', () => {
        ann.text = noteBody.innerText.trim();
        render();
        scheduleAutosave();
      });
      noteBody.addEventListener('keydown', (e) => {
        e.stopPropagation();
        if (e.key === 'Escape') noteBody.blur();
      });
    } else {
      noteBody.innerText = ann.text || '';
    }
    card.appendChild(noteBody);

    // Prevent any click/mousedown inside the card from reaching the underlying video element
    card.addEventListener('mousedown', (e) => {
      e.stopPropagation();
      if (isEditing) {
        selectAnnotation(ann.id);
        startDrag(e, ann.id, 'move');
      }
    });
    card.addEventListener('click', (e) => {
      e.stopPropagation();
      if (!isEditing && ann.targetStepId) {
        jumpToStep(ann.targetStepId);
      }
    });

    // Optional Link to Walkthrough Step
    if (ann.targetStepId) {
      const stepInfo = getStepInfo(ann.targetStepId);
      const linkBtn = document.createElement('div');
      linkBtn.className = 'video-ann-step-link-btn';
      linkBtn.style.cssText = `
        margin-top: 8px;
        padding: 5px 10px;
        background: rgba(56, 189, 248, 0.22);
        border: 1px solid #38bdf8;
        border-radius: 4px;
        color: #38bdf8;
        font-size: 11px;
        font-weight: 700;
        cursor: pointer;
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: 8px;
        pointer-events: auto;
        user-select: none;
        transition: background 0.15s;
      `;
      linkBtn.innerHTML = `<span><i class="fas fa-external-link-alt" style="margin-right: 5px;"></i> Open ${escapeHtml(stepInfo.label)}</span><i class="fas fa-arrow-right"></i>`;
      linkBtn.addEventListener('mouseenter', () => {
        linkBtn.style.background = 'rgba(56, 189, 248, 0.4)';
      });
      linkBtn.addEventListener('mouseleave', () => {
        linkBtn.style.background = 'rgba(56, 189, 248, 0.22)';
      });
      linkBtn.addEventListener('mousedown', (e) => {
        e.stopPropagation();
        e.preventDefault();
      });
      linkBtn.addEventListener('click', (e) => {
        e.stopPropagation();
        e.preventDefault();
        jumpToStep(ann.targetStepId);
      });
      card.appendChild(linkBtn);
    }

    // Ensure anchor coordinates exist when editing
    if (isEditing && isSelected && (ann.x2 === undefined || ann.y2 === undefined)) {
      ann.x2 = Math.min(95, (left + 15));
      ann.y2 = Math.min(95, (top + 15));
    }

    // If pointer/tail coordinates exist, draw connecting tail in SVG
    if (ann.x2 !== undefined && ann.y2 !== undefined) {
      const tipX = ann.x2;
      const tipY = ann.y2;
      const svgPath = document.createElementNS('http://www.w3.org/2000/svg', 'line');
      svgPath.setAttribute('x1', `${left}%`);
      svgPath.setAttribute('y1', `${top}%`);
      svgPath.setAttribute('x2', `${tipX}%`);
      svgPath.setAttribute('y2', `${tipY}%`);
      svgPath.setAttribute('stroke', color);
      svgPath.setAttribute('stroke-width', '2.5');
      svgPath.setAttribute('stroke-dasharray', '4,3');
      svgPath.setAttribute('stroke-linecap', 'round');
      svgEl.appendChild(svgPath);

      // Dot at pointer tip
      const tipCircle = document.createElementNS('http://www.w3.org/2000/svg', 'circle');
      tipCircle.setAttribute('cx', `${tipX}%`);
      tipCircle.setAttribute('cy', `${tipY}%`);
      tipCircle.setAttribute('r', '7');
      tipCircle.setAttribute('fill', color);
      tipCircle.setAttribute('stroke', '#ffffff');
      tipCircle.setAttribute('stroke-width', '2');
      if (isEditing) {
        tipCircle.style.pointerEvents = 'all';
        tipCircle.style.cursor = 'crosshair';
        tipCircle.addEventListener('mousedown', (e) => {
          e.stopPropagation();
          selectAnnotation(ann.id);
          startDrag(e, ann.id, 'tip');
        });
      }
      svgEl.appendChild(tipCircle);

      if (isEditing && isSelected) {
        // Draggable handle for tip / anchor point
        const tipHandle = document.createElement('div');
        tipHandle.className = 'video-ann-handle';
        tipHandle.title = 'Drag anchor point';
        tipHandle.style.cssText = `position: absolute; left: ${tipX}%; top: ${tipY}%; width: 22px; height: 22px; transform: translate(-50%, -50%); background: #ffffff; border: 3px solid ${color}; border-radius: 50%; pointer-events: auto; cursor: crosshair; z-index: 60; box-shadow: 0 2px 8px rgba(0,0,0,0.6);`;
        tipHandle.addEventListener('mousedown', (e) => {
          e.stopPropagation();
          selectAnnotation(ann.id);
          startDrag(e, ann.id, 'tip');
        });
        domEl.appendChild(tipHandle);
      }
    }

    if (isEditing) {
      card.addEventListener('mousedown', (e) => {
        selectAnnotation(ann.id);
        startDrag(e, ann.id, 'move');
      });
    }

    domEl.appendChild(card);
  }

  // 2. Arrow
  function renderArrow(ann, color, isSelected, isEditing) {
    const x1 = ann.x || 30;
    const y1 = ann.y || 40;
    const x2 = ann.x2 !== undefined ? ann.x2 : x1 + 15;
    const y2 = ann.y2 !== undefined ? ann.y2 : y1 - 10;

    // Group in SVG
    const g = document.createElementNS('http://www.w3.org/2000/svg', 'g');
    g.setAttribute('data-id', ann.id);

    // Compute angle & arrowhead
    const ow = overlayEl.clientWidth || 800;
    const oh = overlayEl.clientHeight || 450;
    const px1 = (x1 / 100) * ow;
    const py1 = (y1 / 100) * oh;
    const px2 = (x2 / 100) * ow;
    const py2 = (y2 / 100) * oh;

    const dx = px2 - px1;
    const dy = py2 - py1;
    const angle = Math.atan2(dy, dx);
    const headLen = 16;

    // Arrow line
    const line = document.createElementNS('http://www.w3.org/2000/svg', 'line');
    line.setAttribute('x1', `${px1}`);
    line.setAttribute('y1', `${py1}`);
    line.setAttribute('x2', `${px2}`);
    line.setAttribute('y2', `${py2}`);
    line.setAttribute('stroke', color);
    line.setAttribute('stroke-width', '4');
    line.setAttribute('stroke-linecap', 'round');
    line.style.filter = 'drop-shadow(0 2px 4px rgba(0,0,0,0.85))';
    g.appendChild(line);

    // Arrowhead polygon
    const p1x = px2 - headLen * Math.cos(angle - Math.PI / 6);
    const p1y = py2 - headLen * Math.sin(angle - Math.PI / 6);
    const p2x = px2 - headLen * Math.cos(angle + Math.PI / 6);
    const p2y = py2 - headLen * Math.sin(angle + Math.PI / 6);

    const head = document.createElementNS('http://www.w3.org/2000/svg', 'polygon');
    head.setAttribute('points', `${px2},${py2} ${p1x},${p1y} ${p2x},${p2y}`);
    head.setAttribute('fill', color);
    head.setAttribute('stroke', '#ffffff');
    head.setAttribute('stroke-width', '1.5');
    if (isEditing) {
      head.style.pointerEvents = 'all';
      head.style.cursor = 'crosshair';
      head.addEventListener('mousedown', (e) => {
        e.stopPropagation();
        selectAnnotation(ann.id);
        startDrag(e, ann.id, 'end');
      });
    }
    g.appendChild(head);

    svgEl.appendChild(g);

    // Optional text badge near the start of the arrow
    if (ann.text) {
      const label = document.createElement('div');
      label.style.cssText = `position: absolute; left: ${x1}%; top: ${y1}%; transform: translate(-50%, -130%); background: rgba(15,23,42,0.92); border: 1.5px solid ${color}; border-radius: 4px; padding: 2px 6px; color: #fff; font-size: 11px; font-weight: 600; white-space: nowrap; pointer-events: none; box-shadow: 0 4px 12px rgba(0,0,0,0.7);`;
      label.textContent = ann.text;
      domEl.appendChild(label);
    }

    if (isEditing) {
      // Clickable line hit area
      const hitLine = document.createElementNS('http://www.w3.org/2000/svg', 'line');
      hitLine.setAttribute('x1', `${px1}`);
      hitLine.setAttribute('y1', `${py1}`);
      hitLine.setAttribute('x2', `${px2}`);
      hitLine.setAttribute('y2', `${py2}`);
      hitLine.setAttribute('stroke', 'transparent');
      hitLine.setAttribute('stroke-width', '24');
      hitLine.style.pointerEvents = 'stroke';
      hitLine.style.cursor = 'move';
      hitLine.addEventListener('mousedown', (e) => {
        selectAnnotation(ann.id);
        startDrag(e, ann.id, 'move');
      });
      svgEl.appendChild(hitLine);

      if (isSelected) {
        // Start handle (arrow tail)
        const startH = document.createElement('div');
        startH.className = 'video-ann-handle';
        startH.title = 'Drag arrow tail';
        startH.style.cssText = `position: absolute; left: ${x1}%; top: ${y1}%; width: 22px; height: 22px; transform: translate(-50%, -50%); background: #ffffff; border: 3px solid ${color}; border-radius: 50%; pointer-events: auto; cursor: crosshair; z-index: 60; box-shadow: 0 2px 8px rgba(0,0,0,0.6);`;
        startH.addEventListener('mousedown', (e) => {
          e.stopPropagation();
          selectAnnotation(ann.id);
          startDrag(e, ann.id, 'start');
        });
        domEl.appendChild(startH);

        // End/Tip handle (arrow head)
        const endH = document.createElement('div');
        endH.className = 'video-ann-handle';
        endH.title = 'Drag arrow head';
        endH.style.cssText = `position: absolute; left: ${x2}%; top: ${y2}%; width: 22px; height: 22px; transform: translate(-50%, -50%); background: #ffffff; border: 3px solid ${color}; border-radius: 50%; pointer-events: auto; cursor: crosshair; z-index: 60; box-shadow: 0 2px 8px rgba(0,0,0,0.6);`;
        endH.addEventListener('mousedown', (e) => {
          e.stopPropagation();
          selectAnnotation(ann.id);
          startDrag(e, ann.id, 'end');
        });
        domEl.appendChild(endH);
      }
    }
  }

  // 3. Rectangle Box (pure stroke, transparent fill matching picture annotator)
  function renderRect(ann, color, isSelected, isEditing) {
    const box = document.createElement('div');
    box.className = 'video-ann-rect';
    box.setAttribute('data-id', ann.id);

    const x = ann.x || 25;
    const y = ann.y || 25;
    const w = ann.w || 20;
    const h = ann.h || 15;

    box.style.cssText = `
      position: absolute;
      left: ${x}%;
      top: ${y}%;
      width: ${w}%;
      height: ${h}%;
      border: 3px solid ${color};
      background: rgba(0, 0, 0, 0.001);
      border-radius: 4px;
      pointer-events: auto;
      cursor: ${isEditing ? 'move' : (ann.targetStepId ? 'pointer' : 'default')};
      box-sizing: border-box;
      z-index: ${isSelected ? 50 : 25};
      transition: border-color 0.15s;
    `;

    if (isSelected) {
      box.style.outline = '2px dashed #ffffff';
      box.style.outlineOffset = '2px';
    }

    // Only show label if text was explicitly set
    if (ann.text) {
      const tag = document.createElement('div');
      tag.className = 'video-ann-box-label';
      tag.style.cssText = `
        position: absolute;
        top: -24px;
        left: -2px;
        background: ${color};
        color: #ffffff;
        font-size: ${Math.max(10, (ann.fontSize || 13) - 2)}px;
        font-weight: 700;
        padding: 2px 7px;
        border-radius: 4px 4px 0 0;
        white-space: nowrap;
        box-shadow: 0 2px 6px rgba(0,0,0,0.5);
        pointer-events: none;
      `;
      tag.textContent = ann.text;
      box.appendChild(tag);
    }

    box.addEventListener('mousedown', (e) => {
      e.stopPropagation();
      if (isEditing) {
        selectAnnotation(ann.id);
        startDrag(e, ann.id, 'move');
      }
    });
    box.addEventListener('click', (e) => {
      e.stopPropagation();
      if (!isEditing && ann.targetStepId) {
        jumpToStep(ann.targetStepId);
      }
    });

    if (isEditing && isSelected) {
      // Top-left corner move handle
      const mh = document.createElement('div');
      mh.className = 'video-ann-handle';
      mh.title = 'Drag to move box';
      mh.style.cssText = `
        position: absolute;
        left: -10px;
        top: -10px;
        width: 20px;
        height: 20px;
        background: #ffffff;
        border: 2px solid ${color};
        border-radius: 50%;
        cursor: move;
        display: flex;
        align-items: center;
        justify-content: center;
        box-shadow: 0 2px 8px rgba(0,0,0,0.6);
        pointer-events: auto;
        z-index: 60;
      `;
      mh.innerHTML = '<i class="fas fa-arrows-alt" style="font-size: 10px; color: #0f172a;"></i>';
      mh.addEventListener('mousedown', (e) => {
        e.stopPropagation();
        selectAnnotation(ann.id);
        startDrag(e, ann.id, 'move');
      });
      box.appendChild(mh);

      // Bottom-right resize handle
      const rh = document.createElement('div');
      rh.style.cssText = `
        position: absolute;
        right: -6px;
        bottom: -6px;
        width: 14px;
        height: 14px;
        background: #ffffff;
        border: 2px solid ${color};
        border-radius: 3px;
        cursor: se-resize;
        pointer-events: auto;
        z-index: 60;
      `;
      rh.addEventListener('mousedown', (e) => {
        e.stopPropagation();
        startDrag(e, ann.id, 'resize');
      });
      box.appendChild(rh);
    }

    domEl.appendChild(box);
  }

  // 4. Highlight Area (translucent fill matching picture annotator)
  function renderHighlight(ann, color, isSelected, isEditing) {
    const box = document.createElement('div');
    box.className = 'video-ann-highlight';
    box.setAttribute('data-id', ann.id);

    const x = ann.x || 25;
    const y = ann.y || 25;
    const w = ann.w || 20;
    const h = ann.h || 15;

    box.style.cssText = `
      position: absolute;
      left: ${x}%;
      top: ${y}%;
      width: ${w}%;
      height: ${h}%;
      background: ${hexToRgba(color, 0.35)};
      border-radius: 4px;
      pointer-events: auto;
      cursor: ${isEditing ? 'move' : (ann.targetStepId ? 'pointer' : 'default')};
      box-sizing: border-box;
      z-index: ${isSelected ? 50 : 25};
      transition: background-color 0.15s;
    `;

    if (isSelected) {
      box.style.outline = '2px dashed #ffffff';
      box.style.outlineOffset = '2px';
    }

    if (ann.text) {
      const tag = document.createElement('div');
      tag.style.cssText = `
        position: absolute;
        top: -24px;
        left: 0;
        background: ${color};
        color: #ffffff;
        font-size: ${Math.max(10, (ann.fontSize || 13) - 2)}px;
        font-weight: 700;
        padding: 2px 7px;
        border-radius: 4px;
        white-space: nowrap;
        pointer-events: none;
      `;
      tag.textContent = ann.text;
      box.appendChild(tag);
    }

    box.addEventListener('mousedown', (e) => {
      e.stopPropagation();
      if (isEditing) {
        selectAnnotation(ann.id);
        startDrag(e, ann.id, 'move');
      }
    });
    box.addEventListener('click', (e) => {
      e.stopPropagation();
      if (!isEditing && ann.targetStepId) {
        jumpToStep(ann.targetStepId);
      }
    });

    if (isEditing && isSelected) {
      // Top-left corner move handle
      const mh = document.createElement('div');
      mh.className = 'video-ann-handle';
      mh.title = 'Drag to move highlight';
      mh.style.cssText = `
        position: absolute;
        left: -10px;
        top: -10px;
        width: 20px;
        height: 20px;
        background: #ffffff;
        border: 2px solid ${color};
        border-radius: 50%;
        cursor: move;
        display: flex;
        align-items: center;
        justify-content: center;
        box-shadow: 0 2px 8px rgba(0,0,0,0.6);
        pointer-events: auto;
        z-index: 60;
      `;
      mh.innerHTML = '<i class="fas fa-arrows-alt" style="font-size: 10px; color: #0f172a;"></i>';
      mh.addEventListener('mousedown', (e) => {
        e.stopPropagation();
        selectAnnotation(ann.id);
        startDrag(e, ann.id, 'move');
      });
      box.appendChild(mh);

      const rh = document.createElement('div');
      rh.style.cssText = `
        position: absolute;
        right: -6px;
        bottom: -6px;
        width: 14px;
        height: 14px;
        background: #ffffff;
        border: 2px solid ${color};
        border-radius: 3px;
        cursor: se-resize;
        pointer-events: auto;
        z-index: 60;
      `;
      rh.addEventListener('mousedown', (e) => {
        e.stopPropagation();
        startDrag(e, ann.id, 'resize');
      });
      box.appendChild(rh);
    }

    domEl.appendChild(box);
  }

  // 4. Numbered Step Badge
  function renderBadge(ann, color, isSelected, isEditing) {
    const wrap = document.createElement('div');
    wrap.className = 'video-ann-badge-wrap';
    wrap.setAttribute('data-id', ann.id);

    const x = ann.x || 30;
    const y = ann.y || 30;
    const fs = ann.fontSize || 13;
    let badgeDiameter = 34;
    let badgeNumSize = 16;
    if (fs >= 20) {
      badgeDiameter = 44;
      badgeNumSize = 22;
    } else if (fs <= 11) {
      badgeDiameter = 28;
      badgeNumSize = 13;
    }

    wrap.style.cssText = `
      position: absolute;
      left: ${x}%;
      top: ${y}%;
      transform: translate(-50%, -50%);
      display: flex;
      align-items: center;
      gap: 6px;
      pointer-events: auto;
      cursor: ${isEditing ? 'move' : (ann.targetStepId ? 'pointer' : 'default')};
      user-select: none;
      z-index: ${isSelected ? 50 : 25};
    `;

    // Circular badge
    const circle = document.createElement('div');
    circle.style.cssText = `
      width: ${badgeDiameter}px;
      height: ${badgeDiameter}px;
      border-radius: 50%;
      background: ${color};
      color: #ffffff;
      font-weight: 800;
      font-size: ${badgeNumSize}px;
      display: flex;
      align-items: center;
      justify-content: center;
      box-shadow: 0 4px 14px rgba(0,0,0,0.7), 0 0 0 2px #ffffff;
      flex-shrink: 0;
    `;
    circle.textContent = ann.badge || '1';
    wrap.appendChild(circle);

    // Optional Step Link Indicator
    if (ann.targetStepId) {
      const stepInfo = getStepInfo(ann.targetStepId);
      wrap.title = `Click to jump to ${stepInfo.label}`;
      const linkDot = document.createElement('span');
      linkDot.style.cssText = `
        position: absolute;
        top: -3px;
        right: -3px;
        width: 14px;
        height: 14px;
        background: #0284c7;
        border: 1.5px solid #ffffff;
        border-radius: 50%;
        color: #ffffff;
        font-size: 8px;
        display: flex;
        align-items: center;
        justify-content: center;
        box-shadow: 0 2px 5px rgba(0,0,0,0.5);
      `;
      linkDot.innerHTML = '<i class="fas fa-arrow-right"></i>';
      circle.style.position = 'relative';
      circle.appendChild(linkDot);
    }

    // Optional label text
    if (ann.text) {
      const lbl = document.createElement('div');
      lbl.style.cssText = `
        background: rgba(15,23,42,0.92);
        backdrop-filter: blur(6px);
        -webkit-backdrop-filter: blur(6px);
        border: 1.5px solid ${color};
        color: #f8fafc;
        font-size: ${fs}px;
        font-weight: 600;
        padding: 4px 8px;
        border-radius: 6px;
        white-space: nowrap;
        box-shadow: 0 4px 12px rgba(0,0,0,0.6);
      `;
      lbl.textContent = ann.text;
      wrap.appendChild(lbl);
    }

    if (isSelected) {
      circle.style.boxShadow = `0 4px 14px rgba(0,0,0,0.7), 0 0 0 3px #ffffff, 0 0 0 6px ${color}`;
    }

    wrap.addEventListener('mousedown', (e) => {
      e.stopPropagation();
      if (isEditing) {
        selectAnnotation(ann.id);
        startDrag(e, ann.id, 'move');
      }
    });
    wrap.addEventListener('click', (e) => {
      e.stopPropagation();
      if (!isEditing && ann.targetStepId) {
        jumpToStep(ann.targetStepId);
      }
    });

    domEl.appendChild(wrap);
  }

  // 5. Floating Text
  function renderText(ann, color, isSelected, isEditing) {
    const box = document.createElement('div');
    box.className = 'video-ann-text';
    box.setAttribute('data-id', ann.id);

    const x = ann.x || 30;
    const y = ann.y || 30;

    box.style.cssText = `
      position: absolute;
      left: ${x}%;
      top: ${y}%;
      transform: translate(-10%, -50%);
      background: rgba(15, 23, 42, 0.92);
      backdrop-filter: blur(6px);
      -webkit-backdrop-filter: blur(6px);
      border-left: 4px solid ${color};
      border-radius: 4px;
      color: ${color};
      font-weight: 700;
      font-size: ${ann.fontSize || 16}px;
      padding: 5px 10px;
      box-shadow: 0 4px 14px rgba(0,0,0,0.6);
      pointer-events: auto;
      cursor: ${isEditing ? 'move' : (ann.targetStepId ? 'pointer' : 'default')};
      white-space: nowrap;
      z-index: ${isSelected ? 50 : 25};
      outline: none;
      display: inline-flex;
      align-items: center;
      gap: 6px;
    `;

    if (isSelected) {
      box.style.outline = '2px dashed #ffffff';
      box.style.outlineOffset = '2px';
    }

    // Grip move handle on the left of text
    if (isEditing) {
      const grip = document.createElement('span');
      grip.className = 'video-ann-text-grip';
      grip.title = 'Drag to move text';
      grip.style.cssText = `
        cursor: move;
        color: ${color};
        display: inline-flex;
        align-items: center;
        opacity: 0.85;
        font-size: 11px;
        user-select: none;
      `;
      grip.innerHTML = '<i class="fas fa-grip-vertical"></i>';
      grip.addEventListener('mousedown', (e) => {
        e.stopPropagation();
        selectAnnotation(ann.id);
        startDrag(e, ann.id, 'move');
      });
      box.appendChild(grip);
    }

    // Inline editable text body
    const textEl = document.createElement('span');
    textEl.className = 'video-ann-text-body';
    textEl.style.cssText = `
      color: ${color};
      outline: none;
      min-width: 24px;
      cursor: ${isEditing ? 'text' : (ann.targetStepId ? 'pointer' : 'default')};
      user-select: ${isEditing ? 'text' : 'none'};
      display: inline-block;
    `;

    if (isEditing) {
      textEl.contentEditable = 'true';
      textEl.innerText = ann.text || 'Text note';
      textEl.addEventListener('mousedown', (e) => {
        e.stopPropagation();
        if (!isSelected) selectAnnotation(ann.id);
      });
      textEl.addEventListener('input', () => {
        ann.text = textEl.innerText.trim();
        scheduleAutosave();
      });
      textEl.addEventListener('blur', () => {
        ann.text = textEl.innerText.trim();
        render();
        scheduleAutosave();
      });
      textEl.addEventListener('keydown', (e) => {
        e.stopPropagation();
        if (e.key === 'Enter') {
          e.preventDefault();
          textEl.blur();
        } else if (e.key === 'Escape') {
          textEl.blur();
        }
      });
    } else {
      textEl.textContent = ann.text || 'Text note';
    }
    box.appendChild(textEl);

    // Mousedown on box outside textEl (border, padding, background) drags to move
    box.addEventListener('mousedown', (e) => {
      e.stopPropagation();
      if (isEditing) {
        selectAnnotation(ann.id);
        if (e.target !== textEl) {
          startDrag(e, ann.id, 'move');
        }
      }
    });

    box.addEventListener('click', (e) => {
      e.stopPropagation();
      if (!isEditing && ann.targetStepId) {
        jumpToStep(ann.targetStepId);
      }
    });

    if (isEditing && isSelected) {
      // Top-left corner move handle
      const mh = document.createElement('div');
      mh.className = 'video-ann-handle';
      mh.title = 'Drag to move text';
      mh.style.cssText = `
        position: absolute;
        left: -10px;
        top: -10px;
        width: 20px;
        height: 20px;
        background: #ffffff;
        border: 2px solid ${color};
        border-radius: 50%;
        cursor: move;
        display: flex;
        align-items: center;
        justify-content: center;
        box-shadow: 0 2px 8px rgba(0,0,0,0.6);
        pointer-events: auto;
        z-index: 60;
      `;
      mh.innerHTML = '<i class="fas fa-arrows-alt" style="font-size: 10px; color: #0f172a;"></i>';
      mh.addEventListener('mousedown', (e) => {
        e.stopPropagation();
        selectAnnotation(ann.id);
        startDrag(e, ann.id, 'move');
      });
      box.appendChild(mh);
    }

    domEl.appendChild(box);
  }

  // Get active video duration reliably (prefers actual video duration; falls back to annotations only if unknown)
  function getVideoDuration() {
    let vDur = 0;
    if (videoEl && !isNaN(videoEl.duration) && isFinite(videoEl.duration) && videoEl.duration > 0) {
      vDur = videoEl.duration;
    }
    if (!vDur && currentRecordingId) {
      const btn = document.querySelector(`.rec-item[data-id="${CSS.escape(currentRecordingId)}"]`);
      if (btn) {
        const dur = parseFloat(btn.getAttribute('data-duration'));
        if (dur && !isNaN(dur) && dur > 0) vDur = dur;
      }
    }
    if (vDur > 0) return vDur;

    let maxEnd = 0;
    for (const a of annotations) {
      if (a.endTime > maxEnd) maxEnd = a.endTime;
    }
    return maxEnd > 0 ? maxEnd : 10;
  }

  // Stable multi-lane allocation (preserves assigned lanes so moving objects does not cause them to jump)
  function ensureLanes() {
    let unassigned = annotations.filter(a => typeof a.lane !== 'number');
    if (unassigned.length === 0) return;

    // Build timeline occupancy for existing assigned lanes
    const laneIntervals = [];
    annotations.forEach(a => {
      if (typeof a.lane === 'number') {
        if (!laneIntervals[a.lane]) laneIntervals[a.lane] = [];
        laneIntervals[a.lane].push({ start: a.startTime, end: a.endTime });
      }
    });

    unassigned.forEach(a => {
      let targetLane = 0;
      while (true) {
        const intervals = laneIntervals[targetLane] || [];
        const hasCollision = intervals.some(iv => !(a.endTime <= iv.start + 0.05 || a.startTime >= iv.end - 0.05));
        if (!hasCollision) {
          a.lane = targetLane;
          if (!laneIntervals[targetLane]) laneIntervals[targetLane] = [];
          laneIntervals[targetLane].push({ start: a.startTime, end: a.endTime });
          break;
        }
        targetLane++;
      }
    });
  }

  function getTotalLanes() {
    ensureLanes();
    let max = 0;
    for (const a of annotations) {
      const l = typeof a.lane === 'number' ? a.lane : 0;
      if (l > max) max = l;
    }
    return max + 1;
  }

  function autoArrangeLanes() {
    const sorted = [...annotations].sort((a, b) => a.startTime - b.startTime);
    const laneEndTimes = [];
    sorted.forEach((ann) => {
      let assignedLane = -1;
      for (let i = 0; i < laneEndTimes.length; i++) {
        if (laneEndTimes[i] <= ann.startTime + 0.05) {
          assignedLane = i;
          laneEndTimes[i] = ann.endTime;
          break;
        }
      }
      if (assignedLane === -1) {
        assignedLane = laneEndTimes.length;
        laneEndTimes.push(ann.endTime);
      }
      ann.lane = assignedLane;
    });
  }

  // Render proportional tick marks along the timeline ruler
  let lastRulerDuration = -1;
  let lastRulerZoom = -1;

  function renderTimelineRuler(duration) {
    if (!tlRulerEl) return;
    const durRound = Math.round(duration * 10);
    if (durRound === lastRulerDuration && timelineZoom === lastRulerZoom) return;
    lastRulerDuration = durRound;
    lastRulerZoom = timelineZoom;

    tlRulerEl.innerHTML = '';
    if (duration <= 0) return;

    // Effective visible duration per viewport width shrinks as we zoom in
    const effectiveDur = duration / timelineZoom;
    let step = 5;
    let showDecimal = false;
    if (effectiveDur <= 2) { step = 0.2; showDecimal = true; }
    else if (effectiveDur <= 5) { step = 0.5; showDecimal = true; }
    else if (effectiveDur <= 12) { step = 1; }
    else if (effectiveDur <= 25) { step = 2; }
    else if (effectiveDur <= 60) { step = 5; }
    else if (effectiveDur <= 150) { step = 15; }
    else if (effectiveDur <= 300) { step = 30; }
    else if (effectiveDur <= 900) { step = 60; }
    else step = 120;

    for (let t = 0; t <= duration + 0.0001; t += step) {
      const clampedT = Math.min(duration, t);
      const pct = (clampedT / duration) * 100;
      const mark = document.createElement('div');
      mark.style.cssText = `
        position: absolute;
        left: ${pct}%;
        top: 0;
        transform: translateX(-50%);
        display: flex;
        flex-direction: column;
        align-items: center;
        pointer-events: none;
        user-select: none;
        white-space: nowrap;
      `;
      mark.innerHTML = `
        <span style="font-size: 8.5px; line-height: 10px; color: #64748b;">${formatTime(clampedT, showDecimal)}</span>
        <div style="width: 1px; height: 4px; background: #334155; margin-top: 1px;"></div>
      `;
      tlRulerEl.appendChild(mark);
    }
  }

  function setTimelineZoom(newZoom) {
    const ZOOM_STEPS = [1, 1.5, 2, 3, 5, 8, 10];
    const clamped = Math.max(1, Math.min(10, newZoom));
    timelineZoom = clamped;

    if (tlZoomInnerEl) {
      tlZoomInnerEl.style.width = `${timelineZoom * 100}%`;
    }
    if (tlZoomLabelEl) {
      tlZoomLabelEl.textContent = `${Math.round(timelineZoom * 100)}%`;
      tlZoomLabelEl.style.color = timelineZoom > 1 ? '#38bdf8' : '#cbd5e1';
    }

    lastRulerDuration = -1;
    const dur = getVideoDuration();
    renderTimelineRuler(dur);

    // Keep playhead visible/centered when zooming
    if (tlScrollEl && videoEl) {
      const curPct = Math.max(0, Math.min(1, (videoEl.currentTime || 0) / (dur > 0 ? dur : 1)));
      const maxScroll = Math.max(0, tlScrollEl.scrollWidth - tlScrollEl.clientWidth);
      const targetScroll = curPct * tlScrollEl.scrollWidth - (tlScrollEl.clientWidth / 2);
      tlScrollEl.scrollLeft = Math.max(0, Math.min(maxScroll, targetScroll));
    }

    return ZOOM_STEPS;
  }

  // Update playhead needle, progress fill, and time readouts
  function updatePlayheadUI(curTime, duration) {
    if (!tlPlayheadEl || !tlProgressEl) return;
    const dur = duration > 0 ? duration : 1;
    const clampedCur = Math.max(0, Math.min(dur, curTime));
    const pct = (clampedCur / dur) * 100;

    tlPlayheadEl.style.left = `${pct}%`;
    tlProgressEl.style.width = `${pct}%`;

    if (tlCurTimeEl) tlCurTimeEl.textContent = formatTimeMs(clampedCur);
    if (tlDurTimeEl) tlDurTimeEl.textContent = formatTimeMs(dur);
    if (tlPlayIconEl) {
      tlPlayIconEl.className = (videoEl && !videoEl.paused) ? 'fas fa-pause' : 'fas fa-play';
    }
  }

  function startPlayheadRaf() {
    if (playheadRafId) return;
    const tick = () => {
      if (!videoEl || videoEl.paused || videoEl.ended) {
        playheadRafId = null;
        return;
      }
      updatePlayheadUI(videoEl.currentTime, getVideoDuration());
      playheadRafId = requestAnimationFrame(tick);
    };
    playheadRafId = requestAnimationFrame(tick);
  }

  function stopPlayheadRaf() {
    if (playheadRafId) {
      cancelAnimationFrame(playheadRafId);
      playheadRafId = null;
    }
  }

  // Seeking state & playback position updates
  let pendingSeekTarget = null;
  let seekThrottleTimer = null;

  function safeSeek(targetTime) {
    if (!videoEl) return;
    const dur = getVideoDuration();
    const clampedTime = Math.max(0, Math.min(dur, targetTime));

    pendingSeekTarget = clampedTime;
    updatePlayheadUI(clampedTime, dur);
    render();

    if (seekThrottleTimer) clearTimeout(seekThrottleTimer);
    seekThrottleTimer = setTimeout(() => {
      seekThrottleTimer = null;
      if (!videoEl || pendingSeekTarget === null) return;
      const target = pendingSeekTarget;
      pendingSeekTarget = null;

      if (Math.abs(videoEl.currentTime - target) > 0.02) {
        videoEl.currentTime = target;
      }
    }, 30);
  }

  function togglePlayPause() {
    if (!videoEl) return;
    if (videoEl.paused) {
      const p = videoEl.play();
      if (p !== undefined) p.catch(() => {});
    } else {
      videoEl.pause();
    }
    updatePlayheadUI(videoEl.currentTime, getVideoDuration());
  }

  // Dragging state for timeline segments (trimming start/end, moving entire time span)
  let isTlDragging = false;
  let tlDragState = null;

  function startTimelineDrag(e, annId, dragType) {
    const ann = annotations.find(a => a.id === annId);
    if (!ann || !tlTrackEl) return;

    selectAnnotation(annId);

    const trackRect = tlTrackEl.getBoundingClientRect();
    const duration = getVideoDuration();

    isTlDragging = true;
    tlDragState = {
      annId,
      type: dragType,
      startX: e.clientX,
      startY: e.clientY,
      origStart: ann.startTime,
      origEnd: ann.endTime,
      origLane: typeof ann.lane === 'number' ? ann.lane : 0,
      duration: duration,
      trackWidth: tlInnerEl ? (tlInnerEl.clientWidth || 1) : Math.max(1, trackRect.width - 22)
    };

    window.addEventListener('mousemove', onTimelineDragMove, true);
    window.addEventListener('mouseup', onTimelineDragEnd, true);
  }

  function onTimelineDragMove(e) {
    if (!isTlDragging || !tlDragState) return;
    e.preventDefault();
    e.stopPropagation();

    const { annId, type, startX, startY, origStart, origEnd, origLane, duration, trackWidth } = tlDragState;
    const ann = annotations.find(a => a.id === annId);
    if (!ann) return;

    const deltaPx = e.clientX - startX;
    const deltaSec = (deltaPx / trackWidth) * duration;

    if (type === 'trim-start') {
      let newStart = origStart + deltaSec;
      newStart = Math.max(0, Math.min(ann.endTime - 0.2, newStart));
      newStart = Math.round(newStart * 10) / 10;
      ann.startTime = newStart;
      if (videoEl) safeSeek(newStart);
    } else if (type === 'trim-end') {
      let newEnd = origEnd + deltaSec;
      newEnd = Math.round(newEnd * 10) / 10;
      newEnd = Math.max(ann.startTime + 0.2, Math.min(duration, newEnd));
      ann.endTime = newEnd;
      if (videoEl) safeSeek(newEnd);
    } else if (type === 'move-span') {
      const span = origEnd - origStart;
      let newStart = origStart + deltaSec;
      newStart = Math.max(0, Math.min(duration - span, newStart));
      newStart = Math.round(newStart * 10) / 10;
      ann.startTime = newStart;
      ann.endTime = Math.min(duration, Math.round((newStart + span) * 10) / 10);
      if (videoEl) safeSeek(newStart);

      // Allow intentional vertical dragging between lanes without sudden jumping
      const deltaY = e.clientY - startY;
      const laneStep = 29; // laneHeight (24) + laneGap (5)
      const laneShift = Math.round(deltaY / laneStep);
      const maxAvailableLanes = getTotalLanes();
      const targetLane = Math.max(0, Math.min(maxAvailableLanes, origLane + laneShift));
      ann.lane = targetLane;
    }

    if (videoEl) updatePlayheadUI(videoEl.currentTime, duration);
    render(true);
  }

  function onTimelineDragEnd(e) {
    if (!isTlDragging) return;
    if (e) {
      e.preventDefault();
      e.stopPropagation();
    }
    isTlDragging = false;
    tlDragState = null;
    window.removeEventListener('mousemove', onTimelineDragMove, true);
    window.removeEventListener('mouseup', onTimelineDragEnd, true);
    scheduleAutosave();
  }

  // Timeline track visibility & collapse helpers
  function isTimelineVisible() {
    return localStorage.getItem('ctlabs_video_timeline_visible') !== 'false';
  }

  function isTimelineCollapsed() {
    return localStorage.getItem('ctlabs_video_timeline_collapsed') === 'true';
  }

  function updateTimelineToggleBtnUI(visible) {
    if (tlToggleBtnEl) {
      tlToggleBtnEl.style.borderColor = visible ? '#38bdf8' : '#475569';
      tlToggleBtnEl.style.background = visible ? 'rgba(56, 189, 248, 0.16)' : '#1e293b';
      tlToggleBtnEl.style.color = visible ? '#38bdf8' : '#94a3b8';
      tlToggleBtnEl.title = visible ? 'Hide timeline track' : 'Show timeline track';
    }
    if (tlSettingTimelineCheckboxEl) {
      tlSettingTimelineCheckboxEl.checked = !!visible;
    }
  }

  function updateTimelineCollapsedUI(collapsed) {
    if (tlScrollEl) {
      tlScrollEl.style.display = collapsed ? 'none' : 'block';
    }
    if (tlCollapseIconEl) {
      tlCollapseIconEl.className = collapsed ? 'fas fa-chevron-up' : 'fas fa-chevron-down';
    }
    if (tlCollapseBtnEl) {
      tlCollapseBtnEl.title = collapsed ? 'Expand timeline lanes' : 'Collapse timeline lanes';
    }
  }

  function toggleTimelineCollapsed(explicitState) {
    const cur = isTimelineCollapsed();
    const next = (explicitState !== undefined) ? explicitState : !cur;
    localStorage.setItem('ctlabs_video_timeline_collapsed', next ? 'true' : 'false');
    updateTimelineCollapsedUI(next);
    updateOverlayBounds();
    render();
  }

  function toggleTimeline(explicitState) {
    const cur = isTimelineVisible();
    const next = (explicitState !== undefined) ? explicitState : !cur;
    localStorage.setItem('ctlabs_video_timeline_visible', next ? 'true' : 'false');
    if (trayEl) {
      trayEl.style.display = next ? 'flex' : 'none';
    }
    updateTimelineToggleBtnUI(next);
    if (next) {
      const curTime = videoEl ? videoEl.currentTime : 0;
      renderTimeline(curTime);
    }
    updateOverlayBounds();
    render();
  }

  // Render video annotations timeline track
  function renderTimeline(curTime) {
    if (!trayEl) return;
    const isVisible = isTimelineVisible();
    trayEl.style.display = isVisible ? 'flex' : 'none';
    updateTimelineToggleBtnUI(isVisible);
    if (!isVisible) return;

    updateTimelineCollapsedUI(isTimelineCollapsed());

    const duration = getVideoDuration();
    renderTimelineRuler(duration);
    updatePlayheadUI(curTime, duration);

    // Update annotation count
    if (tlCountNumEl) {
      tlCountNumEl.textContent = annotations.length;
    }

    // Ensure all annotations have stable assigned lanes
    ensureLanes();
    const totalLanes = getTotalLanes();

    // Update lanes badge in timeline header
    if (tlLanesBadgeEl) {
      if (totalLanes > 1) {
        tlLanesBadgeEl.style.display = 'inline-flex';
        if (tlLanesNumEl) tlLanesNumEl.textContent = totalLanes;
      } else {
        tlLanesBadgeEl.style.display = 'none';
      }
    }

    // Dynamic track rail height calculation
    const laneHeight = 24;
    const laneGap = 5;
    const trackPadY = 5;
    const totalTrackHeight = trackPadY * 2 + totalLanes * laneHeight + (totalLanes - 1) * laneGap;
    if (tlTrackEl) {
      tlTrackEl.style.height = `${totalTrackHeight}px`;
    }

    // Render subtle background lane guide rails if multiple lanes exist
    if (tlLaneGuidesEl) {
      tlLaneGuidesEl.innerHTML = '';
      if (totalLanes > 1) {
        for (let l = 0; l < totalLanes; l++) {
          const guide = document.createElement('div');
          const guideTop = trackPadY + l * (laneHeight + laneGap);
          guide.style.cssText = `
            position: absolute;
            top: ${guideTop}px;
            left: 10px;
            right: 10px;
            height: ${laneHeight}px;
            border-radius: 4px;
            background: ${l % 2 === 0 ? 'rgba(255,255,255,0.015)' : 'rgba(255,255,255,0.035)'};
            border: 1px dashed rgba(255,255,255,0.06);
            pointer-events: none;
          `;
          tlLaneGuidesEl.appendChild(guide);
        }
      }
    }

    // Update selected info in timeline header
    if (tlSelInfoEl) {
      const selAnn = annotations.find(a => a.id === selectedId);
      if (selAnn) {
        tlSelInfoEl.style.display = 'flex';
        let icon = 'fas fa-comment-dots';
        if (selAnn.type === 'arrow') icon = 'fas fa-location-arrow';
        if (selAnn.type === 'rect') icon = 'far fa-square';
        if (selAnn.type === 'highlight') icon = 'fas fa-highlighter';
        if (selAnn.type === 'badge') icon = 'fas fa-certificate';
        if (selAnn.type === 'text') icon = 'fas fa-font';

        if (tlSelLabelEl) {
          const title = selAnn.text || selAnn.type;
          tlSelLabelEl.innerHTML = `<i class="${icon}" style="color: ${selAnn.color || '#38bdf8'}; margin-right: 4px;"></i>${escapeHtml(title)}`;
        }
        if (tlSelTimeEl) {
          tlSelTimeEl.textContent = `${formatTime(selAnn.startTime)} - ${formatTime(selAnn.endTime)}`;
        }
        if (tlSelLaneNumEl) {
          tlSelLaneNumEl.textContent = (typeof selAnn.lane === 'number' ? selAnn.lane : 0) + 1;
        }
      } else {
        tlSelInfoEl.style.display = 'none';
      }
    }

    if (!tlSegmentsEl) return;
    tlSegmentsEl.innerHTML = '';

    const sorted = [...annotations].sort((a, b) => a.startTime - b.startTime);
    sorted.forEach((ann) => {
      const seg = document.createElement('div');
      seg.className = 'video-tl-segment';
      seg.setAttribute('data-id', ann.id);

      const isActive = curTime >= ann.startTime && curTime <= ann.endTime;
      const isSelected = ann.id === selectedId;
      const color = ann.color || '#38bdf8';

      const lane = typeof ann.lane === 'number' ? ann.lane : 0;
      const segTop = trackPadY + lane * (laneHeight + laneGap);

      const leftPct = Math.max(0, Math.min(100, (ann.startTime / duration) * 100));
      const rightPct = Math.max(0, Math.min(100, (ann.endTime / duration) * 100));
      const rawWidthPct = Math.max(1.2, rightPct - leftPct);
      const isAtClipEnd = rightPct >= 99.2;

      let icon = 'fas fa-comment-dots';
      if (ann.type === 'arrow') icon = 'fas fa-location-arrow';
      if (ann.type === 'rect') icon = 'far fa-square';
      if (ann.type === 'highlight') icon = 'fas fa-highlighter';
      if (ann.type === 'badge') icon = 'fas fa-certificate';
      if (ann.type === 'text') icon = 'fas fa-font';

      const labelText = ann.text ? (ann.text.length > 18 ? ann.text.substring(0, 16) + '..' : ann.text) : (ann.type === 'badge' ? `#${ann.badge || 1}` : ann.type);

      seg.style.cssText = `
        position: absolute;
        ${isAtClipEnd ? `right: 0px; width: ${rawWidthPct}%; min-width: 24px; max-width: 100%;` : `left: ${leftPct}%; width: ${rawWidthPct}%; min-width: 24px; max-width: calc(100% - ${leftPct}%);`}
        top: ${segTop}px;
        height: ${laneHeight}px;
        background: ${hexToRgba(color, isActive ? 0.45 : 0.22)};
        border: ${isSelected ? '2px solid #ffffff' : `1.5px solid ${color}`};
        border-radius: 4px;
        box-shadow: ${isSelected ? `0 0 10px ${color}, inset 0 0 4px ${color}` : (isActive ? `0 0 6px ${color}` : 'none')};
        display: flex;
        align-items: center;
        padding: 0 4px;
        gap: 4px;
        box-sizing: border-box;
        overflow: hidden;
        cursor: pointer;
        z-index: ${isSelected ? 15 : (isActive ? 12 : 5)};
        transition: border 0.15s, box-shadow 0.15s;
        white-space: nowrap;
      `;

      seg.title = `${ann.type.toUpperCase()}: ${ann.text || ''} (${formatTime(ann.startTime)} - ${formatTime(ann.endTime)})`;

      // Inner label
      const content = document.createElement('div');
      content.style.cssText = `
        display: flex;
        align-items: center;
        gap: 4px;
        font-size: 11px;
        color: #f8fafc;
        flex: 1;
        overflow: hidden;
        pointer-events: none;
      `;

      let stepBadgeHtml = '';
      if (ann.targetStepId) {
        const stepInfo = getStepInfo(ann.targetStepId);
        stepBadgeHtml = `<span style="background: rgba(56,189,248,0.3); border: 1px solid #38bdf8; border-radius: 3px; padding: 0 3px; font-size: 9px; color: #38bdf8; flex-shrink: 0;">➜ ${stepInfo.shortLabel}</span>`;
      }

      content.innerHTML = `
        <i class="${icon}" style="color: ${color}; font-size: 10px; flex-shrink: 0;"></i>
        <span style="overflow: hidden; text-overflow: ellipsis; font-weight: 500;">${escapeHtml(labelText)}</span>
        ${stepBadgeHtml}
      `;
      seg.appendChild(content);

      // Left & right trim handles in edit mode
      if (isEditMode) {
        const leftHandle = document.createElement('div');
        leftHandle.className = 'video-tl-handle-left';
        leftHandle.title = 'Drag to adjust start time';
        leftHandle.style.cssText = `
          position: absolute;
          left: 0;
          top: 0;
          bottom: 0;
          width: 6px;
          cursor: ew-resize;
          background: rgba(255,255,255,0.25);
          border-right: 1px solid rgba(255,255,255,0.4);
          z-index: 2;
        `;
        leftHandle.addEventListener('mousedown', (e) => {
          e.stopPropagation();
          startTimelineDrag(e, ann.id, 'trim-start');
        });
        seg.appendChild(leftHandle);

        const rightHandle = document.createElement('div');
        rightHandle.className = 'video-tl-handle-right';
        rightHandle.title = 'Drag to adjust end time';
        rightHandle.style.cssText = `
          position: absolute;
          right: 0;
          top: 0;
          bottom: 0;
          width: 6px;
          cursor: ew-resize;
          background: rgba(255,255,255,0.25);
          border-left: 1px solid rgba(255,255,255,0.4);
          z-index: 2;
        `;
        rightHandle.addEventListener('mousedown', (e) => {
          e.stopPropagation();
          startTimelineDrag(e, ann.id, 'trim-end');
        });
        seg.appendChild(rightHandle);
      }

      // Drag segment body to shift start & end times together in edit mode
      seg.addEventListener('mousedown', (e) => {
        if (e.target.classList.contains('video-tl-handle-left') || e.target.classList.contains('video-tl-handle-right')) return;
        if (isEditMode) {
          e.stopPropagation();
          startTimelineDrag(e, ann.id, 'move-span');
        }
      });

      // Click to seek and select
      seg.addEventListener('click', (e) => {
        e.stopPropagation();
        if (videoEl) {
          videoEl.currentTime = ann.startTime;
          videoEl.pause();
        }
        selectAnnotation(ann.id);
      });

      tlSegmentsEl.appendChild(seg);
    });
  }

  // Alias for backward compatibility
  function renderTimelineChips(curTime) {
    renderTimeline(curTime);
  }

  // Update properties inputs in toolbar
  function updatePropertiesPanel() {
    const ann = annotations.find(a => a.id === selectedId);

    // Delete button in toolbar
    const deleteBtn = document.getElementById('video-ann-delete-btn');
    if (deleteBtn) {
      deleteBtn.style.display = (ann && isEditMode) ? 'inline-flex' : 'none';
    }

    // Badge counter group
    const badgeGroupEl = document.getElementById('video-ann-badge-group');
    const badgeNumInput = document.getElementById('video-ann-badge-num');
    if (badgeGroupEl) {
      const isBadge = (activeTool === 'badge') || (ann && ann.type === 'badge');
      badgeGroupEl.style.display = isBadge ? 'inline-flex' : 'none';
      if (ann && ann.type === 'badge' && badgeNumInput) {
        badgeNumInput.value = ann.badge || '1';
      }
    }

    // Font size input
    const fontInput = document.getElementById('video-ann-font-size-input');
    if (fontInput) {
      fontInput.value = ann ? (ann.fontSize || (ann.type === 'text' ? 16 : 13)) : activeFontSize;
    }

    // Color swatches in main palette
    const colorSwatches = document.querySelectorAll('.video-ann-color-btn');
    const currentColor = ann ? ann.color : activeColor;
    colorSwatches.forEach(btn => {
      const col = btn.getAttribute('data-color');
      if (col === currentColor) {
        btn.classList.add('active');
      } else {
        btn.classList.remove('active');
      }
    });

    if (!propsEl) return;
    if (!ann || !isEditMode) {
      propsEl.style.display = 'none';
      return;
    }

    propsEl.style.display = 'flex';

    if (startInputEl) startInputEl.value = formatTime(ann.startTime, true);
    if (endInputEl) endInputEl.value = formatTime(ann.endTime, true);
    if (textInputEl) textInputEl.value = ann.text || '';

    if (stepLinkEl) {
      const currentVal = ann.targetStepId || '';
      stepLinkEl.innerHTML = '<option value="">(None - Note only)</option>';
      const stepBtns = document.querySelectorAll('.rec-item-wrapper .rec-item');
      stepBtns.forEach((btn) => {
        const sid = btn.getAttribute('data-id');
        if (!sid || sid === currentRecordingId) return;
        const snum = btn.getAttribute('data-step') || '';
        const stitle = btn.getAttribute('data-title') || sid;
        const opt = document.createElement('option');
        opt.value = sid;
        opt.textContent = (snum ? `#${snum}: ` : '') + (stitle.length > 20 ? stitle.substring(0, 18) + '...' : stitle);
        if (sid === currentVal) opt.selected = true;
        stepLinkEl.appendChild(opt);
      });
      stepLinkEl.value = currentVal;
    }
  }

  // Dragging handlers
  function startDrag(e, annId, handle) {
    if (!isEditMode) return;
    e.preventDefault();
    e.stopPropagation();

    const ann = annotations.find(a => a.id === annId);
    if (!ann) return;

    isDragging = true;
    dragTarget = {
      annId: annId,
      handle: handle,
      startX: e.clientX,
      startY: e.clientY,
      origX: ann.x || 30,
      origY: ann.y || 30,
      origW: ann.w || 20,
      origH: ann.h || 15,
      origX2: ann.x2 !== undefined ? ann.x2 : (ann.x || 30) + 15,
      origY2: ann.y2 !== undefined ? ann.y2 : (ann.y || 30) - 10
    };

    window.addEventListener('mousemove', onDragMove, true);
    window.addEventListener('mouseup', onDragEnd, true);
    window.addEventListener('blur', onDragEnd, true);
  }

  function onDragMove(e) {
    if (!isDragging || !dragTarget || !overlayEl) return;
    const ann = annotations.find(a => a.id === dragTarget.annId);
    if (!ann) return;

    const ow = overlayEl.clientWidth || 800;
    const oh = overlayEl.clientHeight || 450;

    const dxPx = e.clientX - dragTarget.startX;
    const dyPx = e.clientY - dragTarget.startY;

    const dxPct = (dxPx / ow) * 100;
    const dyPct = (dyPx / oh) * 100;

    if (dragTarget.handle === 'move') {
      ann.x = Math.max(0, Math.min(95, parseFloat((dragTarget.origX + dxPct).toFixed(1))));
      ann.y = Math.max(0, Math.min(95, parseFloat((dragTarget.origY + dyPct).toFixed(1))));
      // Arrow translates both start & end together; Callout keeps anchor point pinned to video target
      if (ann.type === 'arrow' && ann.x2 !== undefined && ann.y2 !== undefined) {
        ann.x2 = Math.max(0, Math.min(100, parseFloat((dragTarget.origX2 + dxPct).toFixed(1))));
        ann.y2 = Math.max(0, Math.min(100, parseFloat((dragTarget.origY2 + dyPct).toFixed(1))));
      }
    } else if (dragTarget.handle === 'resize') {
      ann.w = Math.max(5, Math.min(95 - ann.x, parseFloat((dragTarget.origW + dxPct).toFixed(1))));
      ann.h = Math.max(4, Math.min(95 - ann.y, parseFloat((dragTarget.origH + dyPct).toFixed(1))));
    } else if (dragTarget.handle === 'tip' || dragTarget.handle === 'end') {
      ann.x2 = Math.max(0, Math.min(100, parseFloat((dragTarget.origX2 + dxPct).toFixed(1))));
      ann.y2 = Math.max(0, Math.min(100, parseFloat((dragTarget.origY2 + dyPct).toFixed(1))));
    } else if (dragTarget.handle === 'start') {
      ann.x = Math.max(0, Math.min(100, parseFloat((dragTarget.origX + dxPct).toFixed(1))));
      ann.y = Math.max(0, Math.min(100, parseFloat((dragTarget.origY + dyPct).toFixed(1))));
    }

    render();
  }

  function onDragEnd(e) {
    if (!isDragging) return;
    if (e) {
      e.preventDefault();
      e.stopPropagation();
    }
    isDragging = false;
    dragTarget = null;
    window.removeEventListener('mousemove', onDragMove, true);
    window.removeEventListener('mouseup', onDragEnd, true);
    window.removeEventListener('blur', onDragEnd, true);
    render(true);
    scheduleAutosave();
  }

  // Selection
  function selectAnnotation(id) {
    selectedId = id;
    render();
  }

  // Tool Selection
  function selectTool(tool) {
    activeTool = tool || 'select';
    const toolBtns = document.querySelectorAll('.video-ann-tool-btn');
    toolBtns.forEach(b => {
      b.classList.toggle('active', b.getAttribute('data-tool') === activeTool);
    });

    // Badge group visibility in toolbar: show when badge tool is active or a badge is selected
    const badgeGroupEl = document.getElementById('video-ann-badge-group');
    if (badgeGroupEl) {
      const ann = annotations.find(a => a.id === selectedId);
      const isBadge = (activeTool === 'badge') || (ann && ann.type === 'badge');
      badgeGroupEl.style.display = isBadge ? 'inline-flex' : 'none';
    }

    if (overlayEl) {
      if (isEditMode && activeTool !== 'select') {
        overlayEl.style.pointerEvents = 'auto';
        overlayEl.style.cursor = 'crosshair';
      } else {
        overlayEl.style.pointerEvents = 'none';
        overlayEl.style.cursor = 'default';
      }
    }
  }

  // Add Annotation
  function addAnnotation(type = activeTool, posX = 35, posY = 35, customProps = {}) {
    if (!currentRecordingId) return;
    const cur = videoEl ? videoEl.currentTime : 0;
    const vDur = (videoEl && !isNaN(videoEl.duration) && videoEl.duration > 0) ? videoEl.duration : 0;
    const startTime = Math.max(0, Math.floor(cur * 10) / 10);
    let defaultEnd = Math.floor((cur + 4) * 10) / 10;
    if (vDur > 0 && defaultEnd > vDur) {
      defaultEnd = Math.max(startTime + 0.5, Math.floor(vDur * 10) / 10);
    }
    const endTime = Math.max(startTime + 0.5, defaultEnd);

    const actualType = (!type || type === 'select') ? 'callout' : type;

    // Highest badge count helper
    let nextBadge = 1;
    if (actualType === 'badge') {
      const badgeInput = document.getElementById('video-ann-badge-num');
      const manualVal = badgeInput ? parseInt(badgeInput.value, 10) : NaN;
      if (!isNaN(manualVal) && manualVal >= 1) {
        nextBadge = manualVal;
      } else {
        annotations.filter(a => a.type === 'badge').forEach(b => {
          const num = parseInt(b.badge, 10);
          if (!isNaN(num) && num >= nextBadge) nextBadge = num + 1;
        });
      }
    }

    // Assign lowest non-colliding lane for the new annotation
    let newLane = 0;
    while (true) {
      const colliding = annotations.some(a => (a.lane || 0) === newLane && !(endTime <= a.startTime + 0.05 || startTime >= a.endTime - 0.05));
      if (!colliding) break;
      newLane++;
    }

    const newAnn = {
      id: `ann_${Date.now()}_${Math.random().toString(36).substring(2, 7)}`,
      type: actualType,
      color: activeColor,
      fontSize: activeFontSize,
      startTime: startTime,
      endTime: endTime,
      lane: newLane,
      text: actualType === 'callout' ? 'Add note here' : (actualType === 'text' ? 'Important step' : ''),
      x: posX,
      y: posY,
      w: customProps.w !== undefined ? customProps.w : 22,
      h: customProps.h !== undefined ? customProps.h : 15,
      x2: customProps.x2 !== undefined ? customProps.x2 : (actualType === 'arrow' ? Math.min(95, posX + 20) : (actualType === 'callout' ? Math.min(95, posX + 15) : undefined)),
      y2: customProps.y2 !== undefined ? customProps.y2 : (actualType === 'arrow' ? Math.max(5, posY - 15) : (actualType === 'callout' ? Math.min(95, posY + 15) : undefined)),
      badge: actualType === 'badge' ? String(nextBadge) : undefined,
      ...customProps
    };

    annotations.push(newAnn);
    selectedId = newAnn.id;

    if (videoEl && !videoEl.paused) {
      videoEl.pause();
    }

    // Auto-advance badge counter for next placement
    if (actualType === 'badge') {
      const badgeInput = document.getElementById('video-ann-badge-num');
      if (badgeInput) badgeInput.value = nextBadge + 1;
    }

    render();
    scheduleAutosave();

    // Auto-focus inline editable element for callout note or text
    if (actualType === 'callout' || actualType === 'text') {
      setTimeout(() => {
        const el = domEl ? domEl.querySelector(`[data-id="${newAnn.id}"] .video-ann-note-body, [data-id="${newAnn.id}"] .video-ann-text-body`) : null;
        if (el) {
          el.focus();
          if (window.getSelection && document.createRange) {
            const range = document.createRange();
            range.selectNodeContents(el);
            const sel = window.getSelection();
            sel.removeAllRanges();
            sel.addRange(range);
          }
        }
      }, 70);
    }

    showToast(`Added ${actualType} annotation at ${formatTime(startTime)}`, 'fas fa-plus-circle', '#38bdf8');
  }

  // Interactive drawing of new annotations (click & drag rubber-band area selection)
  function startDrawingNew(e) {
    if (!isEditMode) return;
    if (!activeTool || activeTool === 'select') return;

    // Only start drawing on the video stage / overlay background
    if (e.target !== overlayEl && e.target !== svgEl && e.target !== domEl && e.target !== stageEl && e.target !== videoEl) {
      return;
    }

    e.preventDefault();
    if (videoEl && !videoEl.paused) {
      videoEl.pause();
    }

    const pt = getOverlayPctCoords(e.clientX, e.clientY);

    // Single-click tool: Badge
    if (activeTool === 'badge') {
      addAnnotation('badge', pt.x, pt.y);
      return;
    }

    isDrawingNew = true;
    drawState = {
      tool: activeTool,
      startX: e.clientX,
      startY: e.clientY,
      startPctX: pt.x,
      startPctY: pt.y,
      currPctX: pt.x,
      currPctY: pt.y
    };

    window.addEventListener('mousemove', onDrawingMove, true);
    window.addEventListener('mouseup', onDrawingEnd, true);
  }

  function onDrawingMove(e) {
    if (!isDrawingNew || !drawState || !overlayEl) return;
    e.preventDefault();

    const pt = getOverlayPctCoords(e.clientX, e.clientY);
    drawState.currPctX = pt.x;
    drawState.currPctY = pt.y;

    const distPx = Math.hypot(e.clientX - drawState.startX, e.clientY - drawState.startY);
    if (distPx < 4) return;

    if (!drawPreviewEl) {
      drawPreviewEl = document.createElement('div');
      drawPreviewEl.id = 'video-ann-draw-preview';
      drawPreviewEl.style.position = 'absolute';
      drawPreviewEl.style.pointerEvents = 'none';
      drawPreviewEl.style.zIndex = '70';
      overlayEl.appendChild(drawPreviewEl);
    }

    const tool = drawState.tool;
    const startX = drawState.startPctX;
    const startY = drawState.startPctY;
    const currX = drawState.currPctX;
    const currY = drawState.currPctY;

    if (tool === 'rect') {
      const minX = Math.min(startX, currX);
      const minY = Math.min(startY, currY);
      const w = Math.abs(currX - startX);
      const h = Math.abs(currY - startY);

      drawPreviewEl.innerHTML = '';
      drawPreviewEl.style.left = `${minX}%`;
      drawPreviewEl.style.top = `${minY}%`;
      drawPreviewEl.style.width = `${w}%`;
      drawPreviewEl.style.height = `${h}%`;
      drawPreviewEl.style.border = `3px dashed ${activeColor}`;
      drawPreviewEl.style.background = 'transparent';
      drawPreviewEl.style.borderRadius = '4px';
      drawPreviewEl.style.boxShadow = 'none';
      drawPreviewEl.style.display = 'block';
    } else if (tool === 'highlight') {
      const minX = Math.min(startX, currX);
      const minY = Math.min(startY, currY);
      const w = Math.abs(currX - startX);
      const h = Math.abs(currY - startY);

      drawPreviewEl.innerHTML = '';
      drawPreviewEl.style.left = `${minX}%`;
      drawPreviewEl.style.top = `${minY}%`;
      drawPreviewEl.style.width = `${w}%`;
      drawPreviewEl.style.height = `${h}%`;
      drawPreviewEl.style.border = 'none';
      drawPreviewEl.style.background = hexToRgba(activeColor, 0.35);
      drawPreviewEl.style.borderRadius = '4px';
      drawPreviewEl.style.boxShadow = 'none';
      drawPreviewEl.style.display = 'block';
    } else if (tool === 'arrow') {
      drawPreviewEl.style.left = '0';
      drawPreviewEl.style.top = '0';
      drawPreviewEl.style.width = '100%';
      drawPreviewEl.style.height = '100%';
      drawPreviewEl.style.border = 'none';
      drawPreviewEl.style.background = 'transparent';
      drawPreviewEl.style.boxShadow = 'none';
      drawPreviewEl.style.display = 'block';

      const ow = overlayEl.clientWidth || 800;
      const oh = overlayEl.clientHeight || 450;
      const px1 = (startX / 100) * ow;
      const py1 = (startY / 100) * oh;
      const px2 = (currX / 100) * ow;
      const py2 = (currY / 100) * oh;
      const dx = px2 - px1;
      const dy = py2 - py1;
      const angle = Math.atan2(dy, dx);
      const headLen = 16;
      const p1x = px2 - headLen * Math.cos(angle - Math.PI / 6);
      const p1y = py2 - headLen * Math.sin(angle - Math.PI / 6);
      const p2x = px2 - headLen * Math.cos(angle + Math.PI / 6);
      const p2y = py2 - headLen * Math.sin(angle + Math.PI / 6);

      drawPreviewEl.innerHTML = `
        <svg style="width:100%;height:100%;overflow:visible;position:absolute;top:0;left:0;">
          <line x1="${px1}" y1="${py1}" x2="${px2}" y2="${py2}" stroke="${activeColor}" stroke-width="3.5" stroke-dasharray="6,4" stroke-linecap="round"/>
          <polygon points="${px2},${py2} ${p1x},${p1y} ${p2x},${p2y}" fill="${activeColor}" stroke="#ffffff" stroke-width="1.5"/>
        </svg>
      `;
    } else if (tool === 'callout') {
      drawPreviewEl.style.left = '0';
      drawPreviewEl.style.top = '0';
      drawPreviewEl.style.width = '100%';
      drawPreviewEl.style.height = '100%';
      drawPreviewEl.style.border = 'none';
      drawPreviewEl.style.background = 'transparent';
      drawPreviewEl.style.boxShadow = 'none';
      drawPreviewEl.style.display = 'block';

      const ow = overlayEl.clientWidth || 800;
      const oh = overlayEl.clientHeight || 450;
      const px1 = (startX / 100) * ow;
      const py1 = (startY / 100) * oh;
      const px2 = (currX / 100) * ow;
      const py2 = (currY / 100) * oh;

      drawPreviewEl.innerHTML = `
        <svg style="width:100%;height:100%;overflow:visible;position:absolute;top:0;left:0;">
          <line x1="${px1}" y1="${py1}" x2="${px2}" y2="${py2}" stroke="${activeColor}" stroke-width="2" stroke-dasharray="4,3"/>
          <circle cx="${px2}" cy="${py2}" r="6" fill="${activeColor}" stroke="#ffffff" stroke-width="2"/>
        </svg>
        <div style="position:absolute;left:${startX}%;top:${startY}%;border:2px dashed ${activeColor};background:${hexToRgba(activeColor, 0.2)};border-radius:6px;padding:6px 10px;color:#fff;font-size:12px;font-weight:600;box-shadow:0 4px 12px rgba(0,0,0,0.5);">
          <i class="fas fa-sticky-note" style="color:${activeColor};margin-right:5px;"></i> Note
        </div>
      `;
    } else if (tool === 'text') {
      const minX = Math.min(startX, currX);
      const minY = Math.min(startY, currY);
      const w = Math.max(12, Math.abs(currX - startX));
      const h = Math.max(6, Math.abs(currY - startY));

      drawPreviewEl.innerHTML = '';
      drawPreviewEl.style.left = `${minX}%`;
      drawPreviewEl.style.top = `${minY}%`;
      drawPreviewEl.style.width = `${w}%`;
      drawPreviewEl.style.height = `${h}%`;
      drawPreviewEl.style.border = `2px dashed ${activeColor}`;
      drawPreviewEl.style.background = hexToRgba(activeColor, 0.15);
      drawPreviewEl.style.borderRadius = '4px';
      drawPreviewEl.style.display = 'block';
    }
  }

  function onDrawingEnd(e) {
    if (!isDrawingNew) return;
    if (e) {
      e.preventDefault();
      e.stopPropagation();
    }

    ignoreNextClick = true;
    setTimeout(() => { ignoreNextClick = false; }, 120);

    window.removeEventListener('mousemove', onDrawingMove, true);
    window.removeEventListener('mouseup', onDrawingEnd, true);

    if (drawPreviewEl) {
      drawPreviewEl.remove();
      drawPreviewEl = null;
    }

    if (!drawState) {
      isDrawingNew = false;
      return;
    }

    const state = drawState;
    isDrawingNew = false;
    drawState = null;

    const distPx = Math.hypot(e.clientX - state.startX, e.clientY - state.startY);
    const tool = state.tool;

    if (distPx > 8) {
      // User dragged to define area / geometry
      if (tool === 'rect') {
        const minX = Math.max(0, Math.min(95, parseFloat(Math.min(state.startPctX, state.currPctX).toFixed(1))));
        const minY = Math.max(0, Math.min(95, parseFloat(Math.min(state.startPctY, state.currPctY).toFixed(1))));
        const w = Math.max(3, Math.min(100 - minX, parseFloat(Math.abs(state.currPctX - state.startPctX).toFixed(1))));
        const h = Math.max(2.5, Math.min(100 - minY, parseFloat(Math.abs(state.currPctY - state.startPctY).toFixed(1))));
        addAnnotation('rect', minX, minY, { w, h });
      } else if (tool === 'highlight') {
        const minX = Math.max(0, Math.min(95, parseFloat(Math.min(state.startPctX, state.currPctX).toFixed(1))));
        const minY = Math.max(0, Math.min(95, parseFloat(Math.min(state.startPctY, state.currPctY).toFixed(1))));
        const w = Math.max(3, Math.min(100 - minX, parseFloat(Math.abs(state.currPctX - state.startPctX).toFixed(1))));
        const h = Math.max(2.5, Math.min(100 - minY, parseFloat(Math.abs(state.currPctY - state.startPctY).toFixed(1))));
        addAnnotation('highlight', minX, minY, { w, h });
      } else if (tool === 'arrow') {
        const x1 = Math.max(0, Math.min(100, parseFloat(state.startPctX.toFixed(1))));
        const y1 = Math.max(0, Math.min(100, parseFloat(state.startPctY.toFixed(1))));
        const x2 = Math.max(0, Math.min(100, parseFloat(state.currPctX.toFixed(1))));
        const y2 = Math.max(0, Math.min(100, parseFloat(state.currPctY.toFixed(1))));
        addAnnotation('arrow', x1, y1, { x2, y2 });
      } else if (tool === 'callout') {
        const x1 = Math.max(0, Math.min(95, parseFloat(state.startPctX.toFixed(1))));
        const y1 = Math.max(0, Math.min(95, parseFloat(state.startPctY.toFixed(1))));
        const x2 = Math.max(0, Math.min(100, parseFloat(state.currPctX.toFixed(1))));
        const y2 = Math.max(0, Math.min(100, parseFloat(state.currPctY.toFixed(1))));
        addAnnotation('callout', x1, y1, { x2, y2 });
      } else if (tool === 'text') {
        const minX = Math.max(0, Math.min(95, parseFloat(Math.min(state.startPctX, state.currPctX).toFixed(1))));
        const minY = Math.max(0, Math.min(95, parseFloat(Math.min(state.startPctY, state.currPctY).toFixed(1))));
        const w = Math.max(12, Math.min(100 - minX, parseFloat(Math.abs(state.currPctX - state.startPctX).toFixed(1))));
        addAnnotation('text', minX, minY, { w });
      }
    } else {
      // User clicked without dragging: place default object at clicked point
      addAnnotation(tool, state.startPctX, state.startPctY);
    }
  }

  // Delete Annotation
  function deleteAnnotation(id) {
    const idx = annotations.findIndex(a => a.id === id);
    if (idx === -1) return;
    annotations.splice(idx, 1);
    if (selectedId === id) selectedId = null;
    render();
    scheduleAutosave();
    showToast('Annotation deleted', 'fas fa-trash-alt', '#ef4444');
  }

  // Toggle Edit Mode
  function toggleEditMode(forceState) {
    isEditMode = (forceState !== undefined) ? !!forceState : !isEditMode;

    if (toolbarEl) {
      toolbarEl.style.display = isEditMode ? 'flex' : 'none';
    }

    if (toggleBtnEl) {
      if (isEditMode) {
        toggleBtnEl.style.background = '#0284c7';
        toggleBtnEl.style.borderColor = '#38bdf8';
        toggleBtnEl.style.color = '#ffffff';
      } else {
        toggleBtnEl.style.background = '#1e293b';
        toggleBtnEl.style.borderColor = '#475569';
        toggleBtnEl.style.color = '#cbd5e1';
      }
    }

    if (videoEl && isEditMode) {
      videoEl.pause();
    }

    if (!isEditMode) {
      selectedId = null;
    }
    selectTool('select');

    render();
  }

  // Autosave Debounced
  function scheduleAutosave() {
    if (saveDebounceTimer) clearTimeout(saveDebounceTimer);
    saveDebounceTimer = setTimeout(() => {
      saveAnnotations(true);
    }, 800);
  }

  // Save Annotations via API
  function saveAnnotations(silent = false) {
    if (!currentRecordingId) return;

    if (saveBtnEl && !silent) {
      saveBtnEl.innerHTML = '<i class="fas fa-spinner fa-spin" style="color: #38bdf8; font-size: 0.9em;"></i> <span style="font-weight: 500;">Saving...</span>';
    }

    fetch(`/recordings/${encodeURIComponent(currentRecordingId)}/annotations`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json'
      },
      body: JSON.stringify({ annotations: annotations })
    })
      .then(r => r.json())
      .then(data => {
        if (data.ok) {
          if (!silent) {
            showToast('Annotations saved', 'fas fa-check-circle', '#10b981');
          }
        } else {
          showToast(`Error: ${data.error || 'Save failed'}`, 'fas fa-exclamation-triangle', '#ef4444');
        }
      })
      .catch(err => {
        showToast('Save failed: network error', 'fas fa-exclamation-triangle', '#ef4444');
      })
      .finally(() => {
        if (saveBtnEl) {
          saveBtnEl.innerHTML = '<i class="fas fa-save" style="color: #38bdf8; font-size: 0.9em;"></i> <span style="font-weight: 500;">Save</span>';
        }
      });
  }

  // Load annotations for a recording
  function loadForRecording(id) {
    currentRecordingId = id;
    selectedId = null;
    annotations = [];

    if (!id) {
      render();
      return;
    }

    // Check if initial data is embedded on .rec-item button
    const recBtn = document.querySelector(`.rec-item[data-id="${CSS.escape(id)}"]`);
    if (recBtn && recBtn.hasAttribute('data-annotations')) {
      try {
        const parsed = JSON.parse(recBtn.getAttribute('data-annotations'));
        if (Array.isArray(parsed)) {
          annotations = parsed;
          render();
        }
      } catch (e) {}
    }

    // Fetch freshest annotations from server
    fetch(`/recordings/${encodeURIComponent(id)}/annotations`, {
      headers: { 'Accept': 'application/json' }
    })
      .then(r => r.json())
      .then(data => {
        if (data.ok && Array.isArray(data.annotations) && currentRecordingId === id) {
          annotations = data.annotations;
          render();
        }
      })
      .catch(() => {});
  }

  // Clear state when switching away from video
  function clear() {
    stopPlayheadRaf();
    currentRecordingId = null;
    annotations = [];
    selectedId = null;
    lastRulerDuration = -1;
    setTimelineZoom(1);
    if (isEditMode) toggleEditMode(false);
    if (overlayEl) {
      if (svgEl) svgEl.innerHTML = '';
      if (domEl) domEl.innerHTML = '';
    }
    if (tlSegmentsEl) tlSegmentsEl.innerHTML = '';
    if (trayEl) trayEl.style.display = 'none';
  }

  // Setup DOM Event Listeners
  function init() {
    containerEl = document.getElementById('video-container');
    stageEl = document.getElementById('video-stage');
    videoEl = document.getElementById('video-player');
    overlayEl = document.getElementById('video-annotations-overlay');
    svgEl = document.getElementById('video-annotations-svg');
    domEl = document.getElementById('video-annotations-dom');
    toolbarEl = document.getElementById('video-annotation-toolbar');
    toggleBtnEl = document.getElementById('video-annotate-toggle-btn');
    trayEl = document.getElementById('video-annotations-tray');
    chipsEl = document.getElementById('video-annotations-chips');
    tlPlayBtnEl = document.getElementById('video-tl-play-btn');
    tlPlayIconEl = document.getElementById('video-tl-play-icon');
    tlBackBtnEl = document.getElementById('video-tl-back-btn');
    tlFwdBtnEl = document.getElementById('video-tl-fwd-btn');
    tlCurTimeEl = document.getElementById('video-tl-cur-time');
    tlDurTimeEl = document.getElementById('video-tl-dur-time');
    tlCountNumEl = document.getElementById('video-tl-count-num');
    tlSelInfoEl = document.getElementById('video-tl-sel-info');
    tlSelLabelEl = document.getElementById('video-tl-sel-label');
    tlSelTimeEl = document.getElementById('video-tl-sel-time');
    tlRulerEl = document.getElementById('video-tl-ruler');
    tlTrackEl = document.getElementById('video-tl-track');
    tlLaneGuidesEl = document.getElementById('video-tl-lane-guides');
    tlInnerEl = document.getElementById('video-tl-inner');
    tlProgressEl = document.getElementById('video-tl-progress');
    tlSegmentsEl = document.getElementById('video-tl-segments');
    tlPlayheadEl = document.getElementById('video-tl-playhead');
    tlLanesBadgeEl = document.getElementById('video-tl-lanes-badge');
    tlLanesNumEl = document.getElementById('video-tl-lanes-num');
    tlLaneDownBtnEl = document.getElementById('video-tl-lane-down-btn');
    tlLaneUpBtnEl = document.getElementById('video-tl-lane-up-btn');
    tlSelLaneNumEl = document.getElementById('video-tl-sel-lane-num');
    tlAutoArrangeBtnEl = document.getElementById('video-tl-auto-arrange-btn');

    if (tlLaneDownBtnEl) {
      tlLaneDownBtnEl.addEventListener('click', (e) => {
        e.stopPropagation();
        const ann = annotations.find(a => a.id === selectedId);
        if (ann) {
          const curLane = typeof ann.lane === 'number' ? ann.lane : 0;
          ann.lane = Math.max(0, curLane - 1);
          render(true);
          scheduleAutosave();
        }
      });
    }

    if (tlLaneUpBtnEl) {
      tlLaneUpBtnEl.addEventListener('click', (e) => {
        e.stopPropagation();
        const ann = annotations.find(a => a.id === selectedId);
        if (ann) {
          const curLane = typeof ann.lane === 'number' ? ann.lane : 0;
          ann.lane = curLane + 1;
          render(true);
          scheduleAutosave();
        }
      });
    }

    if (tlAutoArrangeBtnEl) {
      tlAutoArrangeBtnEl.addEventListener('click', (e) => {
        e.stopPropagation();
        autoArrangeLanes();
        render(true);
        scheduleAutosave();
      });
    }

    tlToggleBtnEl = document.getElementById('video-timeline-toggle-btn');
    tlCollapseBtnEl = document.getElementById('video-tl-collapse-btn');
    tlCollapseIconEl = document.getElementById('video-tl-collapse-icon');
    tlSettingsBtnEl = document.getElementById('video-settings-btn');
    tlSettingsMenuEl = document.getElementById('video-settings-menu');
    tlSettingTimelineCheckboxEl = document.getElementById('video-setting-timeline-checkbox');
    tlScrollEl = document.getElementById('video-tl-scroll');
    tlZoomInnerEl = document.getElementById('video-tl-zoom-inner');
    tlZoomOutBtnEl = document.getElementById('video-tl-zoom-out-btn');
    tlZoomInBtnEl = document.getElementById('video-tl-zoom-in-btn');
    tlZoomLabelEl = document.getElementById('video-tl-zoom-label');
    tlVolBtnEl = document.getElementById('video-tl-vol-btn');

    const ZOOM_STEPS = [1, 1.5, 2, 3, 5, 8, 10];
    if (tlZoomOutBtnEl) {
      tlZoomOutBtnEl.addEventListener('click', (e) => {
        e.stopPropagation();
        const prev = [...ZOOM_STEPS].reverse().find(z => z < timelineZoom - 0.01) || 1;
        setTimelineZoom(prev);
      });
    }
    if (tlZoomInBtnEl) {
      tlZoomInBtnEl.addEventListener('click', (e) => {
        e.stopPropagation();
        const next = ZOOM_STEPS.find(z => z > timelineZoom + 0.01) || 10;
        setTimelineZoom(next);
      });
    }
    if (tlZoomLabelEl) {
      tlZoomLabelEl.addEventListener('click', (e) => {
        e.stopPropagation();
        setTimelineZoom(1);
      });
    }
    const handleWheelNavigation = (e) => {
      if (e.ctrlKey || e.metaKey || e.altKey) {
        e.preventDefault();
        e.stopPropagation();
        const factor = e.deltaY < 0 ? 1.25 : 0.8;
        setTimelineZoom(Math.round(timelineZoom * factor * 10) / 10);
        return;
      }
      if (e.shiftKey && videoEl) {
        e.preventDefault();
        e.stopPropagation();
        // Shift+Wheel often converts vertical deltaY into deltaX on Linux/macOS
        const delta = e.deltaY !== 0 ? e.deltaY : e.deltaX;
        if (delta === 0) return;
        const step = Math.max(0.05, Math.round((0.5 / timelineZoom) * 100) / 100);
        const dir = delta > 0 ? 1 : -1;
        const dur = getVideoDuration();
        const baseTime = pendingSeekTarget !== null ? pendingSeekTarget : videoEl.currentTime;
        safeSeek(Math.max(0, Math.min(dur, baseTime + dir * step)));
      }
    };

    if (tlScrollEl) {
      tlScrollEl.addEventListener('wheel', handleWheelNavigation, { passive: false });
    }
    if (stageEl) {
      stageEl.addEventListener('wheel', (e) => {
        if (e.shiftKey || e.ctrlKey || e.metaKey || e.altKey) {
          handleWheelNavigation(e);
        }
      }, { passive: false });
    }
    tlVolIconEl = document.getElementById('video-tl-vol-icon');
    tlFsBtnEl = document.getElementById('video-tl-fs-btn');
    tlFsIconEl = document.getElementById('video-tl-fs-icon');
    tlSpeedDownBtnEl = document.getElementById('video-tl-speed-down-btn');
    tlSpeedUpBtnEl = document.getElementById('video-tl-speed-up-btn');
    tlSpeedLabelEl = document.getElementById('video-tl-speed-label');
    tlSpeedTextEl = document.getElementById('video-tl-speed-text');
    tlSpeedIconEl = document.getElementById('video-tl-speed-icon');

    const SPEED_STEPS = [0.25, 0.5, 0.75, 1, 1.25, 1.5, 2];
    const applyPlaybackSpeed = (spd) => {
      playbackSpeed = spd;
      if (videoEl) videoEl.playbackRate = spd;
      if (tlSpeedTextEl) {
        tlSpeedTextEl.textContent = `${spd}x`;
      }
      if (tlSpeedLabelEl) {
        tlSpeedLabelEl.style.color = spd !== 1 ? '#38bdf8' : '#cbd5e1';
      }
      if (tlSpeedIconEl) {
        tlSpeedIconEl.style.color = spd !== 1 ? '#38bdf8' : '#94a3b8';
      }
    };

    if (tlSpeedDownBtnEl) {
      tlSpeedDownBtnEl.addEventListener('click', (e) => {
        e.stopPropagation();
        const prev = [...SPEED_STEPS].reverse().find(s => s < playbackSpeed - 0.001) || SPEED_STEPS[0];
        applyPlaybackSpeed(prev);
      });
    }
    if (tlSpeedUpBtnEl) {
      tlSpeedUpBtnEl.addEventListener('click', (e) => {
        e.stopPropagation();
        const next = SPEED_STEPS.find(s => s > playbackSpeed + 0.001) || SPEED_STEPS[SPEED_STEPS.length - 1];
        applyPlaybackSpeed(next);
      });
    }
    if (tlSpeedLabelEl) {
      tlSpeedLabelEl.addEventListener('click', (e) => {
        e.stopPropagation();
        applyPlaybackSpeed(1);
      });
    }

    const updateVolumeUI = () => {
      if (!videoEl || !tlVolIconEl) return;
      if (videoEl.muted || videoEl.volume === 0) {
        tlVolIconEl.className = 'fas fa-volume-mute';
        if (tlVolBtnEl) tlVolBtnEl.style.color = '#ef4444';
      } else {
        tlVolIconEl.className = 'fas fa-volume-up';
        if (tlVolBtnEl) tlVolBtnEl.style.color = '#94a3b8';
      }
    };

    if (tlVolBtnEl) {
      tlVolBtnEl.addEventListener('click', (e) => {
        e.stopPropagation();
        if (!videoEl) return;
        videoEl.muted = !videoEl.muted;
        updateVolumeUI();
      });
    }

    const toggleFullscreen = () => {
      const fsTarget = containerEl || stageEl || videoEl;
      if (!fsTarget) return;
      if (!document.fullscreenElement) {
        if (fsTarget.requestFullscreen) {
          fsTarget.requestFullscreen().catch(() => {});
        } else if (fsTarget.webkitRequestFullscreen) {
          fsTarget.webkitRequestFullscreen();
        }
      } else {
        if (document.exitFullscreen) {
          document.exitFullscreen().catch(() => {});
        } else if (document.webkitExitFullscreen) {
          document.webkitExitFullscreen();
        }
      }
    };

    if (tlFsBtnEl) {
      tlFsBtnEl.addEventListener('click', (e) => {
        e.stopPropagation();
        toggleFullscreen();
      });
    }

    const updateFullscreenUI = () => {
      if (!tlFsIconEl) return;
      if (document.fullscreenElement) {
        tlFsIconEl.className = 'fas fa-compress';
        if (tlFsBtnEl) tlFsBtnEl.title = 'Exit Fullscreen (F)';
      } else {
        tlFsIconEl.className = 'fas fa-expand';
        if (tlFsBtnEl) tlFsBtnEl.title = 'Toggle Fullscreen (F)';
      }
    };
    document.addEventListener('fullscreenchange', updateFullscreenUI);

    if (tlToggleBtnEl) {
      tlToggleBtnEl.addEventListener('click', (e) => {
        e.stopPropagation();
        toggleTimeline();
      });
      updateTimelineToggleBtnUI(isTimelineVisible());
    }

    if (tlSettingsBtnEl && tlSettingsMenuEl) {
      tlSettingsBtnEl.addEventListener('click', (e) => {
        e.stopPropagation();
        const isOpen = tlSettingsMenuEl.style.display === 'block';
        tlSettingsMenuEl.style.display = isOpen ? 'none' : 'block';
        if (tlSettingTimelineCheckboxEl) {
          tlSettingTimelineCheckboxEl.checked = isTimelineVisible();
        }
      });
      document.addEventListener('click', (e) => {
        if (tlSettingsMenuEl.style.display === 'block' && !tlSettingsMenuEl.contains(e.target) && e.target !== tlSettingsBtnEl) {
          tlSettingsMenuEl.style.display = 'none';
        }
      });
    }

    if (tlSettingTimelineCheckboxEl) {
      tlSettingTimelineCheckboxEl.checked = isTimelineVisible();
      tlSettingTimelineCheckboxEl.addEventListener('change', (e) => {
        e.stopPropagation();
        toggleTimeline(!!tlSettingTimelineCheckboxEl.checked);
      });
    }

    if (tlCollapseBtnEl) {
      updateTimelineCollapsedUI(isTimelineCollapsed());
      tlCollapseBtnEl.addEventListener('click', (e) => {
        e.stopPropagation();
        toggleTimelineCollapsed();
      });
    }
    propsEl = document.getElementById('video-ann-props');
    startInputEl = document.getElementById('video-ann-start');
    endInputEl = document.getElementById('video-ann-end');
    textInputEl = document.getElementById('video-ann-text');
    badgeWrapEl = document.getElementById('video-ann-badge-wrap');
    badgeValEl = document.getElementById('video-ann-badge-val');
    stepLinkEl = document.getElementById('video-ann-step-link');
    fontSizeEl = document.getElementById('video-ann-font-size');
    saveBtnEl = document.getElementById('video-ann-save-btn');

    if (!videoEl || !stageEl) return;

    // Toggle button in main action bar
    if (toggleBtnEl) {
      toggleBtnEl.addEventListener('click', () => toggleEditMode());
    }

    // Tool selector buttons
    const toolBtns = document.querySelectorAll('.video-ann-tool-btn');
    toolBtns.forEach(btn => {
      btn.addEventListener('click', (e) => {
        e.stopPropagation();
        const tool = btn.getAttribute('data-tool');
        selectTool(tool);
      });
    });

    // Time range inputs
    if (startInputEl) {
      startInputEl.addEventListener('change', () => {
        const ann = annotations.find(a => a.id === selectedId);
        if (ann) {
          ann.startTime = parseTime(startInputEl.value);
          render();
          scheduleAutosave();
        }
      });
    }

    if (endInputEl) {
      endInputEl.addEventListener('change', () => {
        const ann = annotations.find(a => a.id === selectedId);
        if (ann) {
          ann.endTime = parseTime(endInputEl.value);
          render();
          scheduleAutosave();
        }
      });
    }

    // Set start/end to current time buttons
    const setStartBtn = document.getElementById('video-ann-set-start-btn');
    if (setStartBtn) {
      setStartBtn.addEventListener('click', () => {
        const ann = annotations.find(a => a.id === selectedId);
        if (ann && videoEl) {
          ann.startTime = Math.max(0, Math.floor(videoEl.currentTime * 10) / 10);
          render();
          scheduleAutosave();
        }
      });
    }

    const setEndBtn = document.getElementById('video-ann-set-end-btn');
    if (setEndBtn) {
      setEndBtn.addEventListener('click', () => {
        const ann = annotations.find(a => a.id === selectedId);
        if (ann && videoEl) {
          ann.endTime = Math.max(ann.startTime + 0.5, Math.floor(videoEl.currentTime * 10) / 10);
          render();
          scheduleAutosave();
        }
      });
    }

    // Text input
    if (textInputEl) {
      textInputEl.addEventListener('input', () => {
        const ann = annotations.find(a => a.id === selectedId);
        if (ann) {
          ann.text = textInputEl.value;
          render();
          scheduleAutosave();
        }
      });
    }

    // Step Link dropdown
    if (stepLinkEl) {
      stepLinkEl.addEventListener('change', () => {
        const ann = annotations.find(a => a.id === selectedId);
        if (ann) {
          ann.targetStepId = stepLinkEl.value || null;
          render(true);
          scheduleAutosave();
        }
      });
    }

    // Font size controls (- <input> +)
    const fontDecBtn = document.getElementById('video-ann-font-dec');
    const fontIncBtn = document.getElementById('video-ann-font-inc');
    const fontInput = document.getElementById('video-ann-font-size-input');

    if (fontDecBtn && fontInput) {
      fontDecBtn.addEventListener('click', () => {
        let val = parseInt(fontInput.value, 10) || 13;
        val = Math.max(8, val - 1);
        fontInput.value = val;
        activeFontSize = val;
        const ann = annotations.find(a => a.id === selectedId);
        if (ann) {
          ann.fontSize = val;
          render(true);
          scheduleAutosave();
        }
      });
    }

    if (fontIncBtn && fontInput) {
      fontIncBtn.addEventListener('click', () => {
        let val = parseInt(fontInput.value, 10) || 13;
        val = Math.min(48, val + 1);
        fontInput.value = val;
        activeFontSize = val;
        const ann = annotations.find(a => a.id === selectedId);
        if (ann) {
          ann.fontSize = val;
          render(true);
          scheduleAutosave();
        }
      });
    }

    if (fontInput) {
      const applyFontVal = () => {
        let val = parseInt(fontInput.value, 10);
        if (isNaN(val)) return;
        val = Math.max(8, Math.min(48, val));
        activeFontSize = val;
        const ann = annotations.find(a => a.id === selectedId);
        if (ann) {
          ann.fontSize = val;
          render(true);
          scheduleAutosave();
        }
      };
      fontInput.addEventListener('change', applyFontVal);
      fontInput.addEventListener('input', applyFontVal);
    }

    // Badge step counter controls (- <input> +)
    const badgeDecBtn = document.getElementById('video-ann-badge-dec');
    const badgeIncBtn = document.getElementById('video-ann-badge-inc');
    const badgeNumInput = document.getElementById('video-ann-badge-num');

    if (badgeDecBtn && badgeNumInput) {
      badgeDecBtn.addEventListener('click', () => {
        let val = parseInt(badgeNumInput.value, 10) || 1;
        val = Math.max(1, val - 1);
        badgeNumInput.value = val;
        const ann = annotations.find(a => a.id === selectedId);
        if (ann && ann.type === 'badge') {
          ann.badge = String(val);
          render();
          scheduleAutosave();
        }
      });
    }

    if (badgeIncBtn && badgeNumInput) {
      badgeIncBtn.addEventListener('click', () => {
        let val = parseInt(badgeNumInput.value, 10) || 1;
        val = val + 1;
        badgeNumInput.value = val;
        const ann = annotations.find(a => a.id === selectedId);
        if (ann && ann.type === 'badge') {
          ann.badge = String(val);
          render();
          scheduleAutosave();
        }
      });
    }

    if (badgeNumInput) {
      badgeNumInput.addEventListener('input', () => {
        const ann = annotations.find(a => a.id === selectedId);
        if (ann && ann.type === 'badge') {
          ann.badge = badgeNumInput.value || '1';
          render();
          scheduleAutosave();
        }
      });
    }

    // Color buttons
    const colorBtns = document.querySelectorAll('.video-ann-color-btn');
    colorBtns.forEach(btn => {
      btn.addEventListener('click', () => {
        const col = btn.getAttribute('data-color');
        activeColor = col;
        colorBtns.forEach(b => b.classList.toggle('active', b.getAttribute('data-color') === col));
        const ann = annotations.find(a => a.id === selectedId);
        if (ann) {
          ann.color = col;
          render();
          scheduleAutosave();
        }
      });
    });

    // Delete button
    const deleteBtn = document.getElementById('video-ann-delete-btn');
    if (deleteBtn) {
      deleteBtn.addEventListener('click', () => {
        if (selectedId) deleteAnnotation(selectedId);
      });
    }

    // Save button
    if (saveBtnEl) {
      saveBtnEl.addEventListener('click', () => saveAnnotations(false));
    }

    // Close button
    const closeBtn = document.getElementById('video-ann-close-btn');
    if (closeBtn) {
      closeBtn.addEventListener('click', () => toggleEditMode(false));
    }

    // Keyboard shortcuts & Play-selector position controls (Capturing phase on window to avoid browser/shadow DOM capture)
    window.addEventListener('keydown', (e) => {
      // Ignore if typing in text inputs, textareas, selects, or contenteditable bodies
      const isTyping = (e.target && (e.target.tagName === 'INPUT' || e.target.tagName === 'TEXTAREA' || e.target.tagName === 'SELECT' || e.target.isContentEditable)) ||
                       (document.activeElement && (document.activeElement.tagName === 'INPUT' || document.activeElement.tagName === 'TEXTAREA' || document.activeElement.tagName === 'SELECT' || document.activeElement.isContentEditable));
      if (isTyping) return;

      // Ignore if video player is not currently active/visible
      if (!videoEl || !containerEl || containerEl.style.display === 'none') return;

      // Ignore if any actual modal dialog is open
      const openW3Modal = document.querySelector('.w3-modal[style*="display: block"]');
      const imgModal = document.getElementById('image-modal');
      const isImgModalOpen = imgModal && imgModal.style.display !== 'none' && imgModal.style.display !== '';
      if (openW3Modal || isImgModalOpen) return;

      const dur = getVideoDuration();

      // Play-selector Position Controls (Arrow Keys, Home, End, Space)
      if (e.key === 'ArrowLeft') {
        e.preventDefault();
        e.stopPropagation();
        let targetTime = 0;
        if (e.ctrlKey || e.metaKey) {
          // Jump to start of previous annotation
          const prevAnns = annotations.filter(a => a.startTime < videoEl.currentTime - 0.2).sort((a, b) => b.startTime - a.startTime);
          targetTime = prevAnns.length > 0 ? prevAnns[0].startTime : 0;
        } else {
          const step = e.shiftKey ? 5 : (e.altKey ? 0.1 : 1);
          targetTime = Math.max(0, videoEl.currentTime - step);
        }
        safeSeek(targetTime);
        return;
      }

      if (e.key === 'ArrowRight') {
        e.preventDefault();
        e.stopPropagation();
        let targetTime = dur;
        if (e.ctrlKey || e.metaKey) {
          // Jump to start of next annotation
          const nextAnns = annotations.filter(a => a.startTime > videoEl.currentTime + 0.2).sort((a, b) => a.startTime - b.startTime);
          targetTime = nextAnns.length > 0 ? nextAnns[0].startTime : dur;
        } else {
          const step = e.shiftKey ? 5 : (e.altKey ? 0.1 : 1);
          targetTime = Math.min(dur, videoEl.currentTime + step);
        }
        safeSeek(targetTime);
        return;
      }

      if (e.key === ' ' || e.code === 'Space') {
        e.preventDefault();
        e.stopPropagation();
        togglePlayPause();
        return;
      }

      if (e.key === 'Home') {
        e.preventDefault();
        e.stopPropagation();
        safeSeek(0);
        return;
      }

      if (e.key === 'End') {
        e.preventDefault();
        e.stopPropagation();
        safeSeek(dur);
        return;
      }

      // Quick keyboard controls for Mute (M) and Fullscreen (F)
      if (!e.ctrlKey && !e.metaKey && !e.altKey && !isEditMode) {
        const k = e.key.toLowerCase();
        if (k === 'm') {
          e.preventDefault();
          e.stopPropagation();
          videoEl.muted = !videoEl.muted;
          updateVolumeUI();
          return;
        }
        if (k === 'f') {
          e.preventDefault();
          e.stopPropagation();
          toggleFullscreen();
          return;
        }
      }

      // Edit-mode specific annotation editing keys (V, C, A, B, N, T, Delete, Escape)
      if (isEditMode) {
        if (e.key === 'Delete' || e.key === 'Backspace') {
          if (selectedId) {
            e.preventDefault();
            e.stopPropagation();
            deleteAnnotation(selectedId);
          }
        } else if (e.key === 'Escape') {
          e.preventDefault();
          e.stopPropagation();
          selectedId = null;
          selectTool('select');
          render();
        } else if (!e.ctrlKey && !e.metaKey && !e.altKey) {
          const k = e.key.toLowerCase();
          if (k === 'v') {
            e.preventDefault();
            e.stopPropagation();
            selectTool('select');
          } else if (k === 'c') {
            e.preventDefault();
            e.stopPropagation();
            selectTool('callout');
          } else if (k === 'a') {
            e.preventDefault();
            e.stopPropagation();
            selectTool('arrow');
          } else if (k === 'b') {
            e.preventDefault();
            e.stopPropagation();
            selectTool('rect');
          } else if (k === 'n') {
            e.preventDefault();
            e.stopPropagation();
            selectTool('badge');
          } else if (k === 't') {
            e.preventDefault();
            e.stopPropagation();
            selectTool('text');
          }
        }
      }
    }, true);

    // Timeline transport buttons
    if (tlPlayBtnEl) {
      tlPlayBtnEl.addEventListener('click', () => {
        togglePlayPause();
      });
    }

    if (tlBackBtnEl) {
      tlBackBtnEl.addEventListener('click', () => {
        if (!videoEl) return;
        safeSeek(videoEl.currentTime - 5);
      });
    }

    if (tlFwdBtnEl) {
      tlFwdBtnEl.addEventListener('click', () => {
        if (!videoEl) return;
        safeSeek(videoEl.currentTime + 5);
      });
    }

    // Timeline track click & scrubbing
    if (tlTrackEl) {
      const handleScrub = (e) => {
        if (!videoEl || !tlTrackEl) return;
        const refEl = tlInnerEl || tlTrackEl;
        const rect = refEl.getBoundingClientRect();
        if (rect.width <= 0) return;
        const offsetX = Math.max(0, Math.min(rect.width, e.clientX - rect.left));
        const pct = offsetX / rect.width;
        const duration = getVideoDuration();
        const newTime = pct * duration;
        safeSeek(newTime);
      };

      tlTrackEl.addEventListener('mousedown', (e) => {
        if (e.target.closest('.video-tl-segment')) return;
        handleScrub(e);

        const onMove = (ev) => {
          ev.preventDefault();
          handleScrub(ev);
        };
        const onUp = () => {
          window.removeEventListener('mousemove', onMove);
          window.removeEventListener('mouseup', onUp);
        };
        window.addEventListener('mousemove', onMove);
        window.addEventListener('mouseup', onUp);
      });
    }

    // Video Player events
    videoEl.addEventListener('timeupdate', () => {
      updatePlayheadUI(videoEl.currentTime, getVideoDuration());
      render();
    });
    videoEl.addEventListener('seeked', () => {
      updatePlayheadUI(videoEl.currentTime, getVideoDuration());
      render();
    });
    videoEl.addEventListener('loadedmetadata', () => {
      if (playbackSpeed !== 1) videoEl.playbackRate = playbackSpeed;
      updateOverlayBounds();
      render();
    });
    videoEl.addEventListener('play', () => {
      updatePlayheadUI(videoEl.currentTime, getVideoDuration());
      startPlayheadRaf();
      render();
    });
    videoEl.addEventListener('pause', () => {
      stopPlayheadRaf();
      updatePlayheadUI(videoEl.currentTime, getVideoDuration());
      render();
    });
    videoEl.addEventListener('ended', () => {
      stopPlayheadRaf();
      updatePlayheadUI(videoEl.currentTime, getVideoDuration());
      render();
    });

    // Resize handling
    if (window.ResizeObserver) {
      const ro = new ResizeObserver(() => {
        updateOverlayBounds();
        render();
      });
      ro.observe(stageEl);
      ro.observe(videoEl);
    }
    window.addEventListener('resize', () => {
      updateOverlayBounds();
      render();
    });
    document.addEventListener('fullscreenchange', () => {
      setTimeout(() => {
        updateOverlayBounds();
        render();
      }, 100);
    });

    // Interactive shape drawing / area selection on mousedown
    overlayEl.addEventListener('mousedown', startDrawingNew);
    stageEl.addEventListener('mousedown', startDrawingNew);

    // Clicking stage toggles play/pause in view mode, or deselects in edit mode
    stageEl.addEventListener('click', (e) => {
      // Don't act if user was dragging or clicked a modal/toolbar
      if (isDrawingNew || isDragging || isTlDragging) return;
      if (isEditMode) return;
      togglePlayPause();
    });

    stageEl.addEventListener('dblclick', (e) => {
      if (isEditMode) return;
      toggleFullscreen();
    });

    // Clicking stage deselects when in select mode and clicking blank space
    stageEl.addEventListener('mousedown', (e) => {
      if (!isEditMode) return;
      if (activeTool === 'select' && (e.target === stageEl || e.target === videoEl || e.target === overlayEl || e.target === domEl || e.target === svgEl)) {
        selectedId = null;
        render();
      }
    });
  }

  // Run init on DOMContentLoaded or immediately if ready
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }

  // Canvas renderer for exporting video with burned-in annotations
  function drawAnnotationsOnCanvas(ctx, w, h, curTime) {
    const active = annotations.filter(a => curTime >= a.startTime && curTime <= a.endTime);
    if (active.length === 0) return;

    const scale = Math.max(0.6, w / 960);

    active.forEach(ann => {
      const color = ann.color || '#38bdf8';
      const x = ((ann.x || 0) / 100) * w;
      const y = ((ann.y || 0) / 100) * h;
      const bw = ((ann.w || 18) / 100) * w;
      const bh = ((ann.h || 10) / 100) * h;

      ctx.save();
      if (ann.type === 'rect') {
        ctx.strokeStyle = color;
        ctx.lineWidth = Math.max(2, 3 * scale);
        ctx.strokeRect(x, y, bw, bh);
      } else if (ann.type === 'highlight') {
        ctx.fillStyle = hexToRgba(color, 0.35);
        ctx.fillRect(x, y, bw, bh);
      } else if (ann.type === 'arrow') {
        const x2 = ((ann.x2 !== undefined ? ann.x2 : (ann.x || 0) + 15) / 100) * w;
        const y2 = ((ann.y2 !== undefined ? ann.y2 : (ann.y || 0) + 15) / 100) * h;
        const lw = Math.max(2, 3.5 * scale);
        ctx.strokeStyle = color;
        ctx.fillStyle = color;
        ctx.lineWidth = lw;
        ctx.lineCap = 'round';
        ctx.beginPath();
        ctx.moveTo(x, y);
        ctx.lineTo(x2, y2);
        ctx.stroke();

        const angle = Math.atan2(y2 - y, x2 - x);
        const headLen = Math.max(10, 14 * scale);
        ctx.beginPath();
        ctx.moveTo(x2, y2);
        ctx.lineTo(x2 - headLen * Math.cos(angle - Math.PI / 6), y2 - headLen * Math.sin(angle - Math.PI / 6));
        ctx.lineTo(x2 - headLen * Math.cos(angle + Math.PI / 6), y2 - headLen * Math.sin(angle + Math.PI / 6));
        ctx.closePath();
        ctx.fill();
      } else if (ann.type === 'badge') {
        const fSize = Math.max(12, (ann.fontSize || 14) * scale);
        const r = Math.max(11, fSize * 0.9);
        ctx.fillStyle = color;
        ctx.beginPath();
        ctx.arc(x, y, r, 0, Math.PI * 2);
        ctx.fill();
        ctx.strokeStyle = '#ffffff';
        ctx.lineWidth = Math.max(1.5, 2 * scale);
        ctx.stroke();

        ctx.fillStyle = '#0f172a';
        ctx.font = `700 ${Math.round(fSize)}px system-ui, -apple-system, sans-serif`;
        ctx.textAlign = 'center';
        ctx.textBaseline = 'middle';
        ctx.fillText(String(ann.badge || 1), x, y + 1);
      } else if (ann.type === 'text') {
        const fSize = Math.max(12, (ann.fontSize || 14) * scale);
        ctx.font = `600 ${Math.round(fSize)}px system-ui, -apple-system, sans-serif`;
        ctx.textAlign = 'left';
        ctx.textBaseline = 'top';
        ctx.shadowColor = 'rgba(0,0,0,0.85)';
        ctx.shadowBlur = 4 * scale;
        ctx.fillStyle = color;
        const lines = String(ann.text || '').split('\n');
        lines.forEach((line, idx) => {
          ctx.fillText(line, x, y + idx * (fSize * 1.3));
        });
      } else if (ann.type === 'callout') {
        const fSize = Math.max(11, (ann.fontSize || 13) * scale);
        const padX = 10 * scale;
        const padY = 7 * scale;
        ctx.font = `500 ${Math.round(fSize)}px system-ui, -apple-system, sans-serif`;
        const textStr = String(ann.text || 'Note');
        const lines = textStr.split('\n');
        let maxTextW = 0;
        lines.forEach(l => {
          const m = ctx.measureText(l).width;
          if (m > maxTextW) maxTextW = m;
        });
        const cardW = Math.max(bw, maxTextW + padX * 2);
        const cardH = Math.max(28 * scale, lines.length * (fSize * 1.35) + padY * 2);

        if (ann.x2 !== undefined && ann.y2 !== undefined) {
          const ax = (ann.x2 / 100) * w;
          const ay = (ann.y2 / 100) * h;
          ctx.strokeStyle = color;
          ctx.lineWidth = Math.max(1.5, 2 * scale);
          ctx.beginPath();
          ctx.moveTo(x + cardW / 2, y + cardH / 2);
          ctx.lineTo(ax, ay);
          ctx.stroke();
          ctx.fillStyle = color;
          ctx.beginPath();
          ctx.arc(ax, ay, 4 * scale, 0, Math.PI * 2);
          ctx.fill();
        }

        ctx.fillStyle = 'rgba(15, 23, 42, 0.92)';
        ctx.strokeStyle = color;
        ctx.lineWidth = Math.max(1.5, 2 * scale);
        const rad = 6 * scale;
        ctx.beginPath();
        ctx.moveTo(x + rad, y);
        ctx.lineTo(x + cardW - rad, y);
        ctx.quadraticCurveTo(x + cardW, y, x + cardW, y + rad);
        ctx.lineTo(x + cardW, y + cardH - rad);
        ctx.quadraticCurveTo(x + cardW, y + cardH, x + cardW - rad, y + cardH);
        ctx.lineTo(x + rad, y + cardH);
        ctx.quadraticCurveTo(x, y + cardH, x, y + cardH - rad);
        ctx.lineTo(x, y + rad);
        ctx.quadraticCurveTo(x, y, x + rad, y);
        ctx.closePath();
        ctx.fill();
        ctx.stroke();

        ctx.fillStyle = '#f8fafc';
        ctx.textAlign = 'left';
        ctx.textBaseline = 'top';
        lines.forEach((line, idx) => {
          ctx.fillText(line, x + padX, y + padY + idx * (fSize * 1.35));
        });
      }
      ctx.restore();
    });
  }

  function exportAnnotatedVideo(opts = {}) {
    return new Promise((resolve, reject) => {
      if (!videoEl || !videoEl.src) {
        return reject(new Error('No active video loaded.'));
      }
      const filename = (opts.filename || 'annotated_video').replace(/\.webm$/i, '') + '.webm';
      const onProgress = typeof opts.onProgress === 'function' ? opts.onProgress : () => {};
      const signal = opts.signal || null;

      const offVideo = document.createElement('video');
      offVideo.crossOrigin = 'anonymous';
      offVideo.playsInline = true;
      offVideo.muted = true;
      offVideo.src = videoEl.currentSrc || videoEl.src;

      let recorder = null;
      let combinedStream = null;
      let rafId = null;
      let stopFallbackTimer = null;
      let aborted = false;
      let finished = false;

      const cleanup = () => {
        if (rafId) {
          cancelAnimationFrame(rafId);
          rafId = null;
        }
        if (stopFallbackTimer) {
          clearTimeout(stopFallbackTimer);
          stopFallbackTimer = null;
        }
        if (combinedStream) {
          try { combinedStream.getTracks().forEach(t => t.stop()); } catch (_) {}
        }
        try { offVideo.pause(); } catch (_) {}
        offVideo.src = '';
      };

      if (signal) {
        signal.addEventListener('abort', () => {
          aborted = true;
          if (recorder && recorder.state !== 'inactive') {
            try { recorder.stop(); } catch (_) {}
          }
          cleanup();
          reject(new Error('Export cancelled'));
        }, { once: true });
      }

      offVideo.addEventListener('error', () => {
        cleanup();
        reject(new Error('Failed to load video for export.'));
      }, { once: true });

      offVideo.addEventListener('loadedmetadata', () => {
        if (aborted) return;
        const w = offVideo.videoWidth || 1280;
        const h = offVideo.videoHeight || 720;
        const dur = (isFinite(offVideo.duration) && offVideo.duration > 0) ? offVideo.duration : getVideoDuration();

        const canvas = document.createElement('canvas');
        canvas.width = w;
        canvas.height = h;
        const ctx = canvas.getContext('2d');

        const canvasStream = canvas.captureStream(30);
        const tracks = [...canvasStream.getVideoTracks()];

        // Preserve audio track if supported and present
        let hasAudio = false;
        try {
          const cap = offVideo.captureStream ? offVideo.captureStream() : (offVideo.mozCaptureStream ? offVideo.mozCaptureStream() : null);
          if (cap) {
            const aTracks = cap.getAudioTracks().filter(t => t.readyState === 'live');
            aTracks.forEach(t => tracks.push(t));
            hasAudio = aTracks.length > 0;
          }
        } catch (_) {}

        combinedStream = new MediaStream(tracks);
        const mimeCandidates = hasAudio
          ? ['video/webm;codecs=vp9,opus', 'video/webm;codecs=vp8,opus', 'video/webm']
          : ['video/webm;codecs=vp9', 'video/webm;codecs=vp8', 'video/webm'];
        const mimeType = (typeof MediaRecorder !== 'undefined' && MediaRecorder.isTypeSupported)
          ? (mimeCandidates.find(m => MediaRecorder.isTypeSupported(m)) || 'video/webm')
          : 'video/webm';

        const chunks = [];
        try {
          recorder = new MediaRecorder(combinedStream, { mimeType, videoBitsPerSecond: 4000000 });
        } catch (_) {
          recorder = new MediaRecorder(combinedStream);
        }

        const completeDownload = () => {
          if (finished || aborted) return;
          finished = true;
          cleanup();
          const blob = new Blob(chunks, { type: 'video/webm' });
          const url = URL.createObjectURL(blob);
          const a = document.createElement('a');
          a.href = url;
          a.download = filename;
          document.body.appendChild(a);
          a.click();
          a.remove();
          setTimeout(() => URL.revokeObjectURL(url), 5000);
          onProgress(100, dur, dur);
          resolve(filename);
        };

        recorder.ondataavailable = (ev) => {
          if (ev.data && ev.data.size > 0) chunks.push(ev.data);
        };

        recorder.onerror = (ev) => {
          cleanup();
          if (!finished && !aborted) {
            finished = true;
            reject(new Error((ev && ev.error && ev.error.message) || 'MediaRecorder error'));
          }
        };

        recorder.onstop = completeDownload;

        let finalizing = false;
        const finalizeExport = () => {
          if (finalizing || finished || aborted) return;
          finalizing = true;
          if (rafId) {
            cancelAnimationFrame(rafId);
            rafId = null;
          }
          try {
            ctx.drawImage(offVideo, 0, 0, w, h);
            drawAnnotationsOnCanvas(ctx, w, h, dur);
          } catch (_) {}

          if (recorder && recorder.state !== 'inactive') {
            try { recorder.requestData(); } catch (_) {}
            try { recorder.stop(); } catch (_) {}
            // Stopping tracks forces MediaRecorder to flush & emit onstop reliably in Firefox/Chrome
            if (combinedStream) {
              try { combinedStream.getTracks().forEach(t => t.stop()); } catch (_) {}
            }
            stopFallbackTimer = setTimeout(completeDownload, 1500);
          } else {
            completeDownload();
          }
        };

        const renderFrame = () => {
          if (aborted || finalizing || finished) return;
          ctx.drawImage(offVideo, 0, 0, w, h);
          drawAnnotationsOnCanvas(ctx, w, h, offVideo.currentTime || 0);
          const pct = Math.min(99, Math.round(((offVideo.currentTime || 0) / (dur > 0 ? dur : 1)) * 100));
          onProgress(pct, offVideo.currentTime || 0, dur);
          if (offVideo.ended) {
            finalizeExport();
            return;
          }
          rafId = requestAnimationFrame(renderFrame);
        };

        offVideo.addEventListener('ended', finalizeExport, { once: true });

        recorder.start(250);
        offVideo.play().then(() => {
          renderFrame();
        }).catch(err => {
          cleanup();
          reject(err);
        });
      }, { once: true });
    });
  }

  // Public API
  window.VideoAnnotations = {
    init,
    loadForRecording,
    clear,
    toggleEditMode,
    toggleTimeline,
    isTimelineVisible,
    selectTool,
    addAnnotation,
    deleteAnnotation,
    selectAnnotation,
    getAnnotations: () => annotations.slice(),
    exportAnnotatedVideo,
    save: saveAnnotations,
    formatTime,
    parseTime
  };
})();
