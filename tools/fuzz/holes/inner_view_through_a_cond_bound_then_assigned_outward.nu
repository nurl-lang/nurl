// map: §7.6 | A2 | runs-clean | - | AGORA-953 (agora #242 twin): a view of an inner block's struct field through a `?`, bound by `:` then assigned outward: copied on the lent paths
// twin of tools/fuzz/holes/inner_view_through_a_cond_assigned_outward.nu (tools/fuzz/holes/elab.py)
$ `stdlib/core/string.nu`

: P { String s i n }

@ mk → String { ^ ( string_from `hello world, long enough for a heap buffer` ) }

@ main → i {
    : ~ String t ( mk )
    ? > ( string_len t ) 0 {
        : P p @ P { ( mk ) 1 }
        : String x . p s
        : __el ? T x ( mk )
        = t __el
    } {}
    ( nurl_println_int ( string_len t ) )
    ^ 0
}
