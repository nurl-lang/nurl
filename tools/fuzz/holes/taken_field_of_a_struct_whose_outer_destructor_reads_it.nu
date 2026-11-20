// taken_field_of_a_struct_whose_outer_destructor_reads_it: AGORA-929 (CodeRabbit on github#2110) — `Inner` has no `% Drop`, `Outer`'s reads `inner.buf`, and a sink takes `. . o inner buf`
// map: §2.14 | A2 | rejected | - | AGORA-929: a sink takes a nested field an enclosing struct's % Drop reads
$ `stdlib/core/string.nu`

: Inner { String buf i n }
: Outer { Inner inner i z }

% Drop Outer { @ drop Outer c → v { ( nurl_println ( string_data . . c inner buf ) ) } }

@ eat sink String v → i { ^ ( string_len v ) }

@ main → i {
    : Outer o @ Outer { @ Inner { ( string_from `a name long enough to own a heap buffer of its own` ) 1 } 2 }
    : i k ( eat . . o inner buf )
    ^ 0
}
