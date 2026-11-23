### Fixed

- **A `:` binding of a `??` whose arm hands on a field of its payload can no longer outlive the matched value** (AGORA-957). `: e ?? g { V p → . p s Nil → ( mk ) }` inside a block, followed by `= outer e` and a read of `outer` after the block, read a field of `g`'s payload after `g` was released. It is refused now, as the same arm over a struct is (AGORA-941). Read the value inside the block, or hand it on with `= outer ?? g { V p → . p s … }`, which copies the field.
