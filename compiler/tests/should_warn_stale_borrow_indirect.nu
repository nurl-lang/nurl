// Borrow checker — a stale container borrow invalidated one call deep
// (docs/MEMORY.md §2.10). `( vec_data v )` hands out a pointer into
// `v`'s buffer; growing `v` may reallocate it, and reading the old
// pointer afterwards reads freed memory that still looks plausible.
//
// The kill rule fired for a stdlib mutator applied directly to the
// container, so the inline `( vec_push v … )` was reported and the same
// push behind `( grow v )` was not — which reads as "wrap the push in a
// helper" being the cure for the diagnostic. The per-function mutation
// summary (g_fn_mutates, the same one §2.5 consults) now invalidates
// the borrow at the helper call too.
$ `stdlib/core/vec.nu`

@ grow ( Vec u ) v → v {
    ( vec_push [u] v # u 2 )
}

// The container is pre-reserved, so the helper's push provably does
// not grow it and the pointer stays valid at run time — which is
// precisely why this is a WARNING and not an error (§2.10). The
// diagnostic is conservative on purpose; the program is correct.
@ main → i {
    : ~ ( Vec u ) v ( vec_with_cap [u] 8 )
    ( vec_push [u] v # u 1 )
    : *u p ( vec_data [u] v )
    ( grow v )
    : i x # i . p 0
    ( nurl_print_int x )
    ( vec_free [u] v )
    ^ 0
}
