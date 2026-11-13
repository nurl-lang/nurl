// inout_handle_stored_into_another_inouts_field_then_given_a_new_value_runs_clean: `= . b held v` (v an `inout ( Vec String )`, b an `inout Hold`), then `= v ( vec_new … )`; the caller frees both.
// Closed (agora #598): an `inout` handle parameter stored by name moves out of its slot (gen_field_rhs empties it where it was not copied, and notes a replace): `= v` drops nothing the field holds, and the caller's binding ends with the new Vec.
// main 4403a920: heap-use-after-free and invalid frees (the field and the slot shared one buffer).
// map: §2.12 | A2 | runs-clean | - | agora #598: an inout handle stored into another inout's field, then given a new value
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: Hold { ( Vec String ) held }

@ stash inout ( Vec String ) v inout Hold b → v { ( vec_free [String] . b held ) = . b held v = v ( vec_new [String] ) }

@ main → i {
    : ~ ( Vec String ) fs ( vec_new [String] )
    ( vec_push [String] fs ( string_from `a string long enough for a heap buffer here` ) )
    : ~ Hold box @ Hold { ( vec_new [String] ) }
    ( stash fs box )
    ( vec_clear [String] . box held )
    ( vec_free [String] fs )
    ( vec_free [String] . box held )
    ^ 0
}
