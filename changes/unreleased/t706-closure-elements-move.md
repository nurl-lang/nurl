### Fixed

- **A container that moves its elements moves closures too** (Agora #706).
  A closure element is owned by the storage it sits in. Library code that
  moved elements read each one into a binding and stored the binding into
  its new slot — a move for every other type, but a closure stored as a
  plain binding is copied: the slot got a clone of its environment and the
  environment it came with was never released. A `HashMap` whose values
  are closures leaked every one its growth rehashed (from the sixth entry
  on); `vec_swap`, `vec_reverse`, `vec_retain`, `sort_by` and a `Heap` over
  closures leaked one environment per element moved. An element that
  changes places — in a rehash, a swap, a sort's shift — is declared a
  write-back (`mem_put_back`) now, which a closure element store honours
  as every other type's store already did. Containers of any other type
  compile to the same instructions as before.
