// field_a_destructor_reads_handed_to_a_forwarding_in_parameter: AGORA-929 (CodeRabbit on github#2110) — `( forward . h buf )` where `forward`'s plain parameter is handed on to a sink (an inferred sink), defined after its caller; `Holder`'s `% Drop` then reads the emptied field
// map: §2.14 | A2 | rejected | - | AGORA-929: a field the destructor reads taken by an inferred sink compiled after its caller
$ `stdlib/core/vec.nu`

: Holder { ( Vec u ) buf i n }

% Drop Holder { @ drop Holder c → v { ( vec_push [u] . c buf # u 1 ) } }

@ main → i {
    : Holder h @ Holder { ( vec_new [u] ) 1 }
    ( vec_push [u] . h buf # u 7 )
    : i k ( forward . h buf )
    ( nurl_println_int k )
    ^ 0
}

@ eat sink ( Vec u ) v → i { ^ ( vec_len [u] v ) }

@ forward ( Vec u ) v → i { ^ ( eat v ) }
