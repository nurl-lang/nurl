// param_elements_read_through_a_struct_holding_the_slice_runs_clean: as param_element_grown_through_a_struct_holding_the_slice, ext only reads through the held slice
// AGORA-910 guard: accepted - reading changes nothing, so the caller's view stays good
// map: §2.10 | A2 | runs-clean | - | AGORA-910
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

: SH { ( Slice String ) s }

@ ext ( Vec String ) v → v {
    : SH h @ SH { ( slice_from_vec [String] v ) }
    ( nurl_println ( string_data ( slice_at [String] . h s 0 ) ) )
}

@ main → i {
    : ( Vec String ) v ( vec_new [String] )
    ( vec_push [String] v ( string_from `an element string long enough for a heap buffer` ) )
    : s view ( string_data ( vec_at [String] v 0 ) )
    ( ext v )
    ( nurl_println view )
    ^ 0
}
