// Borrow checker — iterator invalidation through a helper defined BELOW
// the loop (docs/MEMORY.md §2.5). `grow` pushes to the container it is
// handed, so calling it inside `~ y xs` invalidates the loop's cursor
// exactly as an inline `( vec_push xs … )` does. The per-function
// mutation summary that catches the one-call-deep form is built in
// codegen order, so with `grow` defined after `main` the summary was
// empty at the call — read as "does not mutate" rather than "not known
// yet" — and the loop compiled clean.
//
// The check is now parked at the call and replayed against the final
// summary after the whole module (resolve_pending_iter_mut). Which side
// of the loop the helper is written on does not change the answer.
$ `stdlib/core/vec.nu`

@ main → i {
    : ( Vec i ) xs ( vec_new [i] )
    ( vec_push [i] xs 1 )
    ~ y xs { ( grow xs ) }
    ( vec_free [i] xs )
    ^ 0
}

@ grow ( Vec i ) v → v {
    ( vec_push [i] v 2 )
}
