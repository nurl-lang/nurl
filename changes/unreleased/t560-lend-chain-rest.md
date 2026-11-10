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
