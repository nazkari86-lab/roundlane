// Roundlane editor adapter, MPL-2.0. Source/project drafts only, never login forms.
(() => {
  if (window.__roundlaneEditor?.version === 3) return;
  const edited = { code: false, input: false, project: false, language: false, args: false, mode: false };
  const online = ['www.onlinegdb.com', 'onlinegdb.com'].includes(window.location?.hostname);
  let applying = false, initialized = false, restoredSource = false, initializeAttempts = 0;
  const watched = new WeakSet();
  const stdin = () => document.getElementById('stdinput') || document.querySelector('textarea[name="input"]');
  function watch(doc) {
    if (!doc || watched.has(doc)) return;
    watched.add(doc);
    const change = event => {
      if (applying) return;
      const e = event.target;
      if (doc === document && (e?.name === 'input' || e?.id === 'stdinput')) edited.input = true;
      else if (e?.id === 'lang-select') edited.language = true;
      else if (e?.id === 'cmd_line_args') edited.args = true;
      else if (e?.id === 'input_method_text' || e?.id === 'input_method_interactive') edited.mode = true;
      else if (doc !== document || e?.closest?.('.ace_editor,.CodeMirror') ||
          e?.id === 'sourceCodeTextarea' || ['source', 'sourceCode'].includes(e?.name)) edited.code = true;
    };
    for (const event of ['beforeinput', 'input', 'paste', 'change']) doc.addEventListener(event, change, true);
    doc.addEventListener('click', event => {
      if (!applying && event.target?.closest?.('#control-btn-newfile,#control-btn-upload,.menu_item_rename,.menu_item_delete')) edited.project = true;
    }, true);
  }
  function editor() {
    watch(document);
    const aceNode = document.querySelector('.ace_editor');
    if (aceNode && window.ace) {
      const ace = aceNode.env?.editor;
      if (!ace || typeof ace.getValue !== 'function') return null;
      return { get: () => ace.getValue(), set: s => ace.setValue(s, -1) };
    }
    const mirror = document.querySelector('.CodeMirror')?.CodeMirror;
    if (mirror) return { get: () => mirror.getValue(), set: s => mirror.setValue(s) };
    const source = document.getElementById('sourceCodeTextarea');
    if (source && window.editAreaLoader) {
      const frame = document.getElementById('frame_sourceCodeTextarea');
      try { if (frame?.contentDocument) watch(frame.contentDocument); if (frame && !frame.contentDocument?.body) return null; }
      catch { return null; }
      return { get: () => window.editAreaLoader.getValue('sourceCodeTextarea'), set: s => window.editAreaLoader.setValue('sourceCodeTextarea', s) };
    }
    const plain = source || document.querySelector('textarea[name="source"],textarea[name="sourceCode"]');
    return plain ? { get: () => plain.value, set: s => { plain.value = s; plain.dispatchEvent(new Event('input', { bubbles: true })); } } : null;
  }
  function projectAPI() {
    const api = online && window.ide?.editor;
    return api && typeof api.get_files === 'function' && typeof api.set_files === 'function' ? api : null;
  }
  function validateProject(p) {
    if (!p || !Array.isArray(p.files) || !p.files.length || p.files.length > 32) return null;
    const names = new Set();
    const files = [];
    for (const f of p.files) {
      if (!f || typeof f.name !== 'string' || !f.name.trim() || f.name.length > 128 || /[\/\\\x00-\x1f]/.test(f.name) || names.has(f.name) ||
          typeof f.content !== 'string' || f.content.length > 262144 || (f.encoding != null && f.encoding !== 'base64')) return null;
      names.add(f.name); files.push({ name: f.name, content: f.content, ...(f.encoding ? { encoding: f.encoding } : {}) });
    }
    const value = { files, language: typeof p.language === 'string' ? p.language : '', args: typeof p.args === 'string' && p.args.length <= 8192 ? p.args : '', mode: p.mode === 'interactive' ? 'interactive' : 'text', active: names.has(p.active) ? p.active : files[0].name };
    return JSON.stringify(value).length <= 1048576 ? value : null;
  }
  function captureProject(api) {
    const language = document.getElementById('lang-select');
    return validateProject({ files: api.get_files(), language: language?.value, args: document.getElementById('cmd_line_args')?.value,
      mode: document.getElementById('input_method_interactive')?.checked ? 'interactive' : 'text', active: api.getFile?.().name });
  }
  function capture() {
    try {
      const e = editor(); const code = e?.get();
      if (typeof code !== 'string' || code.length > 262144) return null;
      const input = stdin(); const api = projectAPI(); const project = api ? captureProject(api) : null;
      if (online && !project) return null;
      return { code, input: input && input.value.length <= 131072 ? input.value : null, ...(project ? { project: JSON.stringify(project) } : {}) };
    } catch { return null; }
  }
  function setLanguage(language) {
    const select = document.getElementById('lang-select');
    if (!select || !Array.from(select.options || []).some(o => o.value === language)) return;
    if (select.value !== language) { select.value = language; select.dispatchEvent(new Event('change', { bubbles: true })); }
  }
  function restore(data) {
    try {
      const e = editor(); if (!e || typeof e.get() !== 'string') return 'waiting';
      if (typeof data?.code !== 'string' || data.code.length > 262144) return 'invalid';
      let saved = null; const api = projectAPI();
      if (online && data.project != null) {
        if (typeof data.project !== 'string' || data.project.length > 1048576) return 'invalid';
        try { saved = validateProject(JSON.parse(data.project)); } catch { return 'invalid'; }
        if (!saved) return 'invalid';
        if (!api || typeof api.set_default_editor_filename !== 'function' || typeof api.delete_file !== 'function') return 'waiting';
      }
      restoredSource = true;
      applying = true;
      if (saved) {
        if (!edited.code && !edited.project) {
          if (!edited.language) setLanguage(saved.language);
          // Keep editor_1: OnlineGDB's language switch still references this main editor.
          api.set_default_editor_filename(saved.files[0].name);
          const names = new Set(saved.files.map(f => f.name));
          for (const f of api.get_files()) if (!names.has(f.name)) api.delete_file(f.name);
          api.set_files(saved.files);
          for (const link of document.querySelectorAll?.('.editor_file_tabs a') || []) {
            if (link.querySelector('.filename')?.textContent === saved.active) { link.click(); break; }
          }
        }
        if (!edited.args) { const args = document.getElementById('cmd_line_args'); if (args) args.value = saved.args; }
        if (!edited.mode) { const method = document.getElementById(saved.mode === 'interactive' ? 'input_method_interactive' : 'input_method_text'); if (method) { method.checked = true; method.dispatchEvent(new Event('change', { bubbles: true })); } }
      } else if (!edited.code && !edited.project) e.set(data.code);
      const input = stdin();
      if (!edited.input && input && typeof data.input === 'string' && data.input.length <= 131072) input.value = data.input;
      return Object.values(edited).some(Boolean) ? 'edited' : 'applied';
    } catch { return 'waiting'; }
    finally { applying = false; }
  }
  function initialize(source) {
    if (!online || initialized || typeof source !== 'string' || source.length > 262144) return;
    const e = editor(); const api = projectAPI();
    if (!e || !api || !document.getElementById('lang-select')) {
      if (++initializeAttempts <= 120) window.setTimeout?.(() => initialize(source), 250);
      return;
    }
    if (!document.getElementById('roundlane-ide-policy')) {
      const style = document.createElement('style'); style.id = 'roundlane-ide-policy';
      style.textContent = '#control-btn-askai,#askai-container{display:none!important}';
      (document.head || document.documentElement).appendChild(style);
    }
    if (!restoredSource && !edited.code && !edited.project && !edited.language) {
      applying = true;
      try { setLanguage('c++20'); if (typeof api.set_default_editor_content === 'function') api.set_default_editor_content(source); else e.set(source); initialized = true;
        // Some site startup callbacks replace the template after navigation finishes.
        window.setTimeout?.(() => {
          if (!restoredSource && !edited.code && !edited.project && !edited.language) {
            applying = true; try { e.set(source); } finally { applying = false; }
          }
        }, 750);
      }
      finally { applying = false; }
    } else initialized = true;
  }
  watch(document);
  window.__roundlaneEditor = Object.freeze({ version: 3, capture, restore, initialize });
})();
