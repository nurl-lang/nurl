// A global set at program start: `: ( Locked T ) g ( make )` runs `make`
// once before main, and every thread reads the one Locked. Binding it,
// storing it in a struct or returning it clones the handle — the global
// itself is never moved or dropped. The initialiser may be file-private.
$ `stdlib/core/io.nu`
$ `stdlib/core/string.nu`
$ `stdlib/std/thread.nu`

: Counter { i n String last }

@ __make_counter → ( Locked Counter ) { ^ ( locked_new [Counter] @ Counter { 0 ( string_new ) } ) }

: ( Locked Counter ) g_counter ( __make_counter )

: Holder { ( Locked Counter ) l }

@ bump s who → v {
    : ~ Counter c ( locked_take [Counter] g_counter )
    = . c n + . c n 1
    = . c last ( string_from who )
    ( locked_restore [Counter] g_counter c )
}

@ hold → v { : Holder h @ Holder { g_counter } ( bump `holder` ) }

@ handle → ( Locked Counter ) { ^ g_counter }

@ main → i {
    : ( @ v ) body \ → v { : ~ i k 0 ~ < k 1000 { ( bump `worker` ) = k + k 1 } }
    ?? ( thread_spawn_owned body ) {
        T t → { : ~ i k 0 ~ < k 1000 { ( bump `main` ) = k + k 1 } : i _j ( thread_join t ) }
        F _ → {}
    }
    ( hold )
    : ( Locked Counter ) l ( handle )
    : ~ Counter c ( locked_take [Counter] l )
    ( nurl_println_int . c n )
    ( nurl_println_int ( string_len . c last ) )
    ( locked_restore [Counter] l c )
    ^ 0
}
