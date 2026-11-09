// nested_field_given_a_view_by_a_closure: the closure twin: a closure over h makes the nested store; the one-level store is refused there by CapsOK.
// Closed: a nested field store walks the root binding's own storage, so it keeps the view it stores in that binding (`__field_store_nested__`, the `=.` vpass row) as the one-level store does (agora #348).
// main b997834b: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.12 | A2 | rejected | - | agora #348: a nested field store of a view records the holder's dependency on the source
$ `stdlib/core/string.nu`

: V { s v }
: H { V w i n }

@ main → i {
    : ~ H h @ H { @ V { `a literal` } 1 }
    {
        : String b ( string_from `a string freed at the end of its block` )
        : ( @ v ) f \ → v { = . . h w v ( string_data b ) }
        ( f )
    }
    ( nurl_println . . h w v )
    ^ 0
}
