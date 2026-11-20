// raw_string_field_the_destructor_reads_handed_to_a_sink_runs_clean: AGORA-929 guard (CodeRabbit on github#2110) — a sink's `s` parameter given `. h tag`, a raw-string field the `% Drop` reads: the view is copied, the field stays, accepted
// map: §2.14 | A2 | runs-clean | - | AGORA-929 guard: a raw-string field the destructor reads handed to a sink is copied
$ `stdlib/core/string.nu`

: Holder { String buf s tag }

% Drop Holder { @ drop Holder c → v { ( nurl_println . c tag ) } }

@ show sink s v → i { ( nurl_println v ) ^ 1 }

@ main → i {
    : Holder h @ Holder { ( string_from `a name long enough to own a heap buffer of its own` ) `a tag` }
    : i k ( show . h tag )
    ( nurl_println_int k )
    ^ 0
}
