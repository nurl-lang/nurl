// diag_mem_drop_range_from_safe.nu — `mem_drop_range` drops elements a
// container has given up, by address: raw memory, which only an `unsafe`
// function may vouch for (docs/spec.md §3.3d). Safe code that could call
// it would drop a live Vec's elements under the Vec (a double free).
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ main → i {
    : ~ ( Vec String ) vs ( vec_new [String] )
    ( vec_push [String] vs ( string_from `one` ) )
    ( mem_drop_range [String] ( vec_data [String] vs ) 0 1 )
    ^ 0
}
