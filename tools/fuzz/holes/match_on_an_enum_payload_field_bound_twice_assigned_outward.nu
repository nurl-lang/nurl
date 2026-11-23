// map: §7.6 | A2 | runs-clean | - | AGORA-953: a `??` over an inner enum's payload field, bound by `:`, bound again, then assigned outward: copied on the lent path
// Was a heap-use-after-free under ASan on main 3f08626.
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: P { String s i n }

@ mk → String { ^ ( string_from `hello world, long enough for a heap buffer` ) }

: | G { V P Nil }

@ main → i {
    : ~ String t ( mk )
    ? > ( string_len t ) 0 {
        : G g @ G { V @ P { ( mk ) 1 } }
        : String e ?? g { V p → . p s Nil → ( mk ) }
        : String e2 e
        = t e2
    } {}
    ( nurl_println_int ( string_len t ) )
    ^ 0
}
