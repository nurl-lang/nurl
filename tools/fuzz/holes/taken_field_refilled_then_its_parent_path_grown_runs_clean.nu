// taken_field_refilled_then_its_parent_path_grown_runs_clean: AGORA-929 guard — `. . o a buf` taken by a sink, given a new value, then `. o a` handed to a grower: accepted
// map: §2.1 | A2 | runs-clean | - | AGORA-929 guard: a taken field refilled before a path over it is used
$ `stdlib/core/string.nu`

: Inner { String buf }
: Outer { Inner a Inner b }

@ take sink String v → i { ^ ( string_len v ) }

@ grow inout Inner x → v { ( string_push_str . x buf `appended to the field` ) }

@ main → i {
    : ~ Outer o @ Outer { @ Inner { ( string_from `the inner string, long enough to own a heap buffer` ) } @ Inner { ( string_from `the sibling string, long enough to own a heap buffer` ) } }
    : i n ( take . . o a buf )
    ( grow . o b )
    = . . o a buf ( string_from `a new inner string, long enough to own a heap buffer` )
    ( grow . o a )
    ( nurl_println ( string_data . . o a buf ) )
    ^ 0
}
