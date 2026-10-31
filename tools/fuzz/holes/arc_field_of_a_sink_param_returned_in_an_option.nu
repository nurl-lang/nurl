// arc_field_of_a_sink_param_returned_in_an_option: agora #269 — as arc_field_returned_in_an_option, the struct a `sink` parameter (the field moves out of it: #257).
// Closed: a library handle holds views exactly when its type arguments can (`libhta##`, g_thv_precise), in the borrow checker's binding class too: a struct holding an `( Arc i )` or a `( Box ( Vec i ) )` is an owner, not a view-holder whose field handed back reads as a view of it (bck_bind_class0; agora #269).
// main: rejected ("this returns a view of 'col'") — a correct program.
// map: §2.12 | A2 | runs-clean | - | agora #269: an Arc field of a sink parameter returned in an option
$ `stdlib/std/arc.nu`

: C { ( Arc i ) a i rc }

@ answer sink C col → ?( Arc i ) {
    : ( Arc i ) x . col a
    ^ @ ?( Arc i ) { T x }
}

@ main → i {
    : C c @ C { ( arc_new [i] 41 ) 0 }
    ?? ( answer c ) { T x → { ( nurl_println_int + 1 ( arc_get [i] x ) ) } F → {} }
    ^ 0
}
