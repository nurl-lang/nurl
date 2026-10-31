### Fixed

- **A buffer moved through a copy of its owner's handle ends the owner's views** (Agora #293). A slice of `vs`, then `( vec_reserve [i] w 4096 )` (or pushes that grow it) through `: ( Vec i ) w ( id vs )` or a field viewer `. o buf`, left the slice reading the freed buffer. Such a copy is the owner's own handle, so the realloc ends its views, as when the call names the owner.
- **A view kept through a borrow is kept in the owner** (Agora #292). A slice of a block-local pushed into a vector through an identity copy, a field viewer or an element borrow was recorded on the borrow only, and was read after its source ended. The owner the borrow flattens to now holds the view, and it ends with its source. A view of an older binding still pushes fine.
