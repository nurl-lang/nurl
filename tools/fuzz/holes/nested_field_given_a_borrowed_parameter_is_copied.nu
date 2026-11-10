// nested_field_given_a_borrowed_parameter_is_copied: a borrowed String parameter stored at a nested path of a local struct (`= . . h w name b`) went in as is, and h's drop freed the caller's buffer; the one-level store copies it.
// Closed: a nested field store is a store into the root binding (`__field_store_nested__` clears the by-hand flags), and the store's object and flags are read before its value is made, so a field store inside a value-block value lands on its own binding (agora #348's adversarial pass).
// main b997834b: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.12 | A2 | runs-clean | - | agora #348: a nested field store behaves as the one-level store
$ `stdlib/core/string.nu`

: I { String name }
: H { I w }

@ put String b → v {
    : ~ H h @ H { @ I { ( string_from `the first name, long enough for the heap` ) } }
    = . . h w name b
    ( nurl_println ( string_data . . h w name ) )
}

@ main → i {
    : String b ( string_from `a caller's string, long enough for the heap` )
    ( put b )
    ( nurl_println ( string_data b ) )
    ^ 0
}
