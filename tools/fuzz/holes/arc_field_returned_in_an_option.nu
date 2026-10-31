// arc_field_returned_in_an_option: agora #269 — an `( Arc i )` read out of a local struct's field, bound, and returned inside an option was refused as a view of the struct; the same shape with a Vec, or `^ x` bare, was accepted.
// Closed: a library handle holds views exactly when its type arguments can (`libhta##`, g_thv_precise), in the borrow checker's binding class too: a struct holding an `( Arc i )` or a `( Box ( Vec i ) )` is an owner, not a view-holder whose field handed back reads as a view of it (bck_bind_class0; agora #269).
// main: rejected ("this returns a view of 'col'") — a correct program.
// map: §2.12 | A2 | runs-clean | - | agora #269: an Arc field bound and returned in an option (no view)
$ `stdlib/std/arc.nu`

: C { ( Arc i ) a i rc }

@ answer i k → ?( Arc i ) {
    : C col @ C { ( arc_new [i] + 40 k ) 0 }
    : ( Arc i ) x . col a
    ^ @ ?( Arc i ) { T x }
}

@ main → i {
    ?? ( answer 1 ) { T x → { ( nurl_println_int + 1 ( arc_get [i] x ) ) } F → {} }
    ^ 0
}
