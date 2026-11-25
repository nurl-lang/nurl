$ `stdlib/core/vec.nu`
$ `stdlib/std/thread.nu`

@ eat sink ( Vec i ) v → i { ^ ( vec_len [i] v ) }

@ main → i {
    : ( @ v ) body \ → v {
        : ~ ( Vec i ) a ( vec_new [i] )
        ( vec_push [i] a 1 )
        : i k ( eat a )
        : i n ( vec_len [i] a )
    }
    : !Thread ThreadErr r ( thread_spawn_owned body )
    ^ ?? r { T t → ( thread_join t ) F _ → 1 }
}
