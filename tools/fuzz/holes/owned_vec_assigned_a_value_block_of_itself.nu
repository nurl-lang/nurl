// owned_vec_assigned_a_value_block_of_itself: `: ~ ( Vec i ) v …  = v { v }`, then `v` read.
// Closed: a value block whose tail is the binding itself is that binding given its own value, as `= v v` is (gen_assign reads it by its tail; a block whose tail is a block hands that tail up): nothing is released and the same buffer is not stored back (agora #554).
// main b997834: accepted; AddressSanitizer: heap-use-after-free (the old value released, the same buffer stored back).
// map: §7.6 | A2 | runs-clean | - | agora #554: an owned Vec assigned a value block of itself
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: S { String name i n }

@ main → i {
    : ~ ( Vec i ) v ( vec_new [i] )
    ( vec_push [i] v 7 )
    = v { v }
    ( nurl_println_int ( vec_len [i] v ) )
    ^ 0
}
