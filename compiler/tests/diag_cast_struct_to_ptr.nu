// diag_cast_struct_to_ptr.nu — '# s' / '# *T' of a named struct whose
// FIRST FIELD IS NOT A POINTER. The handle-wrapper read (`# s v` on a
// ( Vec u ) extracts field 0 and bitcasts it) only means anything when
// field 0 really is an address; this used to fall through with no
// conversion and die in clang as invalid IR, not here as a diagnostic.
: Point { i x i y }

@ main → i {
    : Point p @ Point { 1 2 }
    : s q # s p
    ^ ( nurl_str_len q )
}
