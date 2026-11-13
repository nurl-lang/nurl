// inout_slice_handed_a_cursor_of_another_slice_rejected: `: ~ [i d a  ( setl d )` where setl gives its inout slice a new value: d is a cursor over a, and the callee would release a's buffer
// main: accepted; the store leaked the new buffer (and, once the callee released the old one, freed a's).
// map: §2.4 | A2 | rejected | - | agora #545: a `: ~` cursor over another slice handed inout to a callee that replaces it is refused, as for a String
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ mk → [i { ^ [i | 1 2] }

@ sum [i a → i { : ~ i t 0 ~ x a { = t + t x } ^ t }

: Box { [i v }

: Holder { [i v i n }

: Outer { Box b i k }

@ setl inout [i p → v { = p [i | 3 4] }

@ main → i {
    : [i a [i | 5 6]
    : ~ [i d a
    ( setl d )
    ( nurl_println_int + ( sum d ) ( sum a ) )
    ^ 0
}
