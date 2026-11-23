// map: §7.6 | A2 | runs-clean | - | AGORA-953: `: e ? c x ( mk )  : e2 e  = t e2`, x a view of an inner block's field: the second binding keeps how deep the first one's lend lives, so the outer t gets a copy on the lent path
// Was a heap-use-after-free under ASan on main 3f08626.
$ `stdlib/core/string.nu`

: P { String s i n }

@ mk → String { ^ ( string_from `hello world, long enough for a heap buffer` ) }

@ main → i {
    : ~ String t ( mk )
    : b c > ( string_len t ) 3
    ? > ( string_len t ) 0 {
        : P p @ P { ( mk ) 1 }
        : String x . p s
        : String e ? c x ( mk )
        ? c {
            : String e2 e
            = t e2
        } {}
    } {}
    ( nurl_println_int ( string_len t ) )
    ^ 0
}
