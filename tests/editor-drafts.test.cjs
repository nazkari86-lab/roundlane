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

function onlineSetup(files = [{ name: 'main.cpp', content: '// default' }]) {
  const handlers = {}; let active = files[0].name;
  const nodes = {
    stdinput: { id: 'stdinput', value: '7 35\n' },
    'cmd_line_args': { id: 'cmd_line_args', value: '--test' },
    'lang-select': { id: 'lang-select', value: 'c++17', options: ['c++17','c++20','c++23'].map(value => ({value})), dispatchEvent() {} },
    input_method_interactive: { checked: false, dispatchEvent() {} },
    input_method_text: { checked: true, dispatchEvent() {} }
  };
  const first = { env: { editor: { getValue: () => files[0].content, setValue: v => { files[0].content = v; } } } };
  const api = {
    get_files: () => files, getFile: () => files.find(f => f.name === active) || files[0],
    set_files: (newFiles, clear) => { assert.equal(clear, undefined, 'original editor must survive'); files = newFiles.map(f=>({...f})); },
    set_default_editor_filename: name => { files[0].name = name; },
    set_default_editor_content: content => { files[0].content = content; },
    delete_file: name => { assert.notEqual(name, files[0].name); files = files.filter(f=>f.name!==name); }
  };
  const document = {
    addEventListener: (name,fn) => { handlers[name]=fn; },
    getElementById: id => nodes[id],
    querySelector: s => s === '.ace_editor' ? first : null,
    querySelectorAll: () => files.map(f=>({ querySelector:()=>({textContent:f.name}),click:()=>{ active=f.name; } })),
    createElement: () => ({}), head: {appendChild: style=>{nodes[style.id]=style;}}
  };
  const window = { location:{hostname:'www.onlinegdb.com'},ace:{},ide:{editor:api} };
  const context = vm.createContext({ window,document,Event:class{} });
  vm.runInContext(script,context);
  return {adapter:window.__roundlaneEditor,window,nodes,handlers,api,files:()=>files,active:()=>active};
}
test('OnlineGDB: initializes C++20 and starter once without replacing later edits',()=>{
 const a=onlineSetup(); a.adapter.initialize('STARTER');
 assert.equal(a.nodes['lang-select'].value,'c++20');assert.equal(a.files()[0].content,'STARTER');
 a.files()[0].content='MY WORK';a.adapter.initialize('STARTER');assert.equal(a.files()[0].content,'MY WORK');
 assert.ok(a.nodes['roundlane-ide-policy'].textContent.includes('#control-btn-askai'));
});
test('OnlineGDB: project, active file, language, args and input survive restore',()=>{
 const a=onlineSetup([{name:'main.cpp',content:'MAIN'},{name:'lib.h',content:'HEADER'}]);
 a.nodes['lang-select'].value='c++23';const data=a.adapter.capture();const project=JSON.parse(data.project);project.active='lib.h';data.project=JSON.stringify(project);
 const b=onlineSetup([{name:'main.cpp',content:'default'},{name:'extra.cpp',content:'discard'}]);
 assert.equal(b.adapter.restore(data),'applied');assert.equal(JSON.stringify(b.files()),JSON.stringify(a.files()));
 assert.equal(b.active(),'lib.h');assert.equal(b.nodes['lang-select'].value,'c++23');assert.equal(b.nodes.cmd_line_args.value,'--test');assert.equal(b.nodes.stdinput.value,'7 35\n');
});
test('OnlineGDB: input edits do not discard a saved multifile project',()=>{
 const a=onlineSetup();a.nodes.stdinput.value='NEW';a.handlers.input({target:a.nodes.stdinput});
 const data=onlineSetup([{name:'main.cpp',content:'SAVED'},{name:'lib.h',content:'HEADER'}]).adapter.capture();
 assert.equal(a.adapter.restore(data),'edited');assert.equal(a.files().length,2);assert.equal(a.files()[0].content,'SAVED');assert.equal(a.nodes.stdinput.value,'NEW');
});
test('OnlineGDB: editing or adding files blocks source restore but preserves saved stdin',()=>{
 for(const event of ['code','project']){
 const a=onlineSetup([{name:'main.cpp',content:'NEW'}]);
 if(event==='code')a.handlers.input({target:{closest:()=>true}});else a.handlers.click({target:{closest:()=>true}});
 a.adapter.restore(onlineSetup([{name:'main.cpp',content:'OLD'}]).adapter.capture());assert.equal(a.files()[0].content,'NEW');assert.equal(a.nodes.stdinput.value,'7 35\n');
 }
});
test('OnlineGDB: invalid project cannot partially replace code or input',()=>{
 for(const files of [[{name:'../secret',content:'x'}],[{name:'x',content:'a'},{name:'x',content:'b'}],Array.from({length:33},(_,i)=>({name:String(i),content:'x'})),[{name:'x',content:'x'.repeat(262145)}]]){
 const a=onlineSetup();const status=a.adapter.restore({code:'BAD',input:'BAD',project:JSON.stringify({files})});assert.equal(status,'invalid');assert.equal(a.files()[0].content,'// default');assert.equal(a.nodes.stdinput.value,'7 35\n');
 }
});

test('OnlineGDB: missing optional template helper falls back to the initialized Ace editor',()=>{
 const a=onlineSetup();delete a.api.set_default_editor_content;assert.doesNotThrow(()=>a.adapter.initialize('STARTER'));assert.equal(a.adapter.capture().code,'STARTER');
});

test('OnlineGDB: late site startup cannot discard the starter or overwrite a restored draft',()=>{
 for(const saved of [false,true]){
 const a=onlineSetup();const timers=[];a.window.setTimeout=fn=>timers.push(fn);a.adapter.initialize('STARTER');
 a.files()[0].content='SITE DEFAULT';if(saved)a.adapter.restore({code:'SAVED',input:'42'});
 for(const run of timers)run();assert.equal(a.files()[0].content,saved?'SAVED':'STARTER');
 }
});
