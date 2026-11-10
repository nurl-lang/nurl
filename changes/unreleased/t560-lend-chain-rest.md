### Fixed

- **An element of a parameter's element is not freed twice when handed
  back** (Agora #560). `: ( Vec String ) v ( vec_at pvv 0 )` then `?? (
  vec_get [String] v 0 ) { T e → { ^ e } … }`, with pvv a parameter,
  answered "owned" for e although v owned nothing on that run. The caller
  then freed pvv's element a second time. A payload lent out of a root that
  owned nothing on the run now answers "lent" there.
- **A payload's field bound first and handed back is the caller's own**
  (Agora #560). `: String t . p s  ^ t`, with p a `vec_get` payload of a
  local, handed the element's String to the caller while the local freed
  it. t now has the lend pairs of p, so it is copied as `^ . p s` is.
- **A lend of a local handed back through a slice, an inline call, a
  nested or option field, an owned payload or a closure body is copied**
  (Agora #560). Each of these returned an element of a local Vec to the
  caller as its own while the Vec's drop freed it:
  - `^ ( slice_at [String] sl 0 )` of a slice of a local;
  - `( slice_from_vec [String] vs )` written inline as the argument;
  - a slice bound from another slice;
  - `^ . . p q s` and `^ . r o` (an option field) of a `vec_get` payload;
  - `?? . r o { T e → ^ e }`;
  - an element of a `vec_pop` payload, directly or through a local option;
  - `^ . p s` in a closure body, whatever the payload was lent out of.

  Each now follows the lend down to the local it views and copies the
  value on the runs that local drops it.
