// arc_of_views_field_returned_in_an_option: agora #269 — an Arc whose payload views a local String, read out of a struct field and returned inside an option: a view of the local, still refused (the shape the fix must keep).
// Closed: a library handle holds views exactly when its type arguments can (`libhta##`, g_thv_precise), in the borrow checker's binding class too: a struct holding an `( Arc i )` or a `( Box ( Vec i ) )` is an owner, not a view-holder whose field handed back reads as a view of it (bck_bind_class0; agora #269).
// main: rejected.
// map: §2.12 | A2 | rejected | - | agora #269: an Arc whose payload views a local, returned out of a field
$ `stdlib/core/string.nu`
$ `stdlib/std/arc.nu`

: V { s t }
: C { ( Arc V ) a i rc }

@ answer i k → ?( Arc V ) {
    : String st ( string_from `a local string the Arc's payload views` )
    : C col @ C { ( arc_new [V] @ V { ( string_data st ) } ) 0 }
    : ( Arc V ) x . col a
    ^ @ ?( Arc V ) { T x }
}

@ main → i {
    ?? ( answer 1 ) { T x → { ( nurl_println . ( arc_get [V] x ) t ) } F → {} }
    ^ 0
}
