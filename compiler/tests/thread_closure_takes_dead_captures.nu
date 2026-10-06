// thread_closure_takes_dead_captures.nu — a closure a thread runs takes over
// the Strings / Vecs it captured from bindings the spawner no longer uses.
//
// `: String url …` per iteration, captured by `thread_spawn \ → v { … url …
// }`: the binding dropped url at the end of the iteration while the thread
// was still reading it (use after free — the only way out was releasing the
// capture inside the thread body by hand). What the threads report back
// goes through a channel: a handle shared on copy, so each thread's closure
// takes a share of its own and the spawner keeps reading its handle (a Vec
// the threads wrote into would be unsynchronised shared mutation).

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/time.nu`
$ `stdlib/std/channel.nu`

@ work s a i k → v { ( sleep_ms 5 ) ? != ( nurl_str_len a ) + 4 ( nurl_str_len ( nurl_str_int k ) ) { ( nurl_println `capture damaged` ) } {} }

@ main → i {
    : ( Vec Thread ) ts ( vec_new [Thread] )
    : ( Channel i ) results ( chan_new [i] )
    : ~ i k 0
    ~ < k 8 {
        : String url ( string_from ( nurl_str_cat `url-` ( nurl_str_int k ) ) )
        : i kk k
        ?? ( thread_spawn \ → v { ( work ( string_data url ) kk ) : b _sent ( chan_send [i] results 1 ) } ) {
            T th → { ( vec_push [Thread] ts th ) } F _ → {}
        }
        = k + k 1
    }
    : ~ i j 0
    ~ < j ( vec_len [Thread] ts ) { ?? ( vec_get [Thread] ts j ) { T th → { : i _r ( thread_join th ) } F _ → {} } = j + j 1 }
    : i seen ?? ( chan_try_recv [i] results ) { T x → x F → 0 }
    ( nurl_println ( nurl_str_cat `shared result seen: ` ( nurl_str_int seen ) ) )
    ^ 0
}
