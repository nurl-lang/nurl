### Fixed

- **`: T w v` inside a generic instantiated at a closure type compiles**
  (Agora #637, `compiler/nurlc.nu`). `@ hold [T] T v → T { : T w v ^ w }`
  at `[( @ i i )]` was refused with "use of undefined identifier 'w' …
  [while instantiating 'hold__fn1_3_i64_3_i64']"; at `[i]` it compiled.
  The instance's body spells the closure type as a slug word, which
  `:` takes for a type only where the word is noted as one; it was noted
  in the scope of the function whose body made the instance and gone
  with that scope before the instance was compiled, so the `:` read the
  word as the name of an inferred binding. It is noted at the module's
  scope now, as a generic struct's instance name is.
