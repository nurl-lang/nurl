// atomic_basic.nu — std/atomic.nu acceptance.
//
// The single-threaded meaning of every operation (fetch-add and fetch-sub
// return the value before, cas stores only on a match, max only raises),
// then the reason the type exists: four threads changing one word at once
// through copies of the handle. 4 x 50000 fetch-adds must sum exactly, a
// cas-loop increment must lose no update, and a fetch-max race must end
// at the largest value any thread offered. A plain `i` shared this way
// would lose updates; a Locked would take a mutex per add.

$ `stdlib/core/vec.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/atomic.nu`

@ show s label i x → v { ( nurl_print label ) ( nurl_println_int x ) }

// A cas-loop increment: read, try to store one more, retry on a race.
@ cas_inc Atomic a → v {
    : ~ b done F
    ~ ! done {
        : i cur ( atomic_load a )
        = done ( atomic_cas a cur + cur 1 )
    }
}

@ main → i {
    : Atomic a ( atomic_new 5 )
    ( show `load:      ` ( atomic_load a ) )
    ( show `add old:   ` ( atomic_add a 3 ) )
    ( show `after add: ` ( atomic_load a ) )
    ( show `sub old:   ` ( atomic_sub a 2 ) )
    ( show `swap old:  ` ( atomic_swap a 100 ) )
    ( show `cas hit:   ` ? ( atomic_cas a 100 7 ) 1 0 )
    ( show `cas miss:  ` ? ( atomic_cas a 100 9 ) 1 0 )
    ( show `value:     ` ( atomic_load a ) )
    ( show `max old:   ` ( atomic_max a 3 ) )
    ( show `max kept:  ` ( atomic_load a ) )
    ( show `max old 2: ` ( atomic_max a 42 ) )
    ( show `max raised:` ( atomic_load a ) )
    ( atomic_store a -1 )
    ( show `stored:    ` ( atomic_load a ) )

    // A copy of the handle (mem_dup shares it) is the same word.
    : Atomic b ( mem_dup a )
    ( atomic_add b 11 )
    ( show `via copy:  ` ( atomic_load a ) )

    // Four threads, one word each kind of operation.
    : Atomic sum ( atomic_new 0 )
    : Atomic casd ( atomic_new 0 )
    : Atomic hi ( atomic_new 0 )
    : ( Vec Thread ) ts ( vec_new [Thread] )
    : ~ i t 0
    ~ < t 4 {
        : i base * t 1000
        : !Thread ThreadErr r ( thread_spawn \ → v {
            : ~ i k 0
            ~ < k 50000 {
                ( atomic_add sum 1 )
                ? == % k 10 0 { ( cas_inc casd ) } {}
                ( atomic_max hi + base % k 997 )
                = k + k 1
            }
        } )
        ?? r { T th → { ( vec_push [Thread] ts th ) } F _ → { ( nurl_println `spawn failed` ) } }
        = t + t 1
    }
    ~ th ts { ( thread_join th ) }
    ( show `threads sum: ` ( atomic_load sum ) )
    ( show `threads cas: ` ( atomic_load casd ) )
    ( show `threads max: ` ( atomic_load hi ) )
    ^ 0
}
