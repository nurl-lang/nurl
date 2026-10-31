// A closure whose body releases one capture (here: hands it to a `sink`)
// takes only that one over. A handle the enclosing frame still uses after
// the closure — an Atomic the spawner reads after the join, a Vec the frame
// reads after calling the closure — stays the frame's: the spawn's copy of
// the env shares it, and the closure's own env drops nothing of it. Before,
// every handle capture moved into the env and was freed under the frame
// (agora #247).

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/atomic.nu`

@ consume sink String s → i { ^ ( string_len s ) }

@ spawned → v {
    : Atomic rc_out ( atomic_new -1 )
    : String owned ( string_from `hello` )
    : !Thread ThreadErr srv ( thread_spawn \ → v {
        : i r ( consume owned )
        ( atomic_store rc_out r )
    } )
    ?? srv { T t → { ( thread_join t ) } F _ → {} }
    ( nurl_println_int ( atomic_load rc_out ) )
}

@ called_here → v {
    : ( Vec i ) xs ( vec_new [i] )
    ( vec_push [i] xs 7 )
    : String owned ( string_from `hello` )
    {
        : ( @ i ) f \ → i { ^ + ( consume owned ) ( vec_len [i] xs ) }
        ( nurl_println_int ( f ) )
    }
    ( nurl_println_int ( vec_len [i] xs ) )
}

@ main → i {
    ( spawned )
    ( called_here )
    ^ 0
}
