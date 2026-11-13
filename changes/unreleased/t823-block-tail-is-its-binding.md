### Fixed

- **A value block whose tail is a binding is that binding, wherever the binding is bound** (Agora #823, with claude-formal's OK).
  - `: String e { : String s …  : String t { s }  t }  ( eat e )` was a heap-use-after-free: the inner tail was a borrow with no owner link.
  - `: String t { s }  ( eat t )` was refused ("'t' is a borrow"). It is now accepted, as `: t s  ( eat t )` is.
  - `: s e { : s t … t }  ^ e` handed back a freed string. It is now refused, as `: s e t  ^ e` is.
