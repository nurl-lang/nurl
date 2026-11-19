// taken_field_refilled_then_its_holder_assigned_whole_runs_clean: AGORA-929 guard — `. h buf` taken by a sink, given a new value, then `= h2 h`: accepted
// map: §2.1 | A2 | runs-clean | - | AGORA-929 guard: a holder assigned whole after its taken field is refilled
$ `stdlib/core/string.nu`

: Holder { String buf }

@ take sink String v → i { ^ ( string_len v ) }

@ main → i {
    : ~ Holder h @ Holder { ( string_from `the holder's own string, long enough to own a heap buffer` ) }
    : ~ Holder h2 @ Holder { ( string_from `the second holder's string, long enough for the heap too` ) }
    : i n ( take . h buf )
    = . h buf ( string_from `a new string for the holder, long enough for the heap buffer` )
    = h2 h
    ( nurl_println ( string_data . h2 buf ) )
    ^ 0
}
