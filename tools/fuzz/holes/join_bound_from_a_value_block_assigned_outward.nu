// map: §7.6 | A2 | runs-clean | - | AGORA-953: a value block whose tail is a join lending an inner field view (`: e { ? T x ( mk ) }`), bound by `:` then assigned outward: copied on the lent path
// Was a heap-use-after-free under ASan on main 3f08626.
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: P { String s i n }

@ mk → String { ^ ( string_from `hello world, long enough for a heap buffer` ) }

@ main → i {
    : ~ String t ( mk )
    ? T {
        : P p @ P { ( mk ) 1 }
        : String x . p s
        : String e { ? T x ( mk ) }
        = t e
    } {}
    ( nurl_println_int ( string_len t ) )
    ^ 0
}
