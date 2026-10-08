// H32 (OPEN): a Slice of a Vec outlives the Vec. slice_from_vec is a safe
// standard-library function, but the Slice it returns ({ *A data, i len })
// is not tracked as a view of its Vec the way a vec_data pointer is, so
// freeing (or growing) the Vec leaves it dangling and slice_get reads
// freed memory. protobuf's proto_reader holds such a Slice and inherits the
// hole. Known open in 0.71.0 (CHANGELOG, docs/MEMORY.md §6.4).
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

@ main → i {
    : ( Vec u ) v ( vec_new [u] )
    ( vec_push [u] v # u 7 )
    : ( Slice u ) s ( slice_from_vec [u] v )
    ( vec_free [u] v )
    ?? ( slice_get [u] s 0 ) { T x → { ( nurl_println_int # i x ) } F → {} }
    ^ 0
}
