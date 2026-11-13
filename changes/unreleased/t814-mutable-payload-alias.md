### Fixed

- **A local enum's payload handed back under a `: ~` alias is the
  caller's own** (Agora #814). `: ~ String t s ^ t` was answered lent out
  of the enum, which is released on the way out (heap-use-after-free). The
  alias is copied — never taken, since it may have been given another
  value: where the enum keeps its payload, and where the alias owns a
  value of its own.
