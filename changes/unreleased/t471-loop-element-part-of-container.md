### Fixed

- **A `~` loop's element is a part of what the loop iterates** (Agora #471). Before this, a view of the element's own storage could be kept past its container (a heap-use-after-free). The view can be `( string_data x )`, a field of it, a slice of its buffer, or an element read out of it; a borrow of the element behaves the same way. It now ends as a `( vec_at xs k )` binding's does:
  - when the container is released, moved or given a new value;
  - when the container's elements are dropped or replaced;
  - when the element's own buffer moves.

  The container growing does not end it. The same holds for a loop over a field, a borrow or a parameter, and for nested loops. A function of your own that hands such a view of its parameter's element back now tells its callers, a bare `s` result included.

### Changed

- The element mark is one level deep, as `vec_at`'s already was. Growing an element of a `( Vec ( Vec String ) )` ends a view of a String inside that element. A holder emptied before the container ends, or a `vec_set` of another index, is refused as its `vec_at` spelling is.
