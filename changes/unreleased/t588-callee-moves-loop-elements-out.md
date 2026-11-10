### Fixed

- **A function or closure that moves its container's elements out in a `~`
  loop says so to its callers** (Agora #588). `@ wipe ( Vec String ) t → v {
  ~ x t { ( string_free x ) } }` ended no borrow at `( wipe t )`: a view of
  an element taken before the call read freed memory after it, and `~ y t {
  ( wipe t ) ( string_free y ) }` freed an element twice. The same loop in a
  closure over a captured Vec did the same. Both are refused now, as the
  loop written inline already was; a call with no borrow of the elements
  live is unchanged.
