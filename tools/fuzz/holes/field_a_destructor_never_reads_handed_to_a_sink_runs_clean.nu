// field_a_destructor_never_reads_handed_to_a_sink_runs_clean: AGORA-929 guard — a sink takes a field of a struct whose `% Drop` reads only another field: accepted
// map: §2.14 | A2 | runs-clean | - | AGORA-929 guard: a field outside the destructor's read set handed to a sink
$ `stdlib/core/string.nu`

: Named { String s String t i n }

% Drop Named { @ drop Named c → v { ( nurl_println ( string_data . c s ) ) } }

@ eat sink String v → i { ^ ( string_len v ) }

@ main → i {
    : Named h @ Named { ( string_from `a name long enough to own a heap buffer of its own` ) ( string_from `another string long enough to own a heap buffer` ) 1 }
    : i k ( eat . h t )
    ( nurl_println_int k )
    ^ 0
}
