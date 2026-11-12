### Fixed

- **A struct holding an enum with a boxed struct payload is dropped**
  (Agora #787). `: W { Shade s String t }` with `: | Shade { Light Mix Pt }`
  was released by nobody — the enum's box and the String beside it
  leaked — and `: W b a` then `( vec_push [W] v b )` was refused as a copy
  of a borrowed W. Such a struct now gets the drop the compiler writes
  field by field, and is moved, never copied, like a struct holding a
  `% Drop` value.
