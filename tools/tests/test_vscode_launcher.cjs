#!/usr/bin/env node
// Exercise the real extension through mocked VS Code interfaces; no editor needed.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const source = fs.readFileSync(path.join(__dirname, '../../tooling/vscode-nurl/extension.js'), 'utf8');
function launch({ settings = {}, files = [], platform = 'linux', env = {}, folders = [] }) {
  let options;
  const warnings = [];
  const vscode = {
    workspace: {
      getConfiguration: () => ({ get: key => settings[key] }),
      workspaceFolders: folders.map(fsPath => ({ uri: { fsPath } })),
    },
    window: { showWarningMessage: message => warnings.push(message) },
  };
  class LanguageClient {
    constructor(_id, _name, server, client) { options = { server, client }; }
    start() {}
    stop() {}
  }
  const module = { exports: {} };
  const hostPath = platform === 'win32' ? path.win32 : path.posix;
  vm.runInNewContext(source, {
    module, process: { platform, env },
    require(name) {
      if (name === 'path') return hostPath;
      if (name === 'fs') return {
        constants: fs.constants,
        accessSync(p) { if (!files.includes(p)) throw new Error('missing'); },
        statSync: () => ({ isFile: () => true }),
      };
      if (name === 'vscode') return vscode;
      if (name === 'vscode-languageclient/node') return { LanguageClient, TransportKind: { stdio: 0 } };
      throw new Error(name);
    },
  });
  module.exports.activate({ subscriptions: [] });
  return { options, warnings };
}
let run = launch({ files: ['/opt/nurl/bin/nurl-lsp'], env: { PATH: '/opt/nurl/bin:/usr/bin' },
  settings: { 'compiler.path': '/tools/nurlc', 'formatter.path': '/tools/nurlfmt', stdlibRoot: '/tools' } });
assert.equal(run.options.server.run.command, '/opt/nurl/bin/nurl-lsp');
assert.equal(run.options.client.initializationOptions.compilerPath, '/tools/nurlc');
assert.equal(run.options.client.initializationOptions.formatterPath, '/tools/nurlfmt');
assert.equal(run.options.client.initializationOptions.stdlibRoot, '/tools');
run = launch({ settings: { 'server.path': '/missing' },
  files: ['/opt/nurl/bin/nurl-lsp'], env: { PATH: '/opt/nurl/bin' } });
assert.equal(run.options, undefined, 'an explicit invalid path must not select a different toolchain');
assert.equal(run.warnings.length, 1);
run = launch({ platform: 'win32', env: { PATH: 'C:\\Nurl;C:\\Windows', PATHEXT: '.EXE' },
  files: ['C:\\Nurl\\nurl-lsp.EXE'] });
assert.equal(run.options.server.run.command, 'C:\\Nurl\\nurl-lsp.EXE');
run = launch({ platform: 'win32', folders: ['C:\\Project'], files: ['C:\\Project\\build\\nurl-lsp.exe'] });
assert.equal(run.options.server.run.command, 'C:\\Project\\build\\nurl-lsp.exe');
console.log('VS Code launcher: resolved paths, tool configuration, explicit failure and Windows path controls pass');
