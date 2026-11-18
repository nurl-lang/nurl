### Fixed

- **Taking a field out of a copy of a container's element no longer leaves the element and the taker owning one value** (AGORA-870). `: Slot s ( vec_at [Slot] t k )  : ( Vec u ) out . s body  = . s body ( vec_new [u] )  ^ out` was accepted, and the caller's `t` and the result both released the old body, a heap-use-after-free, in safe code. This is refused now. Take the element out of the container instead, `?? ( vec_replace [Slot] t k new ) { T old → … }`; in unsafe code, writing the copy back (`vec_put_back`) is still accepted.
