// thread_arc_dyn_plugin_table.nu — the plugin table of agora #128: trait
// objects of a `: Send Sync` trait in a Vec of Arcs, the Vec itself in an
// Arc that two threads read at once, one plugin handed to the other thread
// down a channel, and an ArcWeak pointing back at one. Every read is
// arc_get's frozen lend; each object is released once, when its last
// handle goes.
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/arc.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/channel.nu`

: Add { i k }
: Mul { i k String tag }

% Op [T] : Send Sync { @ apply T self i x → i @ name T self → String }

% Op Add { @ apply Add a i x → i { ^ + x . a k } @ name Add a → String { ^ ( string_from `add` ) } }

% Op Mul { @ apply Mul m i x → i { ^ * x . m k } @ name Mul m → String { ^ ( string_from ( string_data . m tag ) ) } }

@ run_all ( Vec ( Arc % Op ) ) ops i x → i {
    : ~ i v x
    ~ o ops { = v ( apply ( arc_get [% Op] o ) v ) }
    ^ v
}

@ main → i {
    : ( Vec ( Arc % Op ) ) ops ( vec_new [( Arc % Op )] )
    ( vec_push [( Arc % Op )] ops ( arc_new [% Op] ( dyn Op @ Add { 3 } ) ) )
    ( vec_push [( Arc % Op )] ops ( arc_new [% Op] ( dyn Op @ Mul { 2 ( string_from `mul` ) } ) ) )
    : ( Arc ( Vec ( Arc % Op ) ) ) table ( arc_new [( Vec ( Arc % Op ) )] ops )
    : ( Channel ( Arc % Op ) ) ch ( chan_new [( Arc % Op )] )
    : ( Arc ( Vec ( Arc % Op ) ) ) t1 ( arc_clone [( Vec ( Arc % Op ) )] table )
    : ( Arc ( Vec ( Arc % Op ) ) ) t2 ( arc_clone [( Vec ( Arc % Op ) )] table )
    : ( Channel i ) out ( chan_new [i] )
    ?? ( thread_spawn \ → v {
        : ~ i s 0 : ~ i k 0
        ~ < k 10000 { = s + s ( run_all ( arc_get [( Vec ( Arc % Op ) )] t1 ) k ) = k + k 1 }
        ( chan_send [i] out s )
        ?? ( chan_recv [( Arc % Op )] ch ) { T op → { ( chan_send [i] out ( apply ( arc_get [% Op] op ) 100 ) ) } F → {} }
    } ) {
        T th → {
            : ~ i s 0 : ~ i k 0
            ~ < k 10000 { = s + s ( run_all ( arc_get [( Vec ( Arc % Op ) )] t2 ) k ) = k + k 1 }
            ( chan_send [( Arc % Op )] ch ( arc_clone [% Op] ( vec_at [( Arc % Op )] ( arc_get [( Vec ( Arc % Op ) )] table ) 1 ) ) )
            ( thread_join th )
            ?? ( chan_recv [i] out ) { T a → { ( nurl_print_int + a s ) ( nurl_print `\n` ) } F → {} }
            ?? ( chan_recv [i] out ) { T b → { ( nurl_print_int b ) ( nurl_print `\n` ) } F → {} }
        }
        F _ → {}
    }
    : ( ArcWeak % Op ) w ( arc_downgrade [% Op] ( vec_at [( Arc % Op )] ( arc_get [( Vec ( Arc % Op ) )] table ) 0 ) )
    ?? ( arc_weak_upgrade [% Op] w ) { T strong → { ( nurl_println ( string_data ( name ( arc_get [% Op] strong ) ) ) ) } F → {} }
    ^ 0
}
