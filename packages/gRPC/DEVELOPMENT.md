# gRPC release acceptance

The package and its matching toolchain are validated together before release.
Package directory: `packages/gRPC`; registry name: `grpc`; package version:
`0.1.0`; required toolchain release: `0.65.0`.

Verified on 2026-09-13:

- Official grpcio interoperability in both directions: 14 tests, normally and
  with ASan/UBSan/LSan, covering all four call shapes, binary/duplicate metadata,
  empty and large gzip payloads, verified TLS, deadlines, status details,
  client cancellation/reuse and multiplexing in both directions.
- HTTP/2 h2spec: 146 normal / 147 strict cases for TLS and direct h2c;
  shared HTTP listener retains the documented invalid-preface exception.
- Forced full-duplex HTTP/2 traffic: simultaneous 1 MiB request/response with
  4 KiB socket buffers; both finish without blocking each other.
- Absolute write deadlines across raw/net/TLS and synchronous/fiber paths:
  20 stalled/slow-reader controls. Partial TLS record duplex: TLS 1.2/1.3 and
  sync/fiber, including ASan/UBSan/LSan. Native, WASI/nwasm and QEMU provider
  checks passed; Windows runtime cross-compiles and links.
- 18 malformed gRPC request/limit/deadline cases, each followed by a valid
  call on the same connection, and 16 malformed response/status cases;
  negative certificate verification and large bidirectional traffic between
  two NURL peers over TLS.
- TLS 1.3 KeyUpdate: 32 OpenSSL peer combinations exercise both directions,
  requested responses, repeated updates, fragmented records, synchronous and
  fiber paths, and AES-GCM/ChaCha20-Poly1305, normally and with sanitizers.
- Strict compression differential tests (including 1,000 mutations), Base64
  terminal groups, metadata/status wire tests and bounded decompression.
- HTTP-client decoding failures and protocol paths: 40 cases passed.
- Minimum toolchain parsing and signed registry fixture installation: 44 CLI
  cases passed with leak detection, including library publication, unchanged
  prior packages/locks on failure, changed transitive manifests behind existing
  path links and rejection of unrelated dependency directories. Publication
  refuses unverifiable path overrides and compares root/nested source modules
  against the dependency's authenticated registry archive.
- Raw argument ownership: 35 sanitizer controls passed, including mixed
  owned/borrowed conditional values. Typed pointer element
  `inout`, nested deferred cleanup and precise try diagnostics passed acceptance
  and rejection regressions. Source snapshots remain consistent when a file
  changes during compilation. Test-runner fault controls passed; invocations
  have isolated artifacts and atomic golden publication.
- Refreshed bootstrap and complete compiler corpus: 1,070 passed, no failures
  or missing/orphan records, 19 capability skips. Self-compilation used 46 MiB
  peak RSS against the existing 600 MiB gate.
- Metadata encoding, decoding and status construction enforce cumulative
  byte limits before allocating expanded values, including comma-split binary
  metadata and percent-encoded status messages; wire tests pass leak detection.
- Real line/branch coverage: 12 tests passed normally and with strict
  sanitizers, including saved IR relinking and imported-source attribution.
  Three source-snapshot controls verify a single consistent input snapshot.
- Function linkage: seven controls verify libc/strong-C coexistence, explicit
  C exports, retained callbacks, library modules, split references and readable
  debug names. The original `open` collision also passes static nolibc linking.
- Package test/benchmark runners: five tests passed normally and with strict
  sanitizers, including concurrent same-name tests, literal paths, nonzero
  exits and cleanup. Four signed tool-publication controls verify that
  incomplete copies and failed permission/rename operations preserve the old
  executable and concurrent installs retain private source trees. Filesystem
  controls exercise exclusive temporary directories,
  atomic replacement and read/close failures.

Release gate:

1. Format and review the final source, refresh the committed bootstrap
   snapshot, and pass the complete build, corpus and sanitizer/leak CI gates.
2. Run the gRPC suite normally and with sanitizers, retaining the independent
   peer, malformed-input, cancellation and full-duplex checks.
3. Publish the tested toolchain and install its signed release into a clean
   external prefix. Run the package publication dry run against that compiler
   and standard library.
4. Publish `grpc` to the signed registry, install it into a fresh external
   consumer and compile/run with the installed compiler/stdlib. Verify archive
   identity, signature/checksum and relocation; no local dependency substitution.

The final step is reproducible from the repository with:

```sh
python tools/tests/test_grpc_registry.py --toolchain /path/to/installed/nurl --full-interop
```

The command uses the canonical registry and a fresh directory outside the
checkout. It verifies every installed archive file, runs `nurlpkg test` in the
installed package, and exercises protobuf calls and all four client call shapes
against grpcio. Its preserved JSON report records toolchain versions, archive
hashes, installed-source hashes, commands and interoperability results.
