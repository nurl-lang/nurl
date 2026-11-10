// value_block_local_moved_into_its_binding_then_read_by_an_outer_name: `: ( Vec String ) w { : ~ ( Vec String ) v … v }`, `w` handed to a sink, then `v` read, with an outer `v`.
// Closed: refused. `v` after the block is meant as the outer Vec, but the name still reaches the block's `v`, whose buffer moved into `w` and went with it to the sink: the read was freed memory (agora #575).
// main 2498b4e: accepted; AddressSanitizer: heap-use-after-free.
// map: §7.6 | A2 | rejected | - | agora #575: a value block's local moved into the block's binding, the binding consumed, then the name read
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ eat sink ( Vec String ) x → i { ^ ( vec_len [String] x ) }

@ main → i {
    : ~ ( Vec String ) v ( vec_new [String] )
    ( vec_push [String] v ( string_from `an outer element long enough for a heap buffer` ) )
    : ( Vec String ) w { : ~ ( Vec String ) v ( vec_new [String] ) ( vec_push [String] v ( string_from `an inner element long enough for a heap buffer` ) ) ( vec_push [String] v ( string_from `another inner element long enough for a heap` ) ) v }
    ( nurl_println_int ( eat w ) )
    ( nurl_println_int ( vec_len [String] v ) )
    ( nurl_println ( string_data ( vec_at [String] v 0 ) ) )
    ^ 0
}
