// map: §7.4 | A2 | runs-clean | - | AGORA-953 (CodeRabbit on github#2204): a join over two shares of one Rc (`b` a clone of `a`), bound by `:` and assigned to a capture: the takeover by key takes at most one owner, so the other share keeps its own release
// Was a leak under LSan on main c4c0f35.
$ `stdlib/core/string.nu`
$ `stdlib/std/rc.nu`

: S { String s }

@ id ( Rc S ) a → ( Rc S ) { ^ a }

@ run i k → v {
    : ~ ( Rc S ) o ( rc_new [S] @ S { ( string_from `outer value long enough for the heap here` ) } )
    : ~ ( @ v ) f \ → v {
        : ( Rc S ) a ( rc_new [S] @ S { ( string_from `shared value long enough for the heap ok` ) } )
        : ( Rc S ) b ( rc_clone [S] a )
        : ( Rc S ) e ? == k 0 ( id a ) ( id b )
        = o e
    }
    ( f )
    ( nurl_println ( string_data . ( rc_get [S] o ) s ) )
}

@ main → i { ( run 0 ) ( run 1 ) ^ 0 }
