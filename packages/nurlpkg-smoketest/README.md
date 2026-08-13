# nurlpkg-smoketest

A deliberately trivial package whose only job is to exercise the registry
end to end: **pack → publish → index → resolve → download → verify → extract
→ build → run**.

```sh
cd packages/nurlpkg-smoketest
nurlpkg publish --dry-run     # pack only: prints size + sha256
nurlpkg publish               # upload to the registry

nurlpkg install nurlpkg-smoketest
./deps/nurlpkg-smoketest/nurlpkg-smoketest
# nurlpkg-smoketest 0.1.0 — registry round-trip OK
```

## Why it exists

When `nurlpkg publish` fails, the failure could be in the package, the
packer, the transport, or the registry. This package removes the first
possibility: it has no dependencies, no generated files, and a tarball of
a few kilobytes. If publishing *this* fails, the problem is downstream of
the package.

It is also the canary for **packer determinism**. Two clean checkouts of
the same commit must produce a byte-identical tarball and therefore the
same sha256. If they don't, the packer is sweeping up untracked build
output — which is exactly the bug that made `wasmbuilder` pack to 269 KB
in one clone and 36 KB in another.

```sh
# From two separate clean clones of the same commit:
nurlpkg publish --dry-run | grep sha256   # the two must match
```

Because the tarball is small, it also stays *under* one TCP segment on a
path with a broken MTU — so a successful smoke test here alongside a
failing real publish is a strong hint that the problem is packet size in
the network path, not the registry.

Versions of this package are disposable. Bump the patch number and
republish whenever you need a fresh upload to test against; yanking old
ones is fine.
