### Fixed

- **More ways of handing back a closure keep its effects** (Agora #802). After #656, a returned closure carried what it does to the arguments it captured only for a plain name argument and a `:` binding of the result. These spellings were accepted, and running the closure left the caller's view dangling (heap-use-after-free):
  - an argument that is a field path, `( mk . w xs )`, or an element, `( mk ( vec_at vv 0 ) )`;
  - a join or a block handed back, `^ ? k c1 c2`, or a closure assigned in an arm and then handed back;
  - the result given with `=`;
  - a closure that captured a binding by reference, re-pointed at a parameter, its field or its element before the closure runs.

  These are refused now.
