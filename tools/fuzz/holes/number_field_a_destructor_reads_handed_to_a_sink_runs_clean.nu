// number_field_a_destructor_reads_handed_to_a_sink_runs_clean: AGORA-929 guard (CodeRabbit on github#2110) — a sink's `i` parameter given `. h n`, which the `% Drop` reads: a copy, accepted
// map: §2.14 | A2 | runs-clean | - | AGORA-929 guard: a number field the destructor reads handed to a sink copies it
$ `stdlib/core/string.nu`

: Holder { String buf i n }

% Drop Holder { @ drop Holder c → v { ( nurl_println_int . c n ) } }

@ eat sink i v → i { ^ + v 1 }

@ main → i {
    : Holder h @ Holder { ( string_from `a name long enough to own a heap buffer of its own` ) 7 }
    : i k ( eat . h n )
    ( nurl_println_int k )
    ^ 0
}
