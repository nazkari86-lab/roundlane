// Roundlane editor adapter, MPL-2.0. Reads source editors and custom-test input only.
(() => {
  if (window.__roundlaneEditor?.version === 1) return;
  let edited = false;
  let applying = false;
  const watched = new WeakSet();
  function watch(doc) {
    if (!doc || watched.has(doc)) return;
    watched.add(doc);
    const change = event => {
      if (applying) return;
      const e = event.target;
      if (doc !== document || e?.closest?.('.ace_editor,.CodeMirror') ||
          e?.id === 'sourceCodeTextarea' || ['source', 'sourceCode', 'input'].includes(e?.name)) edited = true;
    };
    doc.addEventListener('beforeinput', change, true);
    doc.addEventListener('input', change, true);
    doc.addEventListener('paste', change, true);
  }
  function editor() {
    watch(document);
    const aceNode = document.querySelector('.ace_editor');
    if (aceNode && window.ace) {
      const ace = window.ace.edit(aceNode);
      return { get: () => ace.getValue(), set: s => ace.setValue(s, -1) };
    }
    const mirror = document.querySelector('.CodeMirror')?.CodeMirror;
    if (mirror) return { get: () => mirror.getValue(), set: s => mirror.setValue(s) };
    const source = document.getElementById('sourceCodeTextarea');
    if (source && window.editAreaLoader) {
      const frame = document.getElementById('frame_sourceCodeTextarea');
      try { if (frame?.contentDocument) watch(frame.contentDocument); } catch {}
      if (!window.editAreaLoader.getValue('sourceCodeTextarea')?.length && frame && !frame.contentDocument?.body) return null;
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
      if (edited) return 'edited';
      if (typeof data?.code !== 'string' || data.code.length > 262144) return 'invalid';
      applying = true;
      e.set(data.code);
      const input = document.querySelector('textarea[name="input"]');
      if (input && typeof data.input === 'string' && data.input.length <= 131072) input.value = data.input;
      return 'applied';
    } catch { return 'waiting'; }
    finally { applying = false; }
  }
  watch(document);
  window.__roundlaneEditor = Object.freeze({ version: 1, capture, restore });
})();
