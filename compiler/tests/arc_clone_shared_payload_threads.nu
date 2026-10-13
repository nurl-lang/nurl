// arc_clone_shared_payload_threads.nu — several threads clone the same
// handle out of a shared Arc's payload at once (h211).
//
// The inner Arc is owned by the outer one's payload; each worker holds a
// clone of the outer Arc and clones the inner handle through it — a
// borrow, the same one in every thread. A share used to skip its locked
// add when it read a count of 1 ("only the owner can be here") and store
// 2: every worker read 1, every worker stored 2, the shares were lost and
// the releases freed the inner value while the payload still held it.
// requires: live

$ `stdlib/core/vec.nu`
$ `stdlib/std/arc.nu`
$ `stdlib/std/thread.nu`

@ main → i {
    : ( Arc ( Arc i ) ) outer ( arc_new [( Arc i )] ( arc_new [i] 7 ) )
    : ( Vec Thread ) ts ( vec_new [Thread] )
    : ~ i j 0
    ~ < j 8 {
        : ( Arc ( Arc i ) ) mine ( arc_clone [( Arc i )] outer )
        : !Thread ThreadErr r ( thread_spawn \ → v {
            : ~ i k 0
            ~ < k 20000 {
                : ( Arc i ) c ( arc_clone [i] ( arc_get [( Arc i )] mine ) )
                = k + k 1
            }
        } )
        ?? r { T t → { ( vec_push [Thread] ts t ) } F e → { ( nurl_print `spawn fail\n` ) } }
        = j + j 1
    }
    = j 0
    ~ < j ( vec_len [Thread] ts ) {
        ?? ( vec_get [Thread] ts j ) { T t → { ( thread_join t ) } F _ → {} }
        = j + j 1
    }
    : ( Arc i ) inner ( arc_get [( Arc i )] outer )
    ( nurl_print `inner strong=` ) ( nurl_println_int ( arc_strong [i] inner ) )
    ( nurl_print `value=` ) ( nurl_println_int ( arc_get [i] inner ) )
    ^ 0
}
