// field_read_through_a_cursor_over_the_receiver_in_its_destructor: AGORA-929 (CodeRabbit on github#2110) — `Holder`'s `% Drop` reads `buf` through a cursor over its receiver, `: ~ Holder a c`, and a sink takes `. h buf`
// map: §2.14 | A2 | rejected | - | AGORA-929: a destructor reading a field through a cursor over its receiver
$ `stdlib/core/vec.nu`

: Holder { ( Vec u ) buf i n }

% Drop Holder { @ drop Holder c → v {
        : ~ Holder a c
        ( vec_push [u] . a buf # u 1 )
    } }

@ eat sink ( Vec u ) v → i { ^ ( vec_len [u] v ) }

@ main → i {
    : Holder h @ Holder { ( vec_new [u] ) 1 }
    ( vec_push [u] . h buf # u 7 )
    : i k ( eat . h buf )
    ( nurl_println_int k )
    ^ 0
}
