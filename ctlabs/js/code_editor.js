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

// --- UNIVERSAL EDITOR FACTORY ---
window.initCodeEditor = function(textAreaId, langMode) {
    // If it already exists, just return it!
    if (window.cmEditors[textAreaId]) {
        setTimeout(() => window.cmEditors[textAreaId].refresh(), 50);
        return window.cmEditors[textAreaId];
    }
    const ta = document.getElementById(textAreaId);
    if (!ta) return null;
    // Build the new editor dynamically
    const editor = CodeMirror.fromTextArea(ta, {
        mode: langMode,
        theme: 'material-ocean',
        lineNumbers: true,
        tabSize: 2,
        viewportMargin: Infinity
    });
    
    editor.setSize("100%", "auto");
    editor.getWrapperElement().style.minHeight = "400px";
    
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
