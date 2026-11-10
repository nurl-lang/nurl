// owned_struct_assigned_a_value_block_of_itself: `: ~ S p @ S { … }  = p { p }`, then `. p name` read.
// Closed: a value block whose tail is the binding itself is that binding given its own value, as `= v v` is (gen_assign reads it by its tail; a block whose tail is a block hands that tail up): nothing is released and the same buffer is not stored back (agora #554).
// main b997834: accepted; AddressSanitizer: heap-use-after-free.
// map: §7.6 | A2 | runs-clean | - | agora #554: an owned struct assigned a value block of itself
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: S { String name i n }

@ main → i {
    : ~ S p @ S { ( string_from `an element string long enough for a heap buffer` ) 1 }
    = p { p }
    ( nurl_println_int ( string_len . p name ) )
    ^ 0
}
