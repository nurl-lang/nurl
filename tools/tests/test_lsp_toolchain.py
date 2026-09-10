#!/usr/bin/env python3
"""Exercise real compiler/LSP binaries outside their source checkout."""
import concurrent.futures
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


def run_process(command, *, input, timeout=30, **kwargs):
    # A hung compiler is the LSP's child. Reap the whole test process group,
    # rather than leaving it alive when communicate times out on the server.
    process = subprocess.Popen(command, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                               stderr=subprocess.PIPE, start_new_session=os.name == 'posix', **kwargs)
    try:
        stdout, stderr = process.communicate(input, timeout=timeout)
    except subprocess.TimeoutExpired:
        if os.name == 'posix':
            os.killpg(process.pid, signal.SIGKILL)
        else:
            process.kill()
        process.communicate()
        raise
    return subprocess.CompletedProcess(command, process.returncode, stdout, stderr)


def frame(message):
    body = json.dumps({'jsonrpc': '2.0', **message}, ensure_ascii=False).encode()
    return f'Content-Length: {len(body)}\r\n\r\n'.encode() + body


def messages(data):
    result = []
    while data:
        header, data = data.split(b'\r\n\r\n', 1)
        fields = dict(line.split(b':', 1) for line in header.split(b'\r\n'))
        length = int(fields[b'Content-Length'])
        if len(data) < length:
            raise AssertionError('truncated LSP frame')
        result.append(json.loads(data[:length]))
        data = data[length:]
    return result


class ToolchainTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.suite_tmp = tempfile.TemporaryDirectory(prefix='nurl-installed-lsp-')
        cls.addClassCleanup(cls.suite_tmp.cleanup)
        cls.prefix = Path(cls.suite_tmp.name) / 'tool chain'
        cls.bin = cls.prefix / 'bin'
        cls.bin.mkdir(parents=True)
        for name in ('nurlc', 'nurlfmt', 'nurl-lsp'):
            source = ROOT / 'build' / name
            if not source.is_file():
                raise RuntimeError(f'Build {source} before running this suite')
            shutil.copy2(source, cls.bin / name)
        # Ship sources, without linking anything back to the source checkout.
        for source in (ROOT / 'stdlib').rglob('*.nu'):
            target = cls.prefix / 'stdlib' / source.relative_to(ROOT / 'stdlib')
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, target)
        cls.env = {k: v for k, v in os.environ.items()
                   if k not in ('NURLC', 'NURLFMT', 'NURL_STDLIB')}
        cls.env['PATH'] = os.defpath
        # Local debug info suffices; optional debuginfod downloads must not
        # turn a sanitizer report into an unbounded network wait.
        cls.env['DEBUGINFOD_URLS'] = ''

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='nurl-project-')
        self.addCleanup(self.tmp.cleanup)
        self.project = Path(self.tmp.name)
        self.source = self.project / 'unsaved ä # %.nu'

    def compiler(self, text, *options, path=None):
        run = run_process([str(self.bin / 'nurlc'), *options, '--', str(path or self.source)],
                              input=text.encode(), cwd=self.project,
                              env={**self.env, 'NURL_STDLIB': str(self.prefix)}, timeout=30)
        self.assertNotIn(b'Sanitizer', run.stderr)
        self.assertNotIn(b'runtime error:', run.stderr)
        return run

    def session(self, text, *, options=None, requests=(), source=None, env=None, command=None, cwd=None):
        source = source or self.source
        uri = source.as_uri()
        requests = [
            {'id': 1, 'method': 'initialize', 'params': {
                'rootUri': self.project.as_uri(), 'capabilities': {},
                'initializationOptions': options or {}}},
            {'method': 'initialized', 'params': {}},
            {'method': 'textDocument/didOpen', 'params': {'textDocument': {
                'uri': uri, 'languageId': 'nurl', 'version': 1, 'text': text}}},
            *requests,
            {'id': 99, 'method': 'shutdown'}, {'method': 'exit'}]
        run = run_process([command or str(self.bin / 'nurl-lsp')],
                             input=b''.join(map(frame, requests)),
                             # Deliberately neither the project nor the repository.
                             cwd=cwd or self.prefix, env=env or self.env, timeout=30)
        self.assertEqual(run.returncode, 0, run.stderr.decode(errors='replace'))
        self.assertNotIn(b'Sanitizer', run.stderr + run.stdout)
        self.assertNotIn(b'runtime error:', run.stderr + run.stdout)
        responses = messages(run.stdout)
        self.assertTrue(any(r.get('id') == 99 and 'result' in r for r in responses), responses)
        diagnostics = [r['params']['diagnostics'] for r in responses
                       if r.get('method') == 'textDocument/publishDiagnostics']
        self.assertTrue(diagnostics, responses)
        return diagnostics, responses

    def test_stdin_preserves_ir_and_logical_path(self):
        (self.project / 'helper.nu').write_text('pub @ answer → i { ^ 42 }\n')
        text = '$ `helper.nu`\n@ main → i { ^ ( answer ) }\n'
        self.source.write_text(text)
        disk = self.compiler('', '--g')
        pipe = self.compiler(text, '--stdin', '--g')
        self.assertEqual(disk.returncode, 0, disk.stderr)
        self.assertEqual(pipe.returncode, 0, pipe.stderr)
        self.assertEqual(disk.stdout, pipe.stdout)
        self.source.write_text('@ main → i { ^ stale_disk_name }')
        updated = self.compiler(text, '--stdin', '--g')
        self.assertEqual(updated.stdout, disk.stdout)
        self.source.unlink()
        self.assertEqual(self.compiler(text, '--stdin', '--g').stdout, disk.stdout)

    def test_check_has_no_output_or_split_side_effects(self):
        run = self.compiler('@ main → i { ^ 0 }', '--stdin', '--check', '--split=2',
                            '--split-min=1', f'--split-out={self.project / "part"}')
        self.assertEqual(run.returncode, 0, run.stderr)
        self.assertEqual(run.stdout, b'')
        self.assertEqual(list(self.project.glob('part.*')), [])
        bad = self.compiler('@ main → i { ^ missing_symbol }', '--stdin', '--check')
        self.assertNotEqual(bad.returncode, 0)
        self.assertEqual(bad.stdout, b'')
        self.assertIn(b'missing_symbol', bad.stderr)

    def test_cli_rejects_unknown_option_and_multiple_files(self):
        for args in [('--stdiin',), ('--stdin', 'second.nu')]:
            with self.subTest(args=args):
                run = self.compiler('@ main → i { ^ 0 }', *args)
                self.assertNotEqual(run.returncode, 0)
                self.assertEqual(run.stdout, b'')

    def test_stdin_growth_and_crlf_preserve_source(self):
        for size in [0, 1, 4095, 4096, 4097, 65536]:
            with self.subTest(size=size):
                text = '// ' + 'x' * size + '\r\n@ main → i { ^ absent_after_large_comment }\r\n'
                run = self.compiler(text, '--stdin', '--check')
                self.assertNotEqual(run.returncode, 0)
                self.assertIn(b':2:', run.stderr)
                self.assertIn(b'absent_after_large_comment', run.stderr)

    def test_external_project_reports_unsaved_error(self):
        self.source.write_text('@ main → i { ^ 0 }')
        diags, _ = self.session('@ main → i { ^ missing_unsaved }')
        self.assertTrue(any('missing_unsaved' in d['message'] for d in diags[0]), diags)
        self.assertEqual(self.source.read_text(), '@ main → i { ^ 0 }')

    def test_sibling_dependency_and_stdlib_imports(self):
        (self.project / 'helper.nu').write_text('pub @ answer → i { ^ 42 }\n')
        dependency = self.project / 'deps' / 'answer'
        dependency.mkdir(parents=True)
        (dependency / 'lib.nu').write_text('pub @ other → i { ^ 1 }\n')
        subdir = self.project / 'src'
        subdir.mkdir()
        diags, _ = self.session('$ `helper.nu`\n$ `deps/answer/lib.nu`\n'
                                '$ `stdlib/core/string.nu`\n'
                                '@ main → i { : String s ( string_from `ok` ) '
                                '( string_free s ) ^ + ( answer ) ( other ) }',
                                source=subdir / 'main.nu')
        self.assertFalse([d for d in diags[0] if d['severity'] == 1], diags)

    def test_path_launch_discovers_installed_stdlib(self):
        decoy = self.project / 'decoy'
        (decoy / 'nurlc').mkdir(parents=True)
        env = {**self.env, 'PATH': str(decoy) + os.pathsep + str(self.bin) + os.pathsep + os.defpath}
        diags, _ = self.session('$ `stdlib/core/string.nu`\n@ main → i { '
            ': String text ( string_new ) ( string_free text ) ^ 0 }',
            command='nurl-lsp', env=env, cwd=self.project)
        self.assertFalse([d for d in diags[0] if d['severity'] == 1], diags)

    def test_check_self_compile_from_stdin(self):
        run = self.compiler((ROOT / 'compiler/nurlc.nu').read_text(), '--check', '--stdin')
        self.assertEqual(run.returncode, 0, run.stderr)
        self.assertEqual(run.stdout, b'')
        self.assertEqual(run.stderr, b'')

    def test_relative_configuration_survives_workspace_chdir(self):
        diags, _ = self.session('@ main → i { ^ missing_configured }',
            options={'compilerPath': 'bin/nurlc', 'formatterPath': 'bin/nurlfmt'})
        self.assertTrue(any('missing_configured' in d['message'] for d in diags[0]), diags)

    def test_explicit_configuration_overrides_environment(self):
        diags, _ = self.session('@ main → i { ^ missing_explicit }',
            options={'compilerPath': str(self.bin / 'nurlc')},
            env={**self.env, 'NURLC': str(self.bin / 'absent')})
        self.assertTrue(any('missing_explicit' in d['message'] for d in diags[0]), diags)

    def test_missing_or_incompatible_compiler_is_visible(self):
        for name in ('missing-nurlc', 'nurlfmt'):
            with self.subTest(name=name):
                diags, _ = self.session('@ main → i { ^ 0 }',
                    options={'compilerPath': str(self.bin / name)})
                self.assertTrue(any(d['severity'] == 1 and 'compiler' in d['message']
                                    for d in diags[0]), diags)

    def test_missing_formatter_is_request_error(self):
        _, responses = self.session('@ main → i { ^ 0 }',
            options={'formatterPath': str(self.bin / 'missing-formatter')},
            requests=[{'id': 2, 'method': 'textDocument/formatting',
                       'params': {'textDocument': {'uri': self.source.as_uri()}, 'options': {}}}])
        response = next(r for r in responses if r.get('id') == 2)
        self.assertEqual(response['error']['code'], -32603, response)

    def test_formatting_eof_uses_utf16(self):
        for text in ['', '@ main → i { ^ 0 }', '@ main → i { ^ 0 } // 😀',
                     '@ main → i { ^ 0 }\n']:
            with self.subTest(text=text):
                _, responses = self.session(text, requests=[{
                    'id': 2, 'method': 'textDocument/formatting',
                    'params': {'textDocument': {'uri': self.source.as_uri()}, 'options': {}}}])
                response = next(r for r in responses if r.get('id') == 2)
                self.assertIn('result', response)
                edit = response['result'][0]
                lines = text.split('\n')
                self.assertEqual(edit['range']['end'], {
                    'line': len(lines) - 1,
                    'character': len(lines[-1].encode('utf-16-le')) // 2})

    def test_borrow_diagnostic_uses_unsaved_source(self):
        text = (ROOT / 'compiler/tests/borrow_use_after_move.nu').read_text()
        self.source.write_text('@ main → i { ^ 0 }')
        run = self.compiler(text, '--stdin', '--check')
        self.assertIn(b': i n ( vec_len [i] v )', run.stderr)
        diags, _ = self.session(text)
        moved = next(d for d in diags[0] if "use of moved value 'v'" in d['message'])
        self.assertEqual(moved['range']['start']['line'], 10)
        self.assertEqual(moved['range']['start']['character'], 0)
        self.assertNotIn('compiler failed:', moved['message'])

    def test_diagnostic_columns_count_utf16(self):
        text = '@ main → i { ( nurl_print `😀ä` ) ^ missing_after_unicode }'
        diags, _ = self.session(text)
        error = next(d for d in diags[0] if 'missing_after_unicode' in d['message'])
        expected = len(text[:text.index('missing_after_unicode')].encode('utf-16-le')) // 2
        self.assertEqual(error['range']['start'], {'line': 0, 'character': expected})

    def test_colons_inside_source_path(self):
        diags, _ = self.session('@ main → i { ^ missing_colon_file }',
                                source=self.project / 'drive:12:part.nu')
        error = next(d for d in diags[0] if 'missing_colon_file' in d['message'])
        self.assertNotIn('compiler failed:', error['message'])
        self.assertEqual(error['range']['start']['character'], 15)

    def test_import_error_preserves_related_location(self):
        imported = self.project / 'broken ä #.nu'
        imported.write_text('pub @ answer → i { ^ imported_missing }')
        diags, _ = self.session('$ `broken ä #.nu`\n@ main → i { ^ ( answer ) }')
        error = next(d for d in diags[0] if 'imported_missing' in d['message'])
        related = error['relatedInformation'][0]['location']
        self.assertEqual(related['uri'], imported.as_uri())
        self.assertEqual(related['range']['start'], {'line': 0, 'character': 21})

    def test_definition_uri_encodes_path(self):
        imported = self.project / 'helper ä # %.nu'
        imported.write_text('pub @ answer → i { ^ 42 }')
        text = '$ `helper ä # %.nu`\n@ main → i { ^ ( answer ) }'
        _, responses = self.session(text, requests=[{
            'id': 2, 'method': 'textDocument/definition', 'params': {
                'textDocument': {'uri': self.source.as_uri()},
                'position': {'line': 1, 'character': 18}}}])
        response = next(r for r in responses if r.get('id') == 2)
        result = response['result']
        location = result[0] if isinstance(result, list) else result
        self.assertEqual(location['uri'], imported.as_uri())

    @unittest.skipIf(os.name == 'nt', 'POSIX executable fault-injection script')
    def test_failed_compiler_with_only_warning_is_visible(self):
        fake = self.project / 'compiler-control'
        fake.write_text(f'#!{sys.executable}\n' +
            'import sys\n'
            'if "--help" in sys.argv:\n'
            ' print("--stdin --check"); sys.exit(0)\n'
            'sys.stdin.buffer.read()\n'
            'print(sys.argv[-1] + ":1:1: warning: injected warning", file=sys.stderr)\n'
            'sys.exit(66)\n')
        fake.chmod(0o755)
        diags, _ = self.session('@ main → i { ^ 0 }', options={'compilerPath': str(fake)})
        self.assertTrue(any(d['severity'] == 2 for d in diags[0]), diags)
        self.assertTrue(any(d['severity'] == 1 and '66' in d['message'] for d in diags[0]), diags)

    def test_concurrent_servers_do_not_share_source(self):
        with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
            futures = [pool.submit(self.session, f'@ main → i {{ ^ absent_{i} }}') for i in range(2)]
            for i, future in enumerate(futures):
                diags, _ = future.result()
                rendered = json.dumps(diags)
                self.assertIn(f'absent_{i}', rendered)
                self.assertNotIn(f'absent_{1-i}', rendered)


if __name__ == '__main__':
    unittest.main(verbosity=2)
