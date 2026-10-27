// thread_arc_dyn_shared.nu — one trait object shared among threads (agora
// #128). An `( Arc %Job )` whose trait promises `: Send Sync` is the Rust
// `Arc<dyn Job + Send + Sync>`: every thread holding a clone reads it with
// arc_get and runs a method on the one shared box. arc_get lends the
// payload of every Arc, one that can lead back to it too — a payload
// holding a trait object, a tree of Arcs: the payload is frozen once made
// (docs/MEMORY.md §6.5), so no store through the lend can close a cycle,
// and a lend is all a reader needs.
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/arc.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/channel.nu`

: Count { i n String name }

% Job [T] : Send Sync { @ run T self i k → i }

% Job Count { @ run Count c i k → i { ^ + * . c n k ( string_len . c name ) } }

@ work ( Arc % Job ) j i k → i {
    : ~ i s 0
    : ~ i r 0
    ~ < r 100000 { = s + s ( run ( arc_get [% Job] j ) k ) = r + r 1 }
    ^ s
}

// A payload holding a trait object among its fields.
: Plugin { String tag % Job job }

// A payload that can hold a handle back to its own Arc (mem_ts_cyclic).
: Node { i v ( Vec ( Arc Node ) ) kids }

@ sum ( Arc Node ) a → i {
    : Node n ( arc_get [Node] a )
    : ~ i s . n v
    ~ k . n kids { = s + s ( sum k ) }
    ^ s
}

@ main → i {
    : ( Arc % Job ) a ( arc_new [% Job] ( dyn Job @ Count { 7 ( string_from `abc` ) } ) )
    : ( Arc % Job ) b ( arc_clone [% Job] a )
    : ( Arc % Job ) c ( arc_clone [% Job] a )
    : ( Channel i ) ch ( chan_new [i] )
    ?? ( thread_spawn \ → v { ( chan_send [i] ch ( work b 1 ) ) } ) {
        T t1 → {
            ?? ( thread_spawn \ → v { ( chan_send [i] ch ( work c 2 ) ) } ) {
                T t2 → { ( thread_join t1 ) ( thread_join t2 ) }
                F _ → { ( thread_join t1 ) }
            }
        }
        F _ → {}
    }
    : ~ i total 0
    : ~ i got 0
    ~ < got 2 {
        ?? ( chan_recv [i] ch ) { T x → { = total + total x } F → {} }
        = got + got 1
    }
    ( nurl_print_int total ) ( nurl_print `\n` )
    ( nurl_print_int ( run ( arc_get [% Job] a ) 0 ) ) ( nurl_print `\n` )

    : ( Arc Plugin ) p ( arc_new [Plugin] @ Plugin { ( string_from `count` ) ( dyn Job @ Count { 5 ( string_from `ab` ) } ) } )
    : ( Arc Plugin ) q ( arc_clone [Plugin] p )
    ?? ( thread_spawn \ → v { ( chan_send [i] ch ( run . ( arc_get [Plugin] q ) job 3 ) ) } ) {
        T t → { ( thread_join t ) }
        F _ → {}
    }
    ?? ( chan_recv [i] ch ) { T x → { ( nurl_print_int x ) ( nurl_print `\n` ) } F → {} }
    ( nurl_println ( string_data . ( arc_get [Plugin] p ) tag ) )

    : ( Vec ( Arc Node ) ) leaves ( vec_new [( Arc Node )] )
    ( vec_push [( Arc Node )] leaves ( arc_new [Node] @ Node { 2 ( vec_new [( Arc Node )] ) } ) )
    ( vec_push [( Arc Node )] leaves ( arc_new [Node] @ Node { 3 ( vec_new [( Arc Node )] ) } ) )
    : ( Arc Node ) root ( arc_new [Node] @ Node { 1 leaves } )
    ( nurl_print_int ( sum root ) ) ( nurl_print `\n` )
    ^ 0
}
