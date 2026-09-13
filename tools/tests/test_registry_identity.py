#!/usr/bin/env python3
"""Signed, isolated registry identities through the real package CLI."""
import gzip
import hashlib
import http.server
import io
import json
import os
from pathlib import Path
import subprocess
import tarfile
import tempfile
import threading
import tomllib
import unittest

from signed_registry_fixture import make_key, sign_file

ROOT = Path(__file__).resolve().parents[2]


class RegistryIdentityTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.binary = Path(os.environ.get('NURLPKG', ROOT / 'build/nurlpkg')).resolve()
        cls.compiler = Path(os.environ.get('NURLC', ROOT / 'build/nurlc')).resolve()
        cls.tmp = tempfile.TemporaryDirectory(prefix='nurl-registry-keys-')
        cls.addClassCleanup(cls.tmp.cleanup)
        cls.keys = {registry: make_key(cls.tmp.name, index + 1)
                    for index, registry in enumerate(['a', 'b'])}

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='nurl-registry-project-')
        self.addCleanup(self.temp.cleanup)
        self.project = Path(self.temp.name)
        self.routes = {}
        self.requests = []
        self.statuses = {}
        self.disconnect = set()
        self.before_get = None
        owner = self
        class Handler(http.server.BaseHTTPRequestHandler):
            def do_POST(self):
                owner.requests.append(self.path)
                self.send_response(500)
                self.send_header('Content-Length', '0')
                self.end_headers()

            def do_GET(self):
                owner.requests.append(self.path)
                if owner.before_get:
                    owner.before_get(self.path)
                if self.path in owner.disconnect:
                    self.close_connection = True
                    return
                body = owner.routes.get(self.path)
                self.send_response(owner.statuses.get(self.path, 200 if body is not None else 404))
                body = body if body is not None else b'not found'
                self.send_header('Content-Length', str(len(body)))
                self.end_headers()
                self.wfile.write(body)
            def log_message(self, *args):
                pass
        self.server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Handler)
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        self.addCleanup(self.stop_server)
        self.base = f'http://127.0.0.1:{self.server.server_port}'
        self.config = self.project / 'registries.toml'
        self.configure({'a': 'a', 'b': 'b'})
        self.env = {key: value for key, value in os.environ.items()
                    if key not in ['NURL_REGISTRY', 'NURL_REGISTRY_PUBKEY', 'NURL_REGISTRY_CONFIG']}
        self.env.update(NURL_REGISTRY_CONFIG=str(self.config), NURL_NO_UPDATE_CHECK='1',
                        DEBUGINFOD_URLS='', ASAN_OPTIONS=os.environ.get(
                            'ASAN_OPTIONS', 'detect_leaks=0:halt_on_error=1'),
                        UBSAN_OPTIONS='halt_on_error=1')

    def stop_server(self):
        self.server.shutdown()
        self.server.server_close()
        self.thread.join(timeout=5)

    def configure(self, keys):
        self.config.write_text('[registries]\n' + ''.join(
            f'"{self.base}/{registry}/" = "{self.keys[key][2]}"\n'
            for registry, key in keys.items()))

    def package(self, registry, name, *, deps=(), identity=None, version='1.0.0',
                extra=(), signature=True, contents=None, nurl_version=None):
        actual_name, actual_version = identity or (name, version)
        manifest = f'[package]\nname="{actual_name}"\nversion="{actual_version}"\n'
        if nurl_version is not None:
            manifest += f'nurl-version="{nurl_version}"\n'
        if deps:
            manifest += '[dependencies]\n' + ''.join(f'{dep}="^1"\n' for dep in deps)
        files = [('nurl.toml', manifest.encode()),
                 ('lib.nu', contents or f'@ {name}_answer → i {{ ^ {11 if registry == "a" else 22} }}\n'.encode()),
                 ('origin.txt', registry.encode()), *extra]
        archive = io.BytesIO()
        with tarfile.open(fileobj=archive, mode='w', format=tarfile.USTAR_FORMAT) as tar:
            for path, data in files:
                entry = tarfile.TarInfo(path)
                entry.size = len(data)
                entry.mode = 0o644
                tar.addfile(entry, io.BytesIO(data))
        data = gzip.compress(archive.getvalue(), mtime=0)
        url = f'/{registry}/pkgs/{name}/{name}-{version}.tar.gz'
        self.routes[url] = data
        if signature:
            payload = self.project / 'sign-input'
            payload.write_bytes(data)
            self.routes[url + '.minisig'] = sign_file(payload, self.keys[registry])
        self.routes[f'/{registry}/index/{name}.json'] = json.dumps({
            'name': name, 'versions': [{'version': version, 'checksum': hashlib.sha256(data).hexdigest(),
                'deps': [{'name': dep, 'req': '^1'} for dep in deps]}]}).encode()
        return url

    def manifest(self, dependencies, *, default='a'):
        self.project.joinpath('nurl.toml').write_text(
            f'[package]\nname="consumer"\nversion="1.0.0"\nregistry="{self.base}/{default}/"\n'
            '[dependencies]\n' + ''.join(f'{name}={{version="^1",registry="{self.base}/{registry}/"}}\n'
                                         for name, registry in dependencies))

    def run_pkg(self, *args, env=None):
        run = subprocess.run([str(self.binary), *args], cwd=self.project,
                             capture_output=True, env=env or self.env, timeout=30)
        self.assertNotIn(b'Sanitizer', run.stdout + run.stderr)
        self.assertNotIn(b'runtime error:', run.stdout + run.stderr)
        return run

    def assert_failed_without_publish(self, *, token=None, env=None):
        lock = self.project / 'nurl.lock'
        lock.write_bytes(b'prior lock must survive\n')
        run = self.run_pkg('install', env=env)
        self.assertNotEqual(run.returncode, 0, run.stdout)
        self.assertNotIn(b'dependencies installed', run.stdout)
        self.assertEqual(lock.read_bytes(), b'prior lock must survive\n')
        if token:
            self.assertIn(token, run.stderr)
        return run

    def test_explicit_registry_and_transitive_origin_survive_install(self):
        self.package('a', 'foo')
        self.package('b', 'bar')
        self.package('b', 'foo', deps=['bar'], contents=b'$ `deps/bar/lib.nu`\n@ foo_answer ' + '→ i { ^ ( bar_answer ) }\n'.encode())
        self.manifest([('foo', 'b')])
        run = self.run_pkg('install')
        self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
        self.assertTrue(all(path.startswith('/b/') for path in self.requests), self.requests)
        for name in ['foo', 'bar']:
            self.assertEqual((self.project / 'deps' / name / 'origin.txt').read_bytes(), b'b')
        lock = tomllib.loads((self.project / 'nurl.lock').read_text())
        self.assertEqual({p['name'] for p in lock['package']}, {'foo', 'bar'})
        self.assertTrue(all(p['source'] == f'registry+{self.base}/b/' for p in lock['package']))
        source = self.project / 'main.nu'
        source.write_text('$ `deps/foo/lib.nu`\n@ main → i { ( nurl_println_int ( foo_answer ) ) ^ 0 }\n')
        built = subprocess.run([str(ROOT / 'nurl.sh'), str(source), str(self.project / 'app')],
                               cwd=self.project, env=self.env, capture_output=True, timeout=60)
        self.assertEqual(built.returncode, 0, built.stdout + built.stderr)
        app = subprocess.run([str(self.project / 'app')], capture_output=True, env=self.env, timeout=10)
        self.assertEqual((app.returncode, app.stdout, app.stderr), (0, b'22\n', b''))

    def test_backtracking_installs_only_the_selected_signed_version(self):
        first = self.package('b', 'foo')
        index = '/b/index/foo.json'
        old = json.loads(self.routes[index])['versions'][0]
        second = self.package('b', 'foo', version='2.0.0', deps=['bar'])
        versions = json.loads(self.routes[index])
        versions['versions'].append(old)
        self.routes[index] = json.dumps(versions).encode()
        self.package('b', 'bar', deps=['foo'])
        self.manifest([('foo', 'b')])
        manifest = self.project / 'nurl.toml'
        manifest.write_text(manifest.read_text().replace('version="^1"', 'version="*"'))
        installed = self.run_pkg('install')
        self.assertEqual(installed.returncode, 0, installed.stdout + installed.stderr)
        self.assertIn(first, self.requests)
        self.assertNotIn(second, self.requests)
        self.assertFalse(any('/pkgs/bar/' in path for path in self.requests))
        self.assertFalse((self.project / 'deps/bar').exists())
        package, = tomllib.loads((self.project / 'nurl.lock').read_text())['package']
        self.assertEqual((package['name'], package['version']), ('foo', '1.0.0'))

    def fallback_graph(self):
        first = self.package('b', 'foo')
        index = '/b/index/foo.json'
        old = json.loads(self.routes[index])['versions'][0]
        self.package('b', 'foo', version='2.0.0', deps=['bar'])
        versions = json.loads(self.routes[index])
        versions['versions'].append(old)
        self.routes[index] = json.dumps(versions).encode()
        self.manifest([('foo', 'b')])
        manifest = self.project / 'nurl.toml'
        manifest.write_text(manifest.read_text().replace('version="^1"', 'version="*"'))
        return first

    def test_missing_transitive_index_allows_a_real_fallback(self):
        first = self.fallback_graph()
        run = self.run_pkg('install')
        self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
        self.assertIn(first, self.requests)
        package, = tomllib.loads((self.project / 'nurl.lock').read_text())['package']
        self.assertEqual(package['version'], '1.0.0')

    def test_index_failure_cannot_silently_downgrade(self):
        for defect in ['server_error', 'unauthorized', 'malformed', 'empty', 'disconnect']:
            with self.subTest(defect=defect):
                self.fallback_graph()
                target = '/b/index/bar.json'
                self.requests.clear()
                self.statuses.clear()
                self.disconnect.clear()
                self.routes[target] = b'' if defect == 'empty' else b'invalid index'
                if defect in ['server_error', 'unauthorized']:
                    self.statuses[target] = 503 if defect == 'server_error' else 401
                if defect == 'disconnect':
                    self.disconnect.add(target)
                run = self.assert_failed_without_publish()
                if defect in ['server_error', 'unauthorized']:
                    self.assertIn(b'HTTP 503' if defect == 'server_error' else b'HTTP 401', run.stderr)
                    self.assertIn((self.base+'/b/index/bar.json').encode(), run.stderr)
                if defect == 'disconnect':
                    self.assertIn(b'request failed: transport', run.stderr)
                self.assertFalse(any('/pkgs/' in path for path in self.requests), self.requests)

    def test_registry_commands_report_http_failure(self):
        self.manifest([('foo', 'b')])
        self.statuses['/b/index/foo.json'] = 503
        env = {**self.env, 'NURL_REGISTRY': self.base+'/b/'}
        manifest = (self.project/'nurl.toml').read_bytes()
        for command in [('info', 'foo'), ('install', 'foo'), ('update', '--all')]:
            with self.subTest(command=command):
                run = self.run_pkg(*command, env=env)
                self.assertNotEqual(run.returncode, 0, run.stdout+run.stderr)
                self.assertIn(b'HTTP 503', run.stderr)
                self.assertNotIn(b'not found', run.stdout+run.stderr)
                self.assertNotIn(b'no published version', run.stdout+run.stderr)
                self.assertEqual((self.project/'nurl.toml').read_bytes(), manifest)
        self.assertFalse(any('/pkgs/' in path for path in self.requests), self.requests)

    def publish_project(self):
        self.manifest([])
        (self.project/'src').mkdir()
        (self.project/'src/main.nu').write_text('@ main → i { ^ 0 }\n')
        (self.project/'nurl.lock').write_bytes(b'prior lock must survive\n')
        return {**self.env, 'HOME': str(self.project/'home'), 'NURL_STDLIB': '',
                'NURL_TOKEN': 'isolated-publish-gate-test'}

    def publish_toolchain(self, name='toolchain'):
        temp = tempfile.TemporaryDirectory(prefix='nurl-publish-target-')
        self.addCleanup(temp.cleanup)
        root = Path(temp.name)/name
        (root/'bin').mkdir(parents=True)
        (root/'bin/nurlc').symlink_to(self.compiler)
        (root/'stdlib').symlink_to(ROOT/'stdlib', target_is_directory=True)
        return root

    def assert_publish_gate_failed(self, env, diagnostic):
        manifest = (self.project/'nurl.toml').read_bytes()
        for args in [('publish', '--dry-run'), ('publish',)]:
            run = self.run_pkg(*args, env=env)
            self.assertNotEqual(run.returncode, 0, run.stdout+run.stderr)
            self.assertIn(diagnostic, run.stderr)
            self.assertNotIn(b'every gate passed', run.stdout)
            self.assertEqual((self.project/'nurl.toml').read_bytes(), manifest)
            self.assertEqual((self.project/'nurl.lock').read_bytes(), b'prior lock must survive\n')
            self.assertEqual(self.requests, [])
        return run

    def test_publish_requires_installed_compiler(self):
        env = self.publish_project()
        self.assert_publish_gate_failed(env, b'no installed compiler')

    def test_publish_requires_toolchain_root(self):
        env = self.publish_project()
        del env['HOME']
        self.assert_publish_gate_failed(env, b'cannot locate the target toolchain')

    def test_publish_reports_compiler_launch_failure(self):
        env = self.publish_project()
        root = self.project/'unlaunchable'
        (root/'bin').mkdir(parents=True)
        (root/'bin/nurlc').write_text('not an executable\n')
        self.assert_publish_gate_failed({**env, 'NURL_STDLIB': str(root)},
                                       b'could not launch the installed compiler')

    def test_publish_preserves_compiler_diagnostics(self):
        env = self.publish_project()
        root = self.publish_toolchain()
        (self.project/'src/main.nu').write_text('@ main → i { ^ missing_symbol }\n')
        run = self.assert_publish_gate_failed({**env, 'NURL_STDLIB': str(root)}, b'missing_symbol')
        self.assertNotIn(b'every imported stdlib FILE exists', run.stderr)

    def test_publish_typechecks_every_library_source_module(self):
        env = self.publish_project()
        root = self.publish_toolchain()
        (self.project/'src/main.nu').unlink()
        (self.project/'src/lib.nu').write_text('@ answer → i { ^ 42 }\n')
        for path in ['src/independent.nu', 'src/nested/module.nu', 'root.nu']:
            with self.subTest(module=path):
                module = self.project/path
                module.parent.mkdir(parents=True, exist_ok=True)
                module.write_text('@ answer → i { ^ missing_library_symbol }\n')
                run = self.assert_publish_gate_failed(
                    {**env, 'NURL_STDLIB': str(root)}, b'missing_library_symbol')
                self.assertIn(path.encode(), run.stderr)
                module.unlink()
        run = self.run_pkg('publish', '--dry-run', env={**env, 'NURL_STDLIB': str(root)})
        self.assertEqual(run.returncode, 0, run.stdout+run.stderr)
        self.assertIn(b'every gate passed', run.stdout)

    def test_publish_library_requires_installed_compiler(self):
        env = self.publish_project()
        (self.project/'src/main.nu').rename(self.project/'src/lib.nu')
        self.assert_publish_gate_failed(env, b'no installed compiler')

    def test_publish_checks_minimum_against_selected_compiler(self):
        env = self.publish_project()
        root = self.publish_toolchain()
        manifest = self.project/'nurl.toml'
        original = manifest.read_text()
        manifest.write_text(original.replace('[package]', '[package]\nnurl-version="999.0.0"'))
        self.assert_publish_gate_failed({**env, 'NURL_STDLIB': str(root)}, b'requires NURL >= 999.0.0')
        manifest.write_text(original.replace('[package]', '[package]\nnurl-version="0.1.0"'))
        run = self.run_pkg('publish', '--dry-run', env={**env, 'NURL_STDLIB': str(root)})
        self.assertEqual(run.returncode, 0, run.stdout+run.stderr)

    def test_root_and_path_minimum_reject_before_link_or_lock(self):
        self.manifest([])
        manifest = self.project/'nurl.toml'
        original = manifest.read_text()
        manifest.write_text(original.replace('[package]', '[package]\nnurl-version="999.0.0"'))
        self.assert_failed_without_publish(token=b'requires NURL >= 999.0.0')
        target = self.project/'local/foo'
        target.mkdir(parents=True)
        (target/'nurl.toml').write_text('[package]\nname="foo"\nversion="1.0.0"\nnurl-version="999.0.0"\n')
        manifest.write_text(original+'foo={path="local/foo"}\n')
        self.assert_failed_without_publish(token=b'requires NURL >= 999.0.0')
        self.assertFalse((self.project/'deps/foo').exists())

    def test_signed_minimum_checked_before_extract_and_preserves_prior_install(self):
        self.package('b', 'foo', nurl_version='999.0.0')
        self.manifest([('foo', 'b')])
        self.assert_failed_without_publish(token=b'PkgToolchain')
        self.assertFalse((self.project/'deps/foo').exists())
        self.package('b', 'foo', nurl_version='0.1.0')
        run = self.run_pkg('install')
        self.assertEqual(run.returncode, 0, run.stdout+run.stderr)
        old = (self.project/'deps/foo/nurl.toml').read_bytes()
        self.package('b', 'foo', nurl_version='999.0.0')
        self.assert_failed_without_publish(token=b'PkgToolchain')
        self.assertEqual((self.project/'deps/foo/nurl.toml').read_bytes(), old)

    def test_existing_path_link_rechecks_changed_transitive_minimum(self):
        self.manifest([])
        manifest = self.project/'nurl.toml'
        manifest.write_text(manifest.read_text()+'foo={path="local/foo"}\n')
        foo, bar = self.project/'local/foo', self.project/'local/bar'
        foo.mkdir(parents=True)
        bar.mkdir()
        (foo/'nurl.toml').write_text('[package]\nname="foo"\nversion="1.0.0"\n[dependencies]\nbar={path="../bar"}\n')
        original = '[package]\nname="bar"\nversion="1.0.0"\n'
        (bar/'nurl.toml').write_text(original)
        run = self.run_pkg('install')
        self.assertEqual(run.returncode, 0, run.stdout+run.stderr)
        (bar/'nurl.toml').write_text(original+'nurl-version="999.0.0"\n')
        self.assert_failed_without_publish(token=b'bar requires NURL >= 999.0.0')

    def test_existing_directory_cannot_substitute_local_path_dependency(self):
        self.manifest([])
        manifest = self.project/'nurl.toml'
        original = manifest.read_text()
        manifest.write_text(original+'foo={path="local/foo"}\n')
        local, installed = self.project/'local/foo', self.project/'deps/foo'
        local.mkdir(parents=True)
        installed.mkdir(parents=True)
        (local/'nurl.toml').write_text('[package]\nname="foo"\nversion="1.0.0"\nnurl-version="0.1.0"\n')
        prior = '[package]\nname="foo"\nversion="2.0.0"\nnurl-version="999.0.0"\n'
        (installed/'nurl.toml').write_text(prior)
        self.assert_failed_without_publish(token=b'existing deps entry is not the declared path')
        self.assertEqual((installed/'nurl.toml').read_text(), prior)
        self.assertFalse(installed.is_symlink())
        # The caller can explicitly select the in-place directory; then that
        # actual manifest, including its minimum, is what must be checked.
        manifest.write_text(original+'foo={path="./deps/../deps/foo"}\n')
        self.assert_failed_without_publish(token=b'requires NURL >= 999.0.0')
        (installed/'nurl.toml').write_text(prior.replace('999.0.0', '0.1.0'))
        run = self.run_pkg('install')
        self.assertEqual(run.returncode, 0, run.stdout+run.stderr)

    def test_publish_compiler_paths_are_literal_arguments(self):
        env = self.publish_project()
        # A shell must never interpret either the spaces or this substitution.
        root = self.publish_toolchain('target $(touch EXECUTED) toolchain')
        run = self.run_pkg('publish', '--dry-run', env={**env, 'NURL_STDLIB': str(root)})
        self.assertFalse((self.project/'EXECUTED').exists())
        self.assertEqual(run.returncode, 0, run.stdout+run.stderr)
        self.assertIn(b'every gate passed', run.stdout)

    def test_publish_uses_default_installed_toolchain(self):
        env = self.publish_project()
        root = self.publish_toolchain('home/.nurl')
        env['HOME'] = str(root.parent)
        # Only this target has the imported module. A compiler-checkout fallback
        # cannot make this positive control pass.
        (root/'stdlib').unlink()
        (root/'stdlib').mkdir()
        (root/'stdlib/target_probe.nu').write_text('@ target_answer → i { ^ 7 }\n')
        (self.project/'src/main.nu').write_text(
            '$ `stdlib/target_probe.nu`\n@ main → i { ^ - ( target_answer ) 7 }\n')
        run = self.run_pkg('publish', '--dry-run', env=env)
        self.assertEqual(run.returncode, 0, run.stdout+run.stderr)
        self.assertIn(b'every gate passed', run.stdout)

    def test_publish_drift_check_refuses_failed_index(self):
        self.project.joinpath('src').mkdir()
        self.project.joinpath('src/main.nu').write_text('@ main → i { ^ 0 }\n')
        local = self.project/'local/foo'
        local.mkdir(parents=True)
        (local/'nurl.toml').write_text('[package]\nname="foo"\nversion="1.0.0"\n')
        self.project.joinpath('nurl.toml').write_text(
            f'[package]\nname="consumer"\nversion="1.0.0"\nregistry="{self.base}/b/"\n'
            '[dependencies]\nfoo={path="local/foo",version="^1"}\n')
        self.statuses['/b/index/foo.json'] = 503
        prefix = tempfile.TemporaryDirectory(prefix='nurl-registry-publish-toolchain-')
        self.addCleanup(prefix.cleanup)
        toolchain = Path(prefix.name)
        (toolchain/'bin').mkdir()
        (toolchain/'bin/nurlc').symlink_to(self.compiler)
        (toolchain/'stdlib').symlink_to(ROOT/'stdlib', target_is_directory=True)
        run = self.run_pkg('publish', '--dry-run', env={**self.env,
            'NURL_STDLIB': str(toolchain)})
        self.assertNotEqual(run.returncode, 0, run.stdout+run.stderr)
        self.assertIn(b'HTTP 503', run.stderr)
        self.assertIn('/b/index/foo.json', self.requests)
        self.assertNotIn(b'UNCHECKED', run.stderr)
        self.assertNotIn(b'every gate passed', run.stdout)

    def publish_override(self):
        env = self.publish_project()
        toolchain = self.publish_toolchain()
        local = self.project/'local/foo'
        local.mkdir(parents=True)
        (local/'nurl.toml').write_text('[package]\nname="foo"\nversion="1.0.0"\n')
        (local/'lib.nu').write_text('@ foo_answer → i { ^ 22 }\n')
        manifest = self.project/'nurl.toml'
        manifest.write_text(manifest.read_text()+
            f'foo={{path="local/foo",version="^1",registry="{self.base}/b/"}}\n')
        return {**env, 'NURL_STDLIB': str(toolchain)}, local

    def assert_override_refused(self, env, diagnostic):
        for command in [('publish', '--dry-run'), ('publish',)]:
            run = self.run_pkg(*command, env=env)
            self.assertNotEqual(run.returncode, 0, run.stdout+run.stderr)
            self.assertIn(diagnostic, run.stderr)
            self.assertNotIn(b'every gate passed', run.stdout)
        self.assertFalse(any('/api/' in path for path in self.requests), self.requests)
        self.assertEqual((self.project/'nurl.lock').read_bytes(), b'prior lock must survive\n')

    def test_publish_drift_verification_errors_refuse_publication(self):
        env, local = self.publish_override()
        for defect, diagnostic in [
                ('http', b'PkgHttp'), ('checksum', b'PkgChecksumMismatch'),
                ('signature', b'PkgBadSig'), ('identity', b'PkgBadIdentity'),
                ('minimum', b'PkgToolchain'), ('gzip', b'PkgDecompress'),
                ('extract', b'PkgUnpack')]:
            with self.subTest(defect=defect):
                self.routes.clear()
                self.statuses.clear()
                self.requests.clear()
                url = self.package('b', 'foo',
                    identity=('impostor', '1.0.0') if defect == 'identity' else None,
                    signature=defect != 'signature',
                    nurl_version='999.0.0' if defect == 'minimum' else None,
                    extra=[('../escape.nu', b'forbidden')] if defect == 'extract' else [])
                if defect == 'http':
                    self.statuses[url] = 503
                if defect == 'checksum':
                    self.routes[url] += b'changed'
                if defect == 'gzip':
                    self.routes[url] = b'not a gzip archive'
                    index = json.loads(self.routes['/b/index/foo.json'])
                    index['versions'][0]['checksum'] = hashlib.sha256(self.routes[url]).hexdigest()
                    self.routes['/b/index/foo.json'] = json.dumps(index).encode()
                    payload = self.project/'bad-gzip'
                    payload.write_bytes(self.routes[url])
                    self.routes[url+'.minisig'] = sign_file(payload, self.keys['b'])
                self.assert_override_refused(env, diagnostic)
                self.assertFalse((local/'escape.nu').exists())

    def test_publish_drift_requires_available_local_version(self):
        env, _ = self.publish_override()
        for defect in ['missing_package', 'missing_version', 'yanked']:
            with self.subTest(defect=defect):
                self.routes.clear()
                self.requests.clear()
                if defect != 'missing_package':
                    self.package('b', 'foo', version='1.1.0' if defect == 'missing_version' else '1.0.0')
                    if defect == 'yanked':
                        index = json.loads(self.routes['/b/index/foo.json'])
                        index['versions'][0]['yanked'] = True
                        self.routes['/b/index/foo.json'] = json.dumps(index).encode()
                self.assert_override_refused(env,
                    b'not found' if defect == 'missing_package' else b'not published and installable')
                self.assertFalse(any('/pkgs/' in path for path in self.requests))

    def test_publish_drift_validates_local_identity_and_requirement(self):
        env, local = self.publish_override()
        manifest = self.project/'nurl.toml'
        original = manifest.read_text()
        original_local = (local/'nurl.toml').read_text()
        for defect, diagnostic in [
                ('absent', b'local dependency manifest'),
                ('malformed', b'local dependency manifest'),
                ('name', b'name does not match'),
                ('version', b'invalid local dependency version'),
                ('requirement', b'invalid path dependency version requirement'),
                ('mismatch', b"but the local copy is"),
                ('no_requirement', b'no registry version requirement')]:
            with self.subTest(defect=defect):
                manifest.write_text(original)
                (local/'nurl.toml').write_text(original_local)
                if defect == 'absent':
                    (local/'nurl.toml').unlink()
                elif defect == 'malformed':
                    (local/'nurl.toml').write_text('not TOML')
                elif defect in ['name', 'version']:
                    (local/'nurl.toml').write_text(original_local.replace(
                        'foo' if defect == 'name' else '1.0.0',
                        'impostor' if defect == 'name' else 'invalid'))
                elif defect == 'requirement':
                    manifest.write_text(original.replace('version="^1"', 'version="invalid"'))
                elif defect == 'mismatch':
                    manifest.write_text(original.replace('version="^1"', 'version="^2"'))
                else:
                    manifest.write_text(original.replace('version="^1",', ''))
                self.assert_override_refused(env, diagnostic)
                self.assertEqual(self.requests, [])

    def test_publish_drift_compares_root_nested_and_relative_source_paths(self):
        env, local = self.publish_override()
        self.package('b', 'foo')
        # Correct explicit origin and matching root library are a positive control.
        self.package('a', 'foo', contents=b'wrong registry source')
        run = self.run_pkg('publish', '--dry-run', env=env)
        self.assertEqual(run.returncode, 0, run.stdout+run.stderr)
        self.assertTrue(all(path.startswith('/b/') for path in self.requests), self.requests)
        (local/'lib.nu').write_text('@ foo_answer → i { ^ 23 }\n')
        self.assert_override_refused(env, b'differs from the published')
        (local/'lib.nu').write_text('@ foo_answer → i { ^ 22 }\n')
        source = '@ nested_answer → i { ^ 7 }\n'.encode()
        nested = local/'src/a/module.nu'
        nested.parent.mkdir(parents=True)
        nested.write_bytes(source)
        for published in ['src/b/module.nu', 'src/a/module.nu']:
            self.package('b', 'foo', extra=[(published, source)])
            run = self.run_pkg('publish', '--dry-run', env=env)
            self.assertEqual(run.returncode, 0 if published == 'src/a/module.nu' else 1,
                             run.stdout+run.stderr)
        nested.write_text('@ nested_answer → i { ^ 8 }\n')
        self.assert_override_refused(env, b'differs from the published')
        nested.unlink()
        self.assert_override_refused(env, b'differs from the published')

    def test_publish_drift_uses_packaged_source_ignores(self):
        env, local = self.publish_override()
        self.package('b', 'foo')
        (local/'.gitignore').write_text('ignored.nu\n')
        for path in ['ignored.nu', 'src/ignored.nu', 'tests/fixture.nu', 'examples/demo.nu',
                     'build/generated.nu']:
            target = local/path
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text('deliberately invalid source ignored by the package source audit')
        run = self.run_pkg('publish', '--dry-run', env=env)
        self.assertEqual(run.returncode, 0, run.stdout+run.stderr)
        self.assertIn(b'every gate passed', run.stdout)

    @unittest.skipIf(os.name == 'nt' or (hasattr(os, 'geteuid') and os.geteuid() == 0),
                     'requires POSIX file read permissions')
    def test_publish_drift_source_inventory_failure_is_not_a_match(self):
        env, local = self.publish_override()
        url = self.package('b', 'foo')
        source = local/'lib.nu'
        temp = self.project/'comparison-temp'
        temp.mkdir()
        def remove_read_permission(path):
            if path == url+'.minisig':
                source.chmod(0)
        self.before_get = remove_read_permission
        try:
            run = self.run_pkg('publish', '--dry-run', env={**env, 'TMPDIR': str(temp)})
            self.assertNotEqual(run.returncode, 0, run.stdout+run.stderr)
            self.assertIn(b'cannot enumerate local dependency sources: PackReadFailed', run.stderr)
            self.assertNotIn(b'differs from the published', run.stderr)
            self.assertNotIn(b'every gate passed', run.stdout)
            self.assertEqual(list(temp.iterdir()), [])
        finally:
            source.chmod(0o644)

    def test_publish_drift_staging_is_private_and_cleaned(self):
        env, _ = self.publish_override()
        url = self.package('b', 'foo')
        temp = self.project/'comparison temporary root'
        temp.mkdir()
        legacy = temp/'nurlpkg-drift-foo'
        legacy.mkdir()
        (legacy/'sentinel').write_text('unrelated directory')
        seen = []
        barrier = threading.Barrier(2)
        def hold_signature(path):
            if path == url+'.minisig':
                barrier.wait(timeout=15)
                seen.append({p.name for p in temp.glob('nurlpkg-drift-*') if p != legacy})
                barrier.wait(timeout=15)
        self.before_get = hold_signature
        processes = [subprocess.Popen([str(self.binary), 'publish', '--dry-run'],
            cwd=self.project, env={**env, 'TMPDIR': str(temp)},
            stdout=subprocess.PIPE, stderr=subprocess.PIPE) for _ in range(2)]
        try:
            for process in processes:
                out, err = process.communicate(timeout=30)
                self.assertEqual(process.returncode, 0, out+err)
                self.assertNotIn(b'Sanitizer', out+err)
                self.assertNotIn(b'runtime error:', out+err)
        finally:
            for process in processes:
                if process.poll() is None:
                    process.kill()
                    process.wait()
        self.assertEqual(len(seen), 2)
        self.assertTrue(all(len(names) == 2 for names in seen), seen)
        self.assertEqual(seen[0], seen[1])
        self.assertEqual((legacy/'sentinel').read_text(), 'unrelated directory')
        self.assertEqual(list(temp.iterdir()), [legacy])

    def test_two_registries_use_independent_keys(self):
        self.package('a', 'alpha')
        self.package('b', 'bravo')
        self.manifest([('alpha', 'a'), ('bravo', 'b')])
        run = self.run_pkg('install')
        self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
        self.assertEqual((self.project / 'deps/alpha/origin.txt').read_bytes(), b'a')
        self.assertEqual((self.project / 'deps/bravo/origin.txt').read_bytes(), b'b')

    def test_wrong_registry_key_cannot_authorize_archive(self):
        self.package('b', 'foo')
        self.manifest([('foo', 'b')])
        self.configure({'a': 'a', 'b': 'a'})
        self.assert_failed_without_publish(token=b'PkgBadSig')
        self.assertFalse((self.project / 'deps/foo').exists())

    def test_missing_signature_rejects_matching_checksum(self):
        self.package('b', 'foo', signature=False)
        self.manifest([('foo', 'b')])
        self.assert_failed_without_publish(token=b'PkgBadSig')
        self.assertFalse((self.project / 'deps/foo').exists())

    def test_signed_wrong_manifest_identity_is_rejected(self):
        for identity in [('other', '1.0.0'), ('foo', '2.0.0')]:
            with self.subTest(identity=identity):
                self.package('b', 'foo', identity=identity)
                self.manifest([('foo', 'b')])
                self.assert_failed_without_publish(token=b'PkgBadIdentity')
                self.assertFalse((self.project / 'deps/foo').exists())

    def test_duplicate_manifest_and_late_unsafe_path_do_not_write_prefix(self):
        for extra, token in [([('./nurl.toml', b'[package]\nname="foo"\nversion="1.0.0"\n')], b'PkgBadIdentity'),
                             ([('../escape', b'bad')], b'PkgUnpack')]:
            with self.subTest(extra=extra):
                self.package('b', 'foo', extra=extra)
                self.manifest([('foo', 'b')])
                self.assert_failed_without_publish(token=token)
                self.assertFalse((self.project / 'deps/foo').exists())
                self.assertFalse((self.project / 'deps/escape').exists())

    def test_changed_bytes_or_checksum_cannot_bypass_signature(self):
        url = self.package('b', 'foo')
        self.manifest([('foo', 'b')])
        self.routes[url] += b'changed'
        self.assert_failed_without_publish(token=b'PkgChecksumMismatch')
        index_path = '/b/index/foo.json'
        index = json.loads(self.routes[index_path])
        index['versions'][0]['checksum'] = hashlib.sha256(self.routes[url]).hexdigest()
        self.routes[index_path] = json.dumps(index).encode()
        self.assert_failed_without_publish(token=b'PkgBadSig')
        self.assertFalse((self.project / 'deps/foo').exists())

    def test_index_name_and_required_checksum_are_checked(self):
        for defect, token in [('name', b'ResolveBadIndex'), ('checksum', b'ResolveBadIndex')]:
            with self.subTest(defect=defect):
                self.package('b', 'foo')
                self.manifest([('foo', 'b')])
                index = json.loads(self.routes['/b/index/foo.json'])
                if defect == 'name':
                    index['name'] = 'other'
                else:
                    del index['versions'][0]['checksum']
                self.routes['/b/index/foo.json'] = json.dumps(index).encode()
                self.assert_failed_without_publish(token=token)
                self.assertFalse((self.project / 'deps/foo').exists())

    def test_failed_authentication_preserves_existing_package(self):
        self.package('b', 'foo')
        self.manifest([('foo', 'b')])
        installed = self.run_pkg('install')
        self.assertEqual(installed.returncode, 0, installed.stderr)
        before = {p.relative_to(self.project): p.read_bytes()
                  for p in (self.project / 'deps').rglob('*') if p.is_file()}
        lock = (self.project / 'nurl.lock').read_bytes()
        self.configure({'b': 'a'})
        failed = self.run_pkg('install')
        self.assertNotEqual(failed.returncode, 0)
        self.assertIn(b'PkgBadSig', failed.stderr)
        self.assertEqual((self.project / 'nurl.lock').read_bytes(), lock)
        self.assertEqual(before, {p.relative_to(self.project): p.read_bytes()
                                 for p in (self.project / 'deps').rglob('*') if p.is_file()})

    def test_lock_error_and_version_drift_preserve_prior_lock(self):
        self.package('b', 'foo')
        self.manifest([('foo', 'b')])
        installed = self.run_pkg('install')
        self.assertEqual(installed.returncode, 0, installed.stderr)
        lock = self.project / 'nurl.lock'
        prior = lock.read_bytes()
        for invalid in [b'[[package', b'package = 7']:
            lock.write_bytes(invalid)
            failed = self.run_pkg('lock')
            self.assertNotEqual(failed.returncode, 0)
            self.assertEqual(lock.read_bytes(), invalid)
        lock.write_bytes(prior)
        manifest = self.project / 'deps/foo/nurl.toml'
        manifest.write_text(manifest.read_text().replace('1.0.0', '2.0.0'))
        failed = self.run_pkg('lock')
        self.assertNotEqual(failed.returncode, 0)
        self.assertIn(b'installed version differs', failed.stderr)
        self.assertEqual(lock.read_bytes(), prior)

    def test_local_lock_refresh_allows_development_version_change(self):
        self.manifest([])
        local = self.project / 'deps/local'
        local.mkdir(parents=True)
        manifest = local / 'nurl.toml'
        manifest.write_text('[package]\nname="local"\nversion="1.0.0"\n')
        first = self.run_pkg('lock')
        self.assertEqual(first.returncode, 0, first.stderr)
        manifest.write_text(manifest.read_text().replace('1.0.0', '2.0.0'))
        refreshed = self.run_pkg('lock')
        self.assertEqual(refreshed.returncode, 0, refreshed.stderr)
        package, = tomllib.loads((self.project / 'nurl.lock').read_text())['package']
        self.assertEqual((package['source'], package['version']), ('deps/local', '2.0.0'))
        self.assertNotIn('checksum', package)

    def test_lock_refuses_missing_or_renamed_registry_manifest(self):
        self.package('b', 'foo')
        self.manifest([('foo', 'b')])
        installed = self.run_pkg('install')
        self.assertEqual(installed.returncode, 0, installed.stderr)
        lock = self.project / 'nurl.lock'
        prior = lock.read_bytes()
        manifest = self.project / 'deps/foo/nurl.toml'
        original = manifest.read_text()
        for state in ['renamed', 'missing', 'local-substitute']:
            with self.subTest(state=state):
                lock.write_bytes(prior)
                if state == 'renamed':
                    manifest.write_text(original.replace('foo', 'other'))
                elif state == 'missing':
                    manifest.unlink()
                else:
                    local = self.project / 'deps/local'
                    local.mkdir()
                    (local / 'nurl.toml').write_text(original)
                failed = self.run_pkg('lock')
                self.assertNotEqual(failed.returncode, 0, failed.stdout)
                self.assertEqual(lock.read_bytes(), prior)

    def test_nul_cannot_truncate_index_identity_or_trust_config(self):
        for field in ['name', 'version', 'checksum', 'dep-name', 'dep-req', 'body', 'config']:
            with self.subTest(field=field):
                self.configure({'b': 'b'})
                self.package('b', 'bar')
                self.package('b', 'foo', deps=['bar'])
                self.manifest([('foo', 'b')])
                route = '/b/index/foo.json'
                index = json.loads(self.routes[route])
                if field == 'name':
                    index['name'] += '\0other'
                elif field in ['version', 'checksum']:
                    index['versions'][0][field] += '\0other'
                elif field.startswith('dep-'):
                    index['versions'][0]['deps'][0][field[4:]] += '\0other'
                self.routes[route] = json.dumps(index).encode()
                if field == 'body':
                    self.routes[route] += b'\0other'
                if field == 'config':
                    self.config.write_bytes(self.config.read_bytes() + b'\0other')
                self.requests.clear()
                token = b'trust configuration' if field == 'config' else b'ResolveBadIndex'
                self.assert_failed_without_publish(token=token)
                self.assertFalse(any('/pkgs/' in path for path in self.requests))

    def test_index_field_types_are_validated_before_resolution(self):
        for defect in ['versions', 'version-entry', 'yanked', 'deps', 'dep-entry', 'req', 'checksum']:
            with self.subTest(defect=defect):
                self.package('b', 'bar')
                self.package('b', 'foo', deps=['bar'])
                self.manifest([('foo', 'b')])
                route = '/b/index/foo.json'
                index = json.loads(self.routes[route])
                version = index['versions'][0]
                if defect == 'versions':
                    index['versions'] = {}
                elif defect == 'version-entry':
                    index['versions'] = [123]
                elif defect == 'yanked':
                    version['yanked'] = 'false'
                elif defect == 'deps':
                    version['deps'] = {}
                elif defect == 'dep-entry':
                    version['deps'] = [123]
                elif defect == 'req':
                    version['deps'][0]['req'] = True
                else:
                    version['checksum'] = None
                self.routes[route] = json.dumps(index).encode()
                self.requests.clear()
                self.assert_failed_without_publish(token=b'ResolveBadIndex')
                self.assertFalse(any('/pkgs/' in path for path in self.requests))

    def test_resolution_error_keeps_lock_and_reports_no_success(self):
        self.manifest([('missing', 'b')])
        self.assert_failed_without_publish(token=b'ResolveNotFound')

    def test_invalid_or_missing_explicit_trust_config_fails_before_download(self):
        self.package('b', 'foo')
        self.manifest([('foo', 'b')])
        for text in ['[registries]\n"' + self.base + '/b/"=123\n',
                     '[registries]\n"' + self.base + '/b/"="not-a-key"\n', None]:
            with self.subTest(config=text):
                self.requests.clear()
                if text is None:
                    self.config.unlink()
                else:
                    self.config.write_text(text)
                self.assert_failed_without_publish(token=b'trust configuration')
                self.assertFalse(any('/pkgs/' in path for path in self.requests))

    def test_legacy_key_override_is_scoped_to_its_registry(self):
        self.package('b', 'foo')
        self.manifest([('foo', 'b')])
        self.configure({})
        env = {**self.env, 'NURL_REGISTRY': self.base + '/a/', 'NURL_REGISTRY_PUBKEY': self.keys['b'][2]}
        self.assert_failed_without_publish(token=b'no trusted signing key', env=env)
        self.assertFalse(any('/pkgs/' in path for path in self.requests))
        env['NURL_REGISTRY'] = self.base + '/b/'
        run = self.run_pkg('install', env=env)
        self.assertEqual(run.returncode, 0, run.stdout + run.stderr)

    def test_flat_layout_conflict_cannot_substitute_same_name_sources(self):
        self.package('a', 'alpha', deps=['foo'])
        self.package('b', 'bravo', deps=['foo'])
        self.package('a', 'foo')
        self.package('b', 'foo')
        self.manifest([('alpha', 'a'), ('bravo', 'b')])
        self.assert_failed_without_publish(token=b'multiple registry sources')
        self.assertFalse(any('/pkgs/' in path for path in self.requests))

    def test_lock_regeneration_preserves_registry_source_and_checksum(self):
        self.package('b', 'foo')
        self.manifest([('foo', 'b')])
        run = self.run_pkg('install')
        self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
        before = tomllib.loads((self.project / 'nurl.lock').read_text())
        run = self.run_pkg('lock')
        self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
        self.assertEqual(tomllib.loads((self.project / 'nurl.lock').read_text()), before)


if __name__ == '__main__':
    unittest.main(verbosity=2)
