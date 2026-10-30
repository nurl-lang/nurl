// mapped_view_outlives_its_file: model loaders mapped a file by hand (open / mmap / munmap) and read it through the bare pointer, which outlived the mapping as easily as it read past it.
// Closed: stdlib/std/mmap.nu maps it into a MappedFile whose bytes are lent as a checked Slice u held to it — a view returned past the MappedFile is rejected, a read past its end panics.
// main's compiler: a function could hand back the mapping's address after unmapping it.
// map: FnOK | A1 | rejected | h258 | function returns view of its local MappedFile's bytes past the owner's drop
$ `stdlib/core/io.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/mmap.nu`

@ view_of ( Vec u ) bytes → ( Slice u ) {
    : MappedFile m ( mapped_of_bytes ( slice_to_vec [u] ( slice_from_vec [u] bytes ) ) )
    ^ ( mapped_bytes m )
}

@ main → i {
    : ( Vec u ) b ( vec_zeroed [u] 64 )
    : ( Slice u ) v ( view_of b )
    ( nurl_println_int ( slice_u32_le v 0 ) )
    ^ 0
}
