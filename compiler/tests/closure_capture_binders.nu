// closure_capture_binders.nu — a select arm's result name and a foreach's
// element are the block's own, not captures of the outer binding they
// shadow (agora #238, after #125's closure_capture_shadowing.nu). The
// capture scan took `→ w {` in a `?? {` select and `~ w xs {` for the outer
// Vec `w`, and the thread's closure moved a Vec it never touches: the
// spawner's next `vec_push` was rejected ("use of moved value 'w'"). The
// outer `w` is still read where the body reads it —
// closure_capture_binders_reads.nu.

$ `stdlib/core/vec.nu`
$ `stdlib/std/channel.nu`
$ `stdlib/std/thread.nu`

@ main → i {
    : ( Vec i ) w ( vec_new [i] )
    ( vec_push [i] w 7 )
    : !Thread ThreadErr t ( thread_spawn \ → v {
        : ( Channel i ) ch ( chan_new [i] )
        ( chan_send [i] ch 5 )
        ?? {
            [i] ch → w { ?? w { T n → ( nurl_println_int n ) F → {} } }
            _ → {}
        }
    } )
    ?? t { T th → { : i _r ( thread_join th ) } F _ → {} }
    : !Thread ThreadErr t2 ( thread_spawn \ → v {
        : ( Vec i ) xs ( vec_new [i] )
        ( vec_push [i] xs 3 )
        ( vec_push [i] xs 4 )
        ~ w xs { ( nurl_println_int w ) }
    } )
    ?? t2 { T th → { : i _r ( thread_join th ) } F _ → {} }
    ( vec_push [i] w 8 )
    ( nurl_println_int ( vec_len [i] w ) )
    ^ 0
}
