// extension.js — VS Code activator for the NURL Language Server.
//
// Resolves the nurl-lsp binary, spawns it with stdio transport via
// vscode-languageclient, and wires its diagnostics into the editor.
// Falls back gracefully:
//
//   1. `nurl.server.path` workspace/user setting (absolute path)
//   2. <workspaceFolder>/build/nurl-lsp (the project's own build)
//   3. PATH lookup for `nurl-lsp`
//
// If none of those resolve to an executable, we surface a friendly
// notification and skip starting the client — syntax highlighting
// keeps working independently of the LSP path.

const path  = require('path');
const fs    = require('fs');
const vscode = require('vscode');
const { LanguageClient, TransportKind } =
    require('vscode-languageclient/node');

let client = null;

function resolveServerPath(context) {
    const cfg = vscode.workspace.getConfiguration('nurl');
    const explicit = (cfg.get('server.path') || '').trim();
    if (explicit && isExecutable(explicit)) return explicit;

    // Look in the workspace's build/ directory.
    const folders = vscode.workspace.workspaceFolders || [];
    for (const f of folders) {
        const candidate = path.join(f.uri.fsPath, 'build', 'nurl-lsp');
        if (isExecutable(candidate)) return candidate;
    }

    // PATH fallback — let the OS resolve.
    if (commandExists('nurl-lsp')) return 'nurl-lsp';

    return null;
}

function isExecutable(p) {
    try {
        fs.accessSync(p, fs.constants.X_OK);
        return true;
    } catch {
        return false;
    }
}

function commandExists(cmd) {
    const sep = process.platform === 'win32' ? ';' : ':';
    const exts = process.platform === 'win32'
        ? (process.env.PATHEXT || '').split(';')
        : [''];
    const dirs = (process.env.PATH || '').split(sep);
    for (const d of dirs) {
        for (const ext of exts) {
            const full = path.join(d, cmd + ext);
            if (isExecutable(full)) return true;
        }
    }
    return false;
}

function activate(context) {
    const serverPath = resolveServerPath(context);
    if (!serverPath) {
        vscode.window.showWarningMessage(
            "NURL: 'nurl-lsp' binary not found. Run ./tools/nurl-lsp/build.sh, " +
            "or set 'nurl.server.path' in settings. Syntax highlighting still works."
        );
        return;
    }

    const serverOptions = {
        run:   { command: serverPath, args: [], transport: TransportKind.stdio },
        debug: { command: serverPath, args: [], transport: TransportKind.stdio },
    };

    const clientOptions = {
        documentSelector: [{ scheme: 'file', language: 'nurl' }],
        // Surface server stderr in the OutputChannel for debugging.
        outputChannelName: 'NURL Language Server',
        synchronize: {
            // The server doesn't care about config changes yet, but
            // hooking these up keeps the option open.
            configurationSection: 'nurl',
        },
    };

    client = new LanguageClient(
        'nurl-lsp',
        'NURL Language Server',
        serverOptions,
        clientOptions
    );

    client.start();
    context.subscriptions.push({
        dispose: () => client && client.stop(),
    });
}

function deactivate() {
    if (!client) return undefined;
    return client.stop();
}

module.exports = { activate, deactivate };
