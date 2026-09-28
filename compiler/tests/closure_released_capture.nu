// A closure body that releases a capture itself (`( string_free r2 )` in a
// thread body — the legacy spelling) takes that capture over when it is
// created: the enclosing binding no longer drops it at the end of its
// scope, where the thread may still be reading it, and the env's own drop
// skips it (docs/MEMORY.md §7.4).

$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`
$ `stdlib/std/thread.nu`

@ work s a → v { ? != ( nurl_str_len a ) 4 { ( nurl_println `capture damaged` ) } {} }

@ main → i {
    : ( Vec Thread ) ts ( vec_new [Thread] )
    : String root ( string_from `root` )
    : ~ i t 0
    ~ < t 4 {
        : String r2 ( string_clone root )
        : ( @ v ) body \ → v {
            ( work ( string_data r2 ) )
            ( string_free r2 )
        }
        ?? ( thread_spawn_owned body ) { T th → { ( vec_push [Thread] ts th ) } F _ → {} }
        = t + t 1
    }
    : ~ i k 0
    ~ < k ( vec_len [Thread] ts ) {
        ?? ( vec_get [Thread] ts k ) { T th → { : i _j ( thread_join th ) } F _ → {} }
        = k + k 1
    }
    ( nurl_println `released captures ok` )
    ^ 0
}
