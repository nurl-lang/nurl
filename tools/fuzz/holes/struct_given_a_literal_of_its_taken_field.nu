// struct_given_a_literal_of_its_taken_field: `= h @ Holder { . h buf }` after a `sink` took the field: the new value copied the null handle, and the assignment marked the field whole again.
// main: accepted; the assignment revived the field path before anything asked the literal's read of it, and vec_push faulted on the null handle (SEGV).
// map: §2.1 | A2 | rejected | - | agora #351: `= h @ Holder { . h buf }` after a `sink` took the field: the new value copied the null handle, and the assignment marked the field whole again
$ `stdlib/core/io.nu`
$ `stdlib/std/bytes.nu`

: Holder { ( Vec u ) buf }

@ take sink ( Vec u ) v → i { ^ ( vec_len [u] v ) }

@ main → i {
    : ~ Holder h @ Holder { ( vec_new [u] ) }
    ( vec_push [u] . h buf # u 66 )
    : i n ( take . h buf )
    = h @ Holder { . h buf }
    ( vec_push [u] . h buf # u 65 )
    ^ 0
}
