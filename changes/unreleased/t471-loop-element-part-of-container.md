### Fixed

- **A `~` loop's element is a part of what the loop iterates** (Agora #471, #350). Before this, a view of the element's own storage could be kept past its container (a heap-use-after-free). The view can be `( string_data x )`, a field of it, a slice of its buffer, or an element read out of it; a borrow of the element, or a closure that captured it, behaves the same way. It now ends as a `( vec_at xs k )` binding's does:
  - when the container is released, moved or given a new value;
  - when the container's elements are dropped or replaced;
  - when the element's own buffer moves.

  The container growing does not end it. The same holds for a loop over a field, a borrow, a parameter or a part of a call's result (`~ x . ( vec_at [B] bs 0 ) items`, a `box_get` or `map_get` payload), and for nested loops. A function of your own that hands such a view of its parameter's element back now tells its callers: in a container, a struct, an option or an enum, or as a bare `s`, directly or through a binding, also when the function comes later in the program. A change made through the loop's element (`string_push_str x …`, `vec_clear e`, `= . x name …`) now ends the views into the container's elements taken before it, within a function (Agora #350).

### Changed

- The element mark is one level deep, as `vec_at`'s already was. Growing an element of a `( Vec ( Vec String ) )` ends a view of a String inside that element. A holder emptied before the container ends, or a `vec_set` of another index, is refused as its `vec_at` spelling is.
