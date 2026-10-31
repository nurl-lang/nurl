// drop_holder_inout_struct_field_given_a_callee_local_then_panics: agora #284 — as drop_holder_inout_param_given_a_callee_local_then_panics, the holder a field of an `inout` struct.
// Closed: an `inout` parameter whose drop may read the views it holds is a holder older than every local of the callee: given a view of one, even for a moment, it is refused where it gains the view (bck_younger_view_check, the `^` parameter mark; agora #284).
// main: rejected (the end-state check).
// map: §2.14 | A2 | rejected | - | agora #284: an inout struct's Drop-holder field given a callee local's view
$ `stdlib/core/string.nu`
$ `stdlib/std/panic.nu`

: W { s v }

% Drop W { @ drop W self → v { ( nurl_println . self v ) } }

: H { W w i n }

@ repoint inout H h i k → v {
    : String b ( string_from `the callee's own string, freed by the unwind before the holder's destructor reads it` )
    = . h w @ W { ( string_data b ) }
    ? > k 2 { ( panic `unwind` ) } {}
    = . h w @ W { `literal again` }
}

@ f i k → v {
    : ~ H h @ H { @ W { `literal` } 0 }
    ( repoint h k )
}

@ main → i {
    : !v PanicInfo r ( recover \ → v { ( f 3 ) } )
    ( puts `ran` )
    ^ 0
}
