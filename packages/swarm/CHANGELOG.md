# Changelog

## Unreleased

Nothing in the package is released by hand any more.

- `Roster` and `Swarm` are library handles over an rcbox (`stdlib/core/rcbox.nu`)
  instead of `*Roster` / `*Swarm` pointers: every copy is the same roster / node,
  and the last owner releases it — the swarm's transport, ring, roster and job
  node with it. A roster keeps its members as `( Vec Member )` values.
- `shard` returns `( Vec Chunk )` (plain `{ lo hi }` values) instead of a
  `( Vec s )` of raw `*Chunk`: read a chunk with `vec_get [Chunk]`.
- New `swarm_worker_count` (the roster size of a node).
- `roster_free`, `swarm_free`, `shard_free`, `hello_free` remain as optional
  early releases; no caller needs them.

## 0.2.2

`hello_free`, `roster_free`, `shard_free`, `swarm_free` now take a **`sink`** parameter.

The compiler-ownership hardening in toolchain 0.65.0 (#1107) reached these
signatures: a free function must consume the handle it releases, so the
checker can prove the caller cannot use it again. The change landed in the
monorepo at the time and this package was never republished, so the registry
has been serving 0.2.1 with different source ever since. That is what this
release closes.

For a caller the effect is the ownership rule, not the call: the value is
gone after the free, and using it again is now a compile error instead of a
use-after-free. Code that already treated it that way needs no edit.
