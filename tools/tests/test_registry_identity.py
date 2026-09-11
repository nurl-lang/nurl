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
        owner = self
        class Handler(http.server.BaseHTTPRequestHandler):
            def do_GET(self):
                owner.requests.append(self.path)
                body = owner.routes.get(self.path)
                self.send_response(200 if body is not None else 404)
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
                        DEBUGINFOD_URLS='', ASAN_OPTIONS='detect_leaks=0:halt_on_error=1',
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
                extra=(), signature=True, contents=None):
        actual_name, actual_version = identity or (name, version)
        manifest = f'[package]\nname="{actual_name}"\nversion="{actual_version}"\n'
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
