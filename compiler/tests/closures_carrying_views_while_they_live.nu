// closures_carrying_views_while_they_live.nu — the routes Agora #469 and
// #467 follow, with closures whose captured handles hold nothing of this
// side's that ends before they run: each runs clean. A Vec of Strings it
// owns, or of literal views, crosses to a thread; an Arc share crosses; a
// closure handed back over views of the caller's String runs while the
// String lives; one over Strings it owns runs after the caller's is gone.
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/arc.nu`
$ `stdlib/std/thread.nu`

: Cfg { ( Vec String ) names i n }

@ mk String s → ( @ v ) {
    : ( Vec s ) h ( vec_new [s] )
    ( vec_push [s] h ( string_data s ) )
    ^ \ → v { ( nurl_println ( vec_at [s] h 0 ) ) }
}

@ mk_own String s → ( @ v ) {
    : ~ ( Vec String ) h ( vec_new [String] )
    ( vec_push [String] h ( string_from ( string_data s ) ) )
    ^ \ → v { ( nurl_println ( string_data ( vec_at [String] h 0 ) ) ) }
}

@ main → i {
    : ~ ( Vec String ) own ( vec_new [String] )
    ( vec_push [String] own ( string_from `owned by the Vec` ) )
    : ~ ( Vec s ) lits ( vec_new [s] )
    ( vec_push [s] lits `a literal` )
    : ( Arc Cfg ) a ( arc_new [Cfg] @ Cfg { ( vec_new [String] ) 3 } )
    : ( Arc Cfg ) a2 ( arc_clone [Cfg] a )
    : !Thread ThreadErr t1 ( thread_spawn \ → v { ( nurl_println ( string_data ( vec_at [String] own 0 ) ) ) } )
    : i _1 ?? t1 { T th → ( thread_join th ) F _ → 0 }
    : !Thread ThreadErr t2 ( thread_spawn \ → v { ( nurl_println ( vec_at [s] lits 0 ) ) } )
    : i _2 ?? t2 { T th → ( thread_join th ) F _ → 0 }
    : !Thread ThreadErr t3 ( thread_spawn \ → v { ( nurl_println_int . ( arc_get [Cfg] a2 ) n ) } )
    : i _3 ?? t3 { T th → ( thread_join th ) F _ → 0 }
    : String s ( string_from `the caller's String, alive while f runs` )
    : ( @ v ) f ( mk s )
    ( f )
    : ~ ( @ v ) g \ → v {}
    {
        : String t ( string_from `freed before g runs` )
        = g ( mk_own t )
    }
    ( g )
    ^ 0
}
