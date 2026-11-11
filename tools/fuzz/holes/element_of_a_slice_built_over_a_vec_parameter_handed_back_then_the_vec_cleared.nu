// element_of_a_slice_built_over_a_vec_parameter_handed_back_then_the_vec_cleared: agora #594 — a function builds a Slice over its Vec parameter and hands back an element read through it; the caller clears the Vec, then reads the element
// Closed: what a returned value reaches is recorded through the view it was read out of (a Slice over the parameter), so the function lends its parameter and the caller's clear is refused while the result is read.
// main a9be57b: accepted; heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #594: a function builds a Slice over its Vec parameter and hands back an element read through it; the caller clears the Vec, then reads the element
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

@ mkvs → ( Vec String ) {
    : ( Vec String ) vs ( vec_new [String] )
    ( vec_push [String] vs ( string_from `hello world slice element number zero` ) )
    ^ vs
}

@ first ( Vec String ) vs → String {
    : ( Slice String ) sl ( slice_from_vec [String] vs )
    ^ ( slice_at [String] sl 0 )
}

@ main → i {
    : ( Vec String ) vs ( mkvs )
    : String r ( first vs )
    ( vec_clear [String] vs )
    ( nurl_println ( string_data r ) )
    ^ 0
}
