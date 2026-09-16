# Changelog

## 0.3.4

`--version` reported 0.3.2 while the manifest said 0.3.3.

The string is a literal in the source and nothing derives it from `nurl.toml`,
so the bump to 0.3.3 moved one and not the other. A published version cannot be
replaced, only superseded — which is what this is.

## 0.3.3

`gw_free`, `gws_free` now take a **`sink`** parameter.

The compiler-ownership hardening in toolchain 0.65.0 (#1107) reached these
signatures: a free function must consume the handle it releases, so the
checker can prove the caller cannot use it again. The change landed in the
monorepo at the time and this package was never republished, so the registry
has been serving 0.3.2 with different source ever since. That is what this
release closes.

For a caller the effect is the ownership rule, not the call: the value is
gone after the free, and using it again is now a compile error instead of a
use-after-free. Code that already treated it that way needs no edit.
