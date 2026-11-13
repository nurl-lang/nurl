// arc_payload_view_in_a_map_written_through_is_refused: a Slice of an Arc's payload put in a local HashMap, read back with map_get and written through, by two threads
// Closed: agora #682, a map a payload view is put in holds one.
// main 07d73fb1: accepted (a data race on every run; ASan: attempting double-free on 4 runs in 6).
// map: §6.5 | A3 | rejected | - | agora #682: a payload view kept as a map's value is still one
$ `stdlib/std/hashmap.nu`
$ `stdlib/std/arc.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/core/option.nu`

@ fresh i k → ( Vec i ) {
    : ( Vec i ) r ( vec_new [i] )
    ( vec_push [i] r k )
    ^ r
}

@ writer ( Arc ( Vec ( Vec i ) ) ) mine i n → v {
    : ( @ i i ) hs \ i x → i { ^ ( hash_int x ) }
    : ( @ b i i ) es \ i a i b → b { ^ ( eq_int a b ) }
    : ~ i k 0
    ~ < k n {
        : ( HashMap i ( Slice ( Vec i ) ) ) m ( map_new [i ( Slice ( Vec i ) )] )
        : ?( Slice ( Vec i ) ) old ( map_set [i ( Slice ( Vec i ) )] m 1 ( slice_from_vec [( Vec i )] ( arc_get [( Vec ( Vec i ) )] mine ) ) hs es )
        ?? ( map_get [i ( Slice ( Vec i ) )] m 1 hs es ) { T w → { ( slice_put [( Vec i )] w 0 ( fresh k ) ) } F → {} }
        = k + k 1
    }
}

@ main → i {
    : ( Vec ( Vec i ) ) rows ( vec_new [( Vec i )] )
    ( vec_push [( Vec i )] rows ( fresh 0 ) )
    : ( Arc ( Vec ( Vec i ) ) ) shared ( arc_new [( Vec ( Vec i ) )] rows )
    : ( Arc ( Vec ( Vec i ) ) ) other ( arc_clone [( Vec ( Vec i ) )] shared )
    : ( @ v ) body \ → v { ( writer other 20000 ) }
    ?? ( thread_spawn body ) {
        T th → {
            ( writer shared 20000 )
            : i joined ( thread_join th )
        }
        F _ → {}
    }
    ^ 0
}
