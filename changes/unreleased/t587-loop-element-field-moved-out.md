### Fixed

- **A field of a `~` loop's element handed to a `sink` is no longer freed
  twice** (Agora #587). `~ x t { ( gone . x name ) }`, or `( string_free
  . x name )`, released the field and left it in the container, which
  released it again (heap use after free). The field is emptied in the
  element's slot now, as a whole element moved out is; a view of it taken
  before the loop cannot be read after, and a function doing this to its
  parameter says so to its callers.
- **A loop element moved out after its container grew empties the right
  slot** (Agora #587). After growth through an alias, `( string_free x )`
  then `break` wrote the emptied slot into the old buffer and left the
  element in the new one (heap use after free, double free). The slot is
  found through the Vec's control block at that moment.
