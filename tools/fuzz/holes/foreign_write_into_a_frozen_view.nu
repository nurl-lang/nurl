// foreign_write_into_a_frozen_view: what a foreign function writes through a pointer it is handed was not a change to anything. An `unsafe` helper that read a file into the slice it was given (pread through the slice's data pointer) had no mutation in its summary, so a caller could hand it a view of an Arc's payload — frozen, read by every thread holding a clone — and the read wrote into it under them.
// Closed: an FFI `*T` parameter is written through unless it is declared `in` (only reads) or `sync` (changes it atomically or under its own lock); the write joins the raw provenance graph like a store through the pointer (gen_ffi_decl's __ffi_writes), so the helper changes its slice parameter and the frozen view is rejected where it is handed over.
// main (before this PR): compiled; the read raced the threads reading the payload.
// map: §6.5 | A3 | rejected | h289 | unsafe helper preads into a slice it is handed; caller hands it a view of an Arc payload
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/core/posix.nu`
$ `stdlib/std/arc.nu`

: Page { ( Vec u ) data }

// Reads into the bytes `dst` views, through a foreign call.
unsafe @ fill_from i32 fd ( Slice u ) dst → i { ^ ( read fd ( slice_data [u] dst ) ( slice_len [u] dst ) ) }

@ main → i {
    : ( Arc Page ) a ( arc_new [Page] @ Page { ( vec_zeroed [u] 16 ) } )
    : ( Slice u ) s ( slice_from_vec [u] . ( arc_get [Page] a ) data )
    : i n ( fill_from # i32 0 s )
    ^ 0
}
