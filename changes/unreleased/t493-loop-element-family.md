### Fixed

- **A `~` loop can no longer go on to its next element after its container's
  buffer moved through another name** (Agora #493). With `: ~ ( Vec String )
  cur t`, a `( vec_push [String] cur … )` inside `~ x t { … }` — or the same
  growth through a helper or a closure — moved `t`'s buffer, and the loop
  read its next element from the old one (heap use after free). The loop now
  holds a view of the storage it iterates, ended by any route; a `break`
  right after the growth, growth after the loop, and index loops stay
  accepted, and the element itself stays readable.
- **A view element of a `~` loop is a borrow of what it views** (Agora #492).
  `~ v ws { ( string_push_str line … ) ( nurl_println v ) }` over a `( Vec s
  )` of views of `line` read freed memory; it is refused now, as the
  `: s v ( vec_at [s] ws k )` spelling already was. The same holds for a
  struct-of-views element, and for a later round of the loop, whose element
  is a copy of a view that ended.
- **Moving a `~` loop's element out ends the borrows of the container's
  elements** (Agora #490). `: s v ( string_data ( vec_at [String] t 0 ) )`,
  then `~ x t { ( string_free x ) }` (or a `sink` call, `vec_free`), then
  reading `v` read freed memory. Moving the element
  out stays allowed; a borrow of the container's elements taken before it
  cannot be read after.
