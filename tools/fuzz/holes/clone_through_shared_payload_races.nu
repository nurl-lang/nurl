// clone_through_shared_payload_races: several threads cloning the same handle out of a shared Arc's payload (or a Shared handle — a Mutex, a Channel — that a struct every thread reads holds) lost shares. A share that read a count of 1 skipped the locked add and stored 2, on the premise that only the one owner could be sharing; but a clone is asked of a borrow, and every thread borrowed the payload's handle at once. Each read 1 and stored 2, and the releases freed the value while the payload still held it.
// Closed: a share always takes the locked add (nurl_rc_share, nurl_arc_share); only a release, which only an owner makes, keeps the shortcut.
// main (before this PR): free(): invalid pointer / SEGV / ASan double-free within a few runs.
// map: §6.5 | A3 | runs-clean | h211 | threads cloning a handle from a shared Arc payload race on refcount
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
            ~ < k 200000 {
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
    : i n ( arc_strong [i] ( arc_get [( Arc i )] outer ) )
    ( nurl_print `inner strong=` ) ( nurl_println_int n )
    ^ ? == n 1 0 1
}
