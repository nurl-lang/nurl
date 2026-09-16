# Changelog

## 0.1.2

`pk_free` now takes a **`sink`** parameter.

The compiler-ownership hardening in the toolchain (#1107) reached this
signature: a free function must consume the handle it releases, so the
checker can prove the caller cannot use it again. The change landed in the
monorepo at the time but this package was never republished — four others
were, in #1130, and this one was missed — so the registry has been serving
0.1.1 with different source ever since. That is what this release closes.

For a caller the effect is the ownership rule, not the call: the value is
gone after the free, and using it again is now a compile error instead of a
use-after-free. Code that already treated it that way needs no edit.

## 0.1.1

Dependency requirements pin the major.

## 0.1.0

PyTorch `.pt` / `.bin` checkpoints — the ZIP container and the pickle
protocol — read in pure NURL, so a model whose weights ship as a pickle
rather than as safetensors can be loaded without Python.
