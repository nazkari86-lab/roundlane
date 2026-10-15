const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const script = fs.readFileSync(`${__dirname}/../hub/editor-drafts.js`, 'utf8');
function setup(kind, code = '// original') {
  const handlers = {};
  const input = { value: '2 3', name: 'input' };
  const node = { value: code, id: 'sourceCodeTextarea', dispatchEvent() {} };
  let buffer = code;
  const document = {
    addEventListener(name, fn) { handlers[name] = fn; },
    querySelector(s) { return s === 'textarea[name="input"]' ? input : s === '.ace_editor' && kind === 'ace' ? node : s === '.CodeMirror' && kind === 'mirror' ? { CodeMirror: { getValue: () => buffer, setValue: v => { buffer = v; } } } : null; },
    getElementById(id) { return id === 'sourceCodeTextarea' && ['area', 'plain'].includes(kind) ? node : null; }
  };
  const window = {};
  if (kind === 'ace') {
    node.env = { editor: { getValue: () => buffer, setValue: v => { buffer = v; } } };
    window.ace = { edit: () => { throw new Error('Reader must not create editors'); } };
  }
  if (kind === 'area') window.editAreaLoader = { getValue: () => buffer, setValue: (id, v) => { buffer = v; } };
  const context = vm.createContext({ window, document, Event: class {} });
  vm.runInContext(script, context);
  return { adapter: window.__roundlaneEditor, input, handlers, document, context, node };
}
for (const kind of ['ace', 'mirror', 'area', 'plain']) test(`${kind}: source and input survive capture/restore`, () => {
  const a = setup(kind, 'int main(){ /* Привет </script> */ }');
  const data = a.adapter.capture();
  assert.equal(data.code, 'int main(){ /* Привет </script> */ }');
  assert.equal(data.input, '2 3');
  const b = setup(kind, '');
  assert.equal(b.adapter.restore(data), 'applied');
  assert.equal(b.adapter.capture().code, data.code);
  assert.equal(b.adapter.capture().input, '2 3');
});
test('missing editor and oversized code do not overwrite a saved draft', () => {
  assert.equal(setup('missing').adapter.capture(), null);
  assert.equal(setup('ace', 'x'.repeat(262145)).adapter.capture(), null);
});
test('an empty editor is a valid deliberate draft', () => assert.equal(setup('ace', '').adapter.capture().code, ''));
test('restore never overwrites input the participant already edited', () => {
  const a = setup('ace', 'new code');
  a.handlers.input({ target: { closest: () => true } });
  vm.runInContext(script, a.context);
  assert.equal(a.adapter.restore({ code: 'old code', input: 'old input' }), 'edited');
  assert.equal(a.adapter.capture().code, 'new code');
});
test('password and unrelated form fields are not captured', () => {
  const a = setup('missing');
  a.handlers.input({ target: { name: 'password', value: 'secret', closest: () => false } });
  assert.equal(a.adapter.capture(), null);
});

test('editing only test input preserves that input but restores saved source', () => {
  const a = setup('ace', '');
  a.input.value = 'new input';
  a.handlers.input({ target: a.input });
  a.adapter.restore({ code: 'saved source', input: 'old input' });
  assert.equal(a.adapter.capture().code, 'saved source');
  assert.equal(a.adapter.capture().input, 'new input');
});

test('editing only source preserves that source but restores saved test input', () => {
  const a = setup('ace', 'new source');
  a.handlers.input({ target: { closest: () => true } });
  a.adapter.restore({ code: 'old source', input: 'saved input' });
  assert.equal(a.adapter.capture().code, 'new source');
  assert.equal(a.adapter.capture().input, 'saved input');
});

test('an Ace container without an initialized editor is left untouched', () => {
  const a = setup('ace');
  delete a.node.env;
  assert.equal(a.adapter.capture(), null);
  assert.equal(a.adapter.restore({ code: 'saved' }), 'waiting');
});

test('editArea waits for its iframe even if its backing textarea has old content', () => {
  const a = setup('area', 'backing textarea');
  const original = a.document.getElementById;
  const frame = { contentDocument: null };
  a.document.getElementById = id => id === 'frame_sourceCodeTextarea' ? frame : original(id);
  assert.equal(a.adapter.capture(), null);
  assert.equal(a.adapter.restore({ code: 'saved' }), 'waiting');
  frame.contentDocument = { body: {}, addEventListener() {} };
  assert.equal(a.adapter.restore({ code: 'saved' }), 'applied');
  assert.equal(a.adapter.capture().code, 'saved');
});

test('invalid source payload cannot partially replace the input', () => {
  const a = setup('ace', 'source');
  assert.equal(a.adapter.restore({ code: 123, input: 'wrong' }), 'invalid');
  assert.equal(a.adapter.capture().code, 'source');
  assert.equal(a.adapter.capture().input, '2 3');
});
