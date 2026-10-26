// A type keyword in a TYPE position inside a closure body is not a use of a
// binding that happens to share its name (agora #122). The capture scan took
// every `v` / `i` / `s` token for a capture, so a thread's closure that only
// spelled the type `( @ v i )` moved the spawner's Vec named `v`, and a later
// `vec_push` on it was rejected as a use of a moved value. The second thread
// spells `s` in each type position — a binding's type, call type arguments,
// a slice literal's element type, `Z`, an aggregate's type, a nested
// closure's header, a select arm's type, and `u` in a cast — while the
// spawner keeps its Vecs named `s` and `u`. The values a body really reads
// through those forms are still captured (`f`).
$ `stdlib/core/vec.nu`
$ `stdlib/std/channel.nu`
$ `stdlib/std/thread.nu`

: Pair { i a i b }

@ main → i {
    : ( Vec i ) v ( vec_new [i] )
    : ( Channel ( @ v i ) ) ch ( chan_new [( @ v i )] )
    ?? ( thread_spawn \ → v { : ?( @ v i ) g ( chan_try_recv [( @ v i )] ch ) } ) {
        T t → { ( thread_join t ) }
        F _ → {}
    }
    ( vec_push [i] v 1 )
    ( nurl_println ( nurl_str_int ( vec_len [i] v ) ) )

    : ( Vec i ) s ( vec_new [i] )
    : ( Vec i ) u ( vec_new [i] )
    ?? ( thread_spawn \ → v {
        : s a `ab`
        : ( Vec s ) names ( vec_new [s] )
        ( vec_push [s] names a )
        : [s xs [s | a a]
        : i n Z s
        : i p # i # u 321
        : ?s o @ ?s { T a }
        : ( @ s s ) same \ s t → s { t }
        ?? o {
            T w → { ( nurl_println ( same w ) ) }
            F → {}
        }
        ( nurl_println ( nurl_str_int + + p . xs length ( vec_len [s] names ) ) )
        ( vec_free [s] names )
        : ( Channel s ) c ( chan_new [s] )
        ( chan_close [s] c )
        ?? {
            [s] c → r { ?? r { T w → { ( nurl_println w ) } F → { ( nurl_println `closed` ) } } }
        }
    } ) {
        T t → { ( thread_join t ) }
        F _ → {}
    }
    ( vec_push [i] s 7 )
    ( vec_push [i] u 7 )

    // Bindings named like type keywords, read in value positions.
    : i i 40
    : i b 2
    : ( @ i ) f \ → i {
        : i x + i b
        : [i xs [i | i b 3]
        : i y # i b
        : Pair p @ Pair { i b }
        : ( @ i i ) add \ i k → i { + k b }
        ^ + + + x ( add . p a ) - Z i 8 + + y . xs length ( vec_len [i] s )
    }
    ( nurl_println ( nurl_str_int ( f ) ) )
    ( vec_free [i] s )
    ( vec_free [i] u )
    ( vec_free [i] v )
    ^ 0
}
