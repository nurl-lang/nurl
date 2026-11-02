// Test: a Slice of Vecs (agora #355). A `( Slice ( Vec u ) )`'s data field
// is a `%Vec__u8*` pointer, which __type_needs_drop asked by its `%Vec__`
// prefix and answered "needs a drop": nurlc emitted `drop__Vec__u8*` and an
// `extractvalue %Vec__u8*`, and clang rejected the program. A pointer owns
// nothing it points at; the Vec it views is dropped by its owner, once.
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

@ main → i {
    : ( Vec ( Vec u ) ) vv ( vec_new [( Vec u )] )
    ( vec_push [( Vec u )] vv ( vec_new [u] ) )
    ( vec_push [u] ( vec_at [( Vec u )] vv 0 ) 7 )
    ( vec_push [u] ( vec_at [( Vec u )] vv 0 ) 9 )
    : ( Slice ( Vec u ) ) sl ( slice_from_vec [( Vec u )] vv )
    ( nurl_println_int ( slice_len [( Vec u )] sl ) )
    ( nurl_println_int ( vec_len [u] ( slice_at [( Vec u )] sl 0 ) ) )
    : ( Vec ( Vec String ) ) ws ( vec_new [( Vec String )] )
    ( vec_push [( Vec String )] ws ( vec_new [String] ) )
    ( vec_push [String] ( vec_at [( Vec String )] ws 0 ) ( string_from `an element long enough for the heap` ) )
    : ( Slice ( Vec String ) ) wl ( slice_from_vec [( Vec String )] ws )
    ( nurl_println ( string_data ( vec_at [String] ( slice_at [( Vec String )] wl 0 ) 0 ) ) )
    ^ 0
}
