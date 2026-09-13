#!/usr/bin/env python3
"""Live release acceptance: install grpc from the canonical registry into a fresh consumer.

python tools/tests/test_grpc_registry.py --toolchain /path/to/installed/nurl --full-interop
The artifact directory is preserved, including a JSON verdict on failure.
This command never publishes, copies local package sources, or falls back to the checkout.
Requires grpcio + protobuf (packages/gRPC/tests/requirements.txt).
"""
import argparse
from concurrent import futures
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import select
import shutil
import subprocess
import sys
import tarfile
import tempfile
import tomllib

ROOT = Path(__file__).resolve().parents[2]
REGISTRY = 'https://reg.nurl-lang.org/'
VERSION = '0.1.0'
MINIMUM = (0, 65, 0)
MESSAGE = 'registry grpc ä — roundtrip'


def require(condition, message):
    if not condition:
        raise AssertionError(message)


def sha256(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def beneath(path, directory):
    return path.resolve().is_relative_to(directory.resolve())


def checked_file(path, directory):
    require(path.is_file() and beneath(path, directory), f'file is missing or escapes its selected root: {path}')
    return path


def no_external_links(directory):
    for path in directory.rglob('*'):
        require(not path.is_symlink(), f'symlink is not an isolated installation: {path}')


class Acceptance:
    def __init__(self, prefix, directory, full):
        self.prefix = prefix.resolve(strict=True)
        self.directory = directory.resolve()
        require(not beneath(self.directory, ROOT), 'consumer must be outside the repository')
        require(not beneath(self.prefix, ROOT), 'toolchain must be an installed prefix outside the repository')
        self.directory.mkdir(parents=True, exist_ok=False)
        self.consumer = self.directory/'consumer'
        self.consumer.mkdir()
        self.provenance = self.directory/'provenance'
        self.provenance.mkdir()
        self.logs = self.directory/'logs'
        self.logs.mkdir()
        self.full = full
        self.report = {'status': 'running', 'live_registry': REGISTRY,
                       'started_at': datetime.now(timezone.utc).isoformat(),
                       'toolchain_prefix': str(self.prefix), 'consumer': str(self.consumer),
                       'checks': [], 'commands': []}
        # Select all NURL paths explicitly; registry trust comes from the selected
        # toolchain's built-in key, not the invoking shell's alternate registry.
        self.env = {key: value for key, value in os.environ.items()
                    if not key.startswith('NURL') and key not in
                    ('CPATH', 'C_INCLUDE_PATH', 'CPLUS_INCLUDE_PATH', 'LIBRARY_PATH',
                     'LD_PRELOAD', 'LD_LIBRARY_PATH', 'DYLD_LIBRARY_PATH')}
        config = self.provenance/'registries.toml'
        config.write_text('[registries]\n')
        self.env.update(NURL_STDLIB=str(self.prefix), NURL_HOME=str(self.prefix),
                        NURL=str(self.prefix/'bin/nurl'), NURL_CC=str(self.prefix/'bin/nurl'),
                        NURLPKG=str(self.prefix/'bin/nurlpkg'),
                        NURL_REGISTRY=REGISTRY, NURL_REGISTRY_CONFIG=str(config),
                        NURL_NO_UPDATE_CHECK='1', NURL_CACHE_DIR=str(self.directory/'cache'),
                        PATH=str(self.prefix/'bin')+os.pathsep+os.defpath,
                        ASAN_OPTIONS='detect_leaks=1:halt_on_error=1',
                        UBSAN_OPTIONS='halt_on_error=1', DEBUGINFOD_URLS='')

    def save(self):
        (self.directory/'report.json').write_text(json.dumps(self.report, indent=2, sort_keys=True)+'\n')

    def run(self, label, command, timeout=180, cwd=None):
        directory = self.consumer if cwd is None else cwd
        result = subprocess.run([str(arg) for arg in command], cwd=directory,
                                env=self.env, capture_output=True, timeout=timeout)
        (self.logs/f'{label}.stdout').write_bytes(result.stdout)
        (self.logs/f'{label}.stderr').write_bytes(result.stderr)
        self.report['commands'].append({'label': label, 'argv': [str(arg) for arg in command],
                                        'cwd': str(directory),
                                        'returncode': result.returncode})
        self.save()
        require(result.returncode == 0, f'{label} failed; see {self.logs}/{label}.stderr')
        require(b'Sanitizer' not in result.stderr and b'runtime error:' not in result.stderr,
                f'{label} reported a sanitizer failure')
        return result.stdout

    def preflight(self):
        versions = {}
        files = {}
        for name in ('nurl', 'nurlc', 'nurlpkg'):
            binary = checked_file(self.prefix/'bin'/name, self.prefix)
            require(os.access(binary, os.X_OK), f'not executable: {binary}')
            output = self.run('version-'+name, [binary, '--version'], 20).decode().strip()
            match = re.search(r'(?<![\d.])(\d+)\.(\d+)\.(\d+)(?![\d.])', output)
            require(match is not None, f'{name} did not report a semantic version')
            version = tuple(map(int, match.groups()))
            require(version >= MINIMUM, f'{name} is {match.group(0)}; grpc requires >=0.65.0')
            versions[name] = {'output': output, 'version': match.group(0)}
            files[str(binary.relative_to(self.prefix))] = sha256(binary)
        require(len({item['version'] for item in versions.values()}) == 1,
                'selected nurl, nurlc, and nurlpkg versions disagree')
        for relative in ('nurl.sh', 'build/nurlc', 'build/nurlpkg', 'stdlib/runtime.o',
                         'stdlib/ext/protobuf.nu', 'stdlib/std/net.nu', 'stdlib/std/tls.nu',
                         'stdlib/ext/http2_client.nu', 'stdlib/ext/http2_conn.nu',
                         'stdlib/ext/registry_trust.nu'):
            path = checked_file(self.prefix/relative, self.prefix)
            files[relative] = sha256(path)
        no_external_links(self.prefix/'stdlib')
        self.report['toolchain'] = {'versions': versions, 'files_sha256': files}
        self.report['checks'].append('selected self-contained toolchain >=0.65.0')

    def download(self, label, url, destination):
        self.run(label, ['curl', '--fail', '--silent', '--show-error', '--location',
                         '--proto', '=https', '--proto-redir', '=https', '--max-time', '60',
                         url, '--output', destination], 70)

    def install(self):
        (self.consumer/'nurl.toml').write_text(
            '[package]\nname = "grpc-registry-consumer"\nversion = "0.1.0"\n'
            f'registry = "{REGISTRY}"\n[dependencies]\ngrpc = "={VERSION}"\n')
        self.run('install', [self.prefix/'bin/nurlpkg', 'install'])
        package = self.consumer/'deps/grpc'
        require(package.is_dir() and not package.is_symlink(), 'registry package was not installed as a real directory')
        no_external_links(package)
        manifest = tomllib.loads((package/'nurl.toml').read_text())['package']
        require(manifest['name'] == 'grpc' and manifest['version'] == VERSION, 'installed package identity mismatch')
        require(manifest.get('nurl-version') == '0.65.0', 'installed minimum toolchain must be 0.65.0')
        lock = tomllib.loads((self.consumer/'nurl.lock').read_text())
        packages = lock.get('package', [])
        require(len(packages) == 1 and packages[0]['name'] == 'grpc', 'unexpected lockfile package set')
        locked = packages[0]
        require(locked['version'] == VERSION and locked.get('source') == 'registry+'+REGISTRY,
                'lockfile does not identify the canonical live registry')
        checksum = locked.get('checksum', '')
        require(re.fullmatch('[0-9a-f]{64}', checksum) is not None, 'lockfile lacks a SHA-256 checksum')
        index_path = self.provenance/'grpc-index.json'
        self.download('download-index', REGISTRY+'index/grpc.json', index_path)
        index = json.loads(index_path.read_text())
        require(index.get('name') == 'grpc', 'canonical index identity mismatch')
        entries = [item for item in index.get('versions', []) if item.get('version') == VERSION]
        require(len(entries) == 1 and not entries[0].get('yanked', False), 'published version absent, duplicated or yanked')
        require(entries[0]['checksum'] == checksum, 'index and lockfile checksums disagree')
        archive = self.provenance/f'grpc-{VERSION}.tar.gz'
        url = REGISTRY+f'pkgs/grpc/grpc-{VERSION}.tar.gz'
        self.download('download-archive', url, archive)
        require(sha256(archive) == checksum, 'independently downloaded tarball hash differs from lockfile')
        signature = archive.with_name(archive.name+'.minisig')
        self.download('download-signature', url+'.minisig', signature)
        require(signature.stat().st_size > 0, 'canonical archive signature is empty')
        installed = {}
        with tarfile.open(archive, 'r:gz') as source:
            for member in source.getmembers():
                name = PurePosixPath(member.name)
                require(not name.is_absolute() and '..' not in name.parts, 'unsafe archive path')
                require(member.isdir() or member.isfile(), 'archive contains a link or special file')
                if member.isdir():
                    continue
                require(str(name) not in installed, 'duplicate archive file')
                path = checked_file(package/str(name), package)
                digest = hashlib.sha256(source.extractfile(member).read()).hexdigest()
                require(sha256(path) == digest, f'installed file differs from canonical archive: {name}')
                installed[str(name)] = digest
        actual = {str(path.relative_to(package)) for path in package.rglob('*') if path.is_file()}
        require(actual == set(installed), 'installed package contains files absent from the signed archive')
        self.report['package'] = {'name': 'grpc', 'version': VERSION, 'minimum_toolchain': '0.65.0',
                                  'source': locked['source'], 'tarball_url': url, 'sha256': checksum,
                                  'signature_sha256': sha256(signature),
                                  'signature_verification': 'selected nurlpkg; canonical built-in registry key',
                                  'installed_files_sha256': installed,
                                  'lock_sha256': sha256(self.consumer/'nurl.lock'),
                                  'index_sha256': sha256(index_path)}
        self.report['checks'].append('live install, lock provenance and every archived file verified')
        return package

    def compile(self, label, source, output):
        self.run('compile-'+label, [self.prefix/'bin/nurl', source, output])
        require(output.is_file(), f'{label} did not produce an executable')
        self.report.setdefault('executables_sha256', {})[label] = sha256(output)
        self.report.setdefault('compiled_sources_sha256', {})[label] = sha256(source)

    def interoperability(self, package):
        import grpc
        import google.protobuf
        from google.protobuf.wrappers_pb2 import StringValue
        self.report['reference_runtime'] = {'grpcio': grpc.__version__,
                                            'protobuf': google.protobuf.__version__}
        source = self.consumer/'main.nu'
        shutil.copyfile(Path(__file__).parent/'fixtures/grpc_registry_consumer.nu', source)
        binary = self.consumer/'consumer'
        self.compile('consumer', source, binary)
        seen = []
        def protobuf_echo(request, context):
            require(request.value == MESSAGE, 'NURL sent an incorrect protobuf string message')
            seen.append(request.value)
            context.set_compression(grpc.Compression.Gzip)
            return StringValue(value='official grpcio: '+request.value)
        def metadata(context):
            context.send_initial_metadata((('trace-bin', b'\x00\xff'),))
            context.set_trailing_metadata((('finished', 'yes'),))
        def unary(data, context):
            metadata(context)
            return data
        def server_stream(data, context):
            metadata(context)
            yield from (data, data, data)
        def client_stream(data, context):
            metadata(context)
            return b''.join(data)
        def bidi(data, context):
            metadata(context)
            yield from data
        executor = futures.ThreadPoolExecutor(max_workers=4)
        server = grpc.server(executor)
        server.add_generic_rpc_handlers((
            grpc.method_handlers_generic_handler('registry.Echo', {'Unary': grpc.unary_unary_rpc_method_handler(
                protobuf_echo, request_deserializer=StringValue.FromString, response_serializer=StringValue.SerializeToString)}),
            grpc.method_handlers_generic_handler('test.Echo', {
                'Unary': grpc.unary_unary_rpc_method_handler(unary),
                'ServerStream': grpc.unary_stream_rpc_method_handler(server_stream),
                'ClientStream': grpc.stream_unary_rpc_method_handler(client_stream),
                'Bidi': grpc.stream_stream_rpc_method_handler(bidi)})))
        port = server.add_insecure_port('127.0.0.1:0')
        require(port > 0, 'grpcio failed to bind localhost')
        server.start()
        try:
            for encoding in ('identity', 'gzip'):
                out = self.run('protobuf-'+encoding, [binary, port, encoding], 15)
                require(out == b'registry protobuf roundtrip passed\n', 'consumer did not confirm the protobuf result')
            require(seen == [MESSAGE, MESSAGE], 'reference server did not decode both protobuf calls')
            self.report['checks'].append('external protobuf consumer roundtrip: identity and gzip')
            if self.full:
                client_source = checked_file(package/'tests/fixtures/client.nu', package)
                client_binary = self.consumer/'installed-client'
                self.compile('installed-client', client_source, client_binary)
                for mode, method in (('unary', 'Unary'), ('client-stream', 'ClientStream'),
                                     ('server-stream', 'ServerStream'), ('bidi', 'Bidi')):
                    self.run('installed-client-'+mode, [client_binary, port, '/test.Echo/'+method,
                                                       mode, 'gzip', 'h2c', 0, 32768], 20)
                self.report['checks'].append('installed client fixture: all four RPC shapes against grpcio')
        finally:
            server.stop(0).wait(timeout=5)
            executor.shutdown(wait=True)
        if self.full:
            self.installed_server(package, grpc, StringValue)

    def installed_server(self, package, grpc, StringValue):
        source = checked_file(package/'tests/fixtures/server.nu', package)
        binary = self.consumer/'installed-server'
        self.compile('installed-server', source, binary)
        process = subprocess.Popen([str(binary), 'gzip'], cwd=self.consumer, env=self.env,
                                   stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        channel = None
        try:
            require(bool(select.select([process.stdout], [], [], 10)[0]), 'installed server did not bind')
            address = process.stdout.readline().decode().strip()
            require(re.fullmatch(r'127\.0\.0\.1:\d+', address) is not None, 'installed server reported invalid address')
            channel = grpc.insecure_channel(address)
            grpc.channel_ready_future(channel).result(timeout=5)
            request = StringValue(value=MESSAGE)
            call = channel.unary_unary('/test.Echo/Unary', request_serializer=StringValue.SerializeToString,
                                        response_deserializer=StringValue.FromString)
            response = call(request, timeout=5, compression=grpc.Compression.Gzip)
            require(response.value == MESSAGE, 'installed server changed the protobuf message')
            channel.close()
            channel = None
            stdout, stderr = process.communicate(timeout=10)
            (self.logs/'installed-server.stdout').write_bytes(address.encode()+b'\n'+stdout)
            (self.logs/'installed-server.stderr').write_bytes(stderr)
            self.report['commands'].append({'label': 'installed-server',
                                             'argv': [str(binary), 'gzip'],
                                             'returncode': process.returncode})
            require(process.returncode == 0 and not stderr, 'installed server failed clean shutdown')
            self.report['checks'].append('installed server fixture: grpcio protobuf roundtrip and clean shutdown')
        finally:
            if channel is not None:
                channel.close()
            if process.poll() is None:
                process.kill()
                process.communicate()

    def execute(self):
        try:
            self.preflight()
            package = self.install()
            self.run('installed-package-tests', [self.prefix/'bin/nurlpkg', 'test'], cwd=package)
            self.report['checks'].append('nurlpkg test passes in the installed registry package')
            self.interoperability(package)
            self.report['status'] = 'passed'
        except Exception as error:
            self.report['status'] = 'failed'
            self.report['error'] = str(error)
            raise
        finally:
            self.report['finished_at'] = datetime.now(timezone.utc).isoformat()
            self.save()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--toolchain', required=True, type=Path, help='installed self-contained NURL >=0.65.0 prefix')
    parser.add_argument('--artifacts', type=Path, help='new artifact directory outside the repository (preserved)')
    parser.add_argument('--full-interop', action='store_true', help='also compile and run published package test fixtures')
    args = parser.parse_args()
    directory = args.artifacts
    if directory is None:
        directory = Path(tempfile.mkdtemp(prefix='nurl-grpc-registry-'))/'acceptance'
    acceptance = None
    try:
        acceptance = Acceptance(args.toolchain, directory, args.full_interop)
        acceptance.execute()
    except Exception as error:
        print(f'FAIL: {error}', file=sys.stderr)
        if acceptance is not None:
            print(f'Report: {acceptance.directory / "report.json"}', file=sys.stderr)
        return 1
    print(f'PASS: grpc {VERSION} installed from {REGISTRY} and exercised from an external consumer')
    print(f'Report: {acceptance.directory / "report.json"}')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
