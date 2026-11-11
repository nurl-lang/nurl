### Fixed

- **A struct that holds itself through an option or a result of a `Box`
  compiles** (Agora #640). `: LNode { ?( Box LNode ) next }` — and
  `!( Box N ) String`, `??( Box N )`, two structs that reach each other
  that way, a generic `Node [A]` — killed the compiler with a
  segmentation fault and no diagnostic as soon as the program used the
  type; a plain `( Box LNode ) next` compiled. Whether the struct owns
  anything asked what the option's payload is, which asked whether the
  `Box` copies, which asked whether the struct owns anything, and that
  answer was worked out afresh each time round until the stack ran out.
  Whether a library handle copies is now asked through the same memo as
  every other copy question, whose in-progress mark ends the walk where
  a type reaches itself. Such a list is dropped node by node, each field
  once, and copied whole where every field copies; programs that
  compiled before produce the same IR.
