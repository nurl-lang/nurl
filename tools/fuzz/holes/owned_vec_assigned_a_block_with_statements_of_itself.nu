// owned_vec_assigned_a_block_with_statements_of_itself: `= v { : i t 1 v }`.
// Closed: a value block whose tail is the binding itself is that binding given its own value, as `= v v` is (gen_assign reads it by its tail; a block whose tail is a block hands that tail up): nothing is released and the same buffer is not stored back (agora #554).
// main b997834: accepted; AddressSanitizer: heap-use-after-free.
// map: §7.6 | A2 | runs-clean | - | agora #554: an owned Vec assigned a value block with statements ending in itself
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: S { String name i n }

@ main → i {
    : ~ ( Vec i ) v ( vec_new [i] )
    ( vec_push [i] v 7 )
    = v { : i t 1 v }
    ( nurl_println_int ( vec_len [i] v ) )
    ^ 0
}
