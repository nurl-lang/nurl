// closure_capture_binders_reads.nu — where a closure body reads the outer
// binding a select arm's result name or a foreach's element shadows inside
// its own block, the outer one is still captured (agora #238, the other
// side of closure_capture_binders.nu): read after the select, before the
// loop, and in a `~ cond {` loop, which binds nothing.

$ `stdlib/core/vec.nu`
$ `stdlib/std/channel.nu`

@ main → i {
    : ( Vec i ) w ( vec_new [i] )
    ( vec_push [i] w 7 )
    ( vec_push [i] w 8 )
    : ( @ i ) g \ → i {
        : ( Channel i ) ch ( chan_new [i] )
        ( chan_send [i] ch 5 )
        : ~ i got 0
        ?? {
            [i] ch → w { ?? w { T n → { = got n } F → {} } }
            _ → {}
        }
        ^ + got ( vec_len [i] w )
    }
    ( nurl_println_int ( g ) )
    : ( @ i ) h \ → i {
        : i before ( vec_len [i] w )
        : ( Vec i ) xs ( vec_new [i] )
        ( vec_push [i] xs 30 )
        : ~ i s 0
        ~ w xs { = s + s w }
        ^ + s before
    }
    ( nurl_println_int ( h ) )
    : ( @ i ) k \ → i {
        : ~ i n 0
        ~ < n ( vec_len [i] w ) { = n + n 1 }
        ^ n
    }
    ( nurl_println_int ( k ) )
    ^ 0
}
