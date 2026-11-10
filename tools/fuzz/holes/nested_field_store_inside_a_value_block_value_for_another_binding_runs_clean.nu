// nested_field_store_inside_a_value_block_value_for_another_binding_runs_clean: the control: the view goes into h, which is read inside b's block; q, given only a number by the inner store, is read after it.
// Closed: a nested field store is a store into the root binding (`__field_store_nested__` clears the by-hand flags), and the store's object and flags are read before its value is made, so a field store inside a value-block value lands on its own binding (agora #348's adversarial pass).
// main b997834b: runs clean.
// map: §2.12 | A2 | runs-clean | - | agora #348: a nested field store behaves as the one-level store
$ `stdlib/core/string.nu`

: V { s v i n }
: H { V w }

@ main → i {
    : ~ H q @ H { @ V { `a literal` 0 } }
    {
        : String b ( string_from `a string freed at the end of its block` )
        : ~ H h @ H { @ V { `a literal` 0 } }
        = . . h w v { = . . q w n 1 ( string_data b ) }
        ( nurl_println . . h w v )
    }
    ( nurl_println . . q w v )
    ^ 0
}
