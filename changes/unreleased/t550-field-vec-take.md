### Fixed

- **A `vec_get` payload of a local struct's Vec is taken out when handed
  back** (Agora #550). `?? ( vec_get [String] . h items 0 ) { T e → { ^ e } … }`,
  with h a local struct, gave the caller the element as its own, and h's
  drop freed it under the caller (heap use after free). The field path
  `h.items` now counts as a lend of h, so the element is taken out of its
  slot. A payload of a payload, a Slice element and a field of a payload
  are still open (Agora #553).
