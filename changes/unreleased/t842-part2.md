### Fixed

- **The last AGORA-842 shapes are refused** (AGORA-842 part 2):
  - a callee growing an element of its option parameter's payload inline, `?? p { T q → ( vec_push ( vec_at q 0 ) … ) }`, including through `rc_get` or `box_get`;
  - an option and a slice of its payload handed to one call that grows the payload;
  - a view of an enum payload's element kept past the enum being moved or sunk.

  Each read freed memory. The same programs that only read, or that read the view first, are still accepted.
- **A `??` payload chain is followed to its end, however deep** (AGORA-842 review). The walks from a payload up to the binding it came out of stopped after a fixed 4 to 64 hops. From 7 nested options on, a slice of the innermost payload handed to one growing call with the outermost option was accepted, and read freed memory. Every such walk now stops only at a name it has already met.
