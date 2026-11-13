### Fixed

- **What an iterator yields holds what the iterator holds** (Agora #472).
  `iter_from_vec` over a `( Vec s )` of views of a String yields copies of
  those views. `iter_collect`, `iter_find`, `iter_map` or `iter_filter`
  collected, a direct `( it 0 )`, or a function of your own draining a
  closure parameter handed them back tied to nothing, and read after the
  String's block they read freed memory. They are refused now, naming the
  String. Iterators over literals, over a String that outlives their
  results, or over numbers still compile.
