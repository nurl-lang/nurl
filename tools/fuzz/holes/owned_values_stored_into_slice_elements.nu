// owned_values_stored_into_slice_elements: agora #415 — `slice_put` of a String and of an i through slices (the shape the fix must keep)
// Closed: only a Slice whose elements hold views is refused (agora #415).
// main: accepted, ran clean.
// map: §2.10 | A2 | runs-clean | - | agora #415: `slice_put` of a String and of an i through slices (the shape the fix must keep)
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

@ main → i {
    : ( Vec String ) ns ( vec_new [String] )
    ( vec_push [String] ns ( string_from `an owned element, long enough` ) )
    : ( Slice String ) sl ( slice_from_vec [String] ns )
    ( slice_put [String] sl 0 ( string_from `a replacement, owned and long enough` ) )
    : ( Vec i ) xs ( vec_new [i] )
    ( vec_push [i] xs 1 )
    ( slice_put [i] ( slice_from_vec [i] xs ) 0 7 )
    ( nurl_println ( string_data ( vec_at [String] ns 0 ) ) )
    ^ 0
}
