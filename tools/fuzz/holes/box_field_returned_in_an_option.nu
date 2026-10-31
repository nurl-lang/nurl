// box_field_returned_in_an_option: agora #269 — as arc_field_returned_in_an_option, a `( Box ( Vec i ) )` field.
// Closed: a library handle holds views exactly when its type arguments can (`libhta##`, g_thv_precise), in the borrow checker's binding class too: a struct holding an `( Arc i )` or a `( Box ( Vec i ) )` is an owner, not a view-holder whose field handed back reads as a view of it (bck_bind_class0; agora #269).
// main: rejected ("this returns a view of 'col'") — a correct program.
// map: §2.12 | A2 | runs-clean | - | agora #269: a Box field bound and returned in an option
$ `stdlib/core/vec.nu`
$ `stdlib/core/box.nu`

: C { ( Box ( Vec i ) ) b i rc }

@ answer i k → ?( Box ( Vec i ) ) {
    : ( Vec i ) xs ( vec_new [i] )
    ( vec_push [i] xs + 40 k )
    : C col @ C { ( box_new [( Vec i )] xs ) 0 }
    : ( Box ( Vec i ) ) x . col b
    ^ @ ?( Box ( Vec i ) ) { T x }
}

@ main → i {
    ?? ( answer 1 ) { T x → { ( nurl_println_int + 1 ( vec_at [i] ( box_get [( Vec i )] x ) 0 ) ) } F → {} }
    ^ 0
}
