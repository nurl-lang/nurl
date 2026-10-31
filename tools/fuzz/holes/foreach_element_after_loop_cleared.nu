// foreach_element_after_loop_cleared: agora #245 — `~ s xs { … }` then `( vec_clear … xs )` and a read of `s`: the element stayed bound after its loop, a view of the slot the clear released (foreach_element_after_loop_cleared).
// Closed: a foreach's element is bound in a scope the loop's exit closes (gen_foreach; agora #245): after the loop the name is undefined, or the outer binding it shadowed.
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §1 | A1 | rejected | - | agora #245: a foreach element read after its loop, once the Vec it viewed was cleared
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ main → i {
    : ( Vec String ) xs ( vec_new [String] )
    ( vec_push [String] xs ( string_from `an element string long enough for a heap buffer` ) )
    ~ s xs { ( nurl_println_int ( string_len s ) ) }
    ( vec_clear [String] xs )
    ( nurl_println ( string_data s ) )
    ^ 0
}
