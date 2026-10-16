const { test } = require('node:test');
const assert = require('node:assert/strict');
const vm = require('node:vm');
const fs = require('node:fs');
const source = fs.readFileSync(`${__dirname}/../hub/app.js`, 'utf8');

function setup(responses) {
  const elements = Object.fromEntries(['group-link', 'compiler-link', 'status', 'retry'].map(id => [id, {
    hidden: false, textContent: '', attrs: {},
    classList: { remove() {}, toggle() {} },
    setAttribute(k, v) { this.attrs[k] = v; },
    removeAttribute(k) { delete this.attrs[k]; if (k === 'href') delete this.href; },
    addEventListener(k, fn) { this[k] = fn; }
  }]));
  const context = vm.createContext({ document: { getElementById: id => elements[id] }, URL, AbortController, setTimeout, clearTimeout,
    fetch: async path => {
      const value = responses[path];
      return { ok: value !== undefined, text: async () => value };
    }
  });
  vm.runInContext(source.replace(/loadContest\(\);\s*$/, ''), context);
  return { elements, load: () => vm.runInContext('loadContest()', context) };
}

test('template failure does not block the group; retry recovers the compiler', async () => {
  const responses = { '/config.json': JSON.stringify({ groupURL: 'https://codeforces.com/group/Test123/contest/12345' }) };
  const { elements, load } = setup(responses);
  await load();
  assert.equal(elements['group-link'].href, 'https://codeforces.com/group/Test123/contest/12345');
  assert.equal(elements['compiler-link'].href, undefined);
  assert.equal(elements.retry.hidden, false);
  responses['/starter.cpp'] = '#include <iostream>\nint main() {}';
  await elements.retry.click();
  assert.equal(new URL(elements['compiler-link'].href).searchParams.get('new_lang'), 'c++20');
  assert.equal(new URL(elements['compiler-link'].href).searchParams.has('source'), false);
  assert.equal(elements.retry.hidden, true);
});

test('wrong host and credentials cannot become the contest link', async () => {
  for (const groupURL of ['https://codeforces.com.evil.test/group/Test123/contest/12345', 'https://user@codeforces.com/group/Test123/contest/12345']) {
    const { elements, load } = setup({ '/config.json': JSON.stringify({ groupURL }), '/starter.cpp': 'int main() {}' });
    await load();
    assert.equal(elements['group-link'].href, undefined);
    assert.equal(elements['group-link'].attrs.tabindex, '-1');
    assert.ok(elements['compiler-link'].href.startsWith('https://www.onlinegdb.com/'));
  }
});

test('successful load hides status and retry and enables keyboard links', async () => {
  const { elements, load } = setup({ '/config.json': JSON.stringify({ groupURL: 'https://codeforces.com/group/Test123/contest/12345' }), '/starter.cpp': 'int main() {}' });
  await load();
  assert.equal(elements.status.hidden, true);
  assert.equal(elements.retry.hidden, true);
  assert.equal(elements['group-link'].attrs.tabindex, undefined);
});
