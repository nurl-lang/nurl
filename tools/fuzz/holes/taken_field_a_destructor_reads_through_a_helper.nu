// taken_field_a_destructor_reads_through_a_helper: AGORA-929 (CodeRabbit on github#2110) — the `% Drop` hands its receiver whole to a helper that reads `buf`, and a sink takes `. h buf`
// map: §2.14 | A2 | rejected | - | AGORA-929: a sink takes a field the destructor reads through a helper call
$ `stdlib/core/string.nu`

: Holder { String buf i n }

@ inspect Holder c → v { ( nurl_println ( string_data . c buf ) ) }

% Drop Holder { @ drop Holder c → v { ( inspect c ) } }

@ eat sink String v → i { ^ ( string_len v ) }

@ main → i {
    : Holder h @ Holder { ( string_from `a name long enough to own a heap buffer of its own` ) 1 }
    : i k ( eat . h buf )
    ^ 0
}
