// slice_field_of_a_lent_back_struct_returned_runs_clean: `@ rq Bag b → [i { ^ . ( idb b ) s }` with `idb` handing its parameter back, defined before and after `rq`: the slice read out of the lent-back struct is the caller's parameter's, not the function's own
// Guard (agora #936): a slice taken out of a temporary answers by the read's flag, which says lent here: no copy is the caller's to release, and the parameter's slice is released once, by its owner.
// main 08e56f54: ran clean.
// map: §7.6 | A2 | runs-clean | - | agora #936: a slice field read out of a struct a call lends back from the function's parameter, returned
: Bag { [i s i n }

@ mk → [i { ^ [i | 1 2 3] }
@ ln [i t → i { : ~ i k 0 ~ x t { = k + k x } ^ k }
@ idb Bag b → Bag { ^ b }
@ rq Bag b → [i { ^ . ( idb b ) s }
@ rr Bag b → [i { ^ . ( idc b ) s }

@ main → i {
    : Bag d @ Bag { ( mk ) 2 }
    ( nurl_println_int ( ln ( rq d ) ) )
    : [i y ( rq d )
    ( nurl_println_int ( ln y ) )
    ( nurl_println_int ( ln ( rr d ) ) )
    ( nurl_println_int ( ln . d s ) )
    ^ 0
}

@ idc Bag b → Bag { ^ b }
