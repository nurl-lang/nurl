// H32: a Slice of a Vec outlives the Vec. slice_from_vec is a safe
// standard-library function, but the Slice it returns ({ *A data, i len })
// was not tracked as a view of its Vec the way a vec_data pointer is, so
// freeing (or growing) the Vec left it dangling and slice_get read freed
// memory; protobuf's proto_reader held such a Slice and inherited the hole.
// Open in 0.71.0, that release's one known exception to the memory
// guarantee; closed in 0.72.0 (views are values, docs/MEMORY.md §2.10,
// §6.2): the read after vec_free is rejected.
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
