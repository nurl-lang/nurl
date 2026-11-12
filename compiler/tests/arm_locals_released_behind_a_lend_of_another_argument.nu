// arm_locals_released_behind_a_lend_of_another_argument.nu — a `?` arm's
// own locals are released at the arm's exit when its value is a call's
// lend of something the arm does not own (Agora #662, #771): the tail call
// is handed one of the arm's locals but lends another argument; it lends a
// field of an outer binding; it lends a field of the arm's own struct (then
// the value is copied first and the locals still go); in a loop; in both
// arms. Where the call may lend the arm's own local the value is copied on
// those runs. Every String is released once.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: O { String name i n }

@ mk i k → String {
    : ~ String r ( string_from `a heap string long enough for the buffer ` )
    ( string_push_int r k )
    ^ r
}

@ idg [T] T x → T { ^ x }

@ first String a String b → String { ^ a }

@ pick String a String b b c → String { ^ ? c a b }

@ other_arg String outer b c → String { ^ ? c { : String junk ( mk 2 ) ( first outer junk ) } ( mk 3 ) }

@ own_arg String outer b c → String { ^ ? c { : String junk ( mk 2 ) ( first junk outer ) } ( mk 3 ) }

@ either String outer b c → String { ^ ? c { : String junk ( mk 2 ) ( pick junk outer c ) } ( mk 3 ) }

@ outer_field O o b c → String { ^ ? c { : String junk ( mk 2 ) ( idg [String] . o name ) } ( mk 3 ) }

@ own_field String outer b c → String { ^ ? c { : O lo @ O { ( mk 2 ) 3 } ( first . lo name outer ) } ( mk 3 ) }

@ both O o String outer b c → String { ^ ? c { : String j1 ( mk 2 ) ( idg [String] . o name ) } { : String j2 ( mk 4 ) ( first j2 outer ) } }

@ main → i {
    : String outer ( mk 8 )
    : O o @ O { ( mk 7 ) 1 }
    ( nurl_println ( string_data ( other_arg outer T ) ) )
    ( nurl_println ( string_data ( own_arg outer T ) ) )
    ( nurl_println ( string_data ( either outer T ) ) )
    ( nurl_println ( string_data ( either outer F ) ) )
    ( nurl_println ( string_data ( outer_field o T ) ) )
    ( nurl_println ( string_data ( own_field outer T ) ) )
    ( nurl_println ( string_data ( both o outer T ) ) )
    ( nurl_println ( string_data ( both o outer F ) ) )
    : ~ i acc 0
    : ~ i j 0
    ~ < j 10 {
        : String x ( other_arg outer == % j 2 0 )
        = acc + acc ( string_len x )
        = j + j 1
    }
    ( nurl_println_int acc )
    ^ 0
}
