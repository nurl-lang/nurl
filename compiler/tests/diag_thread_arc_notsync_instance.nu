// `unsafe % Sync W { }` promises that every instance of the generic `W`
// synchronises itself; `% NotSync ( W i ) { }` takes the promise back for
// one. The frozen-Arc rule asks the negative marker first: growing the
// `( W i )` read out of an Arc's payload is refused, sending on the `( W b )`
// beside it (the line above) is not (agora #693).
$ `stdlib/std/arc.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/channel.nu`
$ `stdlib/core/vec.nu`

: W [A] { ( Channel A ) c ( Vec A ) v }

@ wpush [A] ( W A ) w A x → v { ( vec_push [A] . w v x ) }

@ wsend [A] ( W A ) w A x → v { : b o ( chan_send [A] . w c x ) }

unsafe % Sync W {}

% NotSync ( W i ) {}

: App { ( W i ) wi ( W b ) wb }

unsafe % Sync App {}

@ reader ( Arc App ) mine i n → v {
    ( wsend [b] . ( arc_get [App] mine ) wb T )
    ( wpush [i] . ( arc_get [App] mine ) wi n )
}

@ main → i {
    : ( Arc App ) shared ( arc_new [App] @ App { @ ( W i ) { ( chan_new [i] ) ( vec_new [i] ) } @ ( W b ) { ( chan_new [b] ) ( vec_new [b] ) } } )
    : ( Arc App ) mine ( arc_clone [App] shared )
    ?? ( thread_spawn \ → v { ( reader mine 3 ) } ) {
        T t → { ( thread_join t ) }
        F _ → {}
    }
    ^ 0
}
