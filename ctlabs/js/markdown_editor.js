/**
 * -----------------------------------------------------------------------------
 * File        : ctlabs/js/markdown_editor.js
 * Description : Markdown Editor, CodeMirror, Graphviz & Git Versioning for ctlabs
 * License     : MIT License
 * -----------------------------------------------------------------------------
 */

(function() {
  'use strict';

  // --- DOM Elements ---
  const mdContainer = document.getElementById('md-container');
  const mdTextarea = document.getElementById('md-textarea');
  const mdContentArea = document.getElementById('md-content-area');
  const mdPreviewPane = document.getElementById('md-preview-pane');
  const mdEditPane = document.getElementById('md-edit-pane');
  const mdSplitter = document.getElementById('md-splitter');
  const mdSaveStatus = document.getElementById('md-save-status');
  const mdTabPreview = document.getElementById('md-tab-preview');
  const mdTabEdit = document.getElementById('md-tab-edit');
  const mdTabSplit = document.getElementById('md-tab-split');
  const mdInsertImgBtn = document.getElementById('md-insert-img-btn');
  const mdImgFileInput = document.getElementById('md-img-file-input');

  const mdGraphvizBtn = document.getElementById('md-graphviz-btn');
  const mdGraphvizModal = document.getElementById('md-graphviz-modal');
  const mdGraphvizName = document.getElementById('md-graphviz-name');
  const mdGraphvizExisting = document.getElementById('md-graphviz-existing');
  const mdGraphvizEngine = document.getElementById('md-graphviz-engine');
  const mdGraphvizTemplate = document.getElementById('md-graphviz-template');
  const mdGraphvizTabSource = document.getElementById('md-graphviz-tab-source');
  const mdGraphvizTabDot = document.getElementById('md-graphviz-tab-dot');
  const mdGraphvizTabDotBadge = document.getElementById('md-graphviz-tab-dot-badge');
  const mdGraphvizBlocksBtn = document.getElementById('md-graphviz-blocks-btn');
  const mdGraphvizBlocksMenu = document.getElementById('md-graphviz-blocks-menu');
  const mdGraphvizEmojiBtn = document.getElementById('md-graphviz-emoji-btn');
  const mdGraphvizEmojiMenu = document.getElementById('md-graphviz-emoji-menu');
  const mdGraphvizEmojiSearch = document.getElementById('md-graphviz-emoji-search');
  const mdGraphvizEmojiSearchClear = document.getElementById('md-graphviz-emoji-search-clear');
  const mdGraphvizEmojiGrid = document.getElementById('md-graphviz-emoji-grid');
  const mdGraphvizEmojiFooterPreview = document.getElementById('md-graphviz-emoji-footer-preview');
  const mdGraphvizEmojiCatBtns = document.querySelectorAll('.md-gv-emoji-cat-btn');
  const mdGraphvizDotContainer = document.getElementById('md-graphviz-dot-container');
  const mdGraphvizDotOutput = document.getElementById('md-graphviz-dot-output');
  const mdGraphvizDotUseBtn = document.getElementById('md-graphviz-dot-use-btn');
  const mdGraphvizDotCopyBtn = document.getElementById('md-graphviz-dot-copy-btn');
  const mdGraphvizDotCopyText = document.getElementById('md-graphviz-dot-copy-text');
  const mdGraphvizSource = document.getElementById('md-graphviz-source');
  const mdGraphvizEditorContainer = document.getElementById('md-graphviz-editor-container');
  const mdGraphvizFontDec = document.getElementById('md-graphviz-font-dec');
  const mdGraphvizFontInc = document.getElementById('md-graphviz-font-inc');
  const mdGraphvizFontSizeLabel = document.getElementById('md-graphviz-font-size-label');
  const mdGraphvizFontFamily = document.getElementById('md-graphviz-font-family');
  const mdGraphvizWrapBtn = document.getElementById('md-graphviz-wrap-btn');
  const mdGraphvizVimBtn = document.getElementById('md-graphviz-vim-btn');
  const mdGraphvizSettingsWrapper = document.getElementById('md-graphviz-settings-wrapper');
  const mdGraphvizSettingsBtn = document.getElementById('md-graphviz-settings-btn');
  const mdGraphvizSettingsMenu = document.getElementById('md-graphviz-settings-menu');
  const mdGraphvizSettingWrapCheckbox = document.getElementById('md-graphviz-setting-wrap-checkbox');
  const mdGraphvizSettingVimCheckbox = document.getElementById('md-graphviz-setting-vim-checkbox');
  const mdGraphvizCustomBlocksContainer = document.getElementById('md-graphviz-custom-blocks-container');
  const mdGraphvizBlockModal = document.getElementById('md-graphviz-block-modal');
  const mdGraphvizBlockModalClose = document.getElementById('md-graphviz-block-modal-close');
  const mdGraphvizBlockModalTitle = document.getElementById('md-graphviz-block-modal-title');
  const mdGraphvizBlockName = document.getElementById('md-graphviz-block-name');
  const mdGraphvizBlockCode = document.getElementById('md-graphviz-block-code');
  const mdGraphvizBlockSnippet = document.getElementById('md-graphviz-block-snippet');
  const mdGraphvizBlockDesc = document.getElementById('md-graphviz-block-desc');
  const mdGraphvizBlockError = document.getElementById('md-graphviz-block-error');
  const mdGraphvizBlockCancelBtn = document.getElementById('md-graphviz-block-cancel-btn');
  const mdGraphvizBlockSaveBtn = document.getElementById('md-graphviz-block-save-btn');
  const mdGraphvizVimStatusBar = document.getElementById('md-graphviz-vim-status-bar');
  const mdGraphvizVimStatusMode = document.getElementById('md-graphviz-vim-status-mode');
  const mdGraphvizVimStatusKey = document.getElementById('md-graphviz-vim-status-key');
  const mdGraphvizBgWhite = document.getElementById('md-graphviz-bg-white');
  const mdGraphvizBgSlate = document.getElementById('md-graphviz-bg-slate');
  const mdGraphvizBgChecker = document.getElementById('md-graphviz-bg-checker');
  const mdGraphvizBgPicker = document.getElementById('md-graphviz-bg-picker');
  const mdGraphvizPreview = document.getElementById('md-graphviz-preview');
  const mdGraphvizPreviewImg = document.getElementById('md-graphviz-preview-img');
  const mdGraphvizPreviewEmpty = document.getElementById('md-graphviz-preview-empty');
  const mdGraphvizError = document.getElementById('md-graphviz-error');
  const mdGraphvizStatus = document.getElementById('md-graphviz-status');
  const mdGraphvizRenderBtn = document.getElementById('md-graphviz-render-btn');
  const mdGraphvizDownloadBtn = document.getElementById('md-graphviz-download-btn');
  const mdGraphvizDeleteBtn = document.getElementById('md-graphviz-delete-btn');
  const mdGraphvizSaveNewBtn = document.getElementById('md-graphviz-save-new-btn');
  const mdGraphvizInsertBtn = document.getElementById('md-graphviz-insert-btn');
  const mdGraphvizInsertText = document.getElementById('md-graphviz-insert-text');
  const mdGraphvizInsertIcon = document.getElementById('md-graphviz-insert-icon');
  const mdGraphvizCloseBtn = document.getElementById('md-graphviz-close-btn');
  const mdGraphvizZoomIn = document.getElementById('md-graphviz-zoom-in');
  const mdGraphvizZoomOut = document.getElementById('md-graphviz-zoom-out');
  const mdGraphvizZoomReset = document.getElementById('md-graphviz-zoom-reset');
  const mdGraphvizZoomFit = document.getElementById('md-graphviz-zoom-fit');
  const mdGraphvizSplitContainer = document.getElementById('md-graphviz-split-container');
  const mdGraphvizSplitter = document.getElementById('md-graphviz-splitter');
  const mdGraphvizSplitterGrip = document.getElementById('md-graphviz-splitter-grip');
  const mdGraphvizSourcePane = document.getElementById('md-graphviz-source-pane');
  const mdGraphvizPreviewPane = document.getElementById('md-graphviz-preview-pane');
  const mdGraphvizLayoutSide = document.getElementById('md-graphviz-layout-side');
  const mdGraphvizLayoutStack = document.getElementById('md-graphviz-layout-stack');

  const mdSaveBtn = document.getElementById('md-save-btn');
  const mdSaveBtnText = document.getElementById('md-save-btn-text');
  const mdGitCommitBtn = document.getElementById('md-git-commit-btn');
  const mdGitHistoryBtn = document.getElementById('md-git-history-btn');
  const gitHistoryBtn = document.getElementById('git-history-btn');
  const gitHistoryModal = document.getElementById('git-history-modal');
  const gitHistoryScopeBadge = document.getElementById('git-history-scope-badge');
  const gitHistoryList = document.getElementById('git-history-list');
  const gitWorkingTreeBadge = document.getElementById('git-working-tree-badge');
  const gitSnapshotMsg = document.getElementById('git-snapshot-msg');
  const gitSnapshotBtn = document.getElementById('git-snapshot-btn');
  const gitDiffTitle = document.getElementById('git-diff-title');
  const gitDiffMeta = document.getElementById('git-diff-meta');
  const gitDiffActions = document.getElementById('git-diff-actions');
  const gitDiffBody = document.getElementById('git-diff-body');
  const gitRestoreBtn = document.getElementById('git-restore-btn');
  const gitDiscardBtn = document.getElementById('git-discard-btn');

  const mdSettingsWrapper = document.getElementById('md-settings-wrapper');
  const mdSettingsBtn = document.getElementById('md-settings-btn');
  const mdSettingsMenu = document.getElementById('md-settings-menu');
  const mdSettingWrapCheckbox = document.getElementById('md-setting-wrap-checkbox');
  const mdSettingVimCheckbox = document.getElementById('md-setting-vim-checkbox');
  const mdSettingAutosaveSelect = document.getElementById('md-setting-autosave-select');

  const mdVimStatusBar = document.getElementById('md-vim-status-bar');
  const mdVimStatusMode = document.getElementById('md-vim-status-mode');
  const mdVimStatusKey = document.getElementById('md-vim-status-key');

  const mdEmojiWrapper = document.getElementById('md-emoji-wrapper');
  const mdEmojiBtn = document.getElementById('md-emoji-btn');
  const mdEmojiMenu = document.getElementById('md-emoji-menu');
  const mdEmojiSearch = document.getElementById('md-emoji-search');
  const mdEmojiSearchClear = document.getElementById('md-emoji-search-clear');
  const mdEmojiGrid = document.getElementById('md-emoji-grid');
  const mdEmojiFooterPreview = document.getElementById('md-emoji-footer-preview');
  const mdEmojiCatBtns = document.querySelectorAll('.md-emoji-cat-btn');

  // --- State Variables ---
  let mdCodeEditor = null;
  let currentMdMode = 'preview';
  let mdCache = {};
  let mdRenderTimeout = null;
  let mdIsDirty = false;
  let mdLastSavedContent = null;
  let mdAutoSaveTimer = null;
  let mdIsSaving = false;
  let mdIsLoading = false;
  let mdSaveStatusTimer = null;

  // Auto-save interval in ms (default 0 = off/manual; 2000, 5000, 15000, etc.)
  let mdAutoSaveInterval = 0;
  try {
    const savedInterval = localStorage.getItem('ctlabs_md_autosave_interval');
    if (savedInterval !== null) {
      const parsed = parseInt(savedInterval, 10);
      if (!isNaN(parsed) && parsed >= 0) {
        mdAutoSaveInterval = parsed;
      }
    }
  } catch (e) {}

  let mdWrapCode = false;
  try {
    mdWrapCode = localStorage.getItem('ctlabs_md_wrap_code') === 'true';
  } catch (e) {}

  let mdVimMode = false;
  try {
    mdVimMode = localStorage.getItem('ctlabs_md_vim_mode') === 'true';
  } catch (e) {}

  let mdSplitRatio = 50;
  try {
    const savedMdSplit = localStorage.getItem('ctlabs_md_split_ratio');
    if (savedMdSplit) {
      const parsed = parseFloat(savedMdSplit);
      if (!isNaN(parsed) && parsed >= 15 && parsed <= 85) {
        mdSplitRatio = parsed;
      }
    }
  } catch (e) {}

  // Utilities
  function escapeHtml(str) {
    if (str == null) return '';
    return String(str).replace(/[&<>"']/g, (c) => ({
      '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;'
    }[c]));
  }
  if (!window.escapeHtml) {
    window.escapeHtml = escapeHtml;
  }

  // Scope helpers
  function getActiveWalkthrough() {
    return window.activeWalkthrough || localStorage.getItem('ctlabs_active_walkthrough') || '';
  }

  function getActiveId() {
    return window.activeId || null;
  }

  function getActiveDataType() {
    return window.activeDataType || 'markdown';
  }

  function getActiveNoteTitle() {
    const id = getActiveId();
    if (!id) return '';
    const item = document.querySelector(`.rec-item[data-id="${CSS.escape(id)}"]`);
    return item ? (item.getAttribute('data-title') || id) : id;
  }

  // Helper for dropped files
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

  function stepIdFromHref(href) {
    if (!href) return null;
    const clean = href.trim();
    if (clean.startsWith('#step-')) return clean.substring(6);
    if (clean.startsWith('step://')) return clean.substring(7);
    return null;
  }

  // --- UI Updates for Settings & Vim ---
  function updateVimModeIndicator(e) {
    if (!mdVimStatusMode) return;
    let mode = e ? e.mode : null;
    let subMode = e ? e.subMode : '';
    if (!mode && mdCodeEditor && mdCodeEditor.state && mdCodeEditor.state.vim) {
      const vState = mdCodeEditor.state.vim;
      if (vState.insertMode) mode = 'insert';
      else if (vState.visualMode) mode = 'visual';
      else mode = 'normal';
    }
    if (!mode) mode = 'normal';

    if (mode === 'insert') {
      mdVimStatusMode.textContent = '-- INSERT --';
      mdVimStatusMode.style.color = '#22c55e';
    } else if (mode === 'visual') {
      if (subMode === 'linewise') {
        mdVimStatusMode.textContent = '-- VISUAL LINE --';
      } else if (subMode === 'block') {
        mdVimStatusMode.textContent = '-- VISUAL BLOCK --';
      } else {
        mdVimStatusMode.textContent = '-- VISUAL --';
      }
      mdVimStatusMode.style.color = '#f59e0b';
    } else if (mode === 'replace') {
      mdVimStatusMode.textContent = '-- REPLACE --';
      mdVimStatusMode.style.color = '#ef4444';
    } else {
      mdVimStatusMode.textContent = '-- NORMAL --';
      mdVimStatusMode.style.color = '#38bdf8';
    }
    if (mdVimStatusKey) mdVimStatusKey.textContent = '';
  }

  function updateMdSettingsBtnUI() {
    if (mdSettingsBtn) {
      const icon = mdSettingsBtn.querySelector('i');
      const isCustom = mdWrapCode || mdVimMode || (mdAutoSaveInterval !== 5000);
      if (icon) {
        icon.style.color = isCustom ? '#38bdf8' : '#94a3b8';
      }
      const hints = [];
      if (mdWrapCode) hints.push('Wrap code');
      if (mdVimMode) hints.push('Vi mode');
      if (mdAutoSaveInterval === 0) hints.push('Autosave: Off');
      else hints.push(`Autosave: ${mdAutoSaveInterval / 1000}s`);
      mdSettingsBtn.title = hints.length > 0 ? `Editor settings (${hints.join(', ')})` : 'Editor settings';
    }
  }

  function updateMdWrapCodeUI() {
    if (mdPreviewPane) {
      if (mdWrapCode) {
        mdPreviewPane.classList.add('wrap-code');
      } else {
        mdPreviewPane.classList.remove('wrap-code');
      }
    }
    if (mdSettingWrapCheckbox) {
      mdSettingWrapCheckbox.checked = mdWrapCode;
    }
    updateMdSettingsBtnUI();
  }

  function updateMdVimModeUI() {
    if (mdSettingVimCheckbox) {
      mdSettingVimCheckbox.checked = mdVimMode;
    }
    if (mdVimStatusBar) {
      mdVimStatusBar.style.display = mdVimMode ? 'flex' : 'none';
    }
    if (mdCodeEditor) {
      const currentKeyMap = mdCodeEditor.getOption('keyMap') || 'default';
      if (mdVimMode) {
        if (!currentKeyMap.startsWith('vim')) {
          mdCodeEditor.setOption('keyMap', 'vim');
          updateVimModeIndicator({ mode: 'normal' });
        }
      } else {
        if (currentKeyMap.startsWith('vim')) {
          mdCodeEditor.setOption('keyMap', 'default');
        }
      }
    }
    updateMdSettingsBtnUI();
  }

  function updateMdAutosaveUI() {
    if (mdSettingAutosaveSelect) {
      mdSettingAutosaveSelect.value = String(mdAutoSaveInterval);
    }
    updateMdSettingsBtnUI();
  }

  function updateMdSettingsUI() {
    updateMdWrapCodeUI();
    updateMdVimModeUI();
    updateMdAutosaveUI();
  }

  // --- Extended Markdown Preprocessing ---
  function preprocessExtendedMarkdown(text) {
    if (!text) return '';
    // Normalize relative images/ paths to /recordings/images/
    text = text.replace(/!\[([^\]]*)\]\((?:(?:\.?\/)?(?:recordings?\/+)+|(?:\.?\/)?)(?:images\/)([^)\s]+)(.*?)\)/g, '![$1](/recordings/images/$2$3)');

    // Equal syntax: ![alt](url =300x200), ![alt](url =300), ![alt](url =50%)
    text = text.replace(/!\[([^\]]*)\]\(([^)\s]+)\s+=(\d+(?:%|px)?)(?:x(\d+(?:%|px)?))?\)/g, (match, alt, url, w, h) => {
      const dim = h ? `${w}x${h}` : w;
      const cleanAlt = alt ? `${alt}|${dim}` : dim;
      return `![${cleanAlt}](${url})`;
    });

    // Curly attribute syntax: ![alt](url){width=300 height=200}, ![alt](url){300x200}
    text = text.replace(/!\[([^\]]*)\]\(([^)]+)\)\{([^}]+)\}/g, (match, alt, url, attrs) => {
      let w = '', h = '';
      const dimMatch = attrs.match(/(\d+(?:%|px)?)\s*x\s*(\d+(?:%|px)?)/i);
      if (dimMatch) {
        w = dimMatch[1];
        h = dimMatch[2];
      } else {
        const wMatch = attrs.match(/width\s*[:=]\s*["']?(\d+(?:%|px)?)["']?/i);
        const hMatch = attrs.match(/height\s*[:=]\s*["']?(\d+(?:%|px)?)["']?/i);
        if (wMatch) w = wMatch[1];
        if (hMatch) h = hMatch[1];
        if (!w && !h) {
          const singleDim = attrs.match(/(\d+(?:%|px)?)/);
          if (singleDim) w = singleDim[1];
        }
      }
      const dim = (w && h) ? `${w}x${h}` : (w || h);
      if (dim) {
        const cleanAlt = alt ? `${alt}|${dim}` : dim;
        return `![${cleanAlt}](${url})`;
      }
      return match;
    });

    // Emoji shortcodes replacement (:rocket: -> 🚀)
    if (typeof replaceEmojiShortcodes === 'function') {
      text = replaceEmojiShortcodes(text);
    }

    return text;
  }

  function showMdStatus(state, msg) {
    if (!mdSaveStatus) return;
    clearTimeout(mdSaveStatusTimer);
    mdSaveStatus.style.display = 'inline-flex';
    if (state === 'dirty') {
      mdSaveStatus.innerHTML = '<i class="fas fa-pencil-alt" style="color: #f59e0b; margin-right: 4px;"></i> <span style="color: #cbd5e1;">Unsaved edits...</span>';
      if (mdSaveBtn) {
        mdSaveBtn.style.borderColor = '#38bdf8';
        mdSaveBtn.style.color = '#38bdf8';
        if (mdSaveBtnText) mdSaveBtnText.textContent = 'Save *';
        mdSaveBtn.title = 'Save uncommitted edits to disk (Ctrl+S)';
      }
    } else if (state === 'saving') {
      const text = msg || 'Saving...';
      mdSaveStatus.innerHTML = `<i class="fas fa-spinner fa-spin" style="color: #38bdf8; margin-right: 4px;"></i> <span style="color: #94a3b8;">${text}</span>`;
      if (mdSaveBtn) {
        mdSaveBtn.style.borderColor = '#38bdf8';
        mdSaveBtn.style.color = '#94a3b8';
        if (mdSaveBtnText) mdSaveBtnText.textContent = 'Saving...';
      }
    } else if (state === 'saved') {
      const text = msg || 'Saved';
      mdSaveStatus.innerHTML = `<i class="fas fa-check-circle" style="color: #10b981; margin-right: 4px;"></i> <span style="color: #10b981;">${text}</span>`;
      if (mdSaveBtn) {
        mdSaveBtn.style.borderColor = '#10b981';
        mdSaveBtn.style.color = '#10b981';
        if (mdSaveBtnText) mdSaveBtnText.textContent = 'Saved';
        setTimeout(() => {
          if (!mdIsDirty && mdSaveBtn) {
            mdSaveBtn.style.borderColor = '#475569';
            mdSaveBtn.style.color = '#cbd5e1';
            if (mdSaveBtnText) mdSaveBtnText.textContent = 'Save';
            mdSaveBtn.title = 'Save note to disk (Ctrl+S)';
          }
        }, 2000);
      }
      mdSaveStatusTimer = setTimeout(() => {
        if (!mdIsDirty) mdSaveStatus.style.display = 'none';
      }, 2500);
    } else if (state === 'error') {
      const text = msg || 'Save failed';
      mdSaveStatus.innerHTML = `<i class="fas fa-exclamation-triangle" style="color: #ef4444; margin-right: 4px;"></i> <span style="color: #ef4444;">${text}</span>`;
      if (mdSaveBtn) {
        mdSaveBtn.style.borderColor = '#ef4444';
        mdSaveBtn.style.color = '#ef4444';
        if (mdSaveBtnText) mdSaveBtnText.textContent = 'Save !';
      }
    }
  }

  function onMarkdownContentChanged() {
    if (mdIsLoading) return;
    const current = mdCodeEditor ? mdCodeEditor.getValue() : (mdTextarea ? mdTextarea.value : '');
    if (mdTextarea && mdCodeEditor) {
      mdTextarea.value = current;
    }
    if (currentMdMode === 'split') {
      clearTimeout(mdRenderTimeout);
      mdRenderTimeout = setTimeout(renderMarkdownPreview, 120);
    }

    if (mdLastSavedContent !== null && current !== mdLastSavedContent) {
      mdIsDirty = true;
      showMdStatus('dirty');
      clearTimeout(mdAutoSaveTimer);
      if (mdAutoSaveInterval > 0) {
        mdAutoSaveTimer = setTimeout(() => {
          saveMarkdownContent(true);
        }, mdAutoSaveInterval);
      }
    } else if (current === mdLastSavedContent) {
      mdIsDirty = false;
      if (mdSaveStatus && !mdIsSaving) mdSaveStatus.style.display = 'none';
    }
  }

  function ensureCodeMirrorFoldHelpers() {
    if (typeof CodeMirror === 'undefined' || !CodeMirror.helpers || !CodeMirror.helpers.fold) return;
    try {
      if (CodeMirror.helpers.fold.markdown && !CodeMirror.helpers.fold.gfm) {
        if (CodeMirror.helpers.fold.combine && CodeMirror.helpers.fold.brace && CodeMirror.helpers.fold.indent) {
          CodeMirror.registerHelper('fold', 'gfm', CodeMirror.helpers.fold.combine(
            CodeMirror.helpers.fold.markdown,
            CodeMirror.helpers.fold.brace,
            CodeMirror.helpers.fold.indent
          ));
        } else {
          CodeMirror.registerHelper('fold', 'gfm', CodeMirror.helpers.fold.markdown);
        }
      }
      if (CodeMirror.helpers.fold.brace && !CodeMirror.helpers.fold.dot) {
        if (CodeMirror.helpers.fold.combine && CodeMirror.helpers.fold.comment && CodeMirror.helpers.fold.indent) {
          CodeMirror.registerHelper('fold', 'dot', CodeMirror.helpers.fold.combine(
            CodeMirror.helpers.fold.brace,
            CodeMirror.helpers.fold.comment,
            CodeMirror.helpers.fold.indent
          ));
        } else {
          CodeMirror.registerHelper('fold', 'dot', CodeMirror.helpers.fold.brace);
        }
      }
    } catch (e) {
      console.warn('Failed to configure CodeMirror fold helpers:', e);
    }
  }

  function ensureCodeMirrorVimFoldBindings() {
    if (typeof CodeMirror === 'undefined' || !CodeMirror.Vim) return;
    try {
      if (CodeMirror.Vim._foldBindingsRegistered) return;
      CodeMirror.Vim.defineAction('toggleFold', (cm) => {
        if (typeof cm.foldCode === 'function') cm.foldCode(cm.getCursor(), { scanUp: true });
      });
      CodeMirror.Vim.defineAction('fold', (cm) => {
        if (typeof cm.foldCode === 'function') cm.foldCode(cm.getCursor(), { scanUp: true }, 'fold');
      });
      CodeMirror.Vim.defineAction('unfold', (cm) => {
        if (typeof cm.foldCode === 'function') cm.foldCode(cm.getCursor(), { scanUp: false }, 'unfold');
      });
      CodeMirror.Vim.defineAction('foldAll', (cm) => {
        if (CodeMirror.commands && CodeMirror.commands.foldAll) CodeMirror.commands.foldAll(cm);
      });
      CodeMirror.Vim.defineAction('unfoldAll', (cm) => {
        if (CodeMirror.commands && CodeMirror.commands.unfoldAll) CodeMirror.commands.unfoldAll(cm);
      });

      CodeMirror.Vim.mapCommand('za', 'action', 'toggleFold');
      CodeMirror.Vim.mapCommand('zo', 'action', 'unfold');
      CodeMirror.Vim.mapCommand('zc', 'action', 'fold');
      CodeMirror.Vim.mapCommand('zM', 'action', 'foldAll');
      CodeMirror.Vim.mapCommand('zR', 'action', 'unfoldAll');

      CodeMirror.Vim.defineEx('fold', 'fold', (cm) => {
        if (typeof cm.foldCode === 'function') cm.foldCode(cm.getCursor(), { scanUp: true }, 'fold');
      });
      CodeMirror.Vim.defineEx('unfold', 'unfold', (cm) => {
        if (typeof cm.foldCode === 'function') cm.foldCode(cm.getCursor(), { scanUp: false }, 'unfold');
      });
      CodeMirror.Vim.defineEx('foldtoggle', 'za', (cm) => {
        if (typeof cm.foldCode === 'function') cm.foldCode(cm.getCursor(), { scanUp: true });
      });
      CodeMirror.Vim.defineEx('foldall', 'zM', (cm) => {
        if (CodeMirror.commands && CodeMirror.commands.foldAll) CodeMirror.commands.foldAll(cm);
      });
      CodeMirror.Vim.defineEx('unfoldall', 'zR', (cm) => {
        if (CodeMirror.commands && CodeMirror.commands.unfoldAll) CodeMirror.commands.unfoldAll(cm);
      });

      CodeMirror.Vim._foldBindingsRegistered = true;
    } catch (e) {
      console.warn('Failed to register Vim fold bindings:', e);
    }
  }

  function getMdEditor() {
    if (mdCodeEditor) return mdCodeEditor;
    if (typeof CodeMirror === 'undefined') return null;
    const ta = document.getElementById('md-textarea');
    if (!ta) return null;

    try {
      ensureCodeMirrorFoldHelpers();
      const modeConfig = {
        name: (typeof CodeMirror.overlayMode === 'function') ? 'gfm' : 'markdown',
        highlightFormatting: true,
        fencedCodeBlockHighlighting: true,
        tokenTypeOverrides: {
          header: 'header',
          code: 'comment',
          quote: 'quote',
          list1: 'variable-2',
          list2: 'variable-3',
          list3: 'keyword',
          linkText: 'link',
          linkHref: 'string url',
          em: 'em',
          strong: 'strong'
        }
      };

      mdCodeEditor = CodeMirror.fromTextArea(ta, {
        mode: modeConfig,
        theme: 'material-ocean',
        keyMap: mdVimMode ? 'vim' : 'default',
        lineNumbers: true,
        tabSize: 2,
        lineWrapping: true,
        viewportMargin: Infinity,
        gutters: ['CodeMirror-linenumbers', 'CodeMirror-foldgutter'],
        foldGutter: true,
        foldOptions: { scanUp: true },
        extraKeys: {
          'Ctrl-Q': (cm) => cm.foldCode(cm.getCursor(), { scanUp: true }),
          'Cmd-Q': (cm) => cm.foldCode(cm.getCursor(), { scanUp: true }),
          'Ctrl-S': () => saveMarkdownContent(false),
          'Cmd-S': () => saveMarkdownContent(false),
          'Ctrl-E': () => toggleMdEmojiMenu(),
          'Cmd-E': () => toggleMdEmojiMenu(),
          'Ctrl-Shift-G': () => openGraphvizModal(),
          'Cmd-Shift-G': () => openGraphvizModal(),
          'Ctrl-Shift-C': () => promptAndCommitNote(),
          'Cmd-Shift-C': () => promptAndCommitNote(),
          'Tab': (cm) => {
            if (cm.somethingSelected()) {
              cm.indentSelection('add');
            } else {
              cm.replaceSelection('  ', 'end');
            }
          }
        }
      });

      if (typeof CodeMirror !== 'undefined' && CodeMirror.Vim) {
        ensureCodeMirrorVimFoldBindings();
        CodeMirror.Vim.defineEx('write', 'w', (cm) => {
          if (cm && typeof window.mdGraphvizCodeEditor !== 'undefined' && cm === window.mdGraphvizCodeEditor) {
            if (typeof saveAndInsertGraphviz === 'function') saveAndInsertGraphviz({ saveAsNew: false, closeAfter: false });
          } else {
            saveMarkdownContent(false);
          }
        });
        CodeMirror.Vim.defineEx('wq', 'wq', (cm) => {
          if (cm && typeof window.mdGraphvizCodeEditor !== 'undefined' && cm === window.mdGraphvizCodeEditor) {
            if (typeof saveAndInsertGraphviz === 'function') saveAndInsertGraphviz({ saveAsNew: false, closeAfter: true });
          } else {
            saveMarkdownContent(false);
          }
        });
        CodeMirror.Vim.defineEx('quit', 'q', (cm) => {
          if (cm && typeof window.mdGraphvizCodeEditor !== 'undefined' && cm === window.mdGraphvizCodeEditor) {
            if (mdGraphvizModal) mdGraphvizModal.style.display = 'none';
          }
        });
      }

      mdCodeEditor.on('vim-mode-change', (arg) => {
        updateVimModeIndicator(arg);
      });

      mdCodeEditor.on('vim-keypress', (key) => {
        if (mdVimStatusKey) {
          mdVimStatusKey.textContent = key || '';
        }
      });

      mdCodeEditor.setSize('100%', '100%');
      window.cmEditors = window.cmEditors || {};
      window.cmEditors['md-textarea'] = mdCodeEditor;

      mdCodeEditor.on('change', () => {
        onMarkdownContentChanged();
      });

      mdCodeEditor.on('paste', (cm, e) => {
        const clipboard = e.clipboardData || window.clipboardData;
        if (!clipboard || !clipboard.items) return;
        for (let i = 0; i < clipboard.items.length; i++) {
          const item = clipboard.items[i];
          if (item.kind === 'file' && item.type.startsWith('image/')) {
            e.preventDefault();
            if (typeof e.stopPropagation === 'function') e.stopPropagation();
            const file = item.getAsFile();
            if (file) uploadAndInsertImage(file, cm.getCursor());
            break;
          }
        }
      });

      mdCodeEditor.on('dragover', (cm, e) => {
        if (window.draggedItem) return;
        e.preventDefault();
        if (e.dataTransfer) e.dataTransfer.dropEffect = 'copy';
        const pos = cm.coordsChar({ left: e.clientX, top: e.clientY }, 'window');
        if (pos) {
          cm.setCursor(pos);
        }
      });

      mdCodeEditor.on('drop', (cm, e) => {
        if (window.draggedItem) return;
        e.preventDefault();
        if (typeof e.stopPropagation === 'function') e.stopPropagation();
        e._ctlabsHandled = true;

        const files = getDroppedFiles(e.dataTransfer);
        if (files.length === 0) return;

        const isSingleImg = files.length === 1 && (
          (files[0].type && files[0].type.startsWith('image/')) ||
          (/\.(png|jpe?g|gif|svg|webp)$/i.test(files[0].name || ''))
        );

        if (isSingleImg) {
          const dropPos = cm.coordsChar({ left: e.clientX, top: e.clientY }, 'window');
          if (dropPos) cm.setCursor(dropPos);
          uploadAndInsertImage(files[0], dropPos || cm.getCursor());
        } else if (typeof window.uploadImportFiles === 'function') {
          window.uploadImportFiles(files);
        }
      });

      if (window.ResizeObserver && mdEditPane) {
        try {
          const mdResizeObserver = new ResizeObserver(() => {
            if (mdCodeEditor && mdEditPane && mdEditPane.style.display !== 'none' && mdEditPane.offsetWidth > 0) {
              mdCodeEditor.refresh();
            }
          });
          mdResizeObserver.observe(mdEditPane);
        } catch (e) {}
      }

      mdCodeEditor.on('focus', (cm) => {
        cm.refresh();
      });

      return mdCodeEditor;
    } catch (err) {
      console.error('Failed to initialize CodeMirror editor:', err);
      return null;
    }
  }

  // Marked renderer configuration
  if (typeof marked !== 'undefined') {
    marked.setOptions({
      gfm: true,
      breaks: true
    });

    marked.use({
      renderer: {
        image(arg0, arg1, arg2) {
          let href = '', title = '', text = '';
          if (typeof arg0 === 'object' && arg0 !== null) {
            href = arg0.href || '';
            title = arg0.title || '';
            text = arg0.text || '';
          } else {
            href = arg0 || '';
            title = arg1 || '';
            text = arg2 || '';
          }

          if (href) {
            href = href.replace(/^(?:(?:\.?\/)?(?:recordings?\/+)+|(?:\.?\/)?)images\//, '/recordings/images/');
          }

          let width = '';
          let height = '';
          let cleanAlt = text;

          // Support Obsidian pipe syntax: alt|300x200, 300x200, alt|50%, alt|300
          const pipeMatch = text.match(/^(.*?)(?:\|(.*))$/);
          let dimCandidate = '';
          if (pipeMatch) {
            cleanAlt = pipeMatch[1].trim();
            dimCandidate = pipeMatch[2].trim();
          } else if (/^\d+(?:%|px)?(?:\s*x\s*\d+(?:%|px)?)?$/i.test(text.trim())) {
            cleanAlt = '';
            dimCandidate = text.trim();
          }

          if (dimCandidate) {
            const xMatch = dimCandidate.match(/^(\d+(?:%|px)?)\s*x\s*(\d+(?:%|px)?)$/i);
            if (xMatch) {
              width = xMatch[1];
              height = xMatch[2];
            } else {
              width = dimCandidate;
            }
          }

          let style = [];
          if (width) {
            const wVal = /^\d+$/.test(width) ? `${width}px` : width;
            style.push(`width: ${wVal}`);
          }
          if (height) {
            const hVal = /^\d+$/.test(height) ? `${height}px` : height;
            style.push(`height: ${hVal}`);
          }
          style.push('max-width: 100%');

          const styleAttr = style.length ? ` style="${style.join('; ')};"` : '';
          const widthAttr = width && /^\d+$/.test(width) ? ` width="${width}"` : '';
          const heightAttr = height && /^\d+$/.test(height) ? ` height="${height}"` : '';
          const titleAttr = title ? ` title="${title}"` : '';

          return `<img src="${href}" alt="${cleanAlt}"${titleAttr}${widthAttr}${heightAttr}${styleAttr} />`;
        }
      }
    });
  }

  // --- Split Resizing ---
  function applyMdSplitSizes() {
    if (currentMdMode !== 'split') return;
    if (!mdEditPane || !mdPreviewPane) return;
    mdEditPane.style.flex = `0 0 ${mdSplitRatio}%`;
    mdEditPane.style.maxWidth = `${mdSplitRatio}%`;
    mdEditPane.style.width = `${mdSplitRatio}%`;
    mdPreviewPane.style.flex = '1 1 0%';
    mdPreviewPane.style.minWidth = '0';
    mdPreviewPane.style.maxWidth = '';
    mdPreviewPane.style.width = '';
    const cm = getMdEditor();
    if (cm) cm.refresh();
  }

  let isResizingMdSplit = false;
  let mdSplitRaf = null;

  if (mdSplitter) {
    mdSplitter.addEventListener('pointerdown', (e) => {
      if (e.button !== 0) return;
      if (currentMdMode !== 'split') return;
      isResizingMdSplit = true;
      mdSplitter.classList.add('dragging');
      document.body.style.userSelect = 'none';
      document.body.style.cursor = 'col-resize';
      if (mdSplitter.setPointerCapture) {
        try { mdSplitter.setPointerCapture(e.pointerId); } catch (err) {}
      }
      e.preventDefault();
    });

    mdSplitter.addEventListener('pointermove', (e) => {
      if (!isResizingMdSplit || !mdContentArea) return;
      const rect = mdContentArea.getBoundingClientRect();
      if (rect.width <= 0) return;
      const offsetX = e.clientX - rect.left;
      let pct = (offsetX / rect.width) * 100;
      const minPx = 150;
      const minPct = (minPx / rect.width) * 100;
      const clampedMin = Math.max(15, minPct);
      const clampedMax = Math.min(85, 100 - minPct);
      pct = Math.max(clampedMin, Math.min(clampedMax, pct));
      mdSplitRatio = Math.round(pct * 10) / 10;
      applyMdSplitSizes();

      if (!mdSplitRaf) {
        mdSplitRaf = requestAnimationFrame(() => {
          mdSplitRaf = null;
          const cm = getMdEditor();
          if (cm) cm.refresh();
        });
      }
    });

    const stopMdSplitResize = (e) => {
      if (!isResizingMdSplit) return;
      isResizingMdSplit = false;
      mdSplitter.classList.remove('dragging');
      document.body.style.userSelect = '';
      document.body.style.cursor = '';
      if (e && mdSplitter.releasePointerCapture && e.pointerId !== undefined) {
        try { mdSplitter.releasePointerCapture(e.pointerId); } catch (err) {}
      }
      try {
        localStorage.setItem('ctlabs_md_split_ratio', mdSplitRatio);
      } catch (err) {}
      const cm = getMdEditor();
      if (cm) {
        cm.refresh();
        cm.focus();
      }
    };

    mdSplitter.addEventListener('pointerup', stopMdSplitResize);
    mdSplitter.addEventListener('pointercancel', stopMdSplitResize);

    mdSplitter.addEventListener('dblclick', (e) => {
      e.preventDefault();
      mdSplitRatio = 50;
      applyMdSplitSizes();
      try {
        localStorage.setItem('ctlabs_md_split_ratio', '50');
      } catch (err) {}
    });
  }

  // --- Mode Switching ---
  function setMdMode(mode) {
    currentMdMode = mode;
    [mdTabPreview, mdTabEdit, mdTabSplit].forEach(tab => {
      if (!tab) return;
      tab.classList.remove('active');
      tab.style.background = '#1e293b';
      tab.style.color = '#94a3b8';
      tab.style.borderColor = '#475569';
    });

    const activeTab = (mode === 'preview') ? mdTabPreview : (mode === 'edit' ? mdTabEdit : mdTabSplit);
    if (activeTab) {
      activeTab.classList.add('active');
      activeTab.style.background = '#0284c7';
      activeTab.style.color = '#ffffff';
      activeTab.style.borderColor = '#38bdf8';
    }

    // Emoji, diagram, commit, history, and settings buttons are visible in edit or split mode
    if (mdEmojiWrapper) {
      mdEmojiWrapper.style.display = (mode === 'preview') ? 'none' : 'flex';
      if (mode === 'preview') toggleMdEmojiMenu(false);
    }
    if (mdGraphvizBtn) {
      mdGraphvizBtn.style.display = (mode === 'preview') ? 'none' : 'inline-flex';
    }
    if (mdSaveBtn) {
      mdSaveBtn.style.display = (mode === 'preview') ? 'none' : 'inline-flex';
    }
    if (mdGitCommitBtn) {
      mdGitCommitBtn.style.display = (mode === 'preview') ? 'none' : 'inline-flex';
    }
    if (mdGitHistoryBtn) {
      mdGitHistoryBtn.style.display = (mode === 'preview') ? 'none' : 'inline-flex';
    }
    if (mdSettingsWrapper) {
      mdSettingsWrapper.style.display = (mode === 'preview') ? 'none' : 'inline-block';
      if (mode === 'preview' && mdSettingsMenu) {
        mdSettingsMenu.style.display = 'none';
        if (mdSettingsBtn) {
          mdSettingsBtn.style.background = '#1e293b';
          mdSettingsBtn.style.borderColor = '#475569';
        }
      }
    }

    const cm = getMdEditor();
    if (cm && mdTextarea) {
      mdTextarea.value = cm.getValue();
    }

    // If there are unsaved edits, trigger autosave on mode switch
    if (mdIsDirty && mdAutoSaveInterval > 0) {
      saveMarkdownContent(true);
    }

    if (mode === 'preview') {
      if (mdSplitter) mdSplitter.style.display = 'none';
      if (mdEditPane) {
        mdEditPane.style.display = 'none';
        mdEditPane.style.flex = '1';
        mdEditPane.style.maxWidth = '';
        mdEditPane.style.width = '';
      }
      if (mdPreviewPane) {
        mdPreviewPane.style.display = 'block';
        mdPreviewPane.style.flex = '1';
        mdPreviewPane.style.maxWidth = '';
        mdPreviewPane.style.width = '';
      }
      renderMarkdownPreview();
    } else if (mode === 'edit') {
      if (mdSplitter) mdSplitter.style.display = 'none';
      if (mdEditPane) {
        mdEditPane.style.display = 'flex';
        mdEditPane.style.flex = '1';
        mdEditPane.style.maxWidth = '';
        mdEditPane.style.width = '';
        mdEditPane.style.borderRight = 'none';
      }
      if (mdPreviewPane) mdPreviewPane.style.display = 'none';
      if (cm) {
        setTimeout(() => { cm.refresh(); cm.focus(); }, 40);
      } else if (mdTextarea) {
        mdTextarea.focus();
      }
    } else if (mode === 'split') {
      if (mdEditPane) {
        mdEditPane.style.display = 'flex';
        mdEditPane.style.borderRight = 'none';
      }
      if (mdSplitter) mdSplitter.style.display = 'flex';
      if (mdPreviewPane) {
        mdPreviewPane.style.display = 'block';
      }
      applyMdSplitSizes();
      renderMarkdownPreview();
      if (cm) {
        setTimeout(() => { cm.refresh(); cm.focus(); }, 40);
      }
    }
  }

  function renderMarkdownPreview() {
    if (!mdPreviewPane) return;
    const raw = (mdCodeEditor ? mdCodeEditor.getValue() : (mdTextarea ? mdTextarea.value : '')) || '';
    if (typeof marked !== 'undefined') {
      const preprocessed = preprocessExtendedMarkdown(raw);
      mdPreviewPane.innerHTML = marked.parse(preprocessed);
      if (typeof hljs !== 'undefined') {
        mdPreviewPane.querySelectorAll('pre code').forEach(block => {
          try { hljs.highlightElement(block); } catch (e) {}
        });
      }

      mdPreviewPane.querySelectorAll('img').forEach(img => {
        const link = img.closest('a');
        if (link && stepIdFromHref(link.getAttribute('href'))) {
          img.title = img.title || 'Click to open step';
          img.style.cursor = 'pointer';
          return;
        }
        img.title = img.title || 'Click to enlarge';
        img.addEventListener('click', (e) => {
          e.stopPropagation();
          if (typeof window.openImageModal === 'function') {
            window.openImageModal(img.src, img.alt, img.title);
          }
        });
      });
      updateMdWrapCodeUI();
    } else {
      mdPreviewPane.textContent = raw;
    }
  }

  // --- Load and Save Note Content ---
  function loadMarkdownContent(id) {
    clearTimeout(mdAutoSaveTimer);
    mdIsDirty = false;
    mdIsLoading = true;
    if (mdSaveStatus) mdSaveStatus.style.display = 'none';

    if (mdCache[id] !== undefined) {
      const cached = mdCache[id];
      mdLastSavedContent = cached;
      if (mdTextarea) mdTextarea.value = cached;
      if (mdCodeEditor) {
        mdCodeEditor.setValue(cached);
        mdCodeEditor.clearHistory();
      }
      renderMarkdownPreview();
      mdIsLoading = false;
      return;
    }

    if (mdTextarea) mdTextarea.value = '';
    if (mdCodeEditor) {
      mdCodeEditor.setValue('');
      mdCodeEditor.clearHistory();
    }
    if (mdPreviewPane) mdPreviewPane.innerHTML = '<div style="color: #94a3b8;"><i class="fas fa-spinner fa-spin"></i> Loading note...</div>';

    fetch('/recordings/' + encodeURIComponent(id) + '/content', { credentials: 'same-origin' })
      .then(res => {
        if (!res.ok) throw new Error('Status ' + res.status);
        return res.text();
      })
      .then(content => {
        mdCache[id] = content;
        if (getActiveId() === id) {
          if (mdTextarea) mdTextarea.value = content;
          if (mdCodeEditor) {
            mdCodeEditor.setValue(content);
            mdCodeEditor.clearHistory();
          }
          mdLastSavedContent = content;
          mdIsDirty = false;
          renderMarkdownPreview();
        }
        mdIsLoading = false;
      })
      .catch(err => {
        console.error('Failed to load markdown content:', err);
        mdIsLoading = false;
        if (getActiveId() === id && mdPreviewPane) {
          mdPreviewPane.innerHTML = '<div style="color: #ef4444;"><i class="fas fa-exclamation-triangle"></i> Failed to load note content.</div>';
        }
      });
  }

  // Saves markdown content directly to disk without creating git commits unless commit: true is specified
  function saveMarkdownContent(isAutosave = false, commit = false, commitMessage = null) {
    const activeId = getActiveId();
    const activeDataType = getActiveDataType();
    if (!activeId || activeDataType !== 'markdown') return;
    if (mdIsSaving || mdIsLoading) return;

    const content = mdCodeEditor ? mdCodeEditor.getValue() : (mdTextarea ? mdTextarea.value : '');
    if (content === undefined || content === null || content === 'Loading...') return;

    if (!mdIsDirty && mdLastSavedContent === content && !commit) {
      if (!isAutosave) showMdStatus('saved', 'Saved');
      return;
    }

    clearTimeout(mdAutoSaveTimer);
    mdIsSaving = true;
    showMdStatus('saving', isAutosave ? 'Autosaving...' : (commit ? 'Committing...' : 'Saving...'));

    mdCache[activeId] = content;
    if (mdTextarea) mdTextarea.value = content;

    const payload = { content: content };
    if (commit) {
      payload.commit = true;
      if (commitMessage) payload.message = commitMessage;
    }

    fetch('/recordings/' + encodeURIComponent(activeId) + '/content', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(payload),
      credentials: 'same-origin'
    })
    .then(res => res.json())
    .then(data => {
      mdIsSaving = false;
      if (data.ok) {
        mdLastSavedContent = content;
        mdIsDirty = false;
        showMdStatus('saved', isAutosave ? 'Autosaved' : (commit ? 'Committed' : 'Saved'));

        if (data.title) {
          const activeBtn = document.querySelector(`.rec-item[data-id="${CSS.escape(activeId)}"]`);
          if (activeBtn) {
            activeBtn.setAttribute('data-title', data.title);
            const titleSpan = activeBtn.querySelector('.item-title');
            if (titleSpan) titleSpan.textContent = data.title;
            const step = activeBtn.getAttribute('data-step');
            const titleEl = document.getElementById('rec-title');
            if (titleEl) {
              const span = titleEl.querySelector('span');
              if (span) span.textContent = (step ? '#' + step + ': ' : '') + data.title;
            }
            const editTitle = document.getElementById('edit-title');
            if (editTitle) editTitle.value = data.title;
          }
        }
      } else {
        showMdStatus('error', 'Save failed');
        if (!isAutosave) {
          alert('Failed to save note: ' + (data.error || 'Unknown error'));
        }
      }
    })
    .catch(err => {
      mdIsSaving = false;
      console.error('Save error:', err);
      showMdStatus('error', 'Save error');
      if (!isAutosave) {
        alert('Failed to save note content.');
      }
    });
  }

  // --- Insertion Helpers ---
  function insertMarkdownBlock(snippet, targetPos = null, caretOffset = null) {
    const offset = (caretOffset === null || caretOffset === undefined) ? snippet.length : caretOffset;
    const cm = getMdEditor();

    if (cm) {
      const doc = cm.getDoc();
      const cursor = targetPos || doc.getCursor();
      const cmVal = cm.getValue();
      const cmIndex = cm.indexFromPos(cursor);
      const before = cmVal.substring(0, cmIndex);
      const after = cmVal.substring(cmIndex);
      const prefix = (before.length > 0 && !before.endsWith('\n')) ? '\n\n' : (before.endsWith('\n') && !before.endsWith('\n\n') ? '\n' : '');
      const suffix = (!after.startsWith('\n')) ? '\n\n' : (after.startsWith('\n') && !after.startsWith('\n\n') ? '\n' : '');
      const block = `${prefix}${snippet}${suffix}`;

      doc.replaceRange(block, cursor);
      const newPos = cm.posFromIndex(cmIndex + prefix.length + offset);
      cm.setCursor(newPos);
      if (!mdGraphvizModal || mdGraphvizModal.style.display !== 'block') {
        if (typeof cm.focus === 'function') cm.focus();
      }
      if (mdTextarea) mdTextarea.value = cm.getValue();
    } else if (mdTextarea) {
      const start = (targetPos && typeof targetPos.index === 'number') ? targetPos.index : (mdTextarea.selectionStart !== undefined ? mdTextarea.selectionStart : mdTextarea.value.length);
      const end = (targetPos && typeof targetPos.index === 'number') ? targetPos.index : (mdTextarea.selectionEnd !== undefined ? mdTextarea.selectionEnd : mdTextarea.value.length);
      const before = mdTextarea.value.substring(0, start);
      const after = mdTextarea.value.substring(end);
      const prefix = (before.length > 0 && !before.endsWith('\n')) ? '\n\n' : (before.endsWith('\n') && !before.endsWith('\n\n') ? '\n' : '');
      const suffix = (!after.startsWith('\n')) ? '\n\n' : (after.startsWith('\n') && !after.startsWith('\n\n') ? '\n' : '');
      const block = `${prefix}${snippet}${suffix}`;

      mdTextarea.value = before + block + after;
      const newPos = start + prefix.length + offset;
      mdTextarea.selectionStart = mdTextarea.selectionEnd = newPos;
      if (!mdGraphvizModal || mdGraphvizModal.style.display !== 'block') {
        if (typeof mdTextarea.focus === 'function') mdTextarea.focus();
      }
    }

    onMarkdownContentChanged();
    saveMarkdownContent(false);
  }

  function uploadAndInsertImage(file, targetPos = null) {
    if (!file) return;
    const isImg = (file.type && file.type.startsWith('image/')) ||
                  (/\.(png|jpe?g|gif|svg|webp)$/i.test(file.name || ''));
    if (!isImg) {
      alert('Please select an image file (PNG, JPG, GIF, SVG, WebP).');
      return;
    }

    if (currentMdMode === 'preview') {
      setMdMode('split');
    }

    if (mdSaveStatus) {
      mdSaveStatus.innerHTML = '<i class="fas fa-spinner fa-spin" style="color: #38bdf8;"></i> Uploading picture...';
      mdSaveStatus.style.display = 'inline-flex';
    }

    const formData = new FormData();
    formData.append('image', file);
    formData.append('walkthrough', getActiveWalkthrough());

    fetch('/recordings/upload-image', {
      method: 'POST',
      body: formData,
      credentials: 'same-origin'
    })
    .then(res => res.json())
    .then(data => {
      if (data.ok && data.url) {
        const rawName = (file.name || 'Picture').replace(/\.[^/.]+$/, '').replace(/[^a-zA-Z0-9_-]/g, ' ').trim();
        const altText = rawName || 'Picture';
        const cm = getMdEditor();
        insertMarkdownBlock(`![${altText}](${data.url})`, cm ? cm.getCursor() : targetPos);
      } else {
        alert('Failed to upload picture: ' + (data.error || 'Unknown error'));
        if (mdSaveStatus) mdSaveStatus.style.display = 'none';
      }
    })
    .catch(err => {
      console.error('Picture upload error:', err);
      alert('Failed to upload picture: ' + err.message);
      if (mdSaveStatus) mdSaveStatus.style.display = 'none';
    });
  }

  // --- Unified Curated Emoji Dictionary (loaded from /recordings/emojis) ---
  let ctlabsEmojiList = [];
  let ctlabsEmojiMap = {};
  let ctlabsEmojisLoadingPromise = null;

  async function loadCtlabsEmojis() {
    if (ctlabsEmojiList.length > 0) return ctlabsEmojiList;
    if (ctlabsEmojisLoadingPromise) return ctlabsEmojisLoadingPromise;

    ctlabsEmojisLoadingPromise = (async () => {
      try {
        const res = await fetch('/recordings/emojis');
        if (res.ok) {
          const data = await res.json();
          if (Array.isArray(data)) {
            ctlabsEmojiList = data;
            ctlabsEmojiMap = {};
            data.forEach(item => {
              if (item.code && item.char) {
                ctlabsEmojiMap[item.code] = item.char;
                ctlabsEmojiMap[item.code.toLowerCase()] = item.char;
              }
            });
            window.CTLABS_EMOJI_LIST = ctlabsEmojiList;
            window.CTLABS_EMOJI_MAP = ctlabsEmojiMap;
            window.GITHUB_EMOJI_LIST = ctlabsEmojiList;
            window.GITHUB_EMOJI_MAP = ctlabsEmojiMap;
            window.MARKDOWN_EMOJI_LIST = ctlabsEmojiList;
          }
        }
      } catch (e) {
        console.warn('Failed to load emojis:', e);
      }
      return ctlabsEmojiList;
    })();

    return ctlabsEmojisLoadingPromise;
  }
  // Eagerly fetch emojis in background
  loadCtlabsEmojis();

  function getEmojiMap() {
    if (ctlabsEmojiMap && Object.keys(ctlabsEmojiMap).length > 0) return ctlabsEmojiMap;
    if (typeof window !== 'undefined' && window.GITHUB_EMOJI_MAP) return window.GITHUB_EMOJI_MAP;
    return ctlabsEmojiMap || {};
  }

  function getEmojiList() {
    if (ctlabsEmojiList && ctlabsEmojiList.length > 0) return ctlabsEmojiList;
    if (typeof window !== 'undefined' && Array.isArray(window.GITHUB_EMOJI_LIST) && window.GITHUB_EMOJI_LIST.length > 0) {
      return window.GITHUB_EMOJI_LIST;
    }
    return ctlabsEmojiList || [];
  }

  function replaceEmojiShortcodes(text) {
    if (!text) return text;
    const map = getEmojiMap();
    const codeBlocks = [];
    let cbIdx = 0;
    // Protect fenced code blocks (```...```) and inline code (`...`)
    let processed = text.replace(/(```[\s\S]*?```)/g, (m) => {
      const ph = `__MD_EMOJI_CB_${cbIdx++}__`;
      codeBlocks.push({ ph, val: m });
      return ph;
    });
    processed = processed.replace(/(`[^`\n]+`)/g, (m) => {
      const ph = `__MD_EMOJI_CB_${cbIdx++}__`;
      codeBlocks.push({ ph, val: m });
      return ph;
    });
    // Replace :code: with emoji char if known
    processed = processed.replace(/:([a-zA-Z0-9_+-]+):/g, (match, code) => {
      const lower = code.toLowerCase();
      return map[code] || map[lower] || match;
    });
    // Restore code blocks
    for (let i = codeBlocks.length - 1; i >= 0; i--) {
      processed = processed.replace(codeBlocks[i].ph, codeBlocks[i].val);
    }
    return processed;
  }

  // --- Emoji Picker ---
  async function toggleMdEmojiMenu(open) {
    if (!mdEmojiMenu) return;
    const isClosed = !mdEmojiMenu.style.display || mdEmojiMenu.style.display === 'none';
    const shouldOpen = (open !== undefined) ? open : isClosed;
    mdEmojiMenu.style.display = shouldOpen ? 'flex' : 'none';
    if (shouldOpen) {
      if (ctlabsEmojiList.length === 0) {
        await loadCtlabsEmojis();
      }
      if (mdEmojiSearch) {
        mdEmojiSearch.value = '';
        mdEmojiSearch.focus();
      }
      renderEmojiGrid('all', '');
    }
  }

  function renderEmojiGrid(cat = 'all', query = '') {
    const list = getEmojiList();
    if (!mdEmojiGrid || !list) return;
    const cleanQuery = query.trim().toLowerCase();
    const filtered = list.filter(item => {
      if (cat !== 'all') {
        if (cat === 'github') {
          if (item.cat !== 'github' && item.cat !== 'popular') return false;
        } else if (item.cat !== cat) {
          return false;
        }
      }
      if (cleanQuery) {
        return item.code.toLowerCase().includes(cleanQuery) || item.name.toLowerCase().includes(cleanQuery);
      }
      return true;
    });

    if (filtered.length === 0) {
      mdEmojiGrid.innerHTML = '<div style="grid-column: 1 / -1; padding: 16px; text-align: center; color: #94a3b8; font-size: 0.8em;">No matching emojis</div>';
      return;
    }

    // Limit initial unsearched rendering for smooth DOM performance if viewing all
    const displayItems = cleanQuery ? filtered : filtered.slice(0, 320);

    mdEmojiGrid.innerHTML = displayItems.map(item => {
      const visual = item.img
        ? `<img src="${item.img}" width="22" height="22" alt=":${item.code}:" style="pointer-events: none; border-radius: 2px; vertical-align: middle;">`
        : (item.char || '');
      return `<button type="button" class="md-emoji-cell" data-code="${item.code}" data-char="${item.char || ''}" data-img="${item.img || ''}" data-name="${item.name}" title=":${item.code}: (${item.name})" style="display: flex; align-items: center; justify-content: center; width: 34px; height: 34px; font-size: 1.25em; border: none; background: transparent; border-radius: 4px; cursor: pointer; transition: background 0.1s, transform 0.1s;" onmouseover="this.style.background='#1e293b'; this.style.transform='scale(1.15)';" onmouseout="this.style.background='transparent'; this.style.transform='none';">${visual}</button>`;
    }).join('');

    mdEmojiGrid.querySelectorAll('.md-emoji-cell').forEach(cell => {
      cell.addEventListener('mouseenter', () => {
        if (mdEmojiFooterPreview) {
          mdEmojiFooterPreview.textContent = `:${cell.getAttribute('data-code')}: — ${cell.getAttribute('data-name')}`;
        }
      });
      const handleInsert = (e, forceCode) => {
        e.preventDefault();
        e.stopPropagation();
        const code = cell.getAttribute('data-code');
        const ch = cell.getAttribute('data-char');
        // Left-click inserts character (or :code: if custom image/no char). Right-click inserts :code:.
        const snippet = (forceCode || !ch) ? `:${code}:` : ch;

        if (currentMdMode === 'preview') setMdMode('split');
        const cm = getMdEditor();
        if (cm) {
          cm.replaceSelection(snippet, 'end');
          cm.focus();
        } else if (mdTextarea) {
          const start = mdTextarea.selectionStart;
          const end = mdTextarea.selectionEnd;
          mdTextarea.value = mdTextarea.value.substring(0, start) + snippet + mdTextarea.value.substring(end);
          mdTextarea.selectionStart = mdTextarea.selectionEnd = start + snippet.length;
          mdTextarea.focus();
        }
        onMarkdownContentChanged();
        toggleMdEmojiMenu(false);
      };

      cell.addEventListener('click', (e) => handleInsert(e, false));
      cell.addEventListener('contextmenu', (e) => handleInsert(e, true));
    });
  }

  function setupEmojiPicker() {
    if (mdEmojiBtn) {
      mdEmojiBtn.addEventListener('click', (e) => {
        e.stopPropagation();
        toggleMdEmojiMenu();
      });
    }

    if (mdEmojiSearch) {
      mdEmojiSearch.addEventListener('input', () => {
        const val = mdEmojiSearch.value;
        if (mdEmojiSearchClear) mdEmojiSearchClear.style.display = val ? 'inline-block' : 'none';
        const activeTab = document.querySelector('.md-emoji-cat-btn.active');
        const cat = activeTab ? activeTab.getAttribute('data-cat') : 'all';
        renderEmojiGrid(cat, val);
      });
    }

    if (mdEmojiSearchClear) {
      mdEmojiSearchClear.addEventListener('click', () => {
        if (mdEmojiSearch) {
          mdEmojiSearch.value = '';
          mdEmojiSearch.focus();
        }
        mdEmojiSearchClear.style.display = 'none';
        const activeTab = document.querySelector('.md-emoji-cat-btn.active');
        const cat = activeTab ? activeTab.getAttribute('data-cat') : 'all';
        renderEmojiGrid(cat, '');
      });
    }

    mdEmojiCatBtns.forEach(btn => {
      btn.addEventListener('click', () => {
        mdEmojiCatBtns.forEach(b => {
          b.classList.remove('active');
          b.style.background = 'transparent';
          b.style.color = '#94a3b8';
        });
        btn.classList.add('active');
        btn.style.background = '#0284c7';
        btn.style.color = '#fff';
        const cat = btn.getAttribute('data-cat') || 'all';
        const query = mdEmojiSearch ? mdEmojiSearch.value : '';
        renderEmojiGrid(cat, query);
      });
    });

    document.addEventListener('click', (e) => {
      if (mdEmojiMenu && mdEmojiMenu.style.display !== 'none') {
        if (!mdEmojiMenu.contains(e.target) && e.target !== mdEmojiBtn && !mdEmojiBtn.contains(e.target)) {
          toggleMdEmojiMenu(false);
        }
      }
    });
  }

  // --- Graphviz Diagram Editor ---
  let mdGraphvizCodeEditor = null;
  let mdGraphvizFontSize = 13;
  let mdGraphvizFont = 'courier';
  let mdGraphvizBg = 'white';
  let mdGraphvizLineWrap = false;
  let mdGraphvizVimMode = false;
  let mdGraphvizPreviewUrl = null;
  let mdGraphvizCurrentSvg = '';
  let mdGraphvizScale = 1;
  let mdGraphvizPanX = 0;
  let mdGraphvizPanY = 0;
  let mdGraphvizDragging = false;
  let mdGraphvizDragStart = null;
  let mdGraphvizPendingFit = true;
  let mdGraphvizDebounceTimer = null;
  let mdGraphvizRenderSeq = 0;
  let cachedDiagramBases = new Set();

  const GRAPHVIZ_FONTS = {
    courier: "'Courier New', Courier, monospace",
    mono: "ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace",
    consolas: "Consolas, 'Liberation Mono', Menlo, Courier, monospace",
    fira: "'Fira Code', 'JetBrains Mono', Consolas, monospace"
  };

  try {
    const savedSize = parseInt(localStorage.getItem('ctlabs_graphviz_font_size'), 10);
    if (!isNaN(savedSize) && savedSize >= 10 && savedSize <= 26) mdGraphvizFontSize = savedSize;
    const savedFont = localStorage.getItem('ctlabs_graphviz_font_family');
    if (savedFont && GRAPHVIZ_FONTS[savedFont]) mdGraphvizFont = savedFont;
    const savedBg = localStorage.getItem('ctlabs_graphviz_bg');
    if (savedBg) mdGraphvizBg = savedBg;
    const savedWrap = localStorage.getItem('ctlabs_graphviz_line_wrap');
    if (savedWrap !== null) mdGraphvizLineWrap = savedWrap === 'true';
    const savedVim = localStorage.getItem('ctlabs_graphviz_vim_mode');
    if (savedVim !== null) {
      mdGraphvizVimMode = savedVim === 'true';
    } else {
      mdGraphvizVimMode = localStorage.getItem('ctlabs_md_vim_mode') === 'true';
    }
  } catch (e) {}

  let mdGraphvizLayout = 'side';
  try {
    mdGraphvizLayout = localStorage.getItem('ctlabs_graphviz_layout') || 'side';
  } catch (e) {}

  let mdGraphvizSplitCol = 50;
  let mdGraphvizSplitRow = 50;
  try {
    const savedCol = parseFloat(localStorage.getItem('ctlabs_graphviz_split_col'));
    if (!isNaN(savedCol) && savedCol >= 15 && savedCol <= 85) mdGraphvizSplitCol = savedCol;
    const savedRow = parseFloat(localStorage.getItem('ctlabs_graphviz_split_row'));
    if (!isNaN(savedRow) && savedRow >= 15 && savedRow <= 85) mdGraphvizSplitRow = savedRow;
  } catch (e) {}

  let mdGraphvizActiveTab = 'source';
  let mdGraphvizLastDot = '';

  const MD_GRAPHVIZ_DEFAULT = `digraph G {
  <%= graph_header("My Diagram", rankdir: "LR") %>

  <%= host("h1", name: "Host 1", ip: "192.168.1.10") %>
  <%= host("h2", name: "Host 2", ip: "192.168.1.11") %>
  <%= link("h1", "h2", label: "sync") %>
}`;

  const MD_GRAPHVIZ_SNIPPETS = {
    stack_vertical: `// Force vertical stack order (top to bottom)
node_top -> node_bottom [style=invis, minlen=2];`,
    same_rank: `{ rank=same; node_a; node_b; }`,
    rank_source: `{ rank=source; ingress_node; }`,
    rank_sink: `{ rank=sink; egress_node; }`,
    spacer_node: `spacer_1 [style=invis, shape=point, width=0.1, label=""];`,
    invis_edge: `node_a -> node_b [style=invis, minlen=2];`,
    cluster_stack: `// Order subgraphs vertically
cluster_a_anchor -> cluster_b_anchor [style=invis, minlen=2];`,
    layout_tb: `rankdir="TB";`,
    layout_lr: `rankdir="LR";`,
    host: '<%= host("web1", name: "Web Server", ip: "192.168.1.10") %>',
    router: '<%= router("rtr1", name: "Core Router", ip: "10.0.0.1") %>',
    switch: '<%= switch("sw1", name: "Access Switch", subtitle: "VLAN 10") %>',
    firewall: '<%= firewall("fw1", name: "Edge Firewall", ip: "203.0.113.1") %>',
    gateway: '<%= gateway("gw1", name: "NAT Gateway", ip: "192.168.1.1") %>',
    cloud: '<%= cloud("inet", name: "Internet / WAN", subtitle: "Public Cloud") %>',
    database: '<%= database("db1", name: "Primary DB", ip: "10.0.2.10", engine: "PostgreSQL 16") %>',
    k8s_pod: '<%= k8s_pod("api_pod", name: "API Service", namespace: "prod", ip: "10.244.1.5") %>',
    table_node: '<%= table_node("metrics", title: "Node Metrics", rows: [["CPU", "4 Cores"], ["RAM", "16 GB"], ["Disk", "250 GB SSD"]]) %>',
    badge: '<%= badge("status", "HEALTHY", color: "#22c55e") %>',
    cluster: `<% cluster("app_tier", label: "Application Tier (10.0.1.0/24)", color: "#38bdf8") do %>
  <%= host("app01", name: "App 01", ip: "10.0.1.11") %>
  <%= host("app02", name: "App 02", ip: "10.0.1.12") %>
<% end %>`,
    nested_cluster: `<% cluster("vpc", label: "Virtual Private Cloud (VPC)", color: "#38bdf8") do %>
  <%= host("gw01", name: "NAT Gateway", ip: "10.0.0.1") %>
  <% cluster("private_subnet", label: "Private Subnet (10.0.1.0/24)", color: "#10b981") do %>
    <%= host("app01", name: "App 01", ip: "10.0.1.10") %>
    <%= database("db01", name: "Internal DB", ip: "10.0.1.20") %>
  <% end %>
<% end %>`,
    link: '<%= link("src_id", "dst_id", label: "10 Gbps") %>',
    links: '<%= links("rtr1", "app01", "app02") %>',
    chain: '<%= chain("client", "fw1", "rtr1", "app01") %>',
    loop: `<% (1..3).each do |i| %>
  <%= host("node0" + i.to_s, name: "Node " + i.to_s, ip: "10.0.1." + (10 + i).to_s) %>
<% end %>`,
    condition: `<% if true %>
  <%= badge("env", "PRODUCTION", color: "#ef4444") %>
<% else %>
  <%= badge("env", "STAGING", color: "#f59e0b") %>
<% end %>`,
    header: '<%= graph_header("Network Topology", rankdir: "LR") %>'
  };

  const MD_GRAPHVIZ_TEMPLATES = {
    erb_enterprise: `digraph EnterpriseNetwork {
  <%= graph_header("Enterprise Network Architecture", rankdir: "TB") %>

  <%= cloud("wan", name: "Internet / WAN", subtitle: "BGP AS 65000") %>
  <%= firewall("edge_fw", name: "Perimeter Firewall", ip: "203.0.113.1") %>
  <%= router("core_rtr", name: "Core Router", ip: "10.0.0.1") %>

  <%= cluster_start("dmz", label: "DMZ (10.0.1.0/24)", color: "#f59e0b") %>
    <%= gateway("proxy", name: "Reverse Proxy / LB", ip: "10.0.1.5") %>
  <%= cluster_end %>

  <%= cluster_start("app_tier", label: "Application Tier (10.0.2.0/24)", color: "#38bdf8") %>
    <% (1..2).each do |i| %>
      <%= host("web0" + i.to_s, name: "Web App 0" + i.to_s, ip: "10.0.2.1" + i.to_s) %>
    <% end %>
  <%= cluster_end %>

  <%= cluster_start("data_tier", label: "Data Tier (10.0.3.0/24)", color: "#ec4899") %>
    <%= database("pg01", name: "Primary DB", ip: "10.0.3.10", engine: "PostgreSQL 16") %>
    <%= database("redis01", name: "Cache", ip: "10.0.3.11", engine: "Redis 7") %>
  <%= cluster_end %>

  <%= link("wan", "edge_fw") %>
  <%= link("edge_fw", "core_rtr") %>
  <%= link("core_rtr", "proxy") %>
  <%= links("proxy", "web01", "web02") %>
  <%= links("web01", "pg01", "redis01") %>
  <%= links("web02", "pg01", "redis01") %>
}`,
    erb_k8s: `digraph KubernetesCluster {
  <%= graph_header("Kubernetes Cluster Topology", rankdir: "LR") %>

  <%= gateway("ingress", name: "Ingress Controller", ip: "192.168.10.50") %>

  <%= cluster_start("prod_ns", label: "Namespace: production", color: "#38bdf8") %>
    <%= k8s_pod("frontend", name: "frontend-deploy", namespace: "production", ip: "10.244.1.15") %>
    <%= k8s_pod("api", name: "api-service", namespace: "production", ip: "10.244.2.22") %>
    <%= database("db", name: "postgres-statefulset", ip: "10.244.3.4", engine: "Postgres 16") %>
  <%= cluster_end %>

  <%= cluster_start("monitoring_ns", label: "Namespace: monitoring", color: "#a855f7") %>
    <%= k8s_pod("prom", name: "prometheus-k8s", namespace: "monitoring") %>
    <%= k8s_pod("grafana", name: "grafana", namespace: "monitoring") %>
  <%= cluster_end %>

  <%= link("ingress", "frontend", label: "/app") %>
  <%= link("ingress", "grafana", label: "/grafana") %>
  <%= link("frontend", "api", label: "gRPC") %>
  <%= link("api", "db", label: "SQL") %>
  <%= links("prom", "frontend", "api", "db") %>
}`,
    erb_microservices: `digraph MicroservicesSystem {
  <%= graph_header("Microservices Architecture", rankdir: "TB") %>

  <%= gateway("apigw", name: "API Gateway (Kong)", ip: "10.0.0.10") %>

  <%= cluster_start("services", label: "Microservices", color: "#38bdf8") %>
    <%= host("auth_svc", name: "Auth Service", subtitle: "Go / JWT") %>
    <%= host("user_svc", name: "User Service", subtitle: "Node.js") %>
    <%= host("order_svc", name: "Order Service", subtitle: "Rust") %>
  <%= cluster_end %>

  <%= switch("event_bus", name: "Kafka Event Bus", subtitle: "Cluster") %>

  <%= cluster_start("storage", label: "Datastores", color: "#ec4899") %>
    <%= database("auth_redis", name: "Token Cache", engine: "Redis") %>
    <%= database("user_db", name: "Users DB", engine: "PostgreSQL") %>
    <%= database("order_db", name: "Orders DB", engine: "PostgreSQL") %>
  <%= cluster_end %>

  <%= links("apigw", "auth_svc", "user_svc", "order_svc") %>
  <%= link("auth_svc", "auth_redis") %>
  <%= link("user_svc", "user_db") %>
  <%= link("order_svc", "order_db") %>
  <%= links("event_bus", "user_svc", "order_svc") %>
}`,
    erb_dynamic_loop: `digraph DynamicCluster {
  <%= graph_header("Dynamic Server Farm", rankdir: "TB") %>

  <%= router("lb01", name: "HAProxy Load Balancer", ip: "10.10.0.1") %>

  <%= cluster_start("nodes", label: "Computed Worker Nodes", color: "#10b981") %>
    <% 1.upto(4) do |i| %>
      <%= host("node_0" + i.to_s, name: "Worker 0" + i.to_s, ip: "10.10.1." + (20 + i).to_s, subtitle: (i == 1 ? "Leader" : "Follower")) %>
    <% end %>
  <%= cluster_end %>

  <%= database("shared_storage", name: "NFS / S3 Storage", engine: "ZFS Pool") %>

  <% 1.upto(4) do |i| %>
    <%= link("lb01", "node_0" + i.to_s) %>
    <%= link("node_0" + i.to_s, "shared_storage", style: "dashed") %>
  <% end %>
}`,
    flowchart_lr: `digraph flowchart_lr {
  rankdir=LR;
  node [shape=box, style="rounded,filled", fillcolor="#f1f5f9", color="#475569", fontname="sans-serif", fontcolor="#0f172a"];
  edge [color="#64748b", fontname="sans-serif", fontsize=10];

  start [label="Start", shape=ellipse, fillcolor="#dbeafe", color="#3b82f6"];
  step1 [label="Process Task"];
  check [label="Success?", shape=diamond, fillcolor="#fef3c7", color="#f59e0b"];
  end   [label="Done", shape=ellipse, fillcolor="#dcfce7", color="#22c55e"];

  start -> step1;
  step1 -> check;
  check -> end [label="Yes"];
  check -> step1 [label="Retry (No)"];
}`,
    flowchart_tb: `digraph flowchart_tb {
  rankdir=TB;
  node [shape=box, style="rounded,filled", fillcolor="#f8fafc", color="#64748b", fontname="sans-serif", fontcolor="#0f172a"];
  edge [color="#64748b", fontname="sans-serif", fontsize=10];

  input  [label="User Input", shape=ellipse, fillcolor="#e0e7ff", color="#6366f1"];
  parse  [label="Validate & Parse"];
  route  [label="Route Request", shape=diamond, fillcolor="#fef3c7", color="#f59e0b"];
  render [label="Render View"];
  api    [label="JSON API Response"];

  input -> parse;
  parse -> route;
  route -> render [label="HTML"];
  route -> api [label="JSON"];
}`,
    network: `digraph network_topology {
  rankdir=TB;
  compound=true;
  node [shape=box, style="filled,rounded", fontname="sans-serif", fontsize=11];
  edge [color="#475569", fontname="sans-serif", fontsize=10];

  subgraph cluster_dmz {
    label="Public / DMZ";
    style="rounded,dashed";
    color="#94a3b8";
    fontname="sans-serif";
    fontcolor="#475569";
    lb [label="Load Balancer\\n(Nginx)", fillcolor="#e0f2fe", color="#0284c7"];
  }

  subgraph cluster_app {
    label="App Tier (Private)";
    style="rounded,dashed";
    color="#94a3b8";
    fontname="sans-serif";
    fontcolor="#475569";
    app1 [label="App Server 1", fillcolor="#ede9fe", color="#7c3aed"];
    app2 [label="App Server 2", fillcolor="#ede9fe", color="#7c3aed"];
  }

  subgraph cluster_data {
    label="Database Tier";
    style="rounded,dashed";
    color="#94a3b8";
    fontname="sans-serif";
    fontcolor="#475569";
    db [label="Primary DB\\n(PostgreSQL)", shape=cylinder, fillcolor="#dcfce7", color="#16a34a"];
    cache [label="Cache (Redis)", shape=cylinder, fillcolor="#fee2e2", color="#dc2626"];
  }

  client [label="Clients\\n(Web & Mobile)", shape=ellipse, fillcolor="#f1f5f9", color="#64748b"];

  client -> lb;
  lb -> app1;
  lb -> app2;
  app1 -> db;
  app2 -> db;
  app1 -> cache;
  app2 -> cache;
}`,
    state_machine: `digraph state_machine {
  rankdir=LR;
  node [shape=circle, style="filled", fillcolor="#f8fafc", color="#475569", fontname="sans-serif", fontcolor="#0f172a", width=0.9, fixedsize=true];
  edge [color="#64748b", fontname="sans-serif", fontsize=10];

  init [shape=point, width=0.2];
  idle [label="Idle", fillcolor="#e0f2fe", color="#0284c7"];
  run  [label="Running", fillcolor="#fef3c7", color="#d97706"];
  done [label="Done", shape=doublecircle, fillcolor="#dcfce7", color="#16a34a"];
  fail [label="Failed", shape=doublecircle, fillcolor="#fee2e2", color="#dc2626"];

  init -> idle;
  idle -> run [label="start"];
  run -> idle [label="pause"];
  run -> done [label="complete"];
  run -> fail [label="error"];
  fail -> run [label="retry"];
}`,
    records: `digraph record_example {
  rankdir=LR;
  node [shape=record, fontname="sans-serif", fontsize=11, style="filled", fillcolor="#f8fafc", color="#475569"];
  edge [color="#64748b", fontname="sans-serif", fontsize=10];

  node0 [label="<f0> head | <f1> tail"];
  node1 [label="<f0> val: 42 | <f1> next"];
  node2 [label="<f0> val: 99 | <f1> next = null"];

  node0:f0 -> node1:f0;
  node1:f1 -> node2:f0;
}`
  };

  function updateGraphvizVimIndicator(e) {
    if (!mdGraphvizVimStatusMode) return;
    let mode = e ? e.mode : null;
    let subMode = e ? e.subMode : '';
    if (!mode && mdGraphvizCodeEditor && mdGraphvizCodeEditor.state && mdGraphvizCodeEditor.state.vim) {
      const vState = mdGraphvizCodeEditor.state.vim;
      if (vState.insertMode) mode = 'insert';
      else if (vState.visualMode) mode = 'visual';
      else mode = 'normal';
    }
    if (!mode) mode = 'normal';

    if (mode === 'insert') {
      mdGraphvizVimStatusMode.textContent = '-- INSERT --';
      mdGraphvizVimStatusMode.style.color = '#38bdf8';
    } else if (mode === 'visual') {
      mdGraphvizVimStatusMode.textContent = subMode === 'linewise' ? '-- VISUAL LINE --' : (subMode === 'blockwise' ? '-- VISUAL BLOCK --' : '-- VISUAL --');
      mdGraphvizVimStatusMode.style.color = '#f59e0b';
    } else if (mode === 'replace') {
      mdGraphvizVimStatusMode.textContent = '-- REPLACE --';
      mdGraphvizVimStatusMode.style.color = '#ef4444';
    } else {
      mdGraphvizVimStatusMode.textContent = '-- NORMAL --';
      mdGraphvizVimStatusMode.style.color = '#22c55e';
    }
    if (mdGraphvizVimStatusKey && e && e.keyBuffer === '') {
      mdGraphvizVimStatusKey.textContent = '';
    }
  }

  function setGraphvizLineWrap(enabled) {
    mdGraphvizLineWrap = !!enabled;
    try {
      localStorage.setItem('ctlabs_graphviz_line_wrap', mdGraphvizLineWrap ? 'true' : 'false');
    } catch (e) {}

    if (mdGraphvizWrapBtn) {
      if (mdGraphvizLineWrap) {
        mdGraphvizWrapBtn.style.background = '#0284c7';
        mdGraphvizWrapBtn.style.color = '#ffffff';
        mdGraphvizWrapBtn.style.borderColor = '#38bdf8';
      } else {
        mdGraphvizWrapBtn.style.background = '#0f172a';
        mdGraphvizWrapBtn.style.color = '#94a3b8';
        mdGraphvizWrapBtn.style.borderColor = '#475569';
      }
    }

    if (mdGraphvizSettingWrapCheckbox) {
      mdGraphvizSettingWrapCheckbox.checked = mdGraphvizLineWrap;
    }

    if (mdGraphvizCodeEditor) {
      mdGraphvizCodeEditor.setOption('lineWrapping', mdGraphvizLineWrap);
      mdGraphvizCodeEditor.refresh();
    } else if (mdGraphvizSource) {
      mdGraphvizSource.wrap = mdGraphvizLineWrap ? 'soft' : 'off';
    }
  }

  function setGraphvizVimMode(enabled) {
    mdGraphvizVimMode = !!enabled;
    try {
      localStorage.setItem('ctlabs_graphviz_vim_mode', mdGraphvizVimMode ? 'true' : 'false');
    } catch (e) {}

    if (mdGraphvizVimBtn) {
      if (mdGraphvizVimMode) {
        mdGraphvizVimBtn.style.background = '#16a34a';
        mdGraphvizVimBtn.style.color = '#ffffff';
        mdGraphvizVimBtn.style.borderColor = '#22c55e';
      } else {
        mdGraphvizVimBtn.style.background = '#0f172a';
        mdGraphvizVimBtn.style.color = '#94a3b8';
        mdGraphvizVimBtn.style.borderColor = '#475569';
      }
    }

    if (mdGraphvizSettingVimCheckbox) {
      mdGraphvizSettingVimCheckbox.checked = mdGraphvizVimMode;
    }

    if (mdGraphvizVimStatusBar) {
      mdGraphvizVimStatusBar.style.display = mdGraphvizVimMode ? 'flex' : 'none';
    }

    if (mdGraphvizCodeEditor) {
      const currentKeyMap = mdGraphvizCodeEditor.getOption('keyMap') || 'default';
      if (mdGraphvizVimMode) {
        if (!currentKeyMap.startsWith('vim')) {
          mdGraphvizCodeEditor.setOption('keyMap', 'vim');
          updateGraphvizVimIndicator({ mode: 'normal' });
        }
      } else {
        if (currentKeyMap.startsWith('vim')) {
          mdGraphvizCodeEditor.setOption('keyMap', 'default');
        }
      }
    }
  }

  function toggleGraphvizSettingsMenu(open) {
    if (!mdGraphvizSettingsMenu) return;
    const isClosed = !mdGraphvizSettingsMenu.style.display || mdGraphvizSettingsMenu.style.display === 'none';
    const shouldOpen = (open !== undefined) ? open : isClosed;
    mdGraphvizSettingsMenu.style.display = shouldOpen ? 'block' : 'none';
    if (shouldOpen) {
      if (mdGraphvizBlocksMenu) mdGraphvizBlocksMenu.style.display = 'none';
      if (mdGraphvizEmojiMenu) mdGraphvizEmojiMenu.style.display = 'none';
      if (mdGraphvizSettingWrapCheckbox) mdGraphvizSettingWrapCheckbox.checked = !!mdGraphvizLineWrap;
      if (mdGraphvizSettingVimCheckbox) mdGraphvizSettingVimCheckbox.checked = !!mdGraphvizVimMode;
      if (mdGraphvizFontFamily) mdGraphvizFontFamily.value = mdGraphvizFont;
      if (mdGraphvizFontSizeLabel) mdGraphvizFontSizeLabel.textContent = `${mdGraphvizFontSize}px`;
    }
  }

  function setGraphvizActiveTab(tab) {
    mdGraphvizActiveTab = (tab === 'dot') ? 'dot' : 'source';
    if (mdGraphvizTabSource) {
      if (mdGraphvizActiveTab === 'source') {
        mdGraphvizTabSource.style.background = '#0284c7';
        mdGraphvizTabSource.style.color = '#ffffff';
        mdGraphvizTabSource.style.fontWeight = '600';
      } else {
        mdGraphvizTabSource.style.background = 'transparent';
        mdGraphvizTabSource.style.color = '#94a3b8';
        mdGraphvizTabSource.style.fontWeight = '500';
      }
    }
    if (mdGraphvizTabDot) {
      if (mdGraphvizActiveTab === 'dot') {
        mdGraphvizTabDot.style.background = '#0284c7';
        mdGraphvizTabDot.style.color = '#ffffff';
        mdGraphvizTabDot.style.fontWeight = '600';
      } else {
        mdGraphvizTabDot.style.background = 'transparent';
        mdGraphvizTabDot.style.color = '#94a3b8';
        mdGraphvizTabDot.style.fontWeight = '500';
      }
    }

    if (mdGraphvizActiveTab === 'dot') {
      if (mdGraphvizEditorContainer) mdGraphvizEditorContainer.style.display = 'none';
      if (mdGraphvizDotContainer) mdGraphvizDotContainer.style.display = 'flex';
      if (mdGraphvizVimStatusBar) mdGraphvizVimStatusBar.style.display = 'none';
      updateGraphvizDotDisplay();
    } else {
      if (mdGraphvizEditorContainer) mdGraphvizEditorContainer.style.display = 'flex';
      if (mdGraphvizDotContainer) mdGraphvizDotContainer.style.display = 'none';
      if (mdGraphvizVimMode && mdGraphvizVimStatusBar) mdGraphvizVimStatusBar.style.display = 'flex';
      if (mdGraphvizCodeEditor) {
        mdGraphvizCodeEditor.refresh();
        mdGraphvizCodeEditor.focus();
      }
    }
  }

  function updateGraphvizDotDisplay() {
    if (!mdGraphvizDotOutput) return;
    if (mdGraphvizLastDot && mdGraphvizLastDot.trim()) {
      mdGraphvizDotOutput.textContent = mdGraphvizLastDot;
      if (mdGraphvizTabDotBadge) mdGraphvizTabDotBadge.style.display = 'inline-block';
    } else {
      const src = getGraphvizEditorValue();
      if (src.includes('<%')) {
        mdGraphvizDotOutput.textContent = '// Press Render (Ctrl+Enter) to compile ERB template into DOT';
      } else {
        mdGraphvizDotOutput.textContent = src || '// No DOT code';
      }
      if (mdGraphvizTabDotBadge) mdGraphvizTabDotBadge.style.display = 'none';
    }
  }

  function insertGraphvizSnippet(snippetKey) {
    const text = MD_GRAPHVIZ_SNIPPETS[snippetKey] || snippetKey;
    if (!text) return;

    if (mdGraphvizActiveTab !== 'source') {
      setGraphvizActiveTab('source');
    }

    if (mdGraphvizCodeEditor) {
      const doc = mdGraphvizCodeEditor.getDoc();
      const cursor = doc.getCursor();
      doc.replaceRange(text + '\n', cursor);
      mdGraphvizCodeEditor.focus();
    } else if (mdGraphvizSource) {
      const start = mdGraphvizSource.selectionStart || 0;
      const end = mdGraphvizSource.selectionEnd || 0;
      const current = mdGraphvizSource.value;
      mdGraphvizSource.value = current.substring(0, start) + text + '\n' + current.substring(end);
      mdGraphvizSource.selectionStart = mdGraphvizSource.selectionEnd = start + text.length + 1;
      mdGraphvizSource.focus();
    }

    if (mdGraphvizBlocksMenu) mdGraphvizBlocksMenu.style.display = 'none';
  }

  function escapeHtmlAttr(str) {
    if (!str) return '';
    return String(str)
      .replace(/&/g, '&amp;')
      .replace(/"/g, '&quot;')
      .replace(/'/g, '&#39;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;');
  }

  let mdGraphvizGlobalBlocks = [];

  async function fetchGlobalCustomBlocks() {
    try {
      const res = await fetch('/recordings/graphviz/custom_blocks');
      if (res.ok) {
        const data = await res.json();
        if (data && data.blocks) {
          mdGraphvizGlobalBlocks = data.blocks;
          renderGraphvizBlocksMenu();
        }
      }
    } catch (e) {
      console.warn('Failed to fetch global custom blocks:', e);
    }
  }

  function renderGraphvizBlocksMenu() {
    if (!mdGraphvizCustomBlocksContainer) return;

    const globalBlocks = mdGraphvizGlobalBlocks || [];

    let html = `
      <div style="padding: 4px 10px; font-size: 0.72em; text-transform: uppercase; letter-spacing: 0.5px; color: #4ade80; font-weight: 700; background: #1e293b; display: flex; justify-content: space-between; align-items: center;">
        <span>Custom Blocks</span>
        <button type="button" class="md-gv-add-custom-block-btn" style="background: transparent; border: 1px solid #22c55e; color: #4ade80; border-radius: 3px; padding: 1px 6px; font-size: 0.85em; cursor: pointer; transition: all 0.15s;" onmouseover="this.style.background='#15803d'; this.style.color='#fff';" onmouseout="this.style.background='transparent'; this.style.color='#4ade80';">+ New</button>
      </div>
    `;

    if (globalBlocks.length === 0) {
      html += `<div style="padding: 6px 12px; font-size: 0.75em; color: #64748b;">No global custom blocks yet</div>`;
    } else {
      globalBlocks.forEach(b => {
        const snip = b.snippet || `<%= ${b.name}("id") %>`;
        html += `
          <div style="display: flex; align-items: center; justify-content: space-between; padding: 4px 8px 4px 12px; border-bottom: 1px solid #1e293b;">
            <button type="button" class="md-gv-custom-snippet-item" data-snippet="${escapeHtmlAttr(snip)}" title="${escapeHtmlAttr(b.description || snip)}" style="display: flex; align-items: center; gap: 8px; flex: 1; text-align: left; background: transparent; border: none; color: #e2e8f0; cursor: pointer; font-size: 0.82em; padding: 3px 0; overflow: hidden;">
              <span style="color: #4ade80; font-weight: 600;">📦 ${escapeHtmlAttr(b.name)}</span>
              <code style="font-size: 0.8em; color: #94a3b8; overflow: hidden; text-overflow: ellipsis; white-space: nowrap;">${escapeHtmlAttr(snip)}</code>
            </button>
            <div style="display: flex; align-items: center; gap: 4px; margin-left: 6px;">
              <button type="button" class="md-gv-edit-global-block-btn" data-name="${escapeHtmlAttr(b.name)}" title="Edit global block" style="background: transparent; border: none; color: #94a3b8; cursor: pointer; padding: 2px 4px; font-size: 0.8em;" onmouseover="this.style.color='#38bdf8';" onmouseout="this.style.color='#94a3b8';"><i class="fas fa-edit"></i></button>
              <button type="button" class="md-gv-delete-global-block-btn" data-name="${escapeHtmlAttr(b.name)}" title="Delete global block" style="background: transparent; border: none; color: #94a3b8; cursor: pointer; padding: 2px 4px; font-size: 0.8em;" onmouseover="this.style.color='#ef4444';" onmouseout="this.style.color='#94a3b8';"><i class="fas fa-trash-alt"></i></button>
            </div>
          </div>
        `;
      });
    }

    mdGraphvizCustomBlocksContainer.innerHTML = html;
    wireCustomBlockActions();
  }

  function wireCustomBlockActions() {
    if (!mdGraphvizCustomBlocksContainer) return;

    mdGraphvizCustomBlocksContainer.querySelectorAll('.md-gv-custom-snippet-item').forEach(btn => {
      btn.addEventListener('click', (e) => {
        e.preventDefault();
        e.stopPropagation();
        insertGraphvizSnippet(btn.dataset.snippet);
      });
    });

    mdGraphvizCustomBlocksContainer.querySelectorAll('.md-gv-add-custom-block-btn').forEach(btn => {
      btn.addEventListener('click', (e) => {
        e.preventDefault();
        e.stopPropagation();
        openCustomBlockModal(null);
      });
    });

    mdGraphvizCustomBlocksContainer.querySelectorAll('.md-gv-edit-global-block-btn').forEach(btn => {
      btn.addEventListener('click', (e) => {
        e.preventDefault();
        e.stopPropagation();
        const blockName = btn.dataset.name;
        const block = (mdGraphvizGlobalBlocks || []).find(b => b.name === blockName);
        openCustomBlockModal(block || { name: blockName });
      });
    });

    mdGraphvizCustomBlocksContainer.querySelectorAll('.md-gv-delete-global-block-btn').forEach(btn => {
      btn.addEventListener('click', (e) => {
        e.preventDefault();
        e.stopPropagation();
        deleteCustomBlockGlobally(btn.dataset.name);
      });
    });
  }

  function openCustomBlockModal(block = null) {
    if (!mdGraphvizBlockModal) return;
    if (mdGraphvizBlocksMenu) mdGraphvizBlocksMenu.style.display = 'none';

    if (mdGraphvizBlockError) {
      mdGraphvizBlockError.style.display = 'none';
      mdGraphvizBlockError.textContent = '';
    }

    if (block) {
      if (mdGraphvizBlockModalTitle) mdGraphvizBlockModalTitle.textContent = block.isDocument ? 'Save In-Document Block to Global' : 'Edit Global Custom Block';
      if (mdGraphvizBlockName) {
        mdGraphvizBlockName.value = block.name || '';
        mdGraphvizBlockName.readOnly = false;
      }
      if (mdGraphvizBlockCode) mdGraphvizBlockCode.value = block.code || '';
      if (mdGraphvizBlockSnippet) mdGraphvizBlockSnippet.value = block.snippet || '';
      if (mdGraphvizBlockDesc) mdGraphvizBlockDesc.value = block.description || block.desc || '';
    } else {
      if (mdGraphvizBlockModalTitle) mdGraphvizBlockModalTitle.textContent = 'Create New Global Custom Block';
      if (mdGraphvizBlockName) {
        mdGraphvizBlockName.value = '';
        mdGraphvizBlockName.readOnly = false;
      }
      if (mdGraphvizBlockCode) mdGraphvizBlockCode.value = 'def my_block(id, label: nil)\n  host(id, name: label || id, icon: "💻")\nend';
      if (mdGraphvizBlockSnippet) mdGraphvizBlockSnippet.value = '<%= my_block("srv1") %>';
      if (mdGraphvizBlockDesc) mdGraphvizBlockDesc.value = '';
    }

    mdGraphvizBlockModal.style.display = 'block';
    setTimeout(() => {
      if (mdGraphvizBlockName && !mdGraphvizBlockName.value) {
        mdGraphvizBlockName.focus();
      } else if (mdGraphvizBlockCode) {
        mdGraphvizBlockCode.focus();
      }
    }, 50);
  }

  function closeCustomBlockModal() {
    if (mdGraphvizBlockModal) mdGraphvizBlockModal.style.display = 'none';
  }

  async function saveCustomBlockGlobally() {
    const name = mdGraphvizBlockName ? mdGraphvizBlockName.value.trim() : '';
    const code = mdGraphvizBlockCode ? mdGraphvizBlockCode.value.trim() : '';
    const snippet = mdGraphvizBlockSnippet ? mdGraphvizBlockSnippet.value.trim() : '';
    const description = mdGraphvizBlockDesc ? mdGraphvizBlockDesc.value.trim() : '';

    if (!name) {
      if (mdGraphvizBlockError) {
        mdGraphvizBlockError.textContent = 'Block name is required (e.g. app_tier, k8s_service).';
        mdGraphvizBlockError.style.display = 'block';
      }
      if (mdGraphvizBlockName) mdGraphvizBlockName.focus();
      return;
    }

    if (!/^[a-zA-Z_][a-zA-Z0-9_]*$/.test(name)) {
      if (mdGraphvizBlockError) {
        mdGraphvizBlockError.textContent = 'Invalid block name: must be a valid Ruby identifier (letters, digits, underscores).';
        mdGraphvizBlockError.style.display = 'block';
      }
      if (mdGraphvizBlockName) mdGraphvizBlockName.focus();
      return;
    }

    if (!code) {
      if (mdGraphvizBlockError) {
        mdGraphvizBlockError.textContent = 'Ruby implementation code is required.';
        mdGraphvizBlockError.style.display = 'block';
      }
      if (mdGraphvizBlockCode) mdGraphvizBlockCode.focus();
      return;
    }

    if (mdGraphvizBlockSaveBtn) {
      mdGraphvizBlockSaveBtn.disabled = true;
      mdGraphvizBlockSaveBtn.innerHTML = '<i class="fas fa-spinner fa-spin"></i> Saving...';
    }

    try {
      const res = await fetch('/recordings/graphviz/custom_blocks', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ name, code, snippet, description })
      });
      const data = await res.json();
      if (!res.ok || !data.ok) {
        if (mdGraphvizBlockError) {
          mdGraphvizBlockError.textContent = data.error || 'Failed to save block';
          mdGraphvizBlockError.style.display = 'block';
        }
        return;
      }

      if (data.blocks) {
        mdGraphvizGlobalBlocks = data.blocks;
      } else {
        await fetchGlobalCustomBlocks();
      }

      closeCustomBlockModal();
      renderGraphvizBlocksMenu();
      if (mdGraphvizStatus) {
        mdGraphvizStatus.textContent = `Saved global block: ${name}`;
        mdGraphvizStatus.style.color = '#4ade80';
      }
    } catch (err) {
      if (mdGraphvizBlockError) {
        mdGraphvizBlockError.textContent = err.message || 'Network error saving block';
        mdGraphvizBlockError.style.display = 'block';
      }
    } finally {
      if (mdGraphvizBlockSaveBtn) {
        mdGraphvizBlockSaveBtn.disabled = false;
        mdGraphvizBlockSaveBtn.innerHTML = '<i class="fas fa-save"></i> Save Global Block';
      }
    }
  }

  async function deleteCustomBlockGlobally(name) {
    if (!name) return;
    if (!confirm(`Delete global custom block "${name}"? Templates relying on it may fail to render.`)) {
      return;
    }

    try {
      const res = await fetch(`/recordings/graphviz/custom_blocks/${encodeURIComponent(name)}`, {
        method: 'DELETE'
      });
      const data = await res.json();
      if (res.ok && data.ok) {
        if (data.blocks) {
          mdGraphvizGlobalBlocks = data.blocks;
        } else {
          await fetchGlobalCustomBlocks();
        }
        renderGraphvizBlocksMenu();
        if (mdGraphvizStatus) {
          mdGraphvizStatus.textContent = `Deleted global block: ${name}`;
          mdGraphvizStatus.style.color = '#38bdf8';
        }
      } else {
        alert(data.error || 'Failed to delete custom block');
      }
    } catch (e) {
      alert('Error deleting custom block: ' + e.message);
    }
  }

  function insertGraphvizEmoji(snippet) {
    if (!snippet) return;
    if (mdGraphvizActiveTab !== 'source') {
      setGraphvizActiveTab('source');
    }

    if (mdGraphvizCodeEditor) {
      mdGraphvizCodeEditor.replaceSelection(snippet, 'end');
      mdGraphvizCodeEditor.focus();
    } else if (mdGraphvizSource) {
      const start = mdGraphvizSource.selectionStart || 0;
      const end = mdGraphvizSource.selectionEnd || 0;
      const current = mdGraphvizSource.value;
      mdGraphvizSource.value = current.substring(0, start) + snippet + current.substring(end);
      mdGraphvizSource.selectionStart = mdGraphvizSource.selectionEnd = start + snippet.length;
      mdGraphvizSource.focus();
    }

    if (mdGraphvizEmojiMenu) mdGraphvizEmojiMenu.style.display = 'none';
    scheduleGraphvizPreview();
  }

  async function toggleGraphvizEmojiMenu(open) {
    if (!mdGraphvizEmojiMenu) return;
    const isClosed = !mdGraphvizEmojiMenu.style.display || mdGraphvizEmojiMenu.style.display === 'none';
    const shouldOpen = (open !== undefined) ? open : isClosed;
    mdGraphvizEmojiMenu.style.display = shouldOpen ? 'flex' : 'none';
    if (shouldOpen) {
      if (ctlabsEmojiList.length === 0) {
        await loadCtlabsEmojis();
      }
      if (mdGraphvizBlocksMenu) mdGraphvizBlocksMenu.style.display = 'none';
      if (mdGraphvizEmojiSearch) {
        mdGraphvizEmojiSearch.value = '';
        if (mdGraphvizEmojiSearchClear) mdGraphvizEmojiSearchClear.style.display = 'none';
        setTimeout(() => mdGraphvizEmojiSearch.focus(), 30);
      }
      mdGraphvizEmojiCatBtns.forEach(b => {
        const isAll = b.getAttribute('data-cat') === 'all';
        b.classList.toggle('active', isAll);
        b.style.background = isAll ? '#0284c7' : 'transparent';
        b.style.color = isAll ? '#fff' : '#94a3b8';
      });
      renderGraphvizEmojiGrid('all', '');
    }
  }

  function renderGraphvizEmojiGrid(cat = 'all', query = '') {
    const list = getEmojiList();
    if (!mdGraphvizEmojiGrid || !list) return;
    const cleanQuery = query.trim().toLowerCase();
    const filtered = list.filter(item => {
      if (cat !== 'all') {
        if (cat === 'github') {
          if (item.cat !== 'github' && item.cat !== 'popular') return false;
        } else if (item.cat !== cat) {
          return false;
        }
      }
      if (cleanQuery) {
        return item.code.toLowerCase().includes(cleanQuery) || item.name.toLowerCase().includes(cleanQuery);
      }
      return true;
    });

    if (filtered.length === 0) {
      mdGraphvizEmojiGrid.innerHTML = '<div style="grid-column: 1 / -1; padding: 16px; text-align: center; color: #94a3b8; font-size: 0.8em;">No matching emojis</div>';
      return;
    }

    const displayItems = cleanQuery ? filtered : filtered.slice(0, 320);

    mdGraphvizEmojiGrid.innerHTML = displayItems.map(item => {
      const visual = item.img
        ? `<img src="${item.img}" width="22" height="22" alt=":${item.code}:" style="pointer-events: none; border-radius: 2px; vertical-align: middle;">`
        : (item.char || '');
      return `<button type="button" class="md-gv-emoji-cell" data-code="${item.code}" data-char="${item.char || ''}" data-img="${item.img || ''}" data-name="${item.name}" title=":${item.code}: (${item.name})" style="display: flex; align-items: center; justify-content: center; width: 34px; height: 34px; font-size: 1.25em; border: none; background: transparent; border-radius: 4px; cursor: pointer; transition: background 0.1s, transform 0.1s;" onmouseover="this.style.background='#1e293b'; this.style.transform='scale(1.15)';" onmouseout="this.style.background='transparent'; this.style.transform='none';">${visual}</button>`;
    }).join('');

    mdGraphvizEmojiGrid.querySelectorAll('.md-gv-emoji-cell').forEach(cell => {
      cell.addEventListener('mouseenter', () => {
        if (mdGraphvizEmojiFooterPreview) {
          mdGraphvizEmojiFooterPreview.textContent = `:${cell.getAttribute('data-code')}: — ${cell.getAttribute('data-name')}`;
        }
      });

      const handleGraphvizEmojiInsert = (e, asCode) => {
        e.preventDefault();
        e.stopPropagation();
        const code = cell.getAttribute('data-code');
        const ch = cell.getAttribute('data-char');
        const img = cell.getAttribute('data-img');
        const snippet = (asCode || !ch || img) ? `:${code}:` : ch;

        insertGraphvizEmoji(snippet);
        toggleGraphvizEmojiMenu(false);
      };

      cell.addEventListener('click', (e) => handleGraphvizEmojiInsert(e, false));
      cell.addEventListener('contextmenu', (e) => handleGraphvizEmojiInsert(e, true));
    });
  }

  function setGraphvizPreviewBg(bg) {
    mdGraphvizBg = bg || 'white';
    try { localStorage.setItem('ctlabs_graphviz_bg', mdGraphvizBg); } catch (e) {}

    if (!mdGraphvizPreview) return;

    [mdGraphvizBgWhite, mdGraphvizBgSlate, mdGraphvizBgChecker].forEach(btn => {
      if (btn) btn.style.border = '1px solid #475569';
    });
    if (mdGraphvizBgPicker && mdGraphvizBgPicker.parentElement) {
      mdGraphvizBgPicker.parentElement.style.border = '1px solid #475569';
    }

    if (mdGraphvizBg === 'white') {
      mdGraphvizPreview.style.background = '#ffffff';
      if (mdGraphvizBgWhite) mdGraphvizBgWhite.style.border = '2px solid #38bdf8';
    } else if (mdGraphvizBg === 'slate') {
      mdGraphvizPreview.style.background = '#0f172a';
      if (mdGraphvizBgSlate) mdGraphvizBgSlate.style.border = '2px solid #38bdf8';
    } else if (mdGraphvizBg === 'checker') {
      mdGraphvizPreview.style.background = 'repeating-conic-gradient(#cbd5e1 0% 25%, #f1f5f9 0% 50%) 50% / 16px 16px';
      if (mdGraphvizBgChecker) mdGraphvizBgChecker.style.border = '2px solid #38bdf8';
    } else {
      mdGraphvizPreview.style.background = mdGraphvizBg;
      if (mdGraphvizBgPicker) {
        mdGraphvizBgPicker.value = mdGraphvizBg;
        if (mdGraphvizBgPicker.parentElement) {
          mdGraphvizBgPicker.parentElement.style.border = '2px solid #38bdf8';
        }
      }
    }
  }

  function applyGraphvizEditorFont() {
    const fontStack = GRAPHVIZ_FONTS[mdGraphvizFont] || GRAPHVIZ_FONTS.courier;
    if (mdGraphvizFontSizeLabel) mdGraphvizFontSizeLabel.textContent = `${mdGraphvizFontSize}px`;
    if (mdGraphvizFontFamily) mdGraphvizFontFamily.value = mdGraphvizFont;

    if (mdGraphvizCodeEditor) {
      const wrapper = mdGraphvizCodeEditor.getWrapperElement();
      if (wrapper) {
        wrapper.style.fontSize = `${mdGraphvizFontSize}px`;
        wrapper.style.fontFamily = fontStack;
        const cmLines = wrapper.querySelectorAll('.CodeMirror-line, .CodeMirror-linenumber, .CodeMirror-lines');
        cmLines.forEach(el => { el.style.fontFamily = fontStack; });
      }
      mdGraphvizCodeEditor.refresh();
    } else if (mdGraphvizSource) {
      mdGraphvizSource.style.fontSize = `${mdGraphvizFontSize}px`;
      mdGraphvizSource.style.fontFamily = fontStack;
    }
  }

  function getGraphvizEditorValue() {
    if (mdGraphvizCodeEditor) return mdGraphvizCodeEditor.getValue();
    return mdGraphvizSource ? mdGraphvizSource.value : '';
  }

  function setGraphvizEditorValue(val) {
    if (mdGraphvizCodeEditor) {
      mdGraphvizCodeEditor.setValue(val || '');
    }
    if (mdGraphvizSource) {
      mdGraphvizSource.value = val || '';
    }
  }

  function ensureGraphvizDotMode() {
    if (typeof CodeMirror === 'undefined' || typeof CodeMirror.defineSimpleMode !== 'function') return false;
    if (CodeMirror.modes && CodeMirror.modes.dot) return true;

    try {
      CodeMirror.defineSimpleMode('dot', {
        start: [
          // Keywords & graph declarations
          { regex: /\b(?:strict|digraph|graph|subgraph|node|edge)\b/i, token: 'keyword' },
          // Common Graphviz attribute names
          { regex: /\b(?:label|shape|style|fillcolor|color|bgcolor|pencolor|fontname|fontcolor|fontsize|rankdir|compound|dir|arrowhead|arrowsize|penwidth|weight|len|rank|same|min|max|headport|tailport|margin|width|height|fixedsize|nodesep|ranksep|splines|overlap|layout|size|ratio|dpi|id|tooltip|href|target)\b/i, token: 'builtin' },
          // Edge operators (-> for directed digraphs, -- for undirected graphs)
          { regex: /->|--/, token: 'operator' },
          // Booleans / constants / rank directions
          { regex: /\b(?:true|false|none|both|forward|back|same|LR|TB|RL|BT)\b/i, token: 'atom' },
          // Strings (double quotes with escape support)
          { regex: /"(?:[^\\]|\\.)*?(?:"|$)/, token: 'string' },
          // HTML-like labels: <...>
          { regex: /<[^>]*>/, token: 'string url' },
          // Numeric values and hex colors (#f8fafc)
          { regex: /#[a-fA-F0-9]{3,8}\b/, token: 'atom' },
          { regex: /\b[-+]?(?:\.\d+|\d+\.?\d*)(?:e[-+]?\d+)?\b/i, token: 'number' },
          // Comments: //, /* */, and #
          { regex: /\/\/.*/, token: 'comment' },
          { regex: /\#.*/, token: 'comment' },
          { regex: /\/\*/, token: 'comment', next: 'comment' },
          // Operators and punctuation
          { regex: /[=;,]/, token: 'operator' },
          { regex: /[{}\[\]]/, token: 'bracket' },
          // Node identifiers / attributes values
          { regex: /[a-zA-Z_][a-zA-Z0-9_]*/, token: 'variable' }
        ],
        comment: [
          { regex: /.*?\*\//, token: 'comment', next: 'start' },
          { regex: /.*/, token: 'comment' }
        ],
        meta: {
          lineComment: '//',
          blockCommentStart: '/*',
          blockCommentEnd: '*/'
        }
      });
      return true;
    } catch (e) {
      console.warn('Could not register CodeMirror dot mode:', e);
      return false;
    }
  }

  // Register mode and fold helpers early if CodeMirror is already present
  ensureGraphvizDotMode();
  ensureCodeMirrorFoldHelpers();
  ensureCodeMirrorVimFoldBindings();

  function initGraphvizCodeEditor() {
    ensureGraphvizDotMode();
    ensureCodeMirrorFoldHelpers();
    ensureCodeMirrorVimFoldBindings();
    if (mdGraphvizCodeEditor) {
      if (mdGraphvizCodeEditor.getOption('mode') !== 'dot') {
        mdGraphvizCodeEditor.setOption('mode', 'dot');
      }
      return mdGraphvizCodeEditor;
    }
    if (typeof CodeMirror === 'undefined') return null;
    const ta = document.getElementById('md-graphviz-source');
    if (!ta) return null;

    try {
      mdGraphvizCodeEditor = CodeMirror.fromTextArea(ta, {
        mode: 'dot',
        theme: 'material-ocean',
        lineNumbers: true,
        tabSize: 2,
        lineWrapping: mdGraphvizLineWrap,
        keyMap: mdGraphvizVimMode ? 'vim' : 'default',
        viewportMargin: 10,
        gutters: ['CodeMirror-linenumbers', 'CodeMirror-foldgutter'],
        foldGutter: true,
        foldOptions: { scanUp: true },
        extraKeys: {
          'Ctrl-E': () => toggleGraphvizEmojiMenu(),
          'Cmd-E': () => toggleGraphvizEmojiMenu(),
          'Ctrl-Q': (cm) => cm.foldCode(cm.getCursor(), { scanUp: true }),
          'Cmd-Q': (cm) => cm.foldCode(cm.getCursor(), { scanUp: true }),
          'Ctrl-S': () => saveAndInsertGraphviz({ saveAsNew: false, closeAfter: false }),
          'Cmd-S': () => saveAndInsertGraphviz({ saveAsNew: false, closeAfter: false }),
          'Ctrl-Enter': () => renderGraphviz(),
          'Cmd-Enter': () => renderGraphviz(),
          'Tab': (cm) => {
            if (cm.somethingSelected()) {
              cm.indentSelection('add');
            } else {
              cm.replaceSelection('  ', 'end');
            }
          },
          'Shift-Tab': (cm) => {
            cm.indentSelection('subtract');
          }
        }
      });

      mdGraphvizCodeEditor.on('vim-mode-change', (arg) => {
        updateGraphvizVimIndicator(arg);
      });

      mdGraphvizCodeEditor.on('vim-keypress', (key) => {
        if (mdGraphvizVimStatusKey) {
          mdGraphvizVimStatusKey.textContent = key || '';
        }
      });

      mdGraphvizCodeEditor.setSize('100%', '100%');
      window.cmEditors = window.cmEditors || {};
      window.cmEditors['md-graphviz-source'] = mdGraphvizCodeEditor;
      window.mdGraphvizCodeEditor = mdGraphvizCodeEditor;
      mdGraphvizCodeEditor.on('change', () => {
        if (mdGraphvizSource) mdGraphvizSource.value = mdGraphvizCodeEditor.getValue();
        scheduleGraphvizPreview();
      });

      applyGraphvizEditorFont();
      setTimeout(() => mdGraphvizCodeEditor.refresh(), 30);
      return mdGraphvizCodeEditor;
    } catch (e) {
      console.error('Failed to initialize CodeMirror for Graphviz:', e);
      return null;
    }
  }

  function setGraphvizError(message) {
    if (!mdGraphvizError) return;
    if (message) {
      mdGraphvizError.textContent = message;
      mdGraphvizError.style.display = 'block';
    } else {
      mdGraphvizError.textContent = '';
      mdGraphvizError.style.display = 'none';
    }
  }

  function setGraphvizStatus(message) {
    if (mdGraphvizStatus) mdGraphvizStatus.textContent = message || '';
  }

  function applyGraphvizTransform() {
    if (!mdGraphvizPreviewImg) return;
    mdGraphvizPreviewImg.style.transform = `translate(${mdGraphvizPanX}px, ${mdGraphvizPanY}px) scale(${mdGraphvizScale})`;
    if (mdGraphvizZoomReset) {
      mdGraphvizZoomReset.textContent = `${Math.round(mdGraphvizScale * 100)}%`;
    }
  }

  function applyGraphvizPaneSizes() {
    const isStacked = mdGraphvizLayout === 'stacked';
    if (isStacked) {
      if (mdGraphvizPreviewPane) {
        mdGraphvizPreviewPane.style.width = '100%';
        mdGraphvizPreviewPane.style.height = `calc(${mdGraphvizSplitRow}% - 5px)`;
        mdGraphvizPreviewPane.style.flex = 'none';
      }
      if (mdGraphvizSourcePane) {
        mdGraphvizSourcePane.style.width = '100%';
        mdGraphvizSourcePane.style.height = `calc(${100 - mdGraphvizSplitRow}% - 5px)`;
        mdGraphvizSourcePane.style.flex = 'none';
      }
    } else {
      if (mdGraphvizSourcePane) {
        mdGraphvizSourcePane.style.height = '100%';
        mdGraphvizSourcePane.style.width = `calc(${mdGraphvizSplitCol}% - 5px)`;
        mdGraphvizSourcePane.style.flex = 'none';
      }
      if (mdGraphvizPreviewPane) {
        mdGraphvizPreviewPane.style.height = '100%';
        mdGraphvizPreviewPane.style.width = `calc(${100 - mdGraphvizSplitCol}% - 5px)`;
        mdGraphvizPreviewPane.style.flex = 'none';
      }
    }
    if (mdGraphvizCodeEditor) {
      mdGraphvizCodeEditor.refresh();
    }
  }

  function setGraphvizLayout(layout) {
    mdGraphvizLayout = (layout === 'stacked') ? 'stacked' : 'side';
    try {
      localStorage.setItem('ctlabs_graphviz_layout', mdGraphvizLayout);
    } catch (e) {}

    const isStacked = mdGraphvizLayout === 'stacked';
    if (mdGraphvizSplitContainer) {
      mdGraphvizSplitContainer.style.flexDirection = isStacked ? 'column' : 'row';
    }

    if (mdGraphvizSplitter) {
      if (isStacked) {
        mdGraphvizSplitter.style.width = '100%';
        mdGraphvizSplitter.style.height = '10px';
        mdGraphvizSplitter.style.cursor = 'row-resize';
        mdGraphvizSplitter.style.margin = '2px 0';
        mdGraphvizSplitter.style.borderTop = '1px solid #334155';
        mdGraphvizSplitter.style.borderBottom = '1px solid #334155';
        mdGraphvizSplitter.style.borderLeft = 'none';
        mdGraphvizSplitter.style.borderRight = 'none';
        mdGraphvizSplitter.style.order = '2';
      } else {
        mdGraphvizSplitter.style.width = '10px';
        mdGraphvizSplitter.style.height = '100%';
        mdGraphvizSplitter.style.cursor = 'col-resize';
        mdGraphvizSplitter.style.margin = '0 2px';
        mdGraphvizSplitter.style.borderLeft = '1px solid #334155';
        mdGraphvizSplitter.style.borderRight = '1px solid #334155';
        mdGraphvizSplitter.style.borderTop = 'none';
        mdGraphvizSplitter.style.borderBottom = 'none';
        mdGraphvizSplitter.style.order = '2';
      }
    }

    if (mdGraphvizSplitterGrip) {
      mdGraphvizSplitterGrip.className = isStacked ? 'fas fa-grip-lines' : 'fas fa-grip-vertical';
    }

    if (mdGraphvizSourcePane) {
      mdGraphvizSourcePane.style.order = isStacked ? '3' : '1';
    }
    if (mdGraphvizPreviewPane) {
      mdGraphvizPreviewPane.style.order = isStacked ? '1' : '3';
    }

    applyGraphvizPaneSizes();

    if (mdGraphvizLayoutSide) {
      mdGraphvizLayoutSide.style.background = isStacked ? 'transparent' : '#0284c7';
      mdGraphvizLayoutSide.style.color = isStacked ? '#94a3b8' : '#ffffff';
      mdGraphvizLayoutSide.style.fontWeight = isStacked ? '400' : '600';
    }
    if (mdGraphvizLayoutStack) {
      mdGraphvizLayoutStack.style.background = isStacked ? '#0284c7' : 'transparent';
      mdGraphvizLayoutStack.style.color = isStacked ? '#ffffff' : '#94a3b8';
      mdGraphvizLayoutStack.style.fontWeight = isStacked ? '600' : '400';
    }

    setTimeout(() => {
      if (mdGraphvizCodeEditor) {
        mdGraphvizCodeEditor.refresh();
      }
      if (mdGraphvizPreviewImg && mdGraphvizPreviewImg.style.display !== 'none') {
        fitGraphvizToView();
      }
    }, 35);
  }

  function resetGraphvizView() {
    mdGraphvizScale = 1;
    if (mdGraphvizPreview && mdGraphvizPreviewImg) {
      const nw = mdGraphvizPreviewImg.naturalWidth || 0;
      const nh = mdGraphvizPreviewImg.naturalHeight || 0;
      mdGraphvizPanX = nw ? (mdGraphvizPreview.clientWidth - nw) / 2 : 0;
      mdGraphvizPanY = nh ? (mdGraphvizPreview.clientHeight - nh) / 2 : 0;
    } else {
      mdGraphvizPanX = 0;
      mdGraphvizPanY = 0;
    }
    applyGraphvizTransform();
  }

  function fitGraphvizToView() {
    if (!mdGraphvizPreview || !mdGraphvizPreviewImg) return;
    const nw = mdGraphvizPreviewImg.naturalWidth;
    const nh = mdGraphvizPreviewImg.naturalHeight;
    if (!nw || !nh) return;

    const cw = mdGraphvizPreview.clientWidth - 24;
    const ch = mdGraphvizPreview.clientHeight - 24;
    if (cw <= 0 || ch <= 0) return;

    const scale = Math.min(8, Math.max(0.1, Math.min(cw / nw, ch / nh)));
    mdGraphvizScale = scale;
    mdGraphvizPanX = (mdGraphvizPreview.clientWidth - nw * scale) / 2;
    mdGraphvizPanY = (mdGraphvizPreview.clientHeight - nh * scale) / 2;
    applyGraphvizTransform();
  }

  function zoomGraphvizAt(clientX, clientY, factor) {
    if (!mdGraphvizPreview || !mdGraphvizPreviewImg) return;
    const rect = mdGraphvizPreview.getBoundingClientRect();
    const cx = clientX - rect.left;
    const cy = clientY - rect.top;
    const previous = mdGraphvizScale;
    const next = Math.min(8, Math.max(0.1, previous * factor));
    if (next === previous) return;

    mdGraphvizPanX = cx - (cx - mdGraphvizPanX) * (next / previous);
    mdGraphvizPanY = cy - (cy - mdGraphvizPanY) * (next / previous);
    mdGraphvizScale = next;
    applyGraphvizTransform();
  }

  function zoomGraphvizBy(factor) {
    if (!mdGraphvizPreview) return;
    const rect = mdGraphvizPreview.getBoundingClientRect();
    zoomGraphvizAt(rect.left + rect.width / 2, rect.top + rect.height / 2, factor);
  }

  function setGraphvizPreview(svgText) {
    if (mdGraphvizPreviewUrl) {
      URL.revokeObjectURL(mdGraphvizPreviewUrl);
      mdGraphvizPreviewUrl = null;
    }
    mdGraphvizCurrentSvg = svgText || '';
    if (!mdGraphvizPreviewImg) return;
    if (!svgText) {
      mdGraphvizPreviewImg.style.display = 'none';
      mdGraphvizPreviewImg.removeAttribute('src');
      if (mdGraphvizPreviewEmpty) mdGraphvizPreviewEmpty.style.display = 'flex';
      return;
    }
    const shouldFit = mdGraphvizPendingFit;
    mdGraphvizPendingFit = false;
    mdGraphvizPreviewUrl = URL.createObjectURL(new Blob([svgText], { type: 'image/svg+xml' }));
    mdGraphvizPreviewImg.onload = () => {
      if (shouldFit) {
        fitGraphvizToView();
      } else {
        applyGraphvizTransform();
      }
    };
    mdGraphvizPreviewImg.src = mdGraphvizPreviewUrl;
    mdGraphvizPreviewImg.style.display = 'block';
    if (mdGraphvizPreviewEmpty) mdGraphvizPreviewEmpty.style.display = 'none';
  }

  function scheduleGraphvizPreview() {
    clearTimeout(mdGraphvizDebounceTimer);
    mdGraphvizDebounceTimer = setTimeout(() => {
      if (!mdGraphvizModal || mdGraphvizModal.style.display !== 'block') return;
      const currentVal = getGraphvizEditorValue();
      if (!currentVal.trim()) {
        mdGraphvizRenderSeq += 1;
        setGraphvizError('');
        setGraphvizPreview(null);
        if (mdGraphvizStatus) mdGraphvizStatus.textContent = '';
        return;
      }
      renderGraphviz({ silent: true });
    }, 400);
  }

  function isDiagramReferencedInActiveNote(base, filename) {
    const cm = getMdEditor();
    const text = cm ? cm.getValue() : (mdTextarea ? mdTextarea.value : '');
    if (!text) return false;
    if (filename && text.includes(filename)) return true;
    if (base && (text.includes(`${base}.svg`) || text.includes(`${base}.png`))) return true;
    return false;
  }

  function loadGraphvizSources(selectedBase = '') {
    if (!mdGraphvizExisting) return Promise.resolve();
    const activeWalkthrough = getActiveWalkthrough();
    return fetch(`/walkthroughs/${encodeURIComponent(activeWalkthrough || '')}/graphviz/sources`, {
      credentials: 'same-origin'
    })
    .then(res => res.json())
    .then(list => {
      if (!Array.isArray(list)) return;
      cachedDiagramBases = new Set(list.map(item => item && item.base).filter(Boolean));
      if (window.CtlabsWalkthrough) {
        window.CtlabsWalkthrough.cachedDiagramBases = cachedDiagramBases;
      }
      const current = selectedBase || mdGraphvizExisting.value || '';
      mdGraphvizExisting.innerHTML = '';
      const blank = document.createElement('option');
      blank.value = '';
      blank.textContent = 'New diagram';
      mdGraphvizExisting.appendChild(blank);
      list.forEach(item => {
        if (!item || !item.base) return;
        const opt = document.createElement('option');
        opt.value = item.base;
        opt.textContent = item.base;
        mdGraphvizExisting.appendChild(opt);
      });
      if (current) mdGraphvizExisting.value = current;
    })
    .catch(() => {});
  }

  function loadGraphvizSource(base) {
    if (!base) {
      setGraphvizError('');
      mdGraphvizPendingFit = true;
      setGraphvizPreview(null);
      if (mdGraphvizDeleteBtn) mdGraphvizDeleteBtn.style.display = 'none';
      if (mdGraphvizSaveNewBtn) mdGraphvizSaveNewBtn.style.display = 'none';
      if (mdGraphvizInsertText) mdGraphvizInsertText.textContent = 'Save & Insert';
      if (mdGraphvizInsertIcon) mdGraphvizInsertIcon.className = 'fas fa-plus';
      if (mdGraphvizStatus) mdGraphvizStatus.textContent = '';
      return Promise.resolve();
    }
    if (mdGraphvizStatus) mdGraphvizStatus.textContent = 'Loading…';
    const activeWalkthrough = getActiveWalkthrough();
    return fetch(`/walkthroughs/${encodeURIComponent(activeWalkthrough || '')}/graphviz/sources/${encodeURIComponent(base)}`, {
      credentials: 'same-origin'
    })
    .then(res => res.json())
    .then(data => {
      if (data.ok && typeof data.source === 'string') {
        setGraphvizEditorValue(data.source);
        if (mdGraphvizName) mdGraphvizName.value = base;
        if (mdGraphvizExisting) mdGraphvizExisting.value = base;
        if (mdGraphvizDeleteBtn) mdGraphvizDeleteBtn.style.display = 'inline-flex';
        if (mdGraphvizSaveNewBtn) mdGraphvizSaveNewBtn.style.display = 'inline-flex';

        const isReferenced = isDiagramReferencedInActiveNote(base, `${base}.svg`);
        if (mdGraphvizInsertText) mdGraphvizInsertText.textContent = isReferenced ? 'Save Changes' : 'Save & Insert';
        if (mdGraphvizInsertIcon) mdGraphvizInsertIcon.className = isReferenced ? 'fas fa-save' : 'fas fa-plus';

        setGraphvizError('');
        mdGraphvizPendingFit = true;
        setGraphvizPreview(null);
        if (mdGraphvizStatus) mdGraphvizStatus.textContent = `Loaded ${base}`;
        return renderGraphviz({ silent: true });
      } else {
        setGraphvizError(data.error || 'Could not load diagram.');
        if (mdGraphvizStatus) mdGraphvizStatus.textContent = '';
      }
    })
    .catch(err => {
      setGraphvizError('Load failed: ' + (err.message || 'network error'));
      if (mdGraphvizStatus) mdGraphvizStatus.textContent = '';
    });
  }

  function renderGraphviz(options = {}) {
    const silent = !!options.silent;
    const source = getGraphvizEditorValue();
    if (!source.trim()) {
      if (!silent) setGraphvizError('Enter some DOT source first.');
      return Promise.resolve(false);
    }

    const engine = (mdGraphvizEngine && mdGraphvizEngine.value) || 'dot';
    const seq = ++mdGraphvizRenderSeq;
    setGraphvizError('');
    if (!silent) {
      if (mdGraphvizRenderBtn) mdGraphvizRenderBtn.disabled = true;
      if (mdGraphvizStatus) mdGraphvizStatus.textContent = 'Rendering…';
    }

    const activeWalkthrough = getActiveWalkthrough();
    const body = new URLSearchParams();
    body.set('source', source);
    body.set('engine', engine);
    body.set('walkthrough', activeWalkthrough || '');

    return fetch('/recordings/graphviz/preview', {
      method: 'POST',
      credentials: 'same-origin',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded;charset=UTF-8' },
      body
    })
    .then(res => res.json())
    .then(data => {
      if (seq !== mdGraphvizRenderSeq) return false;
      if (data.ok && data.svg) {
        setGraphvizPreview(data.svg);
        if (data.dot) {
          mdGraphvizLastDot = data.dot;
          updateGraphvizDotDisplay();
        }
        if (!silent && mdGraphvizStatus) mdGraphvizStatus.textContent = 'Preview ready';
        return true;
      }
      setGraphvizError(data.error || 'Failed to render diagram.');
      if (!silent) setGraphvizPreview(null);
      if (mdGraphvizStatus) mdGraphvizStatus.textContent = '';
      return false;
    })
    .catch(err => {
      if (seq !== mdGraphvizRenderSeq) return false;
      setGraphvizError('Render failed: ' + (err.message || 'network error'));
      if (!silent) setGraphvizPreview(null);
      if (mdGraphvizStatus) mdGraphvizStatus.textContent = '';
      return false;
    })
    .finally(() => {
      if (!silent && mdGraphvizRenderBtn) mdGraphvizRenderBtn.disabled = false;
    });
  }

  function saveAndInsertGraphviz(options = {}) {
    const saveAsNew = !!options.saveAsNew;
    const closeAfter = !!options.closeAfter;
    const source = getGraphvizEditorValue();
    if (!source.trim()) {
      setGraphvizError('Enter some DOT source first.');
      return;
    }

    let name = (mdGraphvizName && mdGraphvizName.value.trim()) || 'diagram';
    let base = saveAsNew ? '' : ((mdGraphvizExisting && mdGraphvizExisting.value) || '');
    if (base && name && name !== base) {
      base = name;
    }
    const engine = (mdGraphvizEngine && mdGraphvizEngine.value) || 'dot';

    if (saveAsNew && mdGraphvizExisting && mdGraphvizExisting.value) {
      if (name === mdGraphvizExisting.value) {
        name = `${name}-copy`;
      }
    }

    setGraphvizError('');
    if (mdGraphvizInsertBtn) mdGraphvizInsertBtn.disabled = true;
    if (mdGraphvizSaveNewBtn) mdGraphvizSaveNewBtn.disabled = true;
    if (mdGraphvizStatus) mdGraphvizStatus.textContent = 'Saving…';

    const activeWalkthrough = getActiveWalkthrough();
    const body = new URLSearchParams();
    body.set('source', source);
    body.set('name', name);
    body.set('format', 'svg');
    body.set('engine', engine);
    body.set('walkthrough', activeWalkthrough || '');
    if (base) body.set('base', base);

    fetch('/recordings/graphviz', {
      method: 'POST',
      credentials: 'same-origin',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded;charset=UTF-8' },
      body
    })
    .then(res => res.json())
    .then(data => {
      if (!data.ok || !data.url) {
        setGraphvizError(data.error || 'Failed to save diagram.');
        if (mdGraphvizStatus) mdGraphvizStatus.textContent = '';
        return;
      }

      cachedDiagramBases.add(data.base);
      if (window.CtlabsWalkthrough && window.CtlabsWalkthrough.cachedDiagramBases) {
        window.CtlabsWalkthrough.cachedDiagramBases.add(data.base);
      }

      const cm = getMdEditor();
      const noteText = cm ? cm.getValue() : (mdTextarea ? mdTextarea.value : '');
      const alreadyReferenced = !saveAsNew && (
        noteText.includes(data.filename) ||
        (base && (noteText.includes(`${base}.svg`) || noteText.includes(`${base}.png`)))
      );

      if (alreadyReferenced) {
        if (mdPreviewPane) {
          const previewImgs = mdPreviewPane.querySelectorAll('img');
          previewImgs.forEach(img => {
            if (img.src && (img.src.includes(data.filename) || (base && img.src.includes(base)))) {
              const baseSrc = img.src.split('?')[0];
              img.src = `${baseSrc}?t=${Date.now()}`;
            }
          });
        }
      } else {
        insertMarkdownBlock(`![${name}](${data.url})`, cm ? cm.getCursor() : null);
      }

      if (data.base) {
        if (mdGraphvizExisting) mdGraphvizExisting.value = data.base;
        if (mdGraphvizName) mdGraphvizName.value = data.base;
        if (mdGraphvizDeleteBtn) mdGraphvizDeleteBtn.style.display = 'inline-flex';
        if (mdGraphvizSaveNewBtn) mdGraphvizSaveNewBtn.style.display = 'inline-flex';
        if (mdGraphvizInsertText) mdGraphvizInsertText.textContent = 'Save & Update';
        if (mdGraphvizInsertIcon) mdGraphvizInsertIcon.className = 'fas fa-save';
        loadGraphvizSources(data.base);
      }

      if (data.dot) {
        mdGraphvizLastDot = data.dot;
        updateGraphvizDotDisplay();
      }

      const timeStr = new Date().toLocaleTimeString([], { hour: '2-digit', minute: '2-digit', second: '2-digit' });
      if (mdGraphvizStatus) {
        mdGraphvizStatus.textContent = `Saved (${timeStr})`;
        mdGraphvizStatus.style.color = '#38bdf8';
      }

      renderGraphviz({ silent: true });

      if (closeAfter && mdGraphvizModal) {
        mdGraphvizModal.style.display = 'none';
        if (mdGraphvizStatus) mdGraphvizStatus.textContent = '';
      } else {
        if (mdGraphvizCodeEditor && typeof mdGraphvizCodeEditor.focus === 'function') {
          mdGraphvizCodeEditor.focus();
        } else if (mdGraphvizSource && typeof mdGraphvizSource.focus === 'function') {
          mdGraphvizSource.focus();
        }
      }
    })
    .catch(err => {
      setGraphvizError('Save failed: ' + (err.message || 'network error'));
      if (mdGraphvizStatus) mdGraphvizStatus.textContent = '';
    })
    .finally(() => {
      if (mdGraphvizInsertBtn) mdGraphvizInsertBtn.disabled = false;
      if (mdGraphvizSaveNewBtn) mdGraphvizSaveNewBtn.disabled = false;
    });
  }

  function deleteGraphvizDiagram() {
    const base = mdGraphvizExisting ? mdGraphvizExisting.value : '';
    if (!base) return;

    if (!confirm(`Delete diagram "${base}"? This will remove the source DOT file and the rendered image.`)) {
      return;
    }

    setGraphvizError('');
    if (mdGraphvizDeleteBtn) mdGraphvizDeleteBtn.disabled = true;
    if (mdGraphvizStatus) mdGraphvizStatus.textContent = 'Deleting…';

    const activeWalkthrough = getActiveWalkthrough();
    fetch(`/walkthroughs/${encodeURIComponent(activeWalkthrough || '')}/graphviz/sources/${encodeURIComponent(base)}/delete`, {
      method: 'POST',
      credentials: 'same-origin'
    })
    .then(res => res.json())
    .then(data => {
      if (!data.ok) {
        setGraphvizError(data.error || 'Failed to delete diagram.');
        if (mdGraphvizStatus) mdGraphvizStatus.textContent = '';
        return;
      }

      cachedDiagramBases.delete(base);
      if (window.CtlabsWalkthrough && window.CtlabsWalkthrough.cachedDiagramBases) {
        window.CtlabsWalkthrough.cachedDiagramBases.delete(base);
      }
      if (mdGraphvizExisting) mdGraphvizExisting.value = '';
      if (mdGraphvizName) mdGraphvizName.value = '';
      setGraphvizEditorValue(MD_GRAPHVIZ_DEFAULT);
      if (mdGraphvizDeleteBtn) mdGraphvizDeleteBtn.style.display = 'none';
      if (mdGraphvizSaveNewBtn) mdGraphvizSaveNewBtn.style.display = 'none';
      if (mdGraphvizInsertText) mdGraphvizInsertText.textContent = 'Save & Insert';
      if (mdGraphvizInsertIcon) mdGraphvizInsertIcon.className = 'fas fa-plus';
      if (mdGraphvizStatus) mdGraphvizStatus.textContent = `Deleted ${base}`;

      loadGraphvizSources();
      renderGraphviz({ silent: true });
    })
    .catch(err => {
      setGraphvizError('Delete failed: ' + (err.message || 'network error'));
      if (mdGraphvizStatus) mdGraphvizStatus.textContent = '';
    })
    .finally(() => {
      if (mdGraphvizDeleteBtn) mdGraphvizDeleteBtn.disabled = false;
    });
  }

  function downloadGraphvizSvg() {
    if (!mdGraphvizCurrentSvg) {
      setGraphvizError('No diagram to download. Render your DOT source first.');
      return;
    }
    const name = (mdGraphvizName && mdGraphvizName.value.trim()) || 'diagram';
    const blob = new Blob([mdGraphvizCurrentSvg], { type: 'image/svg+xml;charset=utf-8' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = `${name}.svg`;
    document.body.appendChild(a);
    a.click();
    document.body.removeChild(a);
    setTimeout(() => URL.revokeObjectURL(url), 1000);
  }

  function openGraphvizModal(initialBase = '') {
    if (!mdGraphvizModal) return;
    if (currentMdMode === 'preview') setMdMode('split');
    clearTimeout(mdGraphvizDebounceTimer);
    mdGraphvizRenderSeq += 1;
    setGraphvizError('');
    mdGraphvizPendingFit = true;
    mdGraphvizScale = 1;
    mdGraphvizPanX = 0;
    mdGraphvizPanY = 0;
    setGraphvizPreview(null);
    setGraphvizActiveTab('source');
    if (mdGraphvizBlocksMenu) mdGraphvizBlocksMenu.style.display = 'none';
    if (mdGraphvizEmojiMenu) mdGraphvizEmojiMenu.style.display = 'none';
    if (mdGraphvizSettingsMenu) mdGraphvizSettingsMenu.style.display = 'none';
    fetchGlobalCustomBlocks();

    if (initialBase) {
      if (mdGraphvizName) mdGraphvizName.value = initialBase;
      if (mdGraphvizExisting) mdGraphvizExisting.value = initialBase;
      if (mdGraphvizDeleteBtn) mdGraphvizDeleteBtn.style.display = 'inline-flex';
      if (mdGraphvizSaveNewBtn) mdGraphvizSaveNewBtn.style.display = 'inline-flex';
    } else {
      if (!getGraphvizEditorValue().trim()) {
        setGraphvizEditorValue(MD_GRAPHVIZ_DEFAULT);
      }
      if (mdGraphvizName) mdGraphvizName.value = '';
      if (mdGraphvizExisting) mdGraphvizExisting.value = '';
      if (mdGraphvizDeleteBtn) mdGraphvizDeleteBtn.style.display = 'none';
      if (mdGraphvizSaveNewBtn) mdGraphvizSaveNewBtn.style.display = 'none';
      if (mdGraphvizInsertText) mdGraphvizInsertText.textContent = 'Save & Insert';
      if (mdGraphvizInsertIcon) mdGraphvizInsertIcon.className = 'fas fa-plus';
    }

    if (mdGraphvizStatus) mdGraphvizStatus.textContent = '';
    mdGraphvizModal.style.display = 'block';
    setGraphvizLayout(mdGraphvizLayout);
    setGraphvizPreviewBg(mdGraphvizBg);
    setGraphvizLineWrap(mdGraphvizLineWrap);
    setGraphvizVimMode(mdGraphvizVimMode);
    applyGraphvizTransform();

    initGraphvizCodeEditor();
    applyGraphvizEditorFont();

    setTimeout(() => {
      if (mdGraphvizCodeEditor) {
        mdGraphvizCodeEditor.refresh();
        mdGraphvizCodeEditor.focus();
      } else if (mdGraphvizSource) {
        mdGraphvizSource.focus();
      }
    }, 40);

    loadGraphvizSources(initialBase).then(() => {
      if (initialBase) {
        loadGraphvizSource(initialBase);
      } else {
        const val = getGraphvizEditorValue();
        if (val.trim()) {
          renderGraphviz({ silent: true });
        }
      }
    });
  }

  function handleGraphvizSourceKeydown(e) {
    if (e.key === 'Tab') {
      e.preventDefault();
      const ta = mdGraphvizSource;
      if (!ta) return;
      const start = ta.selectionStart;
      const end = ta.selectionEnd;
      const val = ta.value;

      if (e.shiftKey) {
        const lineStart = val.lastIndexOf('\n', start - 1) + 1;
        const lineEnd = val.indexOf('\n', end);
        const selLines = val.substring(lineStart, lineEnd === -1 ? val.length : lineEnd);
        const unindented = selLines.replace(/^(  | )/gm, '');
        ta.setRangeText(unindented, lineStart, lineEnd === -1 ? val.length : lineEnd, 'select');
      } else {
        if (start !== end) {
          const lineStart = val.lastIndexOf('\n', start - 1) + 1;
          const lineEnd = val.indexOf('\n', end);
          const selLines = val.substring(lineStart, lineEnd === -1 ? val.length : lineEnd);
          const indented = selLines.replace(/^/gm, '  ');
          ta.setRangeText(indented, lineStart, lineEnd === -1 ? val.length : lineEnd, 'select');
        } else {
          ta.setRangeText('  ', start, end, 'end');
        }
      }
      scheduleGraphvizPreview();
      return;
    }

    if ((e.ctrlKey || e.metaKey) && e.key === 's') {
      e.preventDefault();
      saveAndInsertGraphviz({ saveAsNew: false, closeAfter: false });
      return;
    }

    if ((e.ctrlKey || e.metaKey) && e.key.toLowerCase() === 'e') {
      e.preventDefault();
      toggleGraphvizEmojiMenu();
      return;
    }

    if ((e.ctrlKey || e.metaKey) && e.key === 'Enter') {
      e.preventDefault();
      renderGraphviz();
      return;
    }
  }

  function setupGraphvizEditor() {
    if (mdGraphvizBtn) {
      mdGraphvizBtn.addEventListener('click', () => openGraphvizModal());
    }
    if (mdGraphvizTabSource) {
      mdGraphvizTabSource.addEventListener('click', () => setGraphvizActiveTab('source'));
    }
    if (mdGraphvizTabDot) {
      mdGraphvizTabDot.addEventListener('click', () => setGraphvizActiveTab('dot'));
    }
    if (mdGraphvizBlocksBtn && mdGraphvizBlocksMenu) {
      mdGraphvizBlocksBtn.addEventListener('click', (e) => {
        e.stopPropagation();
        if (mdGraphvizEmojiMenu) mdGraphvizEmojiMenu.style.display = 'none';
        if (mdGraphvizSettingsMenu) mdGraphvizSettingsMenu.style.display = 'none';
        const isOpen = mdGraphvizBlocksMenu.style.display === 'block';
        if (!isOpen) {
          renderGraphvizBlocksMenu();
          mdGraphvizBlocksMenu.style.display = 'block';
        } else {
          mdGraphvizBlocksMenu.style.display = 'none';
        }
      });

      document.addEventListener('click', (e) => {
        if (mdGraphvizBlocksMenu && !mdGraphvizBlocksMenu.contains(e.target) && e.target !== mdGraphvizBlocksBtn && !mdGraphvizBlocksBtn.contains(e.target)) {
          mdGraphvizBlocksMenu.style.display = 'none';
        }
      });

      mdGraphvizBlocksMenu.addEventListener('click', (e) => {
        const item = e.target.closest('.md-gv-snippet-item');
        if (item && item.dataset.snippet) {
          e.preventDefault();
          e.stopPropagation();
          insertGraphvizSnippet(item.dataset.snippet);
        }
      });
    }

    if (mdGraphvizSettingsBtn && mdGraphvizSettingsMenu) {
      mdGraphvizSettingsBtn.addEventListener('click', (e) => {
        e.stopPropagation();
        toggleGraphvizSettingsMenu();
      });

      document.addEventListener('click', (e) => {
        if (mdGraphvizSettingsMenu && mdGraphvizSettingsMenu.style.display !== 'none') {
          if (!mdGraphvizSettingsMenu.contains(e.target) && e.target !== mdGraphvizSettingsBtn && !mdGraphvizSettingsBtn.contains(e.target)) {
            toggleGraphvizSettingsMenu(false);
          }
        }
      });
    }

    if (mdGraphvizSettingWrapCheckbox) {
      mdGraphvizSettingWrapCheckbox.addEventListener('change', (e) => {
        setGraphvizLineWrap(e.target.checked);
      });
    }

    if (mdGraphvizSettingVimCheckbox) {
      mdGraphvizSettingVimCheckbox.addEventListener('change', (e) => {
        setGraphvizVimMode(e.target.checked);
      });
    }

    if (mdGraphvizBlockModalClose) {
      mdGraphvizBlockModalClose.addEventListener('click', closeCustomBlockModal);
    }
    if (mdGraphvizBlockCancelBtn) {
      mdGraphvizBlockCancelBtn.addEventListener('click', closeCustomBlockModal);
    }
    if (mdGraphvizBlockSaveBtn) {
      mdGraphvizBlockSaveBtn.addEventListener('click', saveCustomBlockGlobally);
    }
    if (mdGraphvizBlockModal) {
      mdGraphvizBlockModal.addEventListener('click', (e) => {
        if (e.target === mdGraphvizBlockModal) closeCustomBlockModal();
      });
    }

    if (mdGraphvizEmojiBtn && mdGraphvizEmojiMenu) {
      mdGraphvizEmojiBtn.addEventListener('click', (e) => {
        e.stopPropagation();
        if (mdGraphvizBlocksMenu) mdGraphvizBlocksMenu.style.display = 'none';
        toggleGraphvizEmojiMenu();
      });

      if (mdGraphvizEmojiSearch) {
        mdGraphvizEmojiSearch.addEventListener('input', () => {
          const val = mdGraphvizEmojiSearch.value;
          if (mdGraphvizEmojiSearchClear) mdGraphvizEmojiSearchClear.style.display = val ? 'inline-block' : 'none';
          const activeTab = document.querySelector('.md-gv-emoji-cat-btn.active');
          const cat = activeTab ? activeTab.getAttribute('data-cat') : 'all';
          renderGraphvizEmojiGrid(cat, val);
        });
      }

      if (mdGraphvizEmojiSearchClear) {
        mdGraphvizEmojiSearchClear.addEventListener('click', () => {
          if (mdGraphvizEmojiSearch) {
            mdGraphvizEmojiSearch.value = '';
            mdGraphvizEmojiSearch.focus();
          }
          mdGraphvizEmojiSearchClear.style.display = 'none';
          const activeTab = document.querySelector('.md-gv-emoji-cat-btn.active');
          const cat = activeTab ? activeTab.getAttribute('data-cat') : 'all';
          renderGraphvizEmojiGrid(cat, '');
        });
      }

      mdGraphvizEmojiCatBtns.forEach(btn => {
        btn.addEventListener('click', () => {
          mdGraphvizEmojiCatBtns.forEach(b => {
            b.classList.remove('active');
            b.style.background = 'transparent';
            b.style.color = '#94a3b8';
          });
          btn.classList.add('active');
          btn.style.background = '#0284c7';
          btn.style.color = '#fff';
          const cat = btn.getAttribute('data-cat') || 'all';
          const query = mdGraphvizEmojiSearch ? mdGraphvizEmojiSearch.value : '';
          renderGraphvizEmojiGrid(cat, query);
        });
      });

      document.addEventListener('click', (e) => {
        if (mdGraphvizEmojiMenu && mdGraphvizEmojiMenu.style.display !== 'none') {
          if (!mdGraphvizEmojiMenu.contains(e.target) && e.target !== mdGraphvizEmojiBtn && !mdGraphvizEmojiBtn.contains(e.target)) {
            toggleGraphvizEmojiMenu(false);
          }
        }
      });
    }
    if (mdGraphvizDotUseBtn) {
      mdGraphvizDotUseBtn.addEventListener('click', () => {
        const text = mdGraphvizLastDot || (mdGraphvizDotOutput ? mdGraphvizDotOutput.textContent : '');
        if (!text || !text.trim() || text.trim().startsWith('//')) {
          setGraphvizError('No compiled DOT code available yet. Click Render first.');
          return;
        }

        const currentSource = getGraphvizEditorValue();
        if (currentSource.includes('<%')) {
          if (!confirm('Replace your ERB template with the compiled DOT code? You will be editing static DOT from now on.')) {
            return;
          }
        }

        setGraphvizEditorValue(text);
        setGraphvizActiveTab('source');
        if (mdGraphvizStatus) {
          mdGraphvizStatus.textContent = 'Switched to editable DOT';
          mdGraphvizStatus.style.color = '#38bdf8';
        }
        renderGraphviz({ silent: true });
        if (mdGraphvizCodeEditor) {
          mdGraphvizCodeEditor.focus();
        } else if (mdGraphvizSource) {
          mdGraphvizSource.focus();
        }
      });
    }
    if (mdGraphvizDotCopyBtn) {
      mdGraphvizDotCopyBtn.addEventListener('click', () => {
        const text = mdGraphvizLastDot || (mdGraphvizDotOutput ? mdGraphvizDotOutput.textContent : '');
        if (!text) return;
        if (navigator.clipboard && navigator.clipboard.writeText) {
          navigator.clipboard.writeText(text).then(() => {
            if (mdGraphvizDotCopyText) {
              const old = mdGraphvizDotCopyText.textContent;
              mdGraphvizDotCopyText.textContent = 'Copied!';
              setTimeout(() => { mdGraphvizDotCopyText.textContent = old; }, 1500);
            }
          }).catch(() => {});
        }
      });
    }
    if (mdGraphvizExisting) {
      mdGraphvizExisting.addEventListener('change', () => {
        loadGraphvizSource(mdGraphvizExisting.value);
      });
    }
    if (mdGraphvizEngine) {
      mdGraphvizEngine.addEventListener('change', () => {
        const currentVal = getGraphvizEditorValue();
        if (currentVal.trim()) {
          renderGraphviz();
        }
      });
    }
    if (mdGraphvizTemplate) {
      mdGraphvizTemplate.addEventListener('change', () => {
        const key = mdGraphvizTemplate.value;
        if (!key || !MD_GRAPHVIZ_TEMPLATES[key]) return;
        const templateSource = MD_GRAPHVIZ_TEMPLATES[key];

        const currentVal = getGraphvizEditorValue();
        if (currentVal.trim() && currentVal.trim() !== MD_GRAPHVIZ_DEFAULT.trim()) {
          if (!confirm('Replace current DOT source with this template?')) {
            mdGraphvizTemplate.value = '';
            return;
          }
        }

        setGraphvizEditorValue(templateSource);
        if (mdGraphvizName && (!mdGraphvizName.value.trim() || mdGraphvizName.value === 'diagram')) {
          mdGraphvizName.value = key;
        }
        mdGraphvizTemplate.value = '';
        renderGraphviz();
      });
    }
    if (mdGraphvizRenderBtn) {
      mdGraphvizRenderBtn.addEventListener('click', () => renderGraphviz());
    }
    if (mdGraphvizDownloadBtn) {
      mdGraphvizDownloadBtn.addEventListener('click', downloadGraphvizSvg);
    }
    if (mdGraphvizDeleteBtn) {
      mdGraphvizDeleteBtn.addEventListener('click', deleteGraphvizDiagram);
    }
    if (mdGraphvizSaveNewBtn) {
      mdGraphvizSaveNewBtn.addEventListener('click', () => saveAndInsertGraphviz({ saveAsNew: true }));
    }
    if (mdGraphvizInsertBtn) {
      mdGraphvizInsertBtn.addEventListener('click', () => saveAndInsertGraphviz({ saveAsNew: false }));
    }
    if (mdGraphvizModal) {
      mdGraphvizModal.addEventListener('keydown', (e) => {
        if (e.defaultPrevented) return;
        if ((e.ctrlKey || e.metaKey) && e.key === 's') {
          e.preventDefault();
          saveAndInsertGraphviz({ saveAsNew: false, closeAfter: false });
        } else if ((e.ctrlKey || e.metaKey) && e.key === 'Enter') {
          e.preventDefault();
          renderGraphviz();
        }
      });
    }
    if (mdGraphvizCloseBtn) {
      mdGraphvizCloseBtn.addEventListener('click', () => {
        clearTimeout(mdGraphvizDebounceTimer);
        if (mdGraphvizModal) mdGraphvizModal.style.display = 'none';
      });
    }
    if (mdGraphvizSource) {
      mdGraphvizSource.addEventListener('input', scheduleGraphvizPreview);
      mdGraphvizSource.addEventListener('keydown', handleGraphvizSourceKeydown);
    }

    if (mdGraphvizFontDec) {
      mdGraphvizFontDec.addEventListener('click', () => {
        if (mdGraphvizFontSize > 10) {
          mdGraphvizFontSize -= 1;
          try { localStorage.setItem('ctlabs_graphviz_font_size', mdGraphvizFontSize); } catch (e) {}
          applyGraphvizEditorFont();
        }
      });
    }
    if (mdGraphvizFontInc) {
      mdGraphvizFontInc.addEventListener('click', () => {
        if (mdGraphvizFontSize < 26) {
          mdGraphvizFontSize += 1;
          try { localStorage.setItem('ctlabs_graphviz_font_size', mdGraphvizFontSize); } catch (e) {}
          applyGraphvizEditorFont();
        }
      });
    }
    if (mdGraphvizFontFamily) {
      mdGraphvizFontFamily.addEventListener('change', () => {
        mdGraphvizFont = mdGraphvizFontFamily.value || 'courier';
        try { localStorage.setItem('ctlabs_graphviz_font_family', mdGraphvizFont); } catch (e) {}
        applyGraphvizEditorFont();
      });
    }

    if (mdGraphvizWrapBtn) {
      mdGraphvizWrapBtn.addEventListener('click', () => {
        setGraphvizLineWrap(!mdGraphvizLineWrap);
      });
    }
    if (mdGraphvizVimBtn) {
      mdGraphvizVimBtn.addEventListener('click', () => {
        setGraphvizVimMode(!mdGraphvizVimMode);
      });
    }

    if (mdGraphvizBgWhite) {
      mdGraphvizBgWhite.addEventListener('click', () => setGraphvizPreviewBg('white'));
    }
    if (mdGraphvizBgSlate) {
      mdGraphvizBgSlate.addEventListener('click', () => setGraphvizPreviewBg('slate'));
    }
    if (mdGraphvizBgChecker) {
      mdGraphvizBgChecker.addEventListener('click', () => setGraphvizPreviewBg('checker'));
    }
    if (mdGraphvizBgPicker) {
      mdGraphvizBgPicker.addEventListener('input', (e) => setGraphvizPreviewBg(e.target.value));
    }

    if (mdGraphvizZoomIn) {
      mdGraphvizZoomIn.addEventListener('click', () => zoomGraphvizBy(1.2));
    }
    if (mdGraphvizZoomOut) {
      mdGraphvizZoomOut.addEventListener('click', () => zoomGraphvizBy(1 / 1.2));
    }
    if (mdGraphvizZoomReset) {
      mdGraphvizZoomReset.addEventListener('click', resetGraphvizView);
    }
    if (mdGraphvizZoomFit) {
      mdGraphvizZoomFit.addEventListener('click', fitGraphvizToView);
    }
    if (mdGraphvizLayoutSide) {
      mdGraphvizLayoutSide.addEventListener('click', () => setGraphvizLayout('side'));
    }
    if (mdGraphvizLayoutStack) {
      mdGraphvizLayoutStack.addEventListener('click', () => setGraphvizLayout('stacked'));
    }

    if (mdGraphvizSplitter) {
      let isResizingGraphvizSplit = false;
      let graphvizSplitRaf = null;

      mdGraphvizSplitter.addEventListener('mouseenter', () => {
        if (!isResizingGraphvizSplit) {
          mdGraphvizSplitter.style.background = '#334155';
          if (mdGraphvizSplitterGrip) mdGraphvizSplitterGrip.style.color = '#38bdf8';
        }
      });

      mdGraphvizSplitter.addEventListener('mouseleave', () => {
        if (!isResizingGraphvizSplit) {
          mdGraphvizSplitter.style.background = '#1e293b';
          if (mdGraphvizSplitterGrip) mdGraphvizSplitterGrip.style.color = '#64748b';
        }
      });

      mdGraphvizSplitter.addEventListener('pointerdown', (e) => {
        if (e.button !== 0) return;
        isResizingGraphvizSplit = true;
        mdGraphvizSplitter.style.background = '#0284c7';
        if (mdGraphvizSplitterGrip) mdGraphvizSplitterGrip.style.color = '#ffffff';
        document.body.style.userSelect = 'none';
        document.body.style.cursor = mdGraphvizLayout === 'stacked' ? 'row-resize' : 'col-resize';
        if (mdGraphvizSplitter.setPointerCapture) {
          try { mdGraphvizSplitter.setPointerCapture(e.pointerId); } catch (err) {}
        }
        e.preventDefault();
      });

      mdGraphvizSplitter.addEventListener('pointermove', (e) => {
        if (!isResizingGraphvizSplit || !mdGraphvizSplitContainer) return;
        const rect = mdGraphvizSplitContainer.getBoundingClientRect();
        if (mdGraphvizLayout === 'stacked') {
          if (rect.height <= 0) return;
          const offsetY = e.clientY - rect.top;
          let pct = (offsetY / rect.height) * 100;
          const minPx = 120;
          const minPct = (minPx / rect.height) * 100;
          const clampedMin = Math.max(15, minPct);
          const clampedMax = Math.min(85, 100 - minPct);
          pct = Math.max(clampedMin, Math.min(clampedMax, pct));
          mdGraphvizSplitRow = Math.round(pct * 10) / 10;
          applyGraphvizPaneSizes();
        } else {
          if (rect.width <= 0) return;
          const offsetX = e.clientX - rect.left;
          let pct = (offsetX / rect.width) * 100;
          const minPx = 150;
          const minPct = (minPx / rect.width) * 100;
          const clampedMin = Math.max(15, minPct);
          const clampedMax = Math.min(85, 100 - minPct);
          pct = Math.max(clampedMin, Math.min(clampedMax, pct));
          mdGraphvizSplitCol = Math.round(pct * 10) / 10;
          applyGraphvizPaneSizes();
        }

        if (!graphvizSplitRaf) {
          graphvizSplitRaf = requestAnimationFrame(() => {
            graphvizSplitRaf = null;
            if (mdGraphvizPreviewImg && mdGraphvizPreviewImg.style.display !== 'none') {
              fitGraphvizToView();
            }
          });
        }
      });

      const stopGraphvizSplitResize = (e) => {
        if (!isResizingGraphvizSplit) return;
        isResizingGraphvizSplit = false;
        mdGraphvizSplitter.style.background = '#1e293b';
        if (mdGraphvizSplitterGrip) mdGraphvizSplitterGrip.style.color = '#64748b';
        document.body.style.userSelect = '';
        document.body.style.cursor = '';
        if (e && mdGraphvizSplitter.releasePointerCapture && e.pointerId !== undefined) {
          try { mdGraphvizSplitter.releasePointerCapture(e.pointerId); } catch (err) {}
        }
        try {
          if (mdGraphvizLayout === 'stacked') {
            localStorage.setItem('ctlabs_graphviz_split_row', mdGraphvizSplitRow);
          } else {
            localStorage.setItem('ctlabs_graphviz_split_col', mdGraphvizSplitCol);
          }
        } catch (err) {}
        if (mdGraphvizCodeEditor) {
          mdGraphvizCodeEditor.refresh();
        }
        if (mdGraphvizPreviewImg && mdGraphvizPreviewImg.style.display !== 'none') {
          fitGraphvizToView();
        }
      };

      mdGraphvizSplitter.addEventListener('pointerup', stopGraphvizSplitResize);
      mdGraphvizSplitter.addEventListener('pointercancel', stopGraphvizSplitResize);

      mdGraphvizSplitter.addEventListener('dblclick', () => {
        if (mdGraphvizLayout === 'stacked') {
          mdGraphvizSplitRow = 50;
          try { localStorage.setItem('ctlabs_graphviz_split_row', 50); } catch (err) {}
        } else {
          mdGraphvizSplitCol = 50;
          try { localStorage.setItem('ctlabs_graphviz_split_col', 50); } catch (err) {}
        }
        applyGraphvizPaneSizes();
        if (mdGraphvizCodeEditor) {
          mdGraphvizCodeEditor.refresh();
        }
        if (mdGraphvizPreviewImg && mdGraphvizPreviewImg.style.display !== 'none') {
          fitGraphvizToView();
        }
      });
    }

    if (mdGraphvizPreview) {
      mdGraphvizPreview.addEventListener('wheel', (e) => {
        if (!mdGraphvizPreviewImg || mdGraphvizPreviewImg.style.display === 'none') return;
        e.preventDefault();
        zoomGraphvizAt(e.clientX, e.clientY, e.deltaY < 0 ? 1.12 : (1 / 1.12));
      }, { passive: false });

      mdGraphvizPreview.addEventListener('pointerdown', (e) => {
        if (e.button !== 0) return;
        if (e.target.closest('button')) return;
        if (!mdGraphvizPreviewImg || mdGraphvizPreviewImg.style.display === 'none') return;
        mdGraphvizDragging = true;
        mdGraphvizDragStart = { x: e.clientX, y: e.clientY, panX: mdGraphvizPanX, panY: mdGraphvizPanY };
        mdGraphvizPreview.style.cursor = 'grabbing';
        if (mdGraphvizPreview.setPointerCapture) {
          try { mdGraphvizPreview.setPointerCapture(e.pointerId); } catch (err) {}
        }
        e.preventDefault();
      });

      mdGraphvizPreview.addEventListener('pointermove', (e) => {
        if (!mdGraphvizDragging || !mdGraphvizDragStart) return;
        mdGraphvizPanX = mdGraphvizDragStart.panX + (e.clientX - mdGraphvizDragStart.x);
        mdGraphvizPanY = mdGraphvizDragStart.panY + (e.clientY - mdGraphvizDragStart.y);
        applyGraphvizTransform();
      });

      const endGraphvizDrag = (e) => {
        if (!mdGraphvizDragging) return;
        mdGraphvizDragging = false;
        mdGraphvizDragStart = null;
        mdGraphvizPreview.style.cursor = 'grab';
        if (e && mdGraphvizPreview.releasePointerCapture && e.pointerId !== undefined) {
          try { mdGraphvizPreview.releasePointerCapture(e.pointerId); } catch (err) {}
        }
      };
      mdGraphvizPreview.addEventListener('pointerup', endGraphvizDrag);
      mdGraphvizPreview.addEventListener('pointercancel', endGraphvizDrag);
      mdGraphvizPreview.addEventListener('dblclick', (e) => {
        if (e.target.closest('button')) return;
        fitGraphvizToView();
      });
    }
  }

  // --- Git Version History Management ---
  let gitHistoryCurrentScope = { slug: null, path: null };
  let gitHistoryCommits = [];
  let gitHistorySelectedHash = null;
  let gitWorkingTreeChanges = [];

  function openGitHistoryModal(slug, path, focusCommit = false) {
    gitHistoryCurrentScope = {
      slug: (slug && slug.trim()) ? slug.trim() : null,
      path: (path && path.trim()) ? path.trim() : null
    };

    if (gitHistoryScopeBadge) {
      if (gitHistoryCurrentScope.path) {
        gitHistoryScopeBadge.textContent = 'Note: ' + gitHistoryCurrentScope.path.split('/').pop();
      } else if (gitHistoryCurrentScope.slug) {
        gitHistoryScopeBadge.textContent = 'Set: ' + gitHistoryCurrentScope.slug;
      } else {
        gitHistoryScopeBadge.textContent = 'Scope: All';
      }
    }

    if (gitHistoryModal) {
      gitHistoryModal.style.display = 'block';
    }
    if (gitSnapshotMsg) {
      if (focusCommit) {
        const title = getActiveNoteTitle();
        gitSnapshotMsg.value = title ? `Update note '${title}'` : '';
        setTimeout(() => gitSnapshotMsg.focus(), 100);
      } else {
        gitSnapshotMsg.value = '';
      }
    }
    loadGitHistory();
  }

  function promptAndCommitNote() {
    const activeId = getActiveId();
    const activeDataType = getActiveDataType();
    const wk = getActiveWalkthrough();
    if (!activeId || activeDataType !== 'markdown') return;

    // Save content to disk first if dirty
    if (mdIsDirty) {
      saveMarkdownContent(false);
    }

    const fileName = activeId + '.md';
    const filePath = (wk && wk !== 'default') ? (wk + '/' + fileName) : fileName;
    openGitHistoryModal(wk, filePath, true);
  }

  async function loadGitHistory() {
    const listEl = gitHistoryList || document.getElementById('git-history-list');
    const diffEl = gitDiffBody || document.getElementById('git-diff-body');
    const titleEl = gitDiffTitle || document.getElementById('git-diff-title');
    const metaEl = gitDiffMeta || document.getElementById('git-diff-meta');
    const actionsEl = gitDiffActions || document.getElementById('git-diff-actions');
    const workingBadge = gitWorkingTreeBadge || document.getElementById('git-working-tree-badge');

    if (listEl) listEl.innerHTML = '<div style="color: #64748b; font-size: 0.85em; text-align: center; padding: 20px;"><i class="fas fa-spinner fa-spin"></i> Loading revisions...</div>';
    gitHistorySelectedHash = null;
    if (titleEl) titleEl.textContent = 'Select a revision to view diff';
    if (metaEl) metaEl.textContent = '';
    if (actionsEl) actionsEl.style.display = 'none';
    if (workingBadge) workingBadge.style.display = 'none';
    if (diffEl) diffEl.innerHTML = '<span style="color: #64748b;">Select a commit from the list on the left to inspect file changes and unified diffs.</span>';

    try {
      // 1. Check Git Status for uncommitted changes
      let statusData = { clean: true, items: [] };
      try {
        const stRes = await fetch('/recordings/git/status', { credentials: 'same-origin' });
        statusData = await stRes.json();
      } catch (e) {}

      gitWorkingTreeChanges = [];
      if (statusData && Array.isArray(statusData.items)) {
        gitWorkingTreeChanges = statusData.items.filter(item => {
          if (!item || !item.file) return false;
          if (gitHistoryCurrentScope.path) {
            return item.file === gitHistoryCurrentScope.path || item.file.endsWith('/' + gitHistoryCurrentScope.path) || gitHistoryCurrentScope.path.endsWith('/' + item.file);
          }
          if (gitHistoryCurrentScope.slug && gitHistoryCurrentScope.slug !== 'default') {
            return item.file.startsWith(gitHistoryCurrentScope.slug + '/');
          }
          return true;
        });
      }

      if (workingBadge) {
        workingBadge.style.display = (gitWorkingTreeChanges.length > 0) ? 'inline-flex' : 'none';
      }

      // 2. Fetch commits log
      const params = new URLSearchParams();
      if (gitHistoryCurrentScope.slug) params.set('slug', gitHistoryCurrentScope.slug);
      if (gitHistoryCurrentScope.path) params.set('path', gitHistoryCurrentScope.path);
      params.set('limit', '50');

      const res = await fetch('/recordings/git/history?' + params.toString(), { credentials: 'same-origin' });
      const data = await res.json();
      gitHistoryCommits = (data && data.commits) ? data.commits : [];

      renderGitHistoryList();

      // If working tree has uncommitted changes, select it; otherwise select newest commit
      if (gitWorkingTreeChanges.length > 0) {
        await showGitDiff('working');
      } else if (gitHistoryCommits.length > 0) {
        await showGitDiff(gitHistoryCommits[0].hash);
      } else {
        if (listEl) listEl.innerHTML = '<div style="color: #94a3b8; font-size: 0.85em; text-align: center; padding: 20px;">No revisions found yet.</div>';
      }
    } catch (err) {
      console.error('Failed to load git history:', err);
      const msg = (err && err.message) ? err.message : String(err);
      if (listEl) listEl.innerHTML = `<div style="color: #ef4444; font-size: 0.85em; text-align: center; padding: 20px;">Error loading history: ${escapeHtml(msg)}</div>`;
    }
  }

  function renderGitHistoryList() {
    const listEl = gitHistoryList || document.getElementById('git-history-list');
    if (!listEl) return;
    listEl.innerHTML = '';

    // If there are uncommitted changes, render Working Tree item at top
    if (gitWorkingTreeChanges.length > 0) {
      const isSelected = (gitHistorySelectedHash === 'working');
      const item = document.createElement('div');
      item.className = 'git-commit-card';
      item.dataset.hash = 'working';
      item.style.cssText = `padding: 10px 12px; border-radius: 6px; background: ${isSelected ? '#1e293b' : '#131d31'}; border: 1px solid ${isSelected ? '#f59e0b' : '#78350f'}; cursor: pointer; transition: all 0.15s ease;`;

      item.innerHTML = `
        <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 4px;">
          <span style="font-size: 0.78em; color: #f59e0b; font-weight: 700; display: inline-flex; align-items: center; gap: 4px;">
            <i class="fas fa-pencil-alt"></i> Working Tree
          </span>
          <span style="font-size: 0.72em; color: #fde68a; background: #78350f; padding: 1px 6px; border-radius: 3px;">Uncommitted</span>
        </div>
        <div style="font-size: 0.84em; color: #f8fafc; font-weight: 500; margin-bottom: 4px;">
          Uncommitted changes (${gitWorkingTreeChanges.length} file${gitWorkingTreeChanges.length === 1 ? '' : 's'} modified)
        </div>
        <div style="font-size: 0.72em; color: #94a3b8;">
          Click to inspect diff and commit
        </div>
      `;

      item.addEventListener('click', () => showGitDiff('working'));
      listEl.appendChild(item);
    }

    gitHistoryCommits.forEach((commit) => {
      const item = document.createElement('div');
      item.className = 'git-commit-card';
      item.dataset.hash = commit.hash;
      const isSelected = (commit.hash === gitHistorySelectedHash);
      item.style.cssText = `padding: 10px 12px; border-radius: 6px; background: ${isSelected ? '#1e293b' : '#131d31'}; border: 1px solid ${isSelected ? '#0284c7' : '#334155'}; cursor: pointer; transition: all 0.15s ease;`;

      const headerRow = document.createElement('div');
      headerRow.style.cssText = 'display: flex; justify-content: space-between; align-items: center; margin-bottom: 4px;';

      const hashSpan = document.createElement('span');
      hashSpan.style.cssText = 'font-family: ui-monospace, monospace; font-size: 0.78em; color: #38bdf8; font-weight: 700;';
      hashSpan.textContent = commit.short_hash || commit.hash.substring(0, 7);

      const dateSpan = document.createElement('span');
      dateSpan.style.cssText = 'font-size: 0.72em; color: #94a3b8;';
      dateSpan.textContent = (commit.date || '').substring(0, 19);

      headerRow.appendChild(hashSpan);
      headerRow.appendChild(dateSpan);

      const msgDiv = document.createElement('div');
      msgDiv.style.cssText = 'font-size: 0.84em; color: #f8fafc; font-weight: 500; margin-bottom: 6px; word-break: break-word; line-height: 1.35;';
      msgDiv.textContent = commit.message || 'Commit ' + (commit.short_hash || '');

      const footerRow = document.createElement('div');
      footerRow.style.cssText = 'display: flex; justify-content: space-between; align-items: center; font-size: 0.72em; color: #64748b;';

      const authorSpan = document.createElement('span');
      authorSpan.textContent = commit.author || 'ctlabs';

      const countSpan = document.createElement('span');
      const fileCount = Array.isArray(commit.files) ? commit.files.length : 0;
      countSpan.textContent = fileCount + ' file' + (fileCount === 1 ? '' : 's');

      footerRow.appendChild(authorSpan);
      footerRow.appendChild(countSpan);

      item.appendChild(headerRow);
      item.appendChild(msgDiv);
      item.appendChild(footerRow);

      item.addEventListener('click', () => {
        showGitDiff(commit.hash);
      });

      listEl.appendChild(item);
    });
  }

  async function showGitDiff(hash) {
    gitHistorySelectedHash = hash;
    const listEl = gitHistoryList || document.getElementById('git-history-list');
    const diffEl = gitDiffBody || document.getElementById('git-diff-body');
    const titleEl = gitDiffTitle || document.getElementById('git-diff-title');
    const metaEl = gitDiffMeta || document.getElementById('git-diff-meta');
    const actionsEl = gitDiffActions || document.getElementById('git-diff-actions');
    const restoreBtn = gitRestoreBtn || document.getElementById('git-restore-btn');
    const discardBtn = gitDiscardBtn || document.getElementById('git-discard-btn');

    if (listEl) {
      listEl.querySelectorAll('.git-commit-card').forEach(c => {
        const isSel = (c.dataset.hash === hash);
        if (c.dataset.hash === 'working') {
          c.style.background = isSel ? '#1e293b' : '#131d31';
          c.style.borderColor = isSel ? '#f59e0b' : '#78350f';
        } else {
          c.style.background = isSel ? '#1e293b' : '#131d31';
          c.style.borderColor = isSel ? '#0284c7' : '#334155';
        }
      });
    }

    if (diffEl) diffEl.innerHTML = '<span style="color: #64748b;"><i class="fas fa-spinner fa-spin"></i> Loading diff...</span>';
    if (actionsEl) actionsEl.style.display = 'inline-flex';

    if (hash === 'working') {
      if (titleEl) titleEl.textContent = 'Uncommitted Changes (Working Tree vs HEAD)';
      if (metaEl) metaEl.textContent = `${gitWorkingTreeChanges.length} modified file${gitWorkingTreeChanges.length === 1 ? '' : 's'}`;
      if (restoreBtn) restoreBtn.style.display = 'none';
      if (discardBtn) discardBtn.style.display = 'inline-flex';

      try {
        const params = new URLSearchParams();
        if (gitHistoryCurrentScope.slug) params.set('slug', gitHistoryCurrentScope.slug);
        if (gitHistoryCurrentScope.path) params.set('path', gitHistoryCurrentScope.path);

        const res = await fetch('/recordings/git/diff/working?' + params.toString(), { credentials: 'same-origin' });
        const data = await res.json();
        if (!data.ok) throw new Error(data.error || 'Failed to inspect working tree diff');

        const diffText = (data.diff && data.diff.trim()) ? data.diff : (data.stat && data.stat.trim() ? data.stat : '');
        if (!diffText) {
          if (diffEl) diffEl.innerHTML = '<span style="color: #10b981;"><i class="fas fa-check-circle"></i> Working tree is clean. No uncommitted modifications.</span>';
        } else {
          if (diffEl) diffEl.innerHTML = formatGitDiff(diffText);
        }
      } catch (err) {
        console.error('Failed to load working tree diff:', err);
        const msg = (err && err.message) ? err.message : String(err);
        if (diffEl) diffEl.innerHTML = `<span style="color: #ef4444;">Error loading working tree diff: ${escapeHtml(msg)}</span>`;
      }
      return;
    }

    const commit = gitHistoryCommits.find(c => c.hash === hash || (c.short_hash && c.short_hash === hash));
    if (titleEl) titleEl.textContent = commit ? (commit.message || ('Revision ' + hash.substring(0, 7))) : ('Revision ' + hash.substring(0, 7));
    if (metaEl) {
      metaEl.textContent = commit
        ? `Commit ${commit.short_hash || commit.hash.substring(0, 7)} by ${commit.author || 'ctlabs'} on ${commit.date || ''}`
        : '';
    }
    if (restoreBtn) restoreBtn.style.display = 'inline-flex';
    if (discardBtn) discardBtn.style.display = 'none';

    try {
      const res = await fetch('/recordings/git/diff/' + encodeURIComponent(hash), { credentials: 'same-origin' });
      const data = await res.json();
      if (!data.ok) throw new Error(data.error || 'Failed to load diff');

      const diffText = (data.diff && data.diff.trim()) ? data.diff : (data.stat && data.stat.trim() ? data.stat : '');
      if (!diffText) {
        if (diffEl) diffEl.innerHTML = '<span style="color: #64748b;">(No text changes in this commit)</span>';
      } else {
        if (diffEl) diffEl.innerHTML = formatGitDiff(diffText);
      }
    } catch (err) {
      console.error('Failed to load diff:', err);
      const msg = (err && err.message) ? err.message : String(err);
      if (diffEl) diffEl.innerHTML = `<span style="color: #ef4444;">Error loading diff: ${escapeHtml(msg)}</span>`;
    }
  }

  function formatGitDiff(diffText) {
    if (!diffText) return '';
    const lines = diffText.split('\n');
    return lines.map(line => {
      let bg = 'transparent';
      let fg = '#cbd5e1';
      let weight = '400';

      if (line.startsWith('+++') || line.startsWith('---')) {
        fg = '#94a3b8';
        weight = '600';
      } else if (line.startsWith('+')) {
        bg = 'rgba(16, 185, 129, 0.2)';
        fg = '#86efac';
      } else if (line.startsWith('-')) {
        bg = 'rgba(239, 68, 68, 0.2)';
        fg = '#fca5a5';
      } else if (line.startsWith('@@')) {
        bg = 'rgba(56, 189, 248, 0.12)';
        fg = '#38bdf8';
        weight = '600';
      } else if (line.startsWith('diff --git') || line.startsWith('index ')) {
        fg = '#64748b';
        weight = '600';
      } else if (line.startsWith('commit ')) {
        fg = '#38bdf8';
        weight = '600';
      } else if (line.startsWith('Author:') || line.startsWith('Date:')) {
        fg = '#94a3b8';
      }

      const escaped = escapeHtml(line);
      const text = escaped.length > 0 ? escaped : '&nbsp;';
      return `<div style="background: ${bg}; color: ${fg}; font-weight: ${weight}; padding: 0 4px; border-radius: 2px; min-height: 1.45em; margin: 0; box-sizing: border-box;">${text}</div>`;
    }).join('');
  }

  async function createGitSnapshot() {
    let msg = (gitSnapshotMsg && gitSnapshotMsg.value.trim()) || '';
    if (!msg) {
      const title = getActiveNoteTitle();
      msg = title ? `Update note '${title}'` : `Update note (${new Date().toLocaleString()})`;
    }

    // Save note to disk first if dirty
    if (mdIsDirty) {
      saveMarkdownContent(false);
    }

    if (gitSnapshotBtn) {
      gitSnapshotBtn.disabled = true;
      gitSnapshotBtn.innerHTML = '<i class="fas fa-spinner fa-spin"></i> Committing...';
    }

    try {
      const fd = new FormData();
      fd.append('message', msg);
      if (gitHistoryCurrentScope.slug) fd.append('slug', gitHistoryCurrentScope.slug);
      if (gitHistoryCurrentScope.path) fd.append('path', gitHistoryCurrentScope.path);

      const res = await fetch('/recordings/git/commit', {
        method: 'POST',
        body: fd,
        credentials: 'same-origin'
      });
      const data = await res.json();
      if (!data.ok) throw new Error(data.error || 'Failed to commit changes');

      if (gitSnapshotMsg) gitSnapshotMsg.value = '';
      loadGitHistory();
    } catch (err) {
      alert('Git Commit failed: ' + err.message);
    } finally {
      if (gitSnapshotBtn) {
        gitSnapshotBtn.disabled = false;
        gitSnapshotBtn.innerHTML = '<i class="fas fa-code-branch"></i> Commit Changes';
      }
    }
  }

  async function discardWorkingTreeChanges() {
    if (!gitHistoryCurrentScope.path) {
      alert('Select a specific note to discard uncommitted changes.');
      return;
    }
    if (!confirm(`Discard all uncommitted changes to "${gitHistoryCurrentScope.path}"?\n\nThis will revert the file to the last committed version.`)) {
      return;
    }

    try {
      const fd = new FormData();
      fd.append('path', gitHistoryCurrentScope.path);
      if (gitHistoryCurrentScope.slug) fd.append('slug', gitHistoryCurrentScope.slug);

      const res = await fetch('/recordings/git/discard', {
        method: 'POST',
        body: fd,
        credentials: 'same-origin'
      });
      const data = await res.json();
      if (!data.ok) throw new Error(data.error || 'Failed to discard changes');

      const activeId = getActiveId();
      if (activeId) {
        delete mdCache[activeId];
        loadMarkdownContent(activeId);
      }
      loadGitHistory();
    } catch (err) {
      alert('Failed to discard changes: ' + err.message);
    }
  }

  async function restoreGitVersion(hashToRestore) {
    const hash = hashToRestore || gitHistorySelectedHash;
    if (!hash || hash === 'working') {
      alert('Select a committed revision from the list to restore.');
      return;
    }

    const short = hash.substring(0, 7);
    const targetLabel = gitHistoryCurrentScope.path ? `file "${gitHistoryCurrentScope.path}"` : (gitHistoryCurrentScope.slug ? `set "${gitHistoryCurrentScope.slug}"` : 'repository');

    if (!confirm(`Restore ${targetLabel} to revision ${short}?\n\nThis will check out the contents from ${short} and commit the restoration.`)) {
      return;
    }

    try {
      const fd = new FormData();
      fd.append('hash', hash);
      if (gitHistoryCurrentScope.path) fd.append('path', gitHistoryCurrentScope.path);
      if (gitHistoryCurrentScope.slug) fd.append('slug', gitHistoryCurrentScope.slug);

      const res = await fetch('/recordings/git/restore', {
        method: 'POST',
        body: fd,
        credentials: 'same-origin'
      });
      const data = await res.json();
      if (!data.ok) throw new Error(data.error || 'Failed to restore version');

      alert(`Restored successfully from ${short}!`);
      const activeId = getActiveId();
      if (activeId) {
        delete mdCache[activeId];
        loadMarkdownContent(activeId);
      }
      loadGitHistory();
    } catch (err) {
      alert('Restore failed: ' + err.message);
    }
  }

  function setupGitHistory() {
    if (gitHistoryBtn) {
      gitHistoryBtn.addEventListener('click', () => {
        openGitHistoryModal(getActiveWalkthrough());
      });
    }

    if (mdGitHistoryBtn) {
      mdGitHistoryBtn.addEventListener('click', () => {
        const wk = getActiveWalkthrough();
        const activeId = getActiveId();
        const fileName = (getActiveDataType() === 'markdown' && activeId) ? (activeId + '.md') : null;
        const filePath = (fileName && wk && wk !== 'default') ? (wk + '/' + fileName) : fileName;
        openGitHistoryModal(wk, filePath);
      });
    }

    if (mdSaveBtn) {
      mdSaveBtn.addEventListener('click', () => {
        saveMarkdownContent(false);
      });
    }

    if (mdGitCommitBtn) {
      mdGitCommitBtn.addEventListener('click', () => {
        promptAndCommitNote();
      });
    }

    if (gitSnapshotBtn) {
      gitSnapshotBtn.onclick = createGitSnapshot;
    }
  }

  // --- Settings Menu & Auto-save Interval ---
  function setupSettingsMenu() {
    if (mdSettingsBtn && mdSettingsMenu) {
      mdSettingsBtn.addEventListener('click', (e) => {
        e.stopPropagation();
        const isOpen = mdSettingsMenu.style.display !== 'none';
        mdSettingsMenu.style.display = isOpen ? 'none' : 'block';
        mdSettingsBtn.style.background = isOpen ? '#1e293b' : '#334155';
        mdSettingsBtn.style.borderColor = isOpen ? '#475569' : '#38bdf8';
      });

      document.addEventListener('click', (e) => {
        if (mdSettingsMenu.style.display !== 'none') {
          if (!mdSettingsMenu.contains(e.target) && e.target !== mdSettingsBtn && !mdSettingsBtn.contains(e.target)) {
            mdSettingsMenu.style.display = 'none';
            mdSettingsBtn.style.background = '#1e293b';
            mdSettingsBtn.style.borderColor = '#475569';
          }
        }
      });
    }

    if (mdSettingWrapCheckbox) {
      mdSettingWrapCheckbox.addEventListener('change', () => {
        mdWrapCode = mdSettingWrapCheckbox.checked;
        try {
          localStorage.setItem('ctlabs_md_wrap_code', mdWrapCode ? 'true' : 'false');
        } catch (e) {}
        updateMdWrapCodeUI();
      });
    }

    if (mdSettingVimCheckbox) {
      mdSettingVimCheckbox.addEventListener('change', () => {
        mdVimMode = mdSettingVimCheckbox.checked;
        try {
          localStorage.setItem('ctlabs_md_vim_mode', mdVimMode ? 'true' : 'false');
        } catch (e) {}
        updateMdVimModeUI();
      });
    }

    if (mdSettingAutosaveSelect) {
      mdSettingAutosaveSelect.addEventListener('change', () => {
        const val = parseInt(mdSettingAutosaveSelect.value, 10);
        mdAutoSaveInterval = isNaN(val) ? 5000 : Math.max(0, val);
        try {
          localStorage.setItem('ctlabs_md_autosave_interval', String(mdAutoSaveInterval));
        } catch (e) {}
        updateMdAutosaveUI();

        // If autosave was turned off, clear any active timer
        if (mdAutoSaveInterval === 0) {
          clearTimeout(mdAutoSaveTimer);
        }
      });
    }

    updateMdSettingsUI();
  }

  // --- Initial Setup on DOMContentLoaded ---
  let mdInitialized = false;
  function initMarkdownEditor() {
    if (mdInitialized) return;
    mdInitialized = true;
    setupSettingsMenu();
    setupEmojiPicker();
    setupGraphvizEditor();
    setupGitHistory();

    if (mdTabPreview) mdTabPreview.addEventListener('click', () => setMdMode('preview'));
    if (mdTabEdit) mdTabEdit.addEventListener('click', () => setMdMode('edit'));
    if (mdTabSplit) mdTabSplit.addEventListener('click', () => setMdMode('split'));

    if (mdInsertImgBtn && mdImgFileInput) {
      mdInsertImgBtn.addEventListener('click', () => {
        mdImgFileInput.click();
      });

      mdImgFileInput.addEventListener('change', () => {
        const files = Array.from(mdImgFileInput.files || []);
        if (files.length === 0) return;

        if (files.length === 1 && (
          (files[0].type && files[0].type.startsWith('image/')) ||
          (/\.(png|jpe?g|gif|svg|webp)$/i.test(files[0].name || ''))
        )) {
          const cm = getMdEditor();
          uploadAndInsertImage(files[0], cm ? cm.getCursor() : null);
        } else if (typeof window.uploadImportFiles === 'function') {
          window.uploadImportFiles(files);
        }
        mdImgFileInput.value = '';
      });
    }

    // Textarea Tab Indentation & Shortcuts Fallback
    if (mdTextarea) {
      mdTextarea.addEventListener('keydown', (e) => {
        if (e.key === 'Tab') {
          e.preventDefault();
          const start = mdTextarea.selectionStart;
          const end = mdTextarea.selectionEnd;
          mdTextarea.value = mdTextarea.value.substring(0, start) + '  ' + mdTextarea.value.substring(end);
          mdTextarea.selectionStart = mdTextarea.selectionEnd = start + 2;
          onMarkdownContentChanged();
        } else if ((e.ctrlKey || e.metaKey) && e.key === 's') {
          e.preventDefault();
          saveMarkdownContent(false);
        } else if ((e.ctrlKey || e.metaKey) && e.key === 'e') {
          e.preventDefault();
          toggleMdEmojiMenu();
        } else if ((e.ctrlKey || e.metaKey) && e.shiftKey && (e.key === 'G' || e.key === 'g')) {
          e.preventDefault();
          openGraphvizModal();
        } else if ((e.ctrlKey || e.metaKey) && e.shiftKey && (e.key === 'C' || e.key === 'c')) {
          e.preventDefault();
          promptAndCommitNote();
        }
      });

      mdTextarea.addEventListener('input', () => {
        onMarkdownContentChanged();
      });

      mdTextarea.addEventListener('paste', (e) => {
        const clipboard = e.clipboardData || window.clipboardData;
        if (!clipboard || !clipboard.items) return;
        for (let i = 0; i < clipboard.items.length; i++) {
          const item = clipboard.items[i];
          if (item.kind === 'file' && item.type.startsWith('image/')) {
            e.preventDefault();
            const file = item.getAsFile();
            if (file) uploadAndInsertImage(file, { index: mdTextarea.selectionStart });
            break;
          }
        }
      });
    }

    // Drag & Drop onto Markdown Container
    if (mdContainer) {
      mdContainer.addEventListener('dragover', (e) => {
        if (window.draggedItem) return;
        e.preventDefault();
        if (e.dataTransfer) e.dataTransfer.dropEffect = 'copy';
      });

      mdContainer.addEventListener('drop', (e) => {
        if (window.draggedItem || e._ctlabsHandled) return;
        e.preventDefault();
        const files = getDroppedFiles(e.dataTransfer);
        if (files.length === 0) return;

        const isSingleImg = files.length === 1 && (
          (files[0].type && files[0].type.startsWith('image/')) ||
          (/\.(png|jpe?g|gif|svg|webp)$/i.test(files[0].name || ''))
        );

        if (isSingleImg) {
          const cm = getMdEditor();
          uploadAndInsertImage(files[0], cm ? cm.getCursor() : null);
        } else if (typeof window.uploadImportFiles === 'function') {
          window.uploadImportFiles(files);
        }
      });
    }

    // Step link click delegation in preview pane
    if (mdPreviewPane) {
      mdPreviewPane.addEventListener('click', (e) => {
        const link = e.target.closest('a');
        if (!link) return;
        const id = stepIdFromHref(link.getAttribute('href'));
        if (!id) return;
        const target = document.querySelector(`.rec-item[data-id="${CSS.escape(id)}"]`);
        if (!target) return;
        e.preventDefault();
        if (typeof window.selectRecording === 'function') {
          window.selectRecording(target, true);
        } else {
          target.click();
        }
        target.scrollIntoView({ block: 'nearest', behavior: 'smooth' });
      });
    }
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', initMarkdownEditor);
  } else {
    initMarkdownEditor();
  }

  // --- Expose Public Interface ---
  window.MarkdownEditor = {
    init: initMarkdownEditor,
    getEditor: getMdEditor,
    setMode: setMdMode,
    getMode: () => currentMdMode,
    loadContent: loadMarkdownContent,
    saveContent: saveMarkdownContent,
    commitNote: promptAndCommitNote,
    isDirty: () => mdIsDirty,
    renderPreview: renderMarkdownPreview,
    insertBlock: insertMarkdownBlock,
    uploadImage: uploadAndInsertImage,
    openGraphviz: openGraphvizModal,
    initGraphvizEditor: initGraphvizCodeEditor,
    saveGraphviz: saveAndInsertGraphviz,
    openGitHistory: openGitHistoryModal,
    loadGitHistory: loadGitHistory,
    showGitDiff: showGitDiff,
    createSnapshot: createGitSnapshot,
    restoreVersion: restoreGitVersion,
    discardChanges: discardWorkingTreeChanges,
    getAutoSaveInterval: () => mdAutoSaveInterval,
    setAutoSaveInterval: (ms) => {
      mdAutoSaveInterval = ms;
      updateMdAutosaveUI();
    },
    toggleEmoji: toggleMdEmojiMenu,
    get emojis() { return getEmojiList(); },
    replaceEmojiShortcodes: replaceEmojiShortcodes
  };

  window.addEventListener('beforeunload', () => {
    const activeId = getActiveId();
    const activeDataType = getActiveDataType();
    if (mdIsDirty && activeId && activeDataType === 'markdown') {
      try {
        const content = mdCodeEditor ? mdCodeEditor.getValue() : (mdTextarea ? mdTextarea.value : '');
        const blob = new Blob([JSON.stringify({ content: content })], { type: 'application/json' });
        navigator.sendBeacon('/recordings/' + encodeURIComponent(activeId) + '/content', blob);
      } catch (e) {}
    }
  });

  // Global helpers for legacy and external calls
  window.getMdEditor = getMdEditor;
  window.setMdMode = setMdMode;
  window.loadMarkdownContent = loadMarkdownContent;
  window.saveMarkdownContent = saveMarkdownContent;
  window.insertMarkdownBlock = insertMarkdownBlock;
  window.uploadAndInsertImage = uploadAndInsertImage;
  window.openGraphvizModal = openGraphvizModal;
  window.saveAndInsertGraphviz = saveAndInsertGraphviz;
  window.openGitHistoryModal = openGitHistoryModal;
  window.loadGitHistory = loadGitHistory;
  window.showGitDiff = showGitDiff;
  window.createGitSnapshot = createGitSnapshot;
  window.restoreGitVersion = restoreGitVersion;
  window.discardWorkingTreeChanges = discardWorkingTreeChanges;
  window.promptAndCommitNote = promptAndCommitNote;
  window.onMarkdownContentChanged = onMarkdownContentChanged;
  window.toggleMdEmojiMenu = toggleMdEmojiMenu;
  window.getEmojiList = getEmojiList;
  window.getEmojiMap = getEmojiMap;
  window.MARKDOWN_EMOJI_LIST = ctlabsEmojiList;
  window.replaceEmojiShortcodes = replaceEmojiShortcodes;
  window.replaceGitHubEmojis = replaceEmojiShortcodes;

  try {
    Object.defineProperty(window, 'mdIsDirty', {
      get: () => mdIsDirty,
      set: (v) => { mdIsDirty = !!v; },
      configurable: true
    });
    Object.defineProperty(window, 'currentMdMode', {
      get: () => currentMdMode,
      set: (m) => { setMdMode(m); },
      configurable: true
    });
  } catch (e) {}

})();
