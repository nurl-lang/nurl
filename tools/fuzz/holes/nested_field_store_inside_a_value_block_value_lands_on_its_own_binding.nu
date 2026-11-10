// nested_field_store_inside_a_value_block_value_lands_on_its_own_binding: the nested twin: `= . . h w v { = . . q w n 1 ( string_data b ) }`.
// Closed: a nested field store is a store into the root binding (`__field_store_nested__` clears the by-hand flags), and the store's object and flags are read before its value is made, so a field store inside a value-block value lands on its own binding (agora #348's adversarial pass).
// main b997834b: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.12 | A2 | rejected | - | agora #348: a nested field store behaves as the one-level store
$ `stdlib/core/string.nu`

: V { s v i n }
: H { V w }

@ main → i {
    : ~ H h @ H { @ V { `a literal` 0 } }
    : ~ H q @ H { @ V { `a literal` 0 } }
    {
        : String b ( string_from `a string freed at the end of its block` )
        = . . h w v { = . . q w n 1 ( string_data b ) }
    }
    ( nurl_println . . h w v )
    ^ 0
}
