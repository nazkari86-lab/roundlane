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
  if (kind === 'ace') window.ace = { edit: () => ({ getValue: () => buffer, setValue: v => { buffer = v; } }) };
  if (kind === 'area') window.editAreaLoader = { getValue: () => buffer, setValue: (id, v) => { buffer = v; } };
  const context = vm.createContext({ window, document, Event: class {} });
  vm.runInContext(script, context);
  return { adapter: window.__roundlaneEditor, input, handlers, document, context };
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
