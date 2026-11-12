// arc_payload_views_kept_in_containers_are_read.nu — views of an Arc's
// payload kept in containers, read by four threads at once (Agora #682).
// A view read back out of a Vec, a Vec of structs, a map or a helper's
// element is a view of the payload, and only a change through it is
// refused: reading through it is what a frozen payload is for. Each thread
// also changes its own containers — pushes more views into them, truncates
// and clears them — which changes the containers, not the payload.
$ `stdlib/std/arc.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/hashmap.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/core/option.nu`

: Win { ( Slice ( Vec i ) ) w i tag }

@ row i k → ( Vec i ) {
    : ( Vec i ) r ( vec_new [i] )
    : ~ i j 0
    ~ < j k { ( vec_push [i] r j ) = j + j 1 }
    ^ r
}

@ firstw ( Vec ( Slice ( Vec i ) ) ) ws → ( Slice ( Vec i ) ) { ^ ( vec_at [( Slice ( Vec i ) )] ws 0 ) }

@ total ( Vec ( Slice ( Vec i ) ) ) ws → i {
    : ~ i s 0
    ~ w ws { = s + s ( vec_len [i] ( slice_at [( Vec i )] w 0 ) ) }
    ^ s
}

// One round: every container read back, each read the length of row 0 (3).
@ reads ( Arc ( Vec ( Vec i ) ) ) mine → i {
    : ~ i s 0
    : ( Vec ( Slice ( Vec i ) ) ) ws ( vec_new [( Slice ( Vec i ) )] )
    ( vec_push [( Slice ( Vec i ) )] ws ( slice_from_vec [( Vec i )] ( arc_get [( Vec ( Vec i ) )] mine ) ) )
    ( vec_push [( Slice ( Vec i ) )] ws ( slice_from_vec [( Vec i )] ( arc_get [( Vec ( Vec i ) )] mine ) ) )
    ?? ( vec_get [( Slice ( Vec i ) )] ws 1 ) { T w → { = s + s ( vec_len [i] ( slice_at [( Vec i )] w 0 ) ) } F → {} }
    = s + s ( vec_len [i] ( slice_at [( Vec i )] ( vec_at [( Slice ( Vec i ) )] ws 0 ) 0 ) )
    = s + s ( vec_len [i] ( slice_at [( Vec i )] ( firstw ws ) 0 ) )
    = s + s ( total ws )
    ( vec_truncate [( Slice ( Vec i ) )] ws 1 )
    = s + s ( total ws )
    ( vec_clear [( Slice ( Vec i ) )] ws )
    : ( Vec Win ) xs ( vec_new [Win] )
    ( vec_push [Win] xs @ Win { ( slice_from_vec [( Vec i )] ( arc_get [( Vec ( Vec i ) )] mine ) ) 0 } )
    ?? ( vec_get [Win] xs 0 ) { T x → { = s + s ( vec_len [i] ( slice_at [( Vec i )] . x w 0 ) ) } F → {} }
    : ( @ i i ) hs \ i x → i { ^ ( hash_int x ) }
    : ( @ b i i ) es \ i a i b → b { ^ ( eq_int a b ) }
    : ( HashMap i ( Slice ( Vec i ) ) ) m ( map_new [i ( Slice ( Vec i ) )] )
    : ?( Slice ( Vec i ) ) old ( map_set [i ( Slice ( Vec i ) )] m 1 ( slice_from_vec [( Vec i )] ( arc_get [( Vec ( Vec i ) )] mine ) ) hs es )
    ?? ( map_get [i ( Slice ( Vec i ) )] m 1 hs es ) { T w → { = s + s ( vec_len [i] ( slice_at [( Vec i )] w 0 ) ) } F → {} }
    ^ s
}

@ main → i {
    : ( Vec ( Vec i ) ) rows ( vec_new [( Vec i )] )
    ( vec_push [( Vec i )] rows ( row 3 ) )
    ( vec_push [( Vec i )] rows ( row 5 ) )
    : ( Arc ( Vec ( Vec i ) ) ) shared ( arc_new [( Vec ( Vec i ) )] rows )
    : ( Vec Thread ) ts ( vec_new [Thread] )
    : ~ i j 0
    ~ < j 4 {
        : ( Arc ( Vec ( Vec i ) ) ) mine ( arc_clone [( Vec ( Vec i ) )] shared )
        : !Thread ThreadErr r ( thread_spawn \ → v {
            : ~ i k 0
            ~ < k 2000 {
                ? != ( reads mine ) 24 { ( nurl_println `wrong` ) } {}
                = k + k 1
            }
        } )
        ?? r { T t → { ( vec_push [Thread] ts t ) } F e → { ( nurl_println `spawn fail` ) } }
        = j + j 1
    }
    = j 0
    ~ < j ( vec_len [Thread] ts ) {
        ?? ( vec_get [Thread] ts j ) { T t → { ( thread_join t ) } F _ → {} }
        = j + j 1
    }
    ( nurl_print `read by 4 threads: ` )
    ( nurl_println_int ( reads shared ) )
    ^ 0
}
