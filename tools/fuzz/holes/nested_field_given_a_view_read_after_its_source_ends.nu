// nested_field_given_a_view_read_after_its_source_ends: `= . . h w v ( string_data b )` inside b's block, then `( nurl_println . . h w v )` after it: the nested store went through the inner struct's address, was taken for memory managed by hand, and recorded no dependency of h on b.
// Closed: a nested field store walks the root binding's own storage, so it keeps the view it stores in that binding (`__field_store_nested__`, the `=.` vpass row) as the one-level store does (agora #348).
// main b997834b: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.12 | A2 | rejected | - | agora #348: a nested field store of a view records the holder's dependency on the source
$ `stdlib/core/string.nu`

: V { s v }
: H { V w }

@ main → i {
    : ~ H h @ H { @ V { `a literal` } }
    {
        : String b ( string_from `a string freed at the end of its block` )
        = . . h w v ( string_data b )
    }
    ( nurl_println . . h w v )
    ^ 0
}
