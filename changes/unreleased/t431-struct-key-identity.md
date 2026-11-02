### Fixed

- **Telling a struct value from another by key uses a field that
  identifies it** (Agora #431; probes struct_owner_keyed_*). #419's
  identity test (is a lent result the owner's old value?) keyed a struct
  by its first handle field. An enum field whose variant holds a number
  (`Id 1`) keys by that number, which a different value can hold too. So
  `= o ( pick o other k )` with `P { Tag t String s }` took `other`'s
  value for `o`'s own, and both dropped it (heap-use-after-free). The test
  now keys by the first field that is an identity whatever it holds: the
  String here, or past an option field. The hand-over to a borrower keeps
  its key, since it compares a value with a copy of its own handle.
