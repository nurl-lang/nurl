// map: §7.6 | A2 | rejected | - | AGORA-941 (AGORA-242's twin): a field of an inner block's struct through a `?`, bound by `:` then assigned outward
// AGORA-941 (closed): refused - a `:` join's field borrow ends with the struct it reads (main 3ad3d7c8: accepted, heap-use-after-free under ASan)
// twin of tools/fuzz/holes/inner_struct_field_through_a_cond_assigned_outward.nu (tools/fuzz/holes/elab.py)
$ `stdlib/core/string.nu`

: P { String s i n }

@ mk → String { ^ ( string_from `hello world, long enough for a heap buffer` ) }

@ main → i {
    : ~ String t ( mk )
    ? > ( string_len t ) 0 {
        : P p @ P { ( mk ) 1 }
        : __el ? T . p s ( mk )
        = t __el
    } {}
    ( nurl_println_int ( string_len t ) )
    ^ 0
}
