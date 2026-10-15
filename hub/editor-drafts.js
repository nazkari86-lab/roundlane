// Roundlane editor adapter, MPL-2.0. Reads source editors and custom-test input only.
(() => {
  if (window.__roundlaneEditor?.version === 2) return;
  const edited = { code: false, input: false };
  let applying = false;
  const watched = new WeakSet();
  function watch(doc) {
    if (!doc || watched.has(doc)) return;
    watched.add(doc);
    const change = event => {
      if (applying) return;
      const e = event.target;
      if (doc === document && e?.name === 'input') edited.input = true;
      else if (doc !== document || e?.closest?.('.ace_editor,.CodeMirror') ||
          e?.id === 'sourceCodeTextarea' || ['source', 'sourceCode'].includes(e?.name)) edited.code = true;
    };
    doc.addEventListener('beforeinput', change, true);
    doc.addEventListener('input', change, true);
    doc.addEventListener('paste', change, true);
  }
  function editor() {
    watch(document);
    const aceNode = document.querySelector('.ace_editor');
    if (aceNode && window.ace) {
      // ace.edit() would create a new editor and clear a container not ready yet.
      const ace = aceNode.env?.editor;
      if (!ace || typeof ace.getValue !== 'function') return null;
      return { get: () => ace.getValue(), set: s => ace.setValue(s, -1) };
    }
    const mirror = document.querySelector('.CodeMirror')?.CodeMirror;
    if (mirror) return { get: () => mirror.getValue(), set: s => mirror.setValue(s) };
    const source = document.getElementById('sourceCodeTextarea');
    if (source && window.editAreaLoader) {
      const frame = document.getElementById('frame_sourceCodeTextarea');
      try {
        if (frame?.contentDocument) watch(frame.contentDocument);
        if (frame && !frame.contentDocument?.body) return null;
      } catch { return null; }
      return { get: () => window.editAreaLoader.getValue('sourceCodeTextarea'), set: s => window.editAreaLoader.setValue('sourceCodeTextarea', s) };
    }
    const plain = source || document.querySelector('textarea[name="source"],textarea[name="sourceCode"]');
    if (plain) return { get: () => plain.value, set: s => { plain.value = s; plain.dispatchEvent(new Event('input', { bubbles: true })); } };
    return null;
  }
  function capture() {
    try {
      const e = editor();
      const code = e?.get();
      if (typeof code !== 'string' || code.length > 262144) return null;
      const input = document.querySelector('textarea[name="input"]');
      return { code, input: input && input.value.length <= 131072 ? input.value : null };
    } catch { return null; }
  }
  function restore(data) {
    try {
      const e = editor();
      if (!e || typeof e.get() !== 'string') return 'waiting';
      if (typeof data?.code !== 'string' || data.code.length > 262144) return 'invalid';
      applying = true;
      if (!edited.code) e.set(data.code);
      const input = document.querySelector('textarea[name="input"]');
      if (!edited.input && input && typeof data.input === 'string' && data.input.length <= 131072) input.value = data.input;
      return edited.code || edited.input ? 'edited' : 'applied';
    } catch { return 'waiting'; }
    finally { applying = false; }
  }
  watch(document);
  window.__roundlaneEditor = Object.freeze({ version: 2, capture, restore });
})();
