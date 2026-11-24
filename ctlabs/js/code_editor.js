/*
 -----------------------------------------------------------------------------
 File        : ctlabs/public/js/code_editor.js
 License     : MIT License
 -----------------------------------------------------------------------------
*/

// --- GLOBAL CODEMIRROR REGISTRY ---
window.cmEditors = {};

// --- CUSTOM TERRAFORM HIGHLIGHTER ---
if (typeof CodeMirror.defineSimpleMode === 'function') {
  CodeMirror.defineSimpleMode("terraform", {
    start: [
      // Core Terraform Blocks & Keywords
      {regex: /(?:resource|data|provider|variable|output|module|locals|terraform|backend)\b/, token: "keyword"},
      // Built-in functions and types
      {regex: /(?:string|number|bool|list|map|any|object|tuple)\b/, token: "builtin"},
      // Booleans & Null
      {regex: /true|false|null\b/, token: "atom"},
      // Double-quoted Strings (supports escaped quotes)
      {regex: /"(?:[^\\]|\\.)*?(?:"|$)/, token: "string"},
      // Multi-line Strings / Heredoc (<<EOF)
      {regex: /<<-?\s*[A-Za-z0-9_]+/, token: "string", next: "heredoc"},
      // Numbers
      {regex: /0x[a-f\d]+|[-+]?(?:\.\d+|\d+\.?\d*)(?:e[-+]?\d+)?/i, token: "number"},
      // Comments (Hash, Double Slash, and Multi-line)
      {regex: /\#.*/, token: "comment"},
      {regex: /\/\/.*/, token: "comment"},
      {regex: /\/\*/, token: "comment", next: "comment"},
      // Operators
      {regex: /[-+\/*=<>!]+/, token: "operator"},
      // Brackets
      {regex: /[\{\}\[\]\(\)]/, token: "bracket"},
      // Variables and Properties
      {regex: /[a-zA-Z_][a-zA-Z0-9_\-]*\b/, token: "variable-2"}
    ],
    comment: [
      {regex: /.*?\*\//, token: "comment", next: "start"},
      {regex: /.*/, token: "comment"}
    ],
    heredoc: [
      // Safely end heredoc blocks (simple approximation)
      {regex: /^[A-Za-z0-9_]+$/, token: "string", next: "start"},
      {regex: /.*/, token: "string"}
    ],
    meta: {
      lineComment: "#",
      blockCommentStart: "/*",
      blockCommentEnd: "*/"
    }
  });
}

// --- ANSIBLE EDITOR PREFERENCES (vim / line wrap) ---
window.isAnsibleEditorId = function(id) {
    return /^(editor-(Ans|ans-tab-)|edit-ansible-commands)/.test(id || '');
};

window.AnsEditorPrefs = {
    get: function() {
        let wrap = true, vim = false;
        try {
            const w = localStorage.getItem('ctlabs_ansible_line_wrap');
            if (w !== null) wrap = w === 'true';
            vim = localStorage.getItem('ctlabs_ansible_vim_mode') === 'true';
        } catch (e) {}
        return { wrap: wrap, vim: vim };
    },
    set: function(key, val) {
        try { localStorage.setItem(key === 'wrap' ? 'ctlabs_ansible_line_wrap' : 'ctlabs_ansible_vim_mode', val ? 'true' : 'false'); } catch (e) {}
    }
};

window.updateAnsibleVimStatus = function(e) {
    const bar = document.getElementById('ans-vim-status-bar');
    const modeEl = document.getElementById('ans-vim-status-mode');
    const keyEl = document.getElementById('ans-vim-status-key');
    if (!bar || !modeEl) return;

    const prefs = window.AnsEditorPrefs.get();
    const activeTab = window.currentAnsibleTab || '';
    const isPlaySetupFocused = activeTab === 'AnsSettings' && window.cmEditors['editor-AnsPlaySetup'] && window.cmEditors['editor-AnsPlaySetup'].hasFocus();
    const isEditorTab = (activeTab && activeTab !== 'AnsSettings') || isPlaySetupFocused;

    const prevDisplay = bar.style.display;
    if (!prefs.vim || !isEditorTab) {
        bar.style.display = 'none';
        if (prevDisplay !== 'none' && activeTab === 'AnsSettings' && window.cmEditors['editor-AnsPlaySetup']) {
            setTimeout(() => window.cmEditors['editor-AnsPlaySetup'].refresh(), 20);
        }
        return;
    }
    bar.style.display = 'flex';
    if (prevDisplay !== 'flex' && activeTab === 'AnsSettings' && window.cmEditors['editor-AnsPlaySetup']) {
        setTimeout(() => window.cmEditors['editor-AnsPlaySetup'].refresh(), 20);
    }

    let mode = e ? e.mode : null;
    let subMode = e ? e.subMode : '';
    if (!mode) {
        const taId = (activeTab === 'AnsCommands') ? 'edit-ansible-commands' : (activeTab === 'AnsSettings' ? 'editor-AnsPlaySetup' : 'editor-' + activeTab);
        const ed = (activeTab && (window.cmEditors[taId] || window.cmEditors['editor-' + activeTab])) || null;
        if (ed && ed.state && ed.state.vim) {
            const vState = ed.state.vim;
            if (vState.insertMode) mode = 'insert';
            else if (vState.visualMode) mode = 'visual';
            else mode = 'normal';
        }
    }
    if (!mode) mode = 'normal';

    if (mode === 'insert') {
        modeEl.textContent = '-- INSERT --';
        modeEl.style.color = '#38bdf8';
    } else if (mode === 'visual') {
        modeEl.textContent = subMode === 'linewise' ? '-- VISUAL LINE --' : (subMode === 'blockwise' ? '-- VISUAL BLOCK --' : '-- VISUAL --');
        modeEl.style.color = '#f59e0b';
    } else if (mode === 'replace') {
        modeEl.textContent = '-- REPLACE --';
        modeEl.style.color = '#ef4444';
    } else {
        modeEl.textContent = '-- NORMAL --';
        modeEl.style.color = '#22c55e';
    }

    if (keyEl && (!e || e.keyBuffer === '')) {
        keyEl.textContent = '';
    }
};

window.attachAnsibleVimStatus = function(editor) {
    editor.on('vim-mode-change', function(e) {
        window.updateAnsibleVimStatus(e);
    });
    editor.on('vim-keypress', function(key) {
        const el = document.getElementById('ans-vim-status-key');
        if (el) el.textContent = key || '';
    });
};

window.refreshAnsibleToolbar = function() {
    const prefs = window.AnsEditorPrefs.get();
    const wrapCb = document.getElementById('ans-setting-wrap-checkbox');
    const vimCb = document.getElementById('ans-setting-vim-checkbox');
    if (wrapCb) wrapCb.checked = prefs.wrap;
    if (vimCb) vimCb.checked = prefs.vim;

    const btn = document.getElementById('ans-settings-btn');
    if (btn) {
        const icon = btn.querySelector('i');
        if (icon) {
            icon.style.color = (prefs.vim || !prefs.wrap) ? '#38bdf8' : '#94a3b8';
        }
    }
    window.updateAnsibleVimStatus();
};

window.toggleAnsibleSettingsMenu = function(open) {
    const menu = document.getElementById('ans-settings-menu');
    if (!menu) return;
    const isClosed = !menu.style.display || menu.style.display === 'none';
    const shouldOpen = (open !== undefined) ? open : isClosed;
    menu.style.display = shouldOpen ? 'block' : 'none';
    if (shouldOpen) {
        window.refreshAnsibleToolbar();
    }
};

document.addEventListener('click', function(e) {
    const menu = document.getElementById('ans-settings-menu');
    const btn = document.getElementById('ans-settings-btn');
    if (!menu || menu.style.display === 'none') return;
    if (!menu.contains(e.target) && !btn.contains(e.target)) {
        menu.style.display = 'none';
    }
});

window.setAnsibleEditorPref = function(key, val) {
    window.AnsEditorPrefs.set(key, val);
    Object.keys(window.cmEditors).forEach(function(id) {
        if (!window.isAnsibleEditorId(id)) return;
        const ed = window.cmEditors[id];
        if (!ed || !ed.setOption) return;
        if (key === 'wrap') ed.setOption('lineWrapping', !!val);
        if (key === 'vim') {
            if (val) window.ensureCodeMirrorVimConfigured();
            ed.setOption('keyMap', (val && CodeMirror.Vim) ? 'vim' : 'default');
        }
        setTimeout(function() { ed.refresh(); }, 20);
    });
    window.refreshAnsibleToolbar();
};

window.toggleAnsibleWrap = function() { window.setAnsibleEditorPref('wrap', !window.AnsEditorPrefs.get().wrap); };
window.toggleAnsibleVim = function() {
    if (!CodeMirror.Vim) { alert('Vim keymap is not loaded.'); return; }
    window.setAnsibleEditorPref('vim', !window.AnsEditorPrefs.get().vim);
};

// Universal Vim configuration for CodeMirror: Ex commands (:w, :wq, :q) and OS clipboard (Ctrl-C, Ctrl-V)
window.ensureCodeMirrorVimConfigured = function() {
    if (typeof CodeMirror === 'undefined' || !CodeMirror.Vim) return;

    if (!window.__ansVimExDefined) {
        window.__ansVimExDefined = true;
        const inAns = function(cm) { const ta = cm.getTextArea && cm.getTextArea(); return ta && window.isAnsibleEditorId(ta.id); };
        const closeAns = function() { const m = document.getElementById('ansible-editor-modal'); if (m) m.style.display = 'none'; };
        CodeMirror.Vim.defineEx('write', 'w', function(cm) { if (inAns(cm) && window.saveAnsibleConfig) window.saveAnsibleConfig(); });
        CodeMirror.Vim.defineEx('wq', 'wq', function(cm) { if (inAns(cm) && window.saveAnsibleConfig) window.saveAnsibleConfig({ closeAfter: true }); });
        CodeMirror.Vim.defineEx('quit', 'q', function(cm) { if (inAns(cm)) closeAns(); });
    }

    if (!CodeMirror.Vim._clipboardConfigured) {
        CodeMirror.Vim._clipboardConfigured = true;
        try {
            // Unmap <C-c> in insert mode so native browser copy works without exiting insert mode
            CodeMirror.Vim.unmap('<C-c>', 'insert');
        } catch (e) {}

        try {
            // In visual mode, allow Ctrl-C to copy selection to system clipboard and exit visual mode
            CodeMirror.Vim.defineAction('clipboardCopy', function(cm) {
                if (cm.somethingSelected()) {
                    const text = cm.getSelection();
                    if (navigator.clipboard && navigator.clipboard.writeText) {
                        navigator.clipboard.writeText(text).catch(function() {
                            try { document.execCommand('copy'); } catch (err) {}
                        });
                    } else {
                        try { document.execCommand('copy'); } catch (err) {}
                    }
                    if (typeof CodeMirror.Vim.exitVisualMode === 'function') {
                        CodeMirror.Vim.exitVisualMode(cm);
                    }
                }
            });
            CodeMirror.Vim.mapCommand('<C-c>', 'action', 'clipboardCopy', {}, { context: 'visual' });
        } catch (e) {}
    }
};
window.ensureCodeMirrorVimConfigured();

// --- UNIVERSAL EDITOR FACTORY ---
window.initCodeEditor = function(textAreaId, langMode) {
    const existing = window.cmEditors[textAreaId];

    // Reuse the cached editor ONLY if its wrapper is still connected to the
    // document. Switching labs re-renders the modal via innerHTML (labs.js
    // fetchLabInfo), which destroys the old CodeMirror wrapper and leaves a
    // fresh, unwrapped <textarea> behind. In that case the cached editor is
    // orphaned and we must drop it and wrap the new textarea below.
    if (existing) {
        const wrapper = existing.getWrapperElement && existing.getWrapperElement();
        if (wrapper && wrapper.isConnected) {
            setTimeout(() => existing.refresh(), 50);
            return existing;
        }
        delete window.cmEditors[textAreaId];
    }

    const ta = document.getElementById(textAreaId);
    if (!ta) return null;
    // Ansible editor tabs get extra capabilities (vim keymap, line wrapping, bigger area)
    const isAns = window.isAnsibleEditorId(textAreaId);
    const opts = {
        mode: langMode,
        theme: 'material-ocean',
        lineNumbers: true,
        tabSize: 2,
        viewportMargin: 15
    };
    if (isAns) {
        const prefs = window.AnsEditorPrefs.get();
        opts.lineWrapping = prefs.wrap;
        if (prefs.vim && CodeMirror.Vim) {
            window.ensureCodeMirrorVimConfigured();
            opts.keyMap = 'vim';
        }
    }
    const editor = CodeMirror.fromTextArea(ta, opts);

    if (isAns) {
        editor.setSize("100%", "100%");
        editor.getWrapperElement().style.minHeight = "0";
        window.attachAnsibleVimStatus(editor);
        editor.setOption('extraKeys', {
            'Ctrl-S': () => { if (window.saveAnsibleConfig) window.saveAnsibleConfig(); },
            'Cmd-S':  () => { if (window.saveAnsibleConfig) window.saveAnsibleConfig(); }
        });
    } else {
        editor.setSize("100%", "auto");
        editor.getWrapperElement().style.minHeight = "400px";
    }

    window.cmEditors[textAreaId] = editor;
    
    // Refresh to fix the hidden-div glitch
    setTimeout(() => editor.refresh(), 50);
    return editor;
};


// --- PERFECT LAYOUT RESIZER ---
window.autoResizeLayout = function() {
    const wrapper = document.getElementById('lab-layout-wrapper');
    if (wrapper) {
        const rect = wrapper.getBoundingClientRect();
        // Increased to 60px to fully clear the bottom padding of the w3-panels
        const newHeight = window.innerHeight - rect.top - 60;
        wrapper.style.height = Math.max(400, newHeight) + 'px';
    }
};
window.addEventListener('resize', window.autoResizeLayout);

// Modal-level save shortcut (Ctrl+S / Cmd+S)
window.addEventListener('keydown', function(e) {
    const modal = document.getElementById('ansible-editor-modal');
    if (!modal || modal.style.display === 'none') return;
    if ((e.ctrlKey || e.metaKey) && (e.key === 's' || e.key === 'S')) {
        e.preventDefault();
        if (window.__ansibleIsSaving) return;
        if (typeof window.saveAnsibleConfig === 'function') {
            window.saveAnsibleConfig();
        }
    }
});
