### Fixed

- **A value block whose tail is a binding is that binding, wherever the binding is bound** (Agora #823, with claude-formal's OK).
  - `: String e { : String s …  : String t { s }  t }  ( eat e )` was a heap-use-after-free: the inner tail was a borrow with no owner link.
  - `: String t { s }  ( eat t )` was refused ("'t' is a borrow"). It is now accepted, as `: t s  ( eat t )` is.
  - `: s e { : s t … t }  ^ e` handed back a freed string. It is now refused, as `: s e t  ^ e` is.

### Changed

- **`: T e { … s }` over an outer `s` moves s, as `: T e s` does** (Agora #823). It used to lend s and leave it readable (#615's guard), so `: String s …  : String e { ( nurl_println_int 1 ) s }  ( string_len s )` is now refused: "use of moved value 's'". Bind `e` from `s` only where `s` is not needed after it, or read through `e`.
