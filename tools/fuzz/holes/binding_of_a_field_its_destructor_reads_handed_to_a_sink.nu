// binding_of_a_field_its_destructor_reads_handed_to_a_sink: AGORA-929 (CodeRabbit on github#2110) — `: b . h buf` then `( eat b )`: moving the binding takes the field out of `h`, whose `% Drop` then reads the emptied field
// map: §2.14 | A2 | rejected | - | AGORA-929: a field-reader binding of a field the destructor reads, handed to a sink
$ `stdlib/core/vec.nu`

: Holder { ( Vec u ) buf i n }

% Drop Holder { @ drop Holder c → v { ( nurl_println_int ( vec_len [u] . c buf ) ) } }

@ eat sink ( Vec u ) v → i { ^ ( vec_len [u] v ) }

@ main → i {
    : Holder h @ Holder { ( vec_new [u] ) 1 }
    ( vec_push [u] . h buf # u 7 )
    : ( Vec u ) b . h buf
    : i k ( eat b )
    ( nurl_println_int k )
    ^ 0
}
