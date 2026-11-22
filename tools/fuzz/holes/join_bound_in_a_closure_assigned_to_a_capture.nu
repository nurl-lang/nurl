// map: §7.6 | A2 | runs-clean | - | AGORA-953: a join over a view of the closure's own local, bound by `:` in the closure body and assigned to a by-pointer capture: copied on the lent path
// Was a heap-use-after-free under ASan on main 3f08626.
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: P { String s i n }

@ mk → String { ^ ( string_from `hello world, long enough for a heap buffer` ) }

@ main → i {
    : ~ String t ( mk )
    : ( @ v ) f \ → v {
        : P p @ P { ( mk ) 1 }
        : String x . p s
        : String e ? T x ( mk )
        = t e
    }
    ( f )
    ( nurl_println_int ( string_len t ) )
    ^ 0
}
