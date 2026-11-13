// closure_signature_naming_an_rc_crosses_a_thread.nu — a closure that
// captured nothing crosses a thread boundary whatever its signature names
// (Agora #788).
//
// A closure is `{ R (i8*, P…)*, i8* }`, and the Send/Sync walk read it as
// any inline aggregate, member by member: a closure whose code hands back a
// `?( Rc i )` "reached an Rc", and was refused wherever it crossed —
// captured, in a struct's field, in a Vec of options, on a channel, in an
// Arc several threads run it from, or as the type argument of a `Send`
// bound. Each closure here makes a fresh Rc on the thread that runs it and
// drops it there. What a closure holds is what it captured: its capture
// set decides, and these capture nothing.
$ `stdlib/std/rc.nu`
$ `stdlib/std/arc.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/channel.nu`
$ `stdlib/core/vec.nu`

: H { ( @ ?( Rc i ) i ) mk i n }

: Job { ( @ ?( Rc i ) i ) run }

@ show ? ( Rc i ) o → v {
    ?? o { T x → { ( nurl_println_int ( rc_get [i] x ) ) } F → { ( nurl_println `none` ) } }
}

// Captured by the thread's closure.
@ captured → v {
    : ( @ ?( Rc i ) i ) f \ i k → ?( Rc i ) { ^ @ ?( Rc i ) { T ( rc_new [i] k ) } }
    : !Thread ThreadErr r ( thread_spawn \ → v { ( show ( f 1 ) ) } )
    ?? r { T t → { ( thread_join t ) } F e → {} }
}

// In a struct's field.
@ in_a_field → v {
    : H h @ H { \ i k → ?( Rc i ) { ^ @ ?( Rc i ) { T ( rc_new [i] + k 1 ) } } 3 }
    : !Thread ThreadErr r ( thread_spawn \ → v {
        : ( @ ?( Rc i ) i ) m . h mk
        ( show ( m 1 ) )
    } )
    ?? r { T t → { ( thread_join t ) } F e → {} }
}

// In a Vec of options.
@ in_a_vec → v {
    : ( Vec ? ( @ ?( Rc i ) i ) ) fs ( vec_new [? ( @ ?( Rc i ) i )] )
    ( vec_push [? ( @ ?( Rc i ) i )] fs @ ?( @ ?( Rc i ) i ) { T \ i k → ?( Rc i ) { ^ @ ?( Rc i ) { T ( rc_new [i] + k 2 ) } } } )
    : !Thread ThreadErr r ( thread_spawn \ → v {
        ?? ( vec_get [? ( @ ?( Rc i ) i )] fs 0 ) { T o → { ?? o { T g → { ( show ( g 1 ) ) } F → {} } } F _ → {} }
    } )
    ?? r { T t → { ( thread_join t ) } F e → {} }
}

// On a channel.
@ on_a_channel → v {
    : ( Channel Job ) ch ( chan_new [Job] )
    : ( @ ?( Rc i ) i ) f \ i k → ?( Rc i ) { ^ @ ?( Rc i ) { T ( rc_new [i] + k 3 ) } }
    ( chan_send [Job] ch @ Job { f } )
    ?? ( chan_recv [Job] ch ) { T j → { : ( @ ?( Rc i ) i ) m . j run ( show ( m 1 ) ) } F → {} }
}

// In an Arc four threads run it from at once (the Sync question).
// (One run per thread: a closure read out of a captured Arc's payload and
// run in a loop inside a closure body is refused on its second round,
// Agora #644.)
@ in_an_arc → v {
    : ( Arc H ) a ( arc_new [H] @ H { \ i k → ?( Rc i ) { ^ @ ?( Rc i ) { T ( rc_new [i] k ) } } 3 } )
    : ( Vec Thread ) ts ( vec_new [Thread] )
    : ~ i j 0
    ~ < j 4 {
        : ( Arc H ) mine ( arc_clone [H] a )
        : i want j
        : !Thread ThreadErr r ( thread_spawn \ → v {
            : ( @ ?( Rc i ) i ) m . ( arc_get [H] mine ) mk
            ?? ( m want ) { T x → { ? != ( rc_get [i] x ) want { ( nurl_println `wrong` ) } {} } F → { ( nurl_println `none` ) } }
        } )
        ?? r { T t → { ( vec_push [Thread] ts t ) } F e → {} }
        = j + j 1
    }
    = j 0
    ~ < j ( vec_len [Thread] ts ) {
        ?? ( vec_get [Thread] ts j ) { T t → { ( thread_join t ) } F _ → {} }
        = j + j 1
    }
    ( nurl_println `arc: 4 threads` )
}

// The type argument of a `Send` bound.
@ go [X : Send] X x → v {
    : !Thread ThreadErr r ( thread_spawn \ → v { : X y x } )
    ?? r { T t → { ( thread_join t ) } F e → {} }
}

@ bound → v {
    : ( @ ?( Rc i ) i ) f \ i k → ?( Rc i ) { ^ @ ?( Rc i ) { T ( rc_new [i] k ) } }
    ( go [( @ ?( Rc i ) i )] f )
    ( nurl_println `bound: Send` )
}

@ main → i {
    ( captured )
    ( in_a_field )
    ( in_a_vec )
    ( on_a_channel )
    ( in_an_arc )
    ( bound )
    ^ 0
}
