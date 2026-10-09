// diag_raw_boundary.nu — the raw-memory boundary, one rule per function.
// Each body is ordinary-looking safe code that reaches memory the compiler
// cannot follow, and each is rejected with its rule and its fix:
//
// 1. A cast that makes a String out of an integer's bits (`# String 4096`):
//    a String is valid only as its own code built it.
// 2. A literal of a sealed representation (`@ ( Slice u ) { … }`): its
//    `len` covers its `data` only when a constructor made it.
// 3. A call that takes a raw pointer (`nurl_str_at`): it reads as far as
//    its caller says, and a pointer carries no length — `slice_of_str` +
//    `slice_byte` is the safe scan.
// 4. A standard-library internal (`__vec_grow`): it trusts the control
//    block it is handed.

$ `stdlib/core/string.nu`
$ `stdlib/core/slice.nu`

@ forged_string → i {
    : String t # String 4096
    ^ ( string_len t )
}

@ forged_slice → i {
    : ( Slice u ) sl @ ( Slice u ) { # *u 0 64 }
    ^ ( slice_len [u] sl )
}

@ trusted_length String s → i {
    ^ ( nurl_str_at ( string_data s ) 64 3 )
}

@ library_internal String s → v {
    ( __vec_grow [u] ( string_data s ) 64 )
}

@ main → i {
    ^ 0
}
