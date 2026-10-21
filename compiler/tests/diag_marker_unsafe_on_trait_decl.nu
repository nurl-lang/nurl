// diag_marker_unsafe_on_trait_decl.nu
// `unsafe` vouches for something the compiler cannot check, and a trait
// DECLARATION claims nothing: it only names methods. The prefix belongs
// on an impl that asserts thread safety — `unsafe % Send T { }` — so on a
// declaration it is an error, not a silent no-op.

unsafe % Shape {
    @ area i self → i
}

@ main → i { ^ 0 }
