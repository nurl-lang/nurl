// diag_ret_int_to_enum.nu — returning a bare number out of an
// enum-returning function. `^ 7` from a `→ Color` fn emitted `ret i64`
// out of a `define %Color` — invalid IR only the LLVM verifier saw;
// and no number converts into a closed set of named variants anyway.
: | Color { Red Green Blue }

@ pick → Color {
    ^ 7
}

@ main → i {
    : Color c ( pick )
    ^ 0
}
