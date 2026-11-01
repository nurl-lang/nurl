### Fixed

- **A library handle's clone or share hook may not hand back its
  argument** (Agora #334). A struct with `S_drop sink` is a handle, and
  its own `S_clone` or `S_share` makes every copy of one. A hook that
  returned its argument (`@ X_clone X x → X { ^ x }`), or a new value
  over its argument's own Vec (`^ @ X { . x v }`), made each copy a second
  owner of one value: since #288 a literal that copies a parameter that
  way carries nothing of it, so the caller dropped the temporary it had
  passed and the copy read it freed. Through a local literal the
  function kept, it was a heap-use-after-free before #288 too. Such a hook
  is refused where it is written, with a pointer to a counted share
  (`shared_clone`, `arc_clone`, `rc_clone`, `rcbox_share`) or a copy of
  each field. Every hook in the standard library and the packages already
  does one or the other.
