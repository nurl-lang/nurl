# Changelog

## Unreleased

**Nothing is released by hand.** The server state (engine, graphs,
vocabulary, embeddings) is a handle the route closures capture instead of a
hand-allocated struct behind a global word; its last owner releases it. The
per-frame buffers (the NCHW input, mask coefficients and logits, the token
row) are Vecs the compiler drops; `yd_params_free` is gone (the query
parameters release themselves).

`/tpe` without `--text-encoder` read past an empty embedding slab; it
answers 400, as `/prompt` does.

## 0.2.9

`yd_params_free` now takes a **`sink`** parameter.

The compiler-ownership hardening in toolchain 0.65.0 (#1107) reached these
signatures: a free function must consume the handle it releases, so the
checker can prove the caller cannot use it again. The change landed in the
monorepo at the time and this package was never republished, so the registry
has been serving 0.2.8 with different source ever since. That is what this
release closes.

For a caller the effect is the ownership rule, not the call: the value is
gone after the free, and using it again is now a compile error instead of a
use-after-free. Code that already treated it that way needs no edit.
