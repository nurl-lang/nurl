// struct_with_a_taken_field_handed_on_whole: agora #280 — a struct handed on whole after a `sink` took one of its fields: the callee pushed to the null field.
// main: accepted; the push dereferenced a null handle (SIGSEGV).
// map: §2.1 | A2 | rejected | - | agora #280: a struct handed on whole after a `sink` took one of its fields: the callee pushed to the null field
$ `stdlib/core/io.nu`
$ `stdlib/std/bytes.nu`

: Holder { ( Vec u ) buf }

@ take sink ( Vec u ) v → i { ^ ( vec_len [u] v ) }

@ grow Holder h → v { ( vec_push [u] . h buf # u 65 ) }

@ main → i {
    : Holder h @ Holder { ( vec_new [u] ) }
    : i n ( take . h buf )
    ( grow h )
    ^ 0
}
