### Fixed

- **A `vec_get` payload handed back under a defer leaves its Vec whole for
  the defer** (Agora #561). `?? ( vec_get [String] vs 0 ) { T e → { ^ e } … }`,
  with `vs` a local and a `;` defer armed before the `^`, took the element
  out of its slot before the defers ran. A defer that read `vs` saw an
  emptied String (a wrong value, and a fault when its data went to a C
  call). `^ . p s` of a payload of a Vec of structs was left lent there,
  and the Vec's drop after the chain freed what the caller got
  (heap-use-after-free). Under such a defer both are copied now. A payload
  that cannot be copied is refused, as a lend is. Without a defer they
  are still taken out of the slot, with no allocation.
