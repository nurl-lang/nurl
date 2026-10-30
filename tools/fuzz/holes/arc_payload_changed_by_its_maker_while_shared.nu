// arc_payload_changed_by_its_maker_while_shared: an Arc's payload could be changed by the thread that made it while a worker it started read it, and nothing objected: the race check looked only at what a DETACHED closure did to the payload, so the spawning thread's own `vec_set` / `vec_push` through `arc_get` was "one thread changing its own data". It is not: every clone reads the payload without a lock. (A lock did not help either — the check counted any held lock as proof, whichever lock it was.)
// Closed: an Arc's payload is frozen once made. Safe code may not hand an `arc_get` result — or any part of it, at any call depth — to anything that changes it, on any thread, locked or not; `arc_set` is `unsafe`. Shared state that changes is a `Locked [T]` (stdlib/std/thread.nu), changed only with its lock held; state one thread changes is an `Rc`.
// main (before this PR): ASan heap-use-after-free, every run.
// map: §6.5 | A3 | rejected | h213 | spawner vec_sets Arc payload while worker reads it: race, UAF
$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`
$ `stdlib/std/arc.nu`
$ `stdlib/std/thread.nu`

@ long_string → String {
    : String t ( string_from `` )
    : ~ i k 0
    ~ < k 4096 { ( string_push_char t + 97 % k 26 ) = k + k 1 }
    ^ t
}

@ main → i {
    : ( Vec String ) init ( vec_new [String] )
    ( vec_push [String] init ( long_string ) )
    : ( Arc ( Vec String ) ) a ( arc_new [( Vec String )] init )
    : ( Arc ( Vec String ) ) b ( arc_clone [( Vec String )] a )
    : !Thread ThreadErr r ( thread_spawn \ → v {
        : ~ i k 0
        : ~ i s 0
        ~ < k 20000 {
            : ( Vec String ) v ( arc_get [( Vec String )] b )
            ?? ( vec_get [String] v 0 ) {
                T x → { : ~ i j 0 ~ < j ( string_len x ) { = s + s ( string_get x j ) = j + j 1 } }
                F _ → {}
            }
            = k + k 1
        }
    } )
    : ~ i k 0
    ~ < k 20000 {
        : b ignored ( vec_set [String] ( arc_get [( Vec String )] a ) 0 ( long_string ) )
        = k + k 1
    }
    ?? r { T t → { ( thread_join t ) } F _ → {} }
    ( nurl_print `len=` ) ( nurl_println_int ( vec_len [String] ( arc_get [( Vec String )] a ) ) )
    ^ 0
}
