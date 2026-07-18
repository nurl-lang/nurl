// A bare scalar can never initialise an anonymous-aggregate binding (an
// option / slice / result shape) — there is no implicit wrap. This used to
// slip through coerce_store_val's i1-widen branch as `zext i1 … to
// { i1, %Thing }`, invalid IR that nurlc accepted (rc 0) and only clang
// rejected. Must be a NURL diagnostic at the binding.

: Thing { i a i b2 }

@ gimme → b { ^ T }

@ main → i {
    : ?Thing x ( gimme )
    ^ 0
}
