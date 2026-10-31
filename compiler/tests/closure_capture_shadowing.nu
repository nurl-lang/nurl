// closure_capture_shadowing.nu — a name the closure body binds itself is
// not a capture of the outer binding it shadows (agora #125): a `:`
// binding's name from the end of its statement on, a match arm's payload
// name in its guard and result, a nested closure's parameter in its body.
// The capture scan took each for the outer Vec `w`, and the thread's
// closure moved a Vec it never touches: the spawner's next `vec_push` was
// rejected ("use of moved value 'w' — consumed by the closure that
// 'thread_spawn' runs"). The outer `w` is still read where the body reads
// it — closure_capture_shadowing_reads.nu.

$ `stdlib/core/vec.nu`
$ `stdlib/std/thread.nu`

@ main → i {
    : ( Vec i ) w ( vec_new [i] )
    ( vec_push [i] w 7 )
    : !Thread ThreadErr t ( thread_spawn \ → v {
        : i w 3
        ( nurl_println_int w )
    } )
    ?? t { T th → { : i _r ( thread_join th ) } F _ → {} }
    : !Thread ThreadErr t2 ( thread_spawn \ → v {
        : ?i o @ ?i { T 4 }
        ?? o {
            T w ? > w 0 → { ( nurl_println_int w ) }
            T w → ( nurl_println_int - 0 w )
            F → {}
        }
    } )
    ?? t2 { T th → { : i _r ( thread_join th ) } F _ → {} }
    : !Thread ThreadErr t3 ( thread_spawn \ → v {
        : ( @ i i ) f \ i w → i { ^ + w 1 }
        ( nurl_println_int ( f 4 ) )
    } )
    ?? t3 { T th → { : i _r ( thread_join th ) } F _ → {} }
    : !Thread ThreadErr t4 ( thread_spawn \ → v {
        : i n 6
        : ~ i w + n 1
        = w + w 1
        ( nurl_println_int w )
    } )
    ?? t4 { T th → { : i _r ( thread_join th ) } F _ → {} }
    ( vec_push [i] w 8 )
    ( nurl_println_int ( vec_len [i] w ) )
    ^ 0
}
