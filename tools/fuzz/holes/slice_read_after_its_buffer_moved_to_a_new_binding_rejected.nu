// slice_read_after_its_buffer_moved_to_a_new_binding_rejected: `: [i c a` out of an owned slice moves its buffer, so `( sum a )` after it is refused, as after `= c a` and `: String c a`
// Before the walk recorded the move, the read found a's emptied slot and ran on with no elements.
// map: §2.1 | A2 | rejected | - | agora #664: a read of an owned slice after `: [i c a` moved its buffer is refused as a use of a moved value
$ `stdlib/core/vec.nu`

@ mk → [i { ^ [i | 1 2 3] }

@ sum [i a → i { : ~ i t 0 ~ x a { = t + t x } ^ t }

@ main → i {
    : [i a ( mk )
    : [i c a
    ( nurl_println_int ( sum c ) )
    ( nurl_println_int ( sum a ) )
    ^ 0
}
