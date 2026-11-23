### Fixed

- **A `??` over a call, bound by `:` and then handed back, no longer hands back an element of a local** (AGORA-956). `: e ?? ( vec_get [D] v 0 ) { T d → d F → … }` followed by `^ e`, with `v` a local Vec, handed the caller an element `v`'s drop released. The binding now asks what the direct `^ ?? …` asks: a String or another type that can be copied is copied, and a value that cannot be copied is refused with the same message. Take the value out of `v` instead (`vec_remove`, `vec_pop`).
