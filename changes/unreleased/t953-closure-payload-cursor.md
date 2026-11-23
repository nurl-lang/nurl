### Fixed

- **A closure over a `??` payload of a local option, bound by `:` and handed back, is refused** (AGORA-953). `: e ?? oo { T inner → \ → i { … inner … } F → … }  ^ e` handed the caller a closure whose env held a copy of the payload's handle, which `oo` released on the way out: a heap-use-after-free. It is now refused, as the same closure bound by name inside the arm already was. The fix is to write the closure in the return (`^ ?? oo { … }`), where it takes the payload over.
