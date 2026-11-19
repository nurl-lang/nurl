// field_read_of_a_struct_literal_temporary_runs_clean: `( string_len . @ SB { ( string_from `ab` ) 3 } s )`, the same of a Vec field and of a `[i` field handed to a call or bound: a struct literal read only for one field
// Closed (agora #895): a struct literal read for a field is the read's own temporary, as a call's result is (h232, h266): the field leaves with the read and the rest is released there; an owned slice field leaves the same way, owned by the read's flag.
// main aae76ca (with github#2103): LeakSanitizer: the literal (its String, Vec or slice) leaked.
// map: §7.6 | A2 | runs-clean | - | agora #895: a struct literal temporary read only for one field, of a String, a Vec and a slice, handed to a call and bound
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: Bag { [i s i n }
: SB { String s i n }
: VB { ( Vec i ) s i n }

@ mk → [i { ^ [i | 1 2 3] }
@ mkv → ( Vec i ) { : ( Vec i ) v ( vec_new [i] ) ( vec_push [i] v 1 ) ^ v }
@ ln [i t → i { : ~ i k 0 ~ x t { = k + k x } ^ k }

@ main → i {
    ( nurl_println_int ( string_len . @ SB { ( string_from `ab` ) 3 } s ) )
    : String q . @ SB { ( string_from `cd` ) 3 } s
    ( nurl_println_int ( string_len q ) )
    ( nurl_println_int ( vec_len [i] . @ VB { ( mkv ) 3 } s ) )
    ( nurl_println_int ( ln . @ Bag { ( mk ) 3 } s ) )
    : [i x . @ Bag { ( mk ) 3 } s
    ( nurl_println_int ( ln x ) )
    ^ 0
}
