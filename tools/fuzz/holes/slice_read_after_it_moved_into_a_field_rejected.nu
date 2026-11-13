// slice_read_after_it_moved_into_a_field_rejected: `= . h v q  ( sum q )`: q moved its buffer into the field, so reading q after it is refused
// Before the walk recorded the move, the read found q's emptied slot.
// map: §2.1 | A2 | rejected | - | agora #545: an owned slice read after it moved into a field is refused as a use of a moved value
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ mk → [i { ^ [i | 1 2] }

@ sum [i a → i { : ~ i t 0 ~ x a { = t + t x } ^ t }

: Box { [i v }

: Holder { [i v i n }

: Outer { Box b i k }

@ main → i {
    : ~ Holder h @ Holder { [i | 0] 1 }
    : [i q ( mk )
    = . h v q
    ( nurl_println_int + ( sum q ) ( sum . h v ) )
    ^ 0
}
