# cas

A **content-addressed store** over BLAKE3 — the keystone of a verifiable
build → hash → dedup → distribution chain, in pure NURL.

```sh
nurlpkg install cas

cas put artifact.wasm
# → 7be1c02f…  (BLAKE3-256 — from now on, the hash IS the name)

cas snapshot ./build-output
# → f80638…   (one hash names the whole tree)

cas checkout f80638… ./somewhere-else   # materialise, fully verified
cas verify   f80638…                    # deep-prove every object
```

## Why it closes the verifiability loop

* **Put** — bytes are stored under their own BLAKE3 hex. Same bytes,
  same name: storing twice is free (dedup by existence).
* **Get** — every read **re-hashes what it found** and refuses to return
  bytes that don't match their name. A store you rsync, mirror, or fetch
  from an untrusted cache yields either the exact original bytes or an
  error — never silent corruption. (The test suite literally flips a byte
  in the store and watches `get`/`verify`/`checkout` refuse.)
* **Manifest** — a snapshot is a canonical text object
  (`cas-manifest v1` + sorted `hash size path` lines) stored in the CAS
  like any blob, so a manifest hash is a Merkle root: one 64-hex string
  names an entire tree, shares storage with every other tree containing
  the same files, and verifies all the way down. Canonical means
  deterministic: the same tree always snapshots to the same hash.

## Store layout

Plain files, no index, no database, no locks — the filesystem is the
whole data structure (git/OCI-shaped):

```
$CAS_STORE/                 default ~/.cas   (or --store DIR)
  objects/ab/cdef…          immutable, named by content
  tmp/                      staging; writes land by atomic rename
```

Concurrent writers of the same content converge on the same object;
readers never see a torn write.

## CLI

```
cas put <file>                    store → print hash
cas hash <file>                   name without storing
cas get <hash> [-o FILE]          fetch + verify (stdout by default)
cas snapshot <dir>                tree → manifest hash
cas ls <manifest-hash>            list a snapshot
cas checkout <manifest-hash> <dir>  materialise + verify
cas verify <hash>                 deep-prove a blob or snapshot
```

## Library

```nurl
$ `deps/cas/src/manifest.nu`   // pulls cas.nu too

: !Cas String co ( cas_open `/var/lib/mycache` )
?? co { T c → {
    : !String String h ( cas_put c wasm_bytes )        // → hex name
    : !( Vec u ) String back ( cas_get c hex )         // verified fetch
    : !String String snap ( cas_snapshot c `./out` )   // tree → one hash
    : !i String n ( cas_checkout c snap_hex `./dest` )
} F e → { … } }
```

Intended building block for: build caches (wasmbuilder / nurlc outputs),
artifact distribution across a swarm (ship one manifest hash, workers
fetch + verify the objects), and any place where "did I get exactly the
bytes that were built?" must be a provable yes.

## Tests

`./tests/cas_test.sh` — round-trip, dedup, determinism, and the
tamper case: a flipped byte in the store must turn every read into an
error.
