### Changed

- **A struct can be used above its declaration** (Agora #772, #769). A
  struct used by value — a binding, a parameter, a return, a field read,
  a `??` payload's field — in a function above `: S { … }` (or above the
  import that declares it, under an alias or not) compiles: its layout,
  field names included, is read before any body compiles, and its type is
  emitted at the top of the module. It was refused as "declared LATER" for
  a binding, and as "type 'R' has no field 'n'" for a parameter's or a
  payload's field. The emitted functions are the same as with the
  declaration first. A private struct of another file is still refused
  there. An enum value keeps the "declared LATER" rule until its drop is
  known before its declaration (Agora #752); the message now says why.

### Fixed

- A global given a struct literal for its value, `: S g @ S { … }`, is
  refused as a global without a constant value again, not as a function
  `@ S` sharing the type's name.
