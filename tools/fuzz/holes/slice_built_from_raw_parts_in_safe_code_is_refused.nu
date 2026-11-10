// slice_built_from_raw_parts_in_safe_code_is_refused: agora #545 — `@ [i { p n }` in safe code makes a second slice over a buffer another slice owns (here the data pointer of `a`): both free it.
// Closed: a slice built from raw parts takes the buffer behind the pointer for its own, so it is `unsafe` (spec §3.3d); safe code makes a slice with a literal, a copy or a library call.
// main (before this PR): accepted; AddressSanitizer, attempting double-free.
// map: §6.2 | A2 | rejected | - | agora #545: a slice built field by field in safe code over another slice's buffer was freed by both (double free)
@ view → [i {
    : [i a [i | 1 2 3]
    ^ @ [i { . a 0 3 }
}

@ main → i {
    : [i w ( view )
    ~ x w { ( nurl_println ( nurl_str_int x ) ) }
    ^ 0
}
