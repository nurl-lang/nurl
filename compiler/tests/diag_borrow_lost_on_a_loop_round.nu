// diag_borrow_lost_on_a_loop_round.nu — a binding read out of a field is
// handed to a `sink` inside a loop that replaces the field: on a later round
// it may hold nothing. The diagnostic says why, instead of naming an empty
// source and line (agora #278).

$ `stdlib/core/vec.nu`
$ `stdlib/core/io.nu`

: Inner { ( Vec i ) v }
: Outer { Inner cur }

@ eat sink Inner x → i { ^ ( vec_len [i] . x v ) }

@ main → i {
    : ~ Outer o @ Outer { @ Inner { ( vec_new [i] ) } }
    ( vec_push [i] . . o cur v 7 )
    : Inner got . o cur
    : ~ i n 0
    : ~ i s 0
    ~ < n 3 {
        ? == n 2 { = s + s ( eat got ) } {}
        = . o cur @ Inner { ( vec_new [i] ) }
        ( vec_push [i] . . o cur v n )
        = n + n 1
    }
    ( nurl_print_int s )
    ( nurl_println_int ( vec_at [i] . . o cur v 0 ) )
    ^ 0
}
