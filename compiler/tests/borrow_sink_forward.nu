// Borrow checker — indirect use-after-free through a helper defined
// BELOW the call (docs/MEMORY.md §2.2 / §6.4). `release` frees its
// parameter, so auto-sink infers that passing a handle there consumes
// it and any later use is a use-after-move. That inference runs as
// each body compiles, so at `( release v )` the summary did not exist
// yet — and an empty summary was read as "does not consume" rather
// than "not known yet". The identical program with `release` defined
// ABOVE main is rejected (borrow_sink_use_after.nu); this one compiled
// clean and freed the buffer under the following push.
//
// The call site now parks a `pendcall` row and the whole function's
// borrow walk is deferred to the end of the module, where every
// summary is final.
$ `stdlib/core/vec.nu`

@ main → i {
    : ( Vec i ) v ( vec_new [i] )
    ( release v )
    ( vec_push [i] v 1 )
    ^ 0
}

@ release ( Vec i ) v → v {
    ( vec_free [i] v )
}
