// taken_field_the_destructor_reads_through_a_cursor_handed_to_a_helper: AGORA-929 (CodeRabbit on github#2110) — the `% Drop` hands a cursor over its receiver, `: ~ Holder a c`, whole to a helper that reads `buf`, and a sink takes `. h buf`
// map: §2.14 | A2 | rejected | - | AGORA-929: a destructor reading a field through a cursor over its receiver handed to a helper
$ `stdlib/core/vec.nu`

: Holder { ( Vec u ) buf i n }

@ observe Holder c → v { ( nurl_println_int ( vec_len [u] . c buf ) ) }

% Drop Holder { @ drop Holder c → v {
        : ~ Holder a c
        ( observe a )
    } }

@ eat sink ( Vec u ) v → i { ^ ( vec_len [u] v ) }

@ main → i {
    : Holder h @ Holder { ( vec_new [u] ) 1 }
    : i k ( eat . h buf )
    ^ 0
}
