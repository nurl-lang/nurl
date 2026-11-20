// slice_field_taken_out_of_a_temporary_into_a_literal_runs_clean: `@ Bag { . ( mkb ) s 4 }` (a struct a call handed back) and `@ Bag { . ( vec_at [Bag] vs 0 ) s 4 }` (one a Vec lends), then every other place a slice field read out of the lent one goes: an argument, a binding, a length read, a return
// Closed (agora #936): a slice the read takes out of a temporary (h266, agora #895) is the literal's own on every run: taken where the read owned it, copied where it was lent (`fld_lent`), and not copied a second time by the owned-slice field's copy (#841).
// main aae76ca (with github#2103): AddressSanitizer: heap-use-after-free (the struct a call handed back was released under its slice; agora #895), and with that fixed the taken-out slice leaked, copied whole.
// map: §7.6 | A2 | runs-clean | - | agora #936: a slice field read out of a struct temporary, owned and lent, stored into a literal's slice field, and the lent one's other uses
$ `stdlib/core/vec.nu`

: Bag { [i s i n }

@ mk → [i { ^ [i | 1 2 3] }
@ mkb → Bag { ^ @ Bag { ( mk ) 3 } }
@ ln [i t → i { : ~ i k 0 ~ x t { = k + k x } ^ k }
@ first ( Vec Bag ) vs → [i { ^ . ( vec_at [Bag] vs 0 ) s }

@ main → i {
    : ~ ( Vec Bag ) vs ( vec_new [Bag] )
    ( vec_push [Bag] vs @ Bag { ( mk ) 3 } )
    ( nurl_println_int ( ln . ( vec_at [Bag] vs 0 ) s ) )
    : [i x . ( vec_at [Bag] vs 0 ) s
    ( nurl_println_int ( ln x ) )
    ( nurl_println_int . . ( vec_at [Bag] vs 0 ) s length )
    : Bag d @ Bag { . ( vec_at [Bag] vs 0 ) s 4 }
    ( nurl_println_int ( ln . d s ) )
    ( nurl_println_int ( ln ( first vs ) ) )
    : [i y ( first vs )
    ( nurl_println_int ( ln y ) )
    : Bag e @ Bag { . ( mkb ) s 4 }
    ( nurl_println_int ( ln . e s ) )
    ^ 0
}
