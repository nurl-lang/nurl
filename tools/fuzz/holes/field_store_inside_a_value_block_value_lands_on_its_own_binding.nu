// field_store_inside_a_value_block_value_lands_on_its_own_binding: a view stored into h whose value is a block that stores into another binding q first: the dependency landed on q, and h's read after the view's source ended read freed memory.
// Closed: a nested field store is a store into the root binding (`__field_store_nested__` clears the by-hand flags), and the store's object and flags are read before its value is made, so a field store inside a value-block value lands on its own binding (agora #348's adversarial pass).
// main b997834b: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.12 | A2 | rejected | - | agora #348: a nested field store behaves as the one-level store
$ `stdlib/core/string.nu`

: V { s v }
: H { V w }
: Q { i n }

@ main → i {
    : ~ H h @ H { @ V { `a literal` } }
    : ~ Q q @ Q { 0 }
    {
        : String b ( string_from `a string freed at the end of its block` )
        = . . h w v { = . q n 1 ( string_data b ) }
    }
    ( nurl_println . . h w v )
    ^ 0
}
