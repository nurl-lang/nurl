// nested_field_given_a_view_of_a_block_local_field: a view of a block-local struct's String field stored at a nested path of h, read after the block.
// Closed: a nested field store walks the root binding's own storage, so it keeps the view it stores in that binding (`__field_store_nested__`, the `=.` vpass row) as the one-level store does (agora #348).
// main b997834b: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.12 | A2 | rejected | - | agora #348: a nested field store of a view records the holder's dependency on the source
$ `stdlib/core/string.nu`

: V { s v }
: H { V w }
: Named { String name }

@ main → i {
    : ~ H h @ H { @ V { `a literal` } }
    {
        : Named t @ Named { ( string_from `a struct's String field freed at the end of its block` ) }
        = . . h w v ( string_data . t name )
    }
    ( nurl_println . . h w v )
    ^ 0
}
